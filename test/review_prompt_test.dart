import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/services/review_service.dart';
import 'package:lyricx/presentation/widgets/review_prompt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 20);
  Future<ReviewService> ready({Future<bool> Function(Uri)? launch}) async {
    SharedPreferences.setMockInitialValues({
      'review_first_seen': now
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch,
      'review_sessions': 2,
    });
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

  test('waits for real use, distinct songs and multiple sessions', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = ReviewService(prefs, clock: () => now);
    await service.startSession();
    await service.startSession();
    for (final id in ['a', 'a', 'a']) {
      service.recordLyrics(id);
    }
    expect(service.shouldPrompt, false);
    expect(prefs.getInt('review_sessions'), 1);
    final eligible = await ready();
    expect(eligible.shouldPrompt, true);
  });
  test('ask later and never persist across restart', () async {
    final service = await ready();
    await service.later();
    final prefs = await SharedPreferences.getInstance();
    final restart = ReviewService(
      prefs,
      clock: () => now.add(const Duration(days: 13)),
    );
    await restart.startSession();
    for (final id in ['a', 'b', 'c']) {
      restart.recordLyrics(id);
    }
    expect(restart.shouldPrompt, false);
    final later = ReviewService(
      prefs,
      clock: () => now.add(const Duration(days: 15)),
    );
    await later.startSession();
    for (final id in ['a', 'b', 'c']) {
      later.recordLyrics(id);
    }
    expect(later.shouldPrompt, true);
    await later.never();
    final never = ReviewService(
      prefs,
      clock: () => now.add(const Duration(days: 365)),
    );
    await never.startSession();
    for (final id in ['a', 'b', 'c']) {
      never.recordLyrics(id);
    }
    expect(never.shouldPrompt, false);
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
      final unavailable = await ready(launch: (_) async => false);
      expect(await unavailable.openReviewPage(), false);
    },
  );

  for (final choice in [
    'Ask me later',
    'Never',
    'Leave a review now',
    'Dismiss',
    'Failed launch',
  ]) {
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
      expect(find.text('Ask me later'), findsOneWidget);
      expect(find.text('Never'), findsOneWidget);
      expect(find.text('Leave a review now'), findsOneWidget);
      if (choice == 'Dismiss') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester.tap(
          find.text(choice == 'Failed launch' ? 'Leave a review now' : choice),
        );
      }
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(service.shouldPrompt, false);
      if (choice == 'Never' || choice == 'Leave a review now')
        expect(prefs.getBool('review_disabled'), true);
      else
        expect(
          prefs.getInt('review_next_prompt'),
          now.add(const Duration(days: 14)).millisecondsSinceEpoch,
        );
      if (choice == 'Failed launch') {
        expect(launched, 2);
        expect(
          find.textContaining('Could not open Google Play'),
          findsOneWidget,
        );
      }
    });
  }
}
