import 'package:dio/dio.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/utils/song_key.dart';

void main() {
  test(
    'automatic fallback keeps matching plain LRCLIB search lyrics',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final isSearch =
                options.uri.host == 'lrclib.net' &&
                options.uri.path.endsWith('/search');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: isSearch ? 200 : 404,
                data: isSearch
                    ? [
                        {
                          'id': 1,
                          'artistName': 'Test artist',
                          'trackName': 'Test track',
                          'plainLyrics': 'Original test words',
                          'syncedLyrics': null,
                        },
                      ]
                    : {},
              ),
            );
          },
        ),
      );
      final result = await LyricsRemoteDataSource(
        dio,
      ).fetchAllParallel('Test artist', 'Test track');
      expect(result, isNotNull);
      expect(result!.plainLyrics, 'Original test words');
      expect(result.isSynced, false);
      expect(result.isMatchVerified, true);
    },
  );

  test(
    'cache keys preserve Unicode vowel marks and agree across whitespace',
    () {
      expect(songKey(' कलाकार ', ' गीत '), songKey('कलाकार', 'गीत'));
      expect(songKey('Artist', 'दिन'), isNot(songKey('Artist', 'दीन')));
      expect(songKey('Artist', '東京'), isNot(songKey('Artist', '京都')));
    },
  );
}
