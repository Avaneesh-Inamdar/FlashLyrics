import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/utils/lyrics_import.dart';
import 'package:lyricx/core/utils/lrc_parser.dart';
import 'package:lyricx/core/utils/lyrics_image_generator.dart';
import 'package:lyricx/data/datasources/lyrics_local_datasource.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/data/repositories/lyrics_repository_impl.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/services/lyrics_file_service.dart';

class CountingRemote extends LyricsRemoteDataSource {
  CountingRemote() : super(Dio());
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

  @override
  Future<LyricsModel?> findWordSyncedLyrics(String artist, String title) async {
    calls++;
    return null;
  }
}

class DelayedRemote extends CountingRemote {
  final response = Completer<LyricsModel?>();
  @override
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) => response.future;
}

const target = Song(
  id: 'playing',
  title: 'गीत',
  artist: 'कलाकार',
  artworkUrl: 'https://images.genius.com/cover.jpg',
);
const timed =
    '[ar:कलाकार]\n[ti:गीत]\n[offset:250]\n[00:01.50]<00:01.50>Hello <00:02.00>world\n[00:04]Next line';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'queued provider cache writes preserve an import committed ahead of them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final local = LyricsLocalDataSource(prefs);
      final imported = await LyricsImport.parse(timed, target);
      await Future.wait([
        local.cacheLyrics(imported),
        local.cacheLyrics(
          LyricsModel(
            id: 'late',
            songId: imported.songId,
            plainLyrics: 'Late provider',
            isSynced: false,
            source: 'Remote',
            fetchedAt: DateTime.now(),
          ),
          preserveUserProvided: true,
        ),
      ]);
      expect(local.getCachedLyrics(imported.songId)?.lrcLyrics, timed);
    },
  );
  test(
    'Genius artwork survives cache reopening, manual selection and timing upgrades',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lyricsRemoteDataSourceProvider.overrideWithValue(CountingRemote()),
        ],
      );
      addTearDown(container.dispose);
      final model = LyricsModel(
        id: 'genius',
        songId: 'कलाकार_गीत',
        artistName: target.artist,
        trackName: target.title,
        artworkUrl: target.artworkUrl,
        plainLyrics: 'Words',
        isSynced: false,
        source: 'Genius',
        isMatchVerified: true,
        fetchedAt: DateTime.now(),
      );
      final repository = container.read(lyricsRepositoryProvider);
      await repository.cacheLyrics(model);
      final notifier = container.read(lyricsNotifierProvider.notifier);
      notifier.setLyricsFromModel(model, cache: false);
      expect(
        container.read(lyricsNotifierProvider).currentSong?.artworkUrl,
        target.artworkUrl,
      );
      await notifier.setSong(
        Song(id: 'player', artist: target.artist, title: target.title),
      );
      expect(
        container.read(lyricsNotifierProvider).currentSong?.artworkUrl,
        target.artworkUrl,
      );
      final upgrade = LyricsModel(
        id: 'upgraded',
        songId: model.songId,
        artistName: target.artist,
        trackName: target.title,
        plainLyrics: 'Words',
        lrcLyrics: '[00:01]Words',
        isSynced: true,
        source: 'LRCLIB',
        fetchedAt: DateTime.now(),
      );
      await repository.cacheLyrics(upgrade);
      expect(
        LyricsLocalDataSource(prefs).getCachedLyrics(model.songId)!.artworkUrl,
        target.artworkUrl,
      );
    },
  );
  for (final search in [false, true]) {
    test(
      'late ${search ? 'search' : 'detection'} result cannot overwrite a new import',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final remote = DelayedRemote();
        final repository = LyricsRepositoryImpl(
          remoteDataSource: remote,
          localDataSource: LyricsLocalDataSource(prefs),
        );
        final request = search
            ? repository.searchLyrics(target.artist, target.title)
            : repository.getLyrics(target);
        final imported = await LyricsImport.parse(timed, target);
        await repository.cacheLyrics(imported);
        remote.response.complete(
          LyricsModel(
            id: 'remote',
            songId: imported.songId,
            plainLyrics: 'Provider result',
            isSynced: false,
            source: 'Remote',
            fetchedAt: DateTime.now(),
          ),
        );
        expect((await request).plainLyrics, imported.plainLyrics);
        expect(
          (await repository.getCachedLyrics(imported.songId))?.lrcLyrics,
          timed,
        );
      },
    );
  }
  test(
    'imports enhanced LRC, Unicode identity, metadata and clean plain lyrics',
    () async {
      final model = await LyricsImport.parse(timed, target);
      expect(model.songId, 'कलाकार_गीत');
      expect(model.isUserProvided, true);
      expect(model.isMatchVerified, true);
      expect(model.isSynced, true);
      expect(model.plainLyrics, 'Hello world\nNext line');
      expect(model.artworkUrl, target.artworkUrl);
      final parsed = await LrcParser.parse(model.lrcLyrics!);
      expect(parsed.offset, const Duration(milliseconds: 250));
      expect(parsed.lines.first.words.length, 2);
      expect(parsed.getLineIndexAtTime(const Duration(milliseconds: 1749)), -1);
      expect(parsed.getLineIndexAtTime(const Duration(milliseconds: 1750)), 0);
      expect(LyricsModel.fromJson(model.toJson()).isUserProvided, true);
    },
  );

  test(
    'repeated timestamps and long tracks are supported without leaking time tags',
    () async {
      final model = await LyricsImport.parse(
        '[100:01.100][120:02.200]Repeated\n[110:03]Middle',
        target,
      );
      expect(model.plainLyrics, 'Repeated\nMiddle\nRepeated');
      expect(LyricsImageGenerator.prepareLines([model.lrcLyrics!]), [
        'Repeated',
        'Middle',
      ]);
    },
  );

  test(
    'plain lyrics preserve sections and never pretend to have timings',
    () async {
      final model = await LyricsImport.parse(
        '[Verse]\nHello\n\n[Chorus]\nWorld',
        target,
      );
      expect(model.isSynced, false);
      expect(model.lrcLyrics, null);
      expect(model.plainLyrics, '[Verse]\nHello\n\n[Chorus]\nWorld');
    },
  );

  for (final input in [
    '',
    '[ti:Only metadata]',
    '[00:61]Invalid',
    '[00:01]First\nUntimed',
    '[00:01.1234]Broken',
    '[00:01]<00:00>Before line',
    '[00:01]<00:03>A <00:02>B',
    '[offset:abc]\n[00:01]Text',
    '[00:01]Text <00:70>bad',
    'binary\x00text',
    '[00:01:02]Wrong format',
  ]) {
    test(
      'rejects malformed or ambiguous import: ${input.replaceAll('\n', ' / ')}',
      () async {
        await expectLater(
          LyricsImport.parse(input, target),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'rejects missing song identity and oversized data before caching',
    () async {
      await expectLater(
        LyricsImport.parse(
          'Words',
          const Song(id: '', title: '', artist: 'Artist'),
        ),
        throwsFormatException,
      );
      await expectLater(
        LyricsImport.parse('a' * (LyricsImport.maxBytes + 1), target),
        throwsFormatException,
      );
      await expectLater(
        LyricsImport.parse(List.filled(2001, 'Line').join('\n'), target),
        throwsFormatException,
      );
    },
  );

  test(
    'file loading accepts UTF-8 BOM and UTF-16 in both byte orders',
    () async {
      final service = LyricsFileService();
      final utf8File = XFile.fromData(
        Uint8List.fromList([239, 187, 191, ...utf8.encode(timed)]),
        path: 'song.LRC',
      );
      expect(await service.read(utf8File), timed);
      for (final endian in [Endian.little, Endian.big]) {
        final data = ByteData(2 + timed.length * 2)
          ..setUint16(0, 0xFEFF, endian);
        for (var i = 0; i < timed.length; i++) {
          data.setUint16(2 + i * 2, timed.codeUnitAt(i), endian);
        }
        expect(
          await service.read(
            XFile.fromData(data.buffer.asUint8List(), path: 'lyrics.txt'),
          ),
          timed,
        );
      }
      await expectLater(
        service.read(
          XFile.fromData(Uint8List.fromList([255, 0, 255]), path: 'bad.txt'),
        ),
        throwsFormatException,
      );
      await expectLater(
        service.read(XFile.fromData(Uint8List(1), path: 'song.pdf')),
        throwsFormatException,
      );
      await expectLater(
        service.read(
          XFile.fromData(
            Uint8List(LyricsImport.maxBytes + 1),
            path: 'large.txt',
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'import survives restart, force refresh, offline cache and optional upgrades',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final remote = CountingRemote();
      final repository = LyricsRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: LyricsLocalDataSource(prefs),
      );
      final model = await LyricsImport.parse(timed, target);
      await repository.cacheLyrics(model);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lyricsRemoteDataSourceProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);
      await container.read(lyricsNotifierProvider.notifier).setSong(target);
      await container
          .read(lyricsNotifierProvider.notifier)
          .setSong(target, forceRefresh: true);
      expect(container.read(lyricsNotifierProvider).lyrics?.lrcLyrics, timed);
      expect(
        container.read(lyricsNotifierProvider).currentSong?.artworkUrl,
        target.artworkUrl,
      );
      expect(remote.calls, 0);
      final restarted = LyricsRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: LyricsLocalDataSource(prefs),
      );
      expect(
        (await restarted.getLyrics(target)).plainLyrics,
        model.plainLyrics,
      );
      await expectLater(
        restarted.getLyrics(target.copyWith(title: 'Other song')),
        throwsException,
      );
      expect(remote.calls, 1);
    },
  );

  test(
    'image text preparation strips all imported line/word timing and metadata',
    () {
      expect(
        LyricsImageGenerator.prepareLines([
          timed,
          '[100:12.345]<100:12.345>Long track',
          '[00:03][00:07]Repeat',
          '(00:10.2) Parentheses',
        ]),
        ['Hello world', 'Next line', 'Long track', 'Repeat', 'Parentheses'],
      );
    },
  );
}
