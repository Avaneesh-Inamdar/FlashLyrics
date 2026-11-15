import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/settings_screen.dart';
import 'package:lyricx/presentation/widgets/support_highlight.dart';
import 'package:lyricx/presentation/widgets/support_prompt.dart';
import 'package:lyricx/services/support_prompt_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day1 = DateTime(2026, 11, 15, 9);

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.lyricx/media'),
      (_) async => null,
    );
    messenger.setMockMessageHandler(
      'plugins.flutter.io/google_mobile_ads',
      (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  SupportPromptService at(SharedPreferences prefs, DateTime time) =>
      SupportPromptService(prefs, clock: () => time);

  group('once a day on app open', () {
    test('never on the first launch, then once a day', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(at(prefs, day1).shouldShowOnOpen(), false);
      // Reopened later the same day.
      expect(at(prefs, day1.add(const Duration(hours: 5))).shouldShowOnOpen(), false);
      final day2 = at(prefs, day1.add(const Duration(days: 1)));
      expect(day2.shouldShowOnOpen(), true);
      // Only once per app run.
      expect(day2.shouldShowOnOpen(), false);
    });

    test('remind later and OK wait a day; no thanks stops for good', () async {
      SharedPreferences.setMockInitialValues({
        'support_prompt_next': day1.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final today = at(prefs, day1);
      expect(today.shouldShowOnOpen(), true);
      await today.snooze();
      expect(at(prefs, day1.add(const Duration(hours: 23))).shouldShowOnOpen(), false);
      expect(at(prefs, day1.add(const Duration(days: 1))).shouldShowOnOpen(), true);
      await today.never();
      expect(at(prefs, day1.add(const Duration(days: 30))).shouldShowOnOpen(), false);
    });
  });

  Future<ProviderContainer> pumpPrompt(
    WidgetTester tester, {
    required bool adsOn,
  }) async {
    SharedPreferences.setMockInitialValues({
      'support_prompt_next': day1.millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider.notifier).setEnableAds(adsOn);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showSupportPrompt(context, ref),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('FlashLyrics is free'), findsOneWidget);
    expect(find.text('No thanks'), findsOneWidget);
    expect(find.text('Remind me later'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    return container;
  }

  testWidgets('ads off: asks to turn ads on; OK opens Settings at the ads toggle', (
    tester,
  ) async {
    final container = await pumpPrompt(tester, adsOn: false);
    expect(find.textContaining('Please turn ads on'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('FlashLyrics is free'), findsNothing);
    expect(container.read(tabIndexProvider), 3);
    expect(container.read(settingsHighlightProvider), SupportHighlight.adsToggle);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getBool('support_prompt_disabled'), isNull);
    expect(
      prefs.getInt('support_prompt_next'),
      greaterThan(DateTime.now().add(const Duration(hours: 23)).millisecondsSinceEpoch),
    );
  });

  testWidgets('ads on: asks to watch an ad; OK highlights Watch an Ad', (
    tester,
  ) async {
    final container = await pumpPrompt(tester, adsOn: true);
    expect(find.textContaining('watching a short ad'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(container.read(settingsHighlightProvider), SupportHighlight.watchAd);
  });

  testWidgets('No thanks stops the prompt and stays on the current tab', (
    tester,
  ) async {
    final container = await pumpPrompt(tester, adsOn: false);
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
    expect(container.read(tabIndexProvider), 0);
    expect(container.read(settingsHighlightProvider), isNull);
    expect(
      container.read(sharedPreferencesProvider).getBool('support_prompt_disabled'),
      true,
    );
  });

  testWidgets('Remind me later only snoozes', (tester) async {
    final container = await pumpPrompt(tester, adsOn: false);
    await tester.tap(find.text('Remind me later'));
    await tester.pumpAndSettle();
    final prefs = container.read(sharedPreferencesProvider);
    expect(container.read(tabIndexProvider), 0);
    expect(prefs.getBool('support_prompt_disabled'), isNull);
    expect(
      prefs.getInt('support_prompt_next'),
      greaterThan(day1.millisecondsSinceEpoch),
    );
  });

  testWidgets('Settings highlights the ads toggle when asked', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn Ads On/Off'), findsOneWidget);

    BoxDecoration glowOf(String title) {
      final target = find.ancestor(
        of: find.text(title),
        matching: find.byType(SupportHighlightTarget),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: target, matching: find.byType(DecoratedBox)).first,
      );
      return box.decoration as BoxDecoration;
    }

    expect(glowOf('Turn Ads On/Off').border!.top.color.a, 0);
    container.read(settingsHighlightProvider.notifier).state =
        SupportHighlight.adsToggle;
    var peak = 0.0;
    var otherPeak = 0.0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final a = glowOf('Turn Ads On/Off').border!.top.color.a;
      if (a > peak) peak = a;
      final b = glowOf('Watch an Ad to Support').border!.top.color.a;
      if (b > otherPeak) otherPeak = b;
    }
    expect(peak, greaterThan(0.8));
    expect(otherPeak, 0);
    // The request is consumed so it does not replay later.
    expect(container.read(settingsHighlightProvider), isNull);
    // It fades out again after a short hold.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(glowOf('Turn Ads On/Off').border!.top.color.a, 0);
  });
}
