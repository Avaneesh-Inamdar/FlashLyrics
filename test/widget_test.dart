import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/main.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/domain/entities/lyrics.dart';
import 'package:lyricx/core/utils/lrc_parser.dart';
import 'package:lyricx/core/utils/helpers.dart';
import 'package:lyricx/presentation/providers/song_offset_provider.dart';
import 'package:lyricx/presentation/providers/providers.dart';

void main() {
  group('FlashLyrics App Tests', () {
    testWidgets('App smoke test - starts with title', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set up mock SharedPreferences
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Build our app and trigger a frame
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const FlashLyricsApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Verify that the app widget builds
      expect(find.byType(FlashLyricsApp), findsOneWidget);
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

    test('stripTimeTags removes all types of timestamps', () {
      expect(LrcParser.stripTimeTags('[00:12.34]Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('[00:12:34]Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('[00:12]Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('<00:12.34>Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('(00:12.34)Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('01:23 Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('[00:12.34][00:15.00]Hello world'), 'Hello world');
      expect(LrcParser.stripTimeTags('[00:12.34] <00:12.34> Hello <00:13.50> world'), 'Hello world');
      expect(LrcParser.stripTimeTags('[ar:Artist]Hello world'), 'Hello world');
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

  group('Song Offset Tests', () {
    test('generateSongKey creates consistent sanitized keys', () {
      expect(
        generateSongKey(artist: 'The Beatles', title: 'Hey Jude'),
        'the_beatles_hey_jude',
      );
      expect(
        generateSongKey(songId: 'The_Beatles_Hey_Jude'),
        'the_beatles_hey_jude',
      );
    });

    test('SongOffsetNotifier saves and retrieves per-song offset', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SongOffsetNotifier(prefs);

      expect(notifier.getEffectiveOffset(songKey: 'song_1', globalDefault: 0), 0);

      await notifier.setSongOffset('song_1', 350);
      expect(notifier.getEffectiveOffset(songKey: 'song_1', globalDefault: 0), 350);
      expect(notifier.getEffectiveOffset(songKey: 'song_2', globalDefault: 0), 0);

      // Verify persistence by recreating notifier with same prefs
      final newNotifier = SongOffsetNotifier(prefs);
      expect(newNotifier.getEffectiveOffset(songKey: 'song_1', globalDefault: 0), 350);
    });
  });
}
