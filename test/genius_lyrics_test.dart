import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/data/datasources/lyrics_local_datasource.dart';
import 'package:lyricx/data/repositories/lyrics_repository_impl.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/utils/song_key.dart';
import 'package:lyricx/data/datasources/genius_lyrics_datasource.dart';
import 'package:lyricx/data/models/lyrics_model.dart';

const fixture = '''<html><head>
<meta property="og:url" content="https://genius.com/Test-artist-test-track-lyrics">
</head><body><header>Unrelated page heading</header>
<div data-lyrics-container="true">[Verse]<br>Original &amp; test <a>words</a><br><br>Second line<button>Copy</button><span hidden>Ad</span></div>
<div data-lyrics-container="true">[Chorus]<br>Another line<script>tracking()</script></div>
<footer>Embed and recommendations</footer></body></html>''';

Map<String, dynamic> searchFixture({String artist = 'Test artist'}) => {
  'response': {
    'sections': [
      {
        'hits': [
          {
            'type': 'song',
            'result': {
              'title': 'Test track',
              'primary_artist': {'name': artist},
              'url': 'https://genius.com/Test-artist-test-track-lyrics',
            },
          },
          {
            'type': 'artist',
            'result': {'name': 'Ignore artist hits'},
          },
        ],
      },
    ],
  },
};

class EmptyRemote extends LyricsRemoteDataSource {
  EmptyRemote() : super(Dio());
  int calls = 0;
  @override
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    calls++;
    return null;
  }
}

void main() {
  test(
    'repository uses Genius only after a miss and reuses its offline cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      final local = LyricsLocalDataSource(
        await SharedPreferences.getInstance(),
      );
      final remote = EmptyRemote();
      final dio = Dio();
      var requests = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: options.uri.path.startsWith('/api/')
                    ? searchFixture()
                    : fixture,
              ),
            );
          },
        ),
      );
      final repository = LyricsRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: local,
        geniusDataSource: GeniusLyricsDataSource(dio),
      );
      const playing = Song(
        id: 'playing',
        title: 'Test track',
        artist: 'Test artist',
      );
      final first = await repository.getLyrics(playing);
      expect(first.source, 'Genius');
      expect(await repository.getLyrics(playing), first);
      expect(remote.calls, 1);
      expect(requests, 2);
    },
  );

  final song = GeniusSong(
    title: 'Test track',
    artist: 'Test artist',
    url: Uri.parse('https://genius.com/Test-artist-test-track-lyrics'),
  );

  test(
    'extracts only lyric containers, preserving sections and linked words',
    () {
      final result = GeniusLyricsDataSource.parsePage(fixture, song);
      expect(
        result.plainLyrics,
        '[Verse]\nOriginal & test words\n\nSecond line\n\n[Chorus]\nAnother line',
      );
      expect(result.isSynced, false);
      expect(result.source, 'Genius');
      expect(
        LyricsModel.fromJson(result.toJson()).sourceUrl,
        song.url.toString(),
      );
    },
  );

  test('rejects challenge, missing lyrics, oversized or mismatched pages', () {
    for (final page in [
      '<html>Verify you are human</html>',
      '',
      'x' * 3000001,
      fixture.replaceAll('Test-artist-test-track-lyrics', 'Other-song-lyrics'),
    ]) {
      expect(
        () => GeniusLyricsDataSource.parsePage(page, song),
        throwsFormatException,
      );
    }
  });

  test('accepts only Genius HTTPS song URLs and removes tracking', () {
    expect(
      GeniusLyricsDataSource.validateSongUrl('${song.url}?from=search#lyrics'),
      song.url,
    );
    for (final url in [
      'http://genius.com/Test-lyrics',
      'https://genius.com.evil.test/Test-lyrics',
      'https://localhost/Test-lyrics',
      'https://genius.com/artists/Test',
      'https://user:password@genius.com/Test-lyrics',
      'https://genius.com:8080/Test-lyrics',
    ]) {
      expect(
        () => GeniusLyricsDataSource.validateSongUrl(url),
        throwsFormatException,
      );
    }
  });

  test('search parses real song hits and rejects malformed responses', () {
    final results = GeniusLyricsDataSource.parseSearch(searchFixture());
    expect(results, hasLength(1));
    expect(results.single.title, 'Test track');
    expect(results.single.artist, 'Test artist');
    expect(
      () => GeniusLyricsDataSource.parseSearch('<html>Blocked</html>'),
      throwsFormatException,
    );
  });

  test('same title by another artist is never an automatic match', () {
    expect(
      GeniusLyricsDataSource.matches(song, 'Wrong artist', 'Test track'),
      false,
    );
    expect(
      GeniusLyricsDataSource.matches(song, 'Test artist', 'Wrong title'),
      false,
    );
    expect(GeniusLyricsDataSource.matches(song, '', 'Test track'), false);
    expect(
      GeniusLyricsDataSource.matches(song, 'TEST ARTIST', 'Test Track!'),
      true,
    );
  });

  test(
    'automatic fallback searches then fetches, marks exact match verified',
    () async {
      final dio = Dio();
      final requests = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri.path);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: options.uri.path.startsWith('/api/')
                    ? searchFixture()
                    : fixture,
              ),
            );
          },
        ),
      );
      final result = await GeniusLyricsDataSource(
        dio,
      ).findExact('Test artist', 'Test track');
      expect(requests, ['/api/search/song', '/Test-artist-test-track-lyrics']);
      expect(result!.isMatchVerified, true);
      expect(result.songId, songKey('Test artist', 'Test track'));
    },
  );

  test('wrong artist never triggers a lyrics download', () async {
    final dio = Dio();
    var count = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          count++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: searchFixture(artist: 'Wrong artist'),
            ),
          );
        },
      ),
    );
    expect(
      await GeniusLyricsDataSource(dio).findExact('Test artist', 'Test track'),
      isNull,
    );
    expect(count, 1);
  });

  test('blocked access does not retry or return fabricated lyrics', () async {
    final dio = Dio();
    var count = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          count++;
          handler.resolve(
            Response(requestOptions: options, statusCode: 403, data: 'Blocked'),
          );
        },
      ),
    );
    expect(
      await GeniusLyricsDataSource(dio).findExact('Test artist', 'Test track'),
      isNull,
    );
    expect(count, 1);
  });

  test('overall deadline cancels the pending request', () async {
    final dio = Dio();
    CancelToken? token;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          token = options.cancelToken;
          final error = await token!.whenCancel;
          handler.reject(error);
        },
      ),
    );
    expect(
      await GeniusLyricsDataSource(dio).findExact(
        'Test artist',
        'Test track',
        budget: const Duration(milliseconds: 20),
      ),
      isNull,
    );
    expect(token!.isCancelled, true);
  });
}
