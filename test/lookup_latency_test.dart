import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/constants/app_constants.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';

void main() {
  test('search shows available matches without waiting for stalled providers', () async {
    final dio = Dio();
    final stalled = <void Function()>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.uri.path.endsWith('/search')) {
        handler.resolve(Response(requestOptions: options, statusCode: 200, data: [{
          'id': 1, 'artistName': 'Artist', 'trackName': 'Song',
          'plainLyrics': 'Original test lyrics', 'syncedLyrics': '[00:01]Original test lyrics',
        }]));
      } else {
        stalled.add(() => handler.resolve(Response(requestOptions: options, statusCode: 404, data: {})));
      }
    }));
    final watch = Stopwatch()..start();
    final matches = await LyricsRemoteDataSource(dio).searchByQuery('Artist - Song',
        providerPriority: ['lrclib', 'textyl']).timeout(const Duration(seconds: 2));
    expect(matches.single.trackName, 'Song');
    expect(watch.elapsedMilliseconds, lessThan(1500));
    final count = matches.length;
    for (final complete in stalled) { complete(); }
    await Future<void>.delayed(Duration.zero);
    expect(matches.length, count);
    dio.close(force: true);
  });
  test('Settings version agrees with the release version', () {
    final version = RegExp(r'^version: ([^+]+)\+(\d+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(AppConstants.appVersion, version.group(1));
    expect(AppConstants.appVersion, '1.4.4');
    expect(version.group(2), '16');
  });
  for (final preferred in ['lrclib', 'textyl']) {
    test('verified lyrics return without waiting for a stalled provider ($preferred)', () async {
      final dio = Dio();
      final stalled = <void Function()>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.uri.host == 'lrclib.net') {
          handler.resolve(Response(requestOptions: options, statusCode: 200,
            data: options.uri.path.endsWith('/search') ? [] : {
              'artistName': 'Test artist', 'trackName': 'Test track',
              'plainLyrics': 'Original test line',
              'syncedLyrics': '[00:01.00]Original test line',
            }));
        } else {
          stalled.add(() => handler.resolve(Response(requestOptions: options, statusCode: 404, data: {})));
        }
      }));
      final watch = Stopwatch()..start();
      final result = await LyricsRemoteDataSource(dio).fetchAllParallel(
        'Test artist', 'Test track', providerPriority: [preferred, if (preferred != 'lrclib') 'lrclib'],
      ).timeout(const Duration(seconds: 2));
      expect(result, isNotNull);
      expect(result!.isMatchVerified, true);
      expect(watch.elapsedMilliseconds, lessThan(1500));
      for (final complete in stalled) { complete(); }
      dio.close(force: true);
    });
  }
}
