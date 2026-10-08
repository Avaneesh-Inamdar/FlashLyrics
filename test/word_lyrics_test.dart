import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/utils/lrc_parser.dart';
import 'package:lyricx/core/utils/word_lyrics.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/presentation/widgets/synced_lyrics_display.dart';

const wordFixture = '''version: '1.0'
lines:
  - text: 'Hello दुनिया'
    start_ms: 1000
    words:
      - text: 'Hello '
        start_ms: 1000
        end_ms: 1400
      - text: 'दुनिया'
        start_ms: 1600
        end_ms: 2200
  - text: 'Next line'
    start_ms: 3000
''';

void main() {
  test(
    'LRCLIB word timings survive conversion and offline serialization',
    () async {
      final content = wordSyncedLrc({'lyricsfile': wordFixture});
      expect(content, isNotNull);
      final cached = LyricsModel.fromJson(
        LyricsModel(
          id: 'test',
          songId: 'test',
          plainLyrics: 'Hello दुनिया\nNext line',
          lrcLyrics: content,
          isSynced: true,
          source: 'LRCLIB',
          fetchedAt: DateTime(2026),
        ).toJson(),
      );
      final parsed = await LrcParser.parse(cached.lrcLyrics!);
      expect(parsed.lines.first.text, 'Hello दुनिया');
      expect(parsed.lines.first.words.length, 2);
      expect(parsed.lines.first.words.last.start.inMilliseconds, 1600);
      expect(parsed.lines.first.words.first.end!.inMilliseconds, 1400);
      expect(parsed.lines.last.words, isEmpty);
    },
  );

  test('bad optional timing data preserves fast line-sync fallback', () {
    for (final raw in [
      '[broken',
      'lines: nope',
      wordFixture.replaceFirst('1600', '900'),
    ]) {
      expect(
        wordSyncedLrc({'lyricsfile': raw, 'syncedLyrics': '[00:01]Fallback'}),
        '[00:01]Fallback',
      );
    }
    expect(wordSyncedLrc({'plainLyrics': 'Plain'}), isNull);
  });

  test(
    'enhanced LRC handles repeated lines, offsets and tag-free text',
    () async {
      final parsed = await LrcParser.parse(
        '[offset:100]\n[00:01][00:05]<00:01.0>One <00:01.5>two<00:02>',
      );
      expect(parsed.lines.map((l) => l.text), ['One two', 'One two']);
      expect(parsed.lines.last.words.last.start.inMilliseconds, 5500);
      expect(parsed.getLineIndexAtTime(const Duration(milliseconds: 1050)), -1);
      expect(parsed.getLineIndexAtTime(const Duration(milliseconds: 1100)), 0);
    },
  );

  testWidgets('word highlight follows position, pause and backward seek', (
    tester,
  ) async {
    final lrc = wordSyncedLrc({'lyricsfile': wordFixture})!;
    Future<void> show(int ms) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 400,
            child: SyncedLyricsDisplay(
              lrcContent: lrc,
              currentPosition: Duration(milliseconds: ms),
              isPlaying: false,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    Color? color(int index) {
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('word-synced-line')),
      );
      return (text.textSpan! as TextSpan).children![index].style?.color;
    }

    await show(1100);
    final firstColor = color(0);
    expect(color(1), isNot(firstColor));
    await show(1700);
    expect(color(1), firstColor);
    await tester.pump(const Duration(seconds: 5));
    expect(color(1), firstColor); // Paused: no drifting clock.
    await show(1100);
    expect(color(0), firstColor);
    await tester.pumpWidget(const SizedBox());
  });
}
