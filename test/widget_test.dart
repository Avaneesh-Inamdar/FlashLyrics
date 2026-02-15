import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/main.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/domain/entities/lyrics.dart';
import 'package:lyricx/core/utils/lrc_parser.dart';
import 'package:lyricx/core/utils/helpers.dart';

void main() {
  group('FlashLyrics App Tests', () {
    testWidgets('App smoke test - starts with title', (
      WidgetTester tester,
    ) async {
      // Set up mock SharedPreferences
      SharedPreferences.setMockInitialValues({});

      // Build our app and trigger a frame
      await tester.pumpWidget(
        ProviderScope(overrides: [], child: const FlashLyricsApp()),
      );
      await tester.pump();

      // Verify that the app starts with a title
      expect(find.text('FlashLyrics'), findsOneWidget);
    });
  });

  group('Song Entity Tests', () {
    test('Song equality', () {
      const song1 = Song(
        id: 'test_1',
        title: 'Test Song',
        artist: 'Test Artist',
      );
      const song2 = Song(
        id: 'test_1',
        title: 'Test Song',
        artist: 'Test Artist',
      );
      expect(song1, equals(song2));
    });

    test('Song copyWith', () {
      const song = Song(
        id: 'test_1',
        title: 'Test Song',
        artist: 'Test Artist',
      );
      final updated = song.copyWith(title: 'New Title');
      expect(updated.title, 'New Title');
      expect(updated.artist, 'Test Artist');
    });
  });

  group('Lyrics Entity Tests', () {
    test('Lyrics lines parsing', () {
      final lyrics = Lyrics(
        id: 'test_1',
        songId: 'song_1',
        plainLyrics: 'Line 1\nLine 2\nLine 3',
        isSynced: false,
        source: 'test',
        fetchedAt: DateTime.now(),
      );
      expect(lyrics.lines.length, 3);
    });
  });

  group('LRC Parser Tests', () {
    test('Parse valid LRC', () async {
      const lrc = '''
[ti:Test Song]
[ar:Test Artist]
[00:00.00]First line
[00:05.00]Second line
[00:10.00]Third line
''';
      final parsed = await LrcParser.parse(lrc);
      expect(parsed.title, 'Test Song');
      expect(parsed.artist, 'Test Artist');
      expect(parsed.lines.length, 3);
    });

    test('Get line at time', () async {
      const lrc = '''
[00:00.00]First
[00:05.00]Second
[00:10.00]Third
''';
      final parsed = await LrcParser.parse(lrc);
      final line = parsed.getLineAtTime(const Duration(seconds: 7));
      expect(line?.text, 'Second');
    });

    test('isValidLrc', () {
      expect(LrcParser.isValidLrc('[00:00.00]Test'), true);
      expect(LrcParser.isValidLrc('Plain text'), false);
    });
  });

  group('Helper Tests', () {
    test('String capitalize', () {
      expect('hello'.capitalize, 'Hello');
      expect(''.capitalize, '');
    });

    test('String titleCase', () {
      expect('hello world'.titleCase, 'Hello World');
    });

    test('Duration formatted', () {
      expect(const Duration(minutes: 3, seconds: 45).formatted, '03:45');
    });

    test('List getOrNull', () {
      final list = [1, 2, 3];
      expect(list.getOrNull(1), 2);
      expect(list.getOrNull(5), null);
    });
  });
}
