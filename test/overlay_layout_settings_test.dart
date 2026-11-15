import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('floating window layout settings', () {
    test('defaults keep the existing floating window', () {
      const settings = AppSettings();
      expect(settings.floatingOverlayShowHeader, isTrue);
      expect(settings.floatingOverlayTvMode, isFalse);
    });

    test('settings saved by 1.4.4 load with title shown and TV mode off', () {
      final legacy = <String, dynamic>{
        'fontSize': 22.0,
        'floatingLyricsEnabled': true,
        'floatingOverlaySeekEnabled': true,
        'themeMode': 'dark',
      };
      final settings = AppSettings.fromJson(legacy);
      expect(settings.floatingOverlayShowHeader, isTrue);
      expect(settings.floatingOverlayTvMode, isFalse);
      expect(settings.floatingOverlaySeekEnabled, isTrue);
      expect(settings.fontSize, 22.0);
    });

    test('round-trips through JSON and copyWith', () {
      final settings = const AppSettings().copyWith(
        floatingOverlayShowHeader: false,
        floatingOverlayTvMode: true,
      );
      final restored = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(restored.floatingOverlayShowHeader, isFalse);
      expect(restored.floatingOverlayTvMode, isTrue);
      // Unrelated copyWith calls keep the values.
      final other = restored.copyWith(fontSize: 14);
      expect(other.floatingOverlayShowHeader, isFalse);
      expect(other.floatingOverlayTvMode, isTrue);
    });

    test('notifier stores the keys the Android overlay reads', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);
      notifier.setFloatingOverlayShowHeader(false);
      notifier.setFloatingOverlayTvMode(true);
      await Future<void>.delayed(Duration.zero);
      final stored =
          jsonDecode(prefs.getString('app_settings')!) as Map<String, dynamic>;
      // LyricsOverlayService reads these exact names from flutter.app_settings.
      expect(stored['floatingOverlayShowHeader'], isFalse);
      expect(stored['floatingOverlayTvMode'], isTrue);
    });

    test('reset restores the default layout', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs)
        ..setFloatingOverlayShowHeader(false)
        ..setFloatingOverlayTvMode(true)
        ..resetToDefaults();
      expect(notifier.state.floatingOverlayShowHeader, isTrue);
      expect(notifier.state.floatingOverlayTvMode, isFalse);
    });
  });

  testWidgets('Settings toggles hide the title and enable TV mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2600);
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

    Switch switchFor(String title) {
      final row = find.ancestor(
        of: find.text(title),
        matching: find.byType(Row),
      );
      return tester.widget<Switch>(
        find.descendant(of: row.first, matching: find.byType(Switch)),
      );
    }

    expect(find.text('Overlay Song Title'), findsOneWidget);
    expect(find.text('TV Mode'), findsOneWidget);
    expect(switchFor('Overlay Song Title').value, isTrue);
    expect(switchFor('TV Mode').value, isFalse);

    // Hide the title/artist header (the requested toggle).
    switchFor('Overlay Song Title').onChanged!(false);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).floatingOverlayShowHeader, isFalse);
    expect(switchFor('Overlay Song Title').value, isFalse);

    // TV mode always hides the header, so the title switch is locked off.
    switchFor('Overlay Song Title').onChanged!(true);
    switchFor('TV Mode').onChanged!(true);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).floatingOverlayTvMode, isTrue);
    expect(switchFor('Overlay Song Title').value, isFalse);
    expect(switchFor('Overlay Song Title').onChanged, isNull);
    expect(find.text('Hidden while TV Mode is on'), findsOneWidget);

    // Turning TV mode off restores the saved title preference.
    switchFor('TV Mode').onChanged!(false);
    await tester.pumpAndSettle();
    expect(switchFor('Overlay Song Title').value, isTrue);
    expect(switchFor('Overlay Song Title').onChanged, isNotNull);
  });
}
