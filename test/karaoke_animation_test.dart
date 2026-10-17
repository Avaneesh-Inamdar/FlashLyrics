import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/utils/karaoke_timing.dart';
import 'package:lyricx/core/utils/lrc_parser.dart';
import 'package:lyricx/presentation/widgets/karaoke_line.dart';
import 'package:lyricx/presentation/widgets/synced_lyrics_display.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/domain/entities/lyrics.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/widgets/lyrics_display.dart';

void main() {
  testWidgets(
    'line-only karaoke is optional and explicitly labelled estimated',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lyrics = Lyrics(
        id: 'test',
        songId: 'test',
        plainLyrics: 'Stay with me\nNext line',
        lrcLyrics: '[00:01]Stay with me\n[00:04]Next line',
        isSynced: true,
        source: 'Test',
        fetchedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LyricsDisplay(
                  lyrics: lyrics,
                  currentPosition: const Duration(milliseconds: 1500),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Line by line'), findsOneWidget);
      expect(find.byType(KaraokeLine), findsNothing);
      await tester.tap(find.text('Karaoke'));
      await tester.pump();
      expect(find.text('Karaoke · estimated timing'), findsOneWidget);
      expect(find.byType(KaraokeLine), findsOneWidget);
      expect(lyrics.lrcLyrics, isNot(contains('<')));
    await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'estimated timing stays within its line and never invents a final-line endpoint',
    () {
      const line = LrcLine(
        timestamp: Duration(seconds: 2),
        text: 'Stay with me',
      );
      final words = estimateWords(line, const Duration(seconds: 5));
      expect(words.first.start, line.timestamp);
      expect(words.last.end, const Duration(seconds: 5));
      expect(words.map((w) => w.text).join(), line.text);
      expect(estimateWords(line, null), isEmpty);
      expect(estimateWords(line, const Duration(seconds: 1)), isEmpty);
    },
  );

  testWidgets(
    'frame interpolation fills words without rebuilding the lyric list',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SyncedLyricsDisplay(
            lrcContent:
                '[00:01]<00:01>Keep <00:02>the <00:02.5>light <00:03>on<00:04>\n[00:05]Next line',
            currentPosition: Duration(milliseconds: 1200),
            isPlaying: true,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final first = tester.widget<KaraokeLine>(find.byType(KaraokeLine));
      final initialPosition = first.position.value;
      await tester.pump(const Duration(milliseconds: 250));
      final next = tester.widget<KaraokeLine>(find.byType(KaraokeLine));
      expect(identical(first, next), true);
      expect(next.position.value, greaterThan(initialPosition));
      expect(
        wordProgress(next.line.words.first, next.position.value),
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(
        next.position.value,
        lessThanOrEqualTo(const Duration(milliseconds: 2700)),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'word renderer wraps safely at large text scale in $direction',
      (tester) async {
        final position = ValueNotifier(const Duration(milliseconds: 1500));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.8),
                disableAnimations: true,
              ),
              child: Directionality(
                textDirection: direction,
                child: Center(
                  child: SizedBox(
                    width: 180,
                    child: KaraokeLine(
                      line: const LrcLine(
                        timestamp: Duration(seconds: 1),
                        text: 'Longer lyric words wrap naturally',
                        words: [
                          LrcWord(
                            start: Duration(seconds: 1),
                            end: Duration(seconds: 2),
                            text: 'Longer lyric ',
                          ),
                          LrcWord(
                            start: Duration(seconds: 2),
                            end: Duration(seconds: 3),
                            text: 'words wrap naturally',
                          ),
                        ],
                      ),
                      position: position,
                      style: const TextStyle(fontSize: 24),
                      color: Colors.black,
                      reduceMotion: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        position.dispose();
      },
    );
  }
}
