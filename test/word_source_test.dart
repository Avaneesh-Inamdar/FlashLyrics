import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'word_lyrics_test.dart' show wordFixture;

void main() {
  test(
    'word enrichment rejects other artists and chooses genuine timing data',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.queryParameters, {
              'artist_name': 'Artist',
              'track_name': 'Song',
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {
                    'id': 1,
                    'artistName': 'Other',
                    'trackName': 'Song',
                    'lyricsfile': wordFixture,
                  },
                  {
                    'id': 2,
                    'artistName': 'Artist',
                    'trackName': 'Song',
                    'syncedLyrics': '[00:01]Line',
                  },
                  {
                    'id': 3,
                    'artistName': 'Artist',
                    'trackName': 'Song',
                    'lyricsfile': wordFixture,
                  },
                ],
              ),
            );
          },
        ),
      );
      final result = await LyricsRemoteDataSource(
        dio,
      ).findWordSyncedLyrics('Artist', 'Song');
      expect(result!.id, 'lrclib_words_3');
      expect(result.lrcLyrics, contains('<00:01.600>'));
      expect(result.isMatchVerified, true);
      dio.close(force: true);
    },
  );

  test('word lookup failure is optional and does not throw', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
    expect(
      await LyricsRemoteDataSource(dio).findWordSyncedLyrics('Artist', 'Song'),
      isNull,
    );
    dio.close(force: true);
  });
}
