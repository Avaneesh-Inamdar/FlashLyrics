import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/app_filter_screen.dart';
import 'package:lyricx/services/media_detection_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.lyricx/media');
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methodCalls.add(call);
      if (call.method == 'getInstalledApps') {
        return [
          {
            'packageName': 'org.leetzone.android.yatsewidgetfree',
            'appName': 'Yatse',
            'isSeenMedia': true,
          },
          {
            'packageName': 'com.spotify.music',
            'appName': 'Spotify',
            'isSeenMedia': true,
          },
          {
            'packageName': 'com.google.android.apps.youtube.music',
            'appName': 'YouTube Music',
            'isSeenMedia': false,
          },
        ];
      }
      if (call.method == 'setAppFilter') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AppSettings app filter serialization', () {
    test('defaults to off with empty blacklist and whitelist', () {
      const settings = AppSettings();
      expect(settings.appFilterMode, AppFilterMode.off);
      expect(settings.blacklistedApps, isEmpty);
      expect(settings.whitelistedApps, isEmpty);
    });

    test('migrates legacy JSON without app filter keys', () {
      final migrated = AppSettings.fromJson({'fontSize': 20.0});
      expect(migrated.appFilterMode, AppFilterMode.off);
      expect(migrated.blacklistedApps, isEmpty);
      expect(migrated.whitelistedApps, isEmpty);
    });

    test('round-trips blacklist and whitelist through JSON', () {
      const original = AppSettings(
        appFilterMode: AppFilterMode.blacklist,
        blacklistedApps: ['org.leetzone.android.yatsewidgetfree'],
        whitelistedApps: ['com.spotify.music'],
      );
      final decoded = AppSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.appFilterMode, AppFilterMode.blacklist);
      expect(
        decoded.blacklistedApps,
        ['org.leetzone.android.yatsewidgetfree'],
      );
      expect(decoded.whitelistedApps, ['com.spotify.music']);
    });
  });

  group('SettingsNotifier app filter actions', () {
    test('updates mode, toggles packages, clears, and syncs to native', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs);

      await notifier.setAppFilterMode(AppFilterMode.blacklist);
      expect(notifier.state.appFilterMode, AppFilterMode.blacklist);

      await notifier.toggleAppInFilter(
        'org.leetzone.android.yatsewidgetfree',
        isBlacklist: true,
      );
      expect(
        notifier.state.blacklistedApps,
        ['org.leetzone.android.yatsewidgetfree'],
      );

      // Toggle again removes it
      await notifier.toggleAppInFilter(
        'org.leetzone.android.yatsewidgetfree',
        isBlacklist: true,
      );
      expect(notifier.state.blacklistedApps, isEmpty);

      // Whitelist toggle + clear
      await notifier.setAppFilterMode(AppFilterMode.whitelist);
      await notifier.toggleAppInFilter('com.spotify.music', isBlacklist: false);
      expect(notifier.state.whitelistedApps, ['com.spotify.music']);
      await notifier.clearAppFilterList(isBlacklist: false);
      expect(notifier.state.whitelistedApps, isEmpty);

      final filterCalls =
          methodCalls.where((c) => c.method == 'setAppFilter').toList();
      expect(filterCalls, isNotEmpty);
      expect((filterCalls.last.arguments as Map)['mode'], 'whitelist');
    });
  });

  group('MediaDetectionService app filter channel', () {
    test('getInstalledApps parses native app list', () async {
      final apps = await MediaDetectionService.getInstalledApps();
      expect(apps, hasLength(3));
      expect(apps.first.appName, 'Yatse');
      expect(apps.first.isSeenMedia, isTrue);
    });
  });

  group('AppFilterScreen widget', () {
    testWidgets('switches modes, searches, and toggles blacklisted app',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: AppFilterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Default mode is All
      expect(find.text('Filter Mode'), findsOneWidget);
      expect(
        find.textContaining('All supported music & media apps are detected'),
        findsOneWidget,
      );

      // Switch to Blacklist
      await tester.tap(find.text('Blacklist'));
      await tester.pumpAndSettle();

      expect(find.text('Yatse'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Detected'), findsNWidgets(2));

      // Toggle Yatse into blacklist
      await tester.tap(find.text('Yatse'));
      await tester.pumpAndSettle();

      final saved = AppSettings.fromJson(
        jsonDecode(prefs.getString('app_settings')!) as Map<String, dynamic>,
      );
      expect(saved.appFilterMode, AppFilterMode.blacklist);
      expect(
        saved.blacklistedApps,
        ['org.leetzone.android.yatsewidgetfree'],
      );

      // Search filters the list
      await tester.enterText(find.byType(TextField), 'Spot');
      await tester.pumpAndSettle();
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text('Yatse'), findsNothing);

      // Switch to Whitelist shows empty-whitelist banner
      await tester.tap(find.text('Whitelist'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Whitelist is empty'),
        findsOneWidget,
      );
    });
  });
}
