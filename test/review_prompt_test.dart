import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/services/review_service.dart';
import 'package:lyricx/presentation/widgets/review_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 20);
  const rate = 'Rate on Google Play';
  const later = 'Remind me later';
  const never = "Don't remind me again";

  Future<ReviewService> ready({Future<bool> Function(Uri)? launch}) async {
    SharedPreferences.setMockInitialValues({});
    final service = ReviewService(
      await SharedPreferences.getInstance(),
      clock: () => now,
      launch: launch,
    );
    await service.startSession();
    for (final id in ['a', 'b', 'c']) {
      service.recordLyrics(id);
    }
    return service;
  }

  ReviewService restart(SharedPreferences prefs, DateTime at) =>
      ReviewService(prefs, clock: () => at);

  test('asks after three different songs, not repeats of one', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = ReviewService(prefs, clock: () => now);
    await service.startSession();
    for (final id in ['a', 'a', 'a', '']) {
      service.recordLyrics(id);
    }
    expect(service.songCount, 1);
    expect(service.shouldPrompt, false);
    service.recordLyrics('b');
    expect(service.shouldPrompt, false);
    service.recordLyrics('c');
    expect(service.songCount, 3);
    expect(service.shouldPrompt, true);
  });

  test('song count carries across app restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = restart(prefs, now);
    await first.startSession();
    first
      ..recordLyrics('a')
      ..recordLyrics('b');
    expect(first.shouldPrompt, false);
    final second = restart(prefs, now);
    await second.startSession();
    second.recordLyrics('c');
    expect(second.shouldPrompt, true);
  });

  test('not before the session starts, and only once per session', () async {
    SharedPreferences.setMockInitialValues({'review_song_count': 5});
    final service = ReviewService(
      await SharedPreferences.getInstance(),
      clock: () => now,
    );
    expect(service.shouldPrompt, false);
    await service.startSession();
    expect(service.shouldPrompt, true);
    service.markShown();
    expect(service.shouldPrompt, false);
  });

  test('remind later waits for more songs and a day; never persists', () async {
    final service = await ready();
    await service.later();
    final prefs = await SharedPreferences.getInstance();

    // Next day but no new songs yet.
    final nextDay = restart(prefs, now.add(const Duration(days: 2)));
    await nextDay.startSession();
    for (final id in ['d', 'e', 'f']) {
      nextDay.recordLyrics(id);
    }
    expect(nextDay.shouldPrompt, false);
    nextDay.recordLyrics('g');
    expect(nextDay.shouldPrompt, true);

    // Enough songs but the same day.
    SharedPreferences.setMockInitialValues({});
    final sameDayPrefs = await SharedPreferences.getInstance();
    final s = restart(sameDayPrefs, now);
    await s.startSession();
    for (final id in ['a', 'b', 'c']) {
      s.recordLyrics(id);
    }
    await s.later();
    final soon = restart(sameDayPrefs, now.add(const Duration(hours: 2)));
    await soon.startSession();
    for (final id in ['1', '2', '3', '4', '5']) {
      soon.recordLyrics(id);
    }
    expect(soon.shouldPrompt, false);

    await nextDay.never();
    final year = restart(prefs, now.add(const Duration(days: 365)));
    await year.startSession();
    for (final id in ['x', 'y', 'z']) {
      year.recordLyrics(id);
    }
    expect(year.shouldPrompt, false);
  });

  test(
    'review link tries Play first then browser, without crashing on failure',
    () async {
      final calls = <Uri>[];
      final service = await ready(
        launch: (uri) async {
          calls.add(uri);
          if (uri.scheme == 'market') throw Exception();
          return true;
        },
      );
      expect(await service.openReviewPage(), true);
      expect(calls.map((uri) => uri.scheme), ['market', 'https']);
      expect(calls.first.queryParameters['id'], 'music.flashlyrics.app');
      final unavailable = await ready(launch: (_) async => false);
      expect(await unavailable.openReviewPage(), false);
    },
  );

  for (final choice in [later, never, rate, 'Dismiss', 'Failed launch']) {
    testWidgets('rating prompt action: $choice', (tester) async {
      var launched = 0;
      final service = await ready(
        launch: (_) async {
          launched++;
          return choice != 'Failed launch';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showReviewPrompt(context, service),
                child: const Text('Prompt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prompt'));
      await tester.pumpAndSettle();
      expect(find.text('Enjoying FlashLyrics?'), findsOneWidget);
      expect(find.text(later), findsOneWidget);
      expect(find.text(never), findsOneWidget);
      expect(find.text(rate), findsOneWidget);
      if (choice == 'Dismiss') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester.tap(find.text(choice == 'Failed launch' ? rate : choice));
      }
      await tester.pumpAndSettle();
      expect(find.text('Enjoying FlashLyrics?'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(service.shouldPrompt, false);
      if (choice == never || choice == rate) {
        expect(prefs.getBool('review_disabled'), true);
      } else {
        expect(prefs.getBool('review_disabled'), isNull);
        expect(
          prefs.getInt('review_next_prompt'),
          now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        );
        expect(prefs.getInt('review_next_song_count'), 3 + 4);
      }
      expect(launched, choice == rate ? 1 : (choice == 'Failed launch' ? 2 : 0));
      if (choice == 'Failed launch') {
        expect(
          find.textContaining('Could not open Google Play'),
          findsOneWidget,
        );
      }
    });
  }
}
