import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/settings_screen.dart';
import 'package:lyricx/services/support_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final adCalls = <String>[];

  setUp(() {
    adCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.lyricx/media'),
      (_) async => null,
    );
    // The ads plugin never answers, like a device with no ad available.
    messenger.setMockMessageHandler('plugins.flutter.io/google_mobile_ads', (
      message,
    ) async {
      // The plugin uses its own codec; strings are still plain UTF-8 bytes.
      adCalls.add(
        String.fromCharCodes(message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        )),
      );
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  test('release builds request the real unit, debug builds the test unit', () {
    expect(SupportAd.unitId(release: true), SupportAd.prodUnitId);
    expect(SupportAd.unitId(release: false), SupportAd.testUnitId);
    // Tests run in debug mode.
    expect(SupportAd.unitId(), SupportAd.testUnitId);
    expect(SupportAd.prodUnitId, 'ca-app-pub-3987982513065210/5885312023');
    expect(SupportAd.testUnitId, 'ca-app-pub-3940256099942544/5224354917');
  });

  testWidgets('Settings support ad: loads, then explains when none is available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.text('Watch an Ad to Support');
    expect(tile, findsOneWidget);
    expect(
      find.text('Watch a short video ad to support development'),
      findsOneWidget,
    );
    // It is the first thing in Settings, above permissions.
    expect(find.text('SUPPORT DEVELOPMENT'), findsOneWidget);
    expect(
      tester.getTopLeft(tile).dy,
      lessThan(tester.getTopLeft(find.text('PERMISSIONS')).dy),
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading ad…'), findsOneWidget);

    // Tapping again while loading does not start a second request.
    await tester.tap(find.text('Loading ad…'), warnIfMissed: false);
    await tester.pump();
    final loads = adCalls.where((c) => c.contains('loadRewardedAd')).toList();
    expect(loads, hasLength(1));
    expect(loads.single, contains(SupportAd.testUnitId));
    expect(loads.single, isNot(contains(SupportAd.prodUnitId)));

    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.text('Loading ad…'), findsNothing);
    expect(find.textContaining('No ad is available right now'), findsOneWidget);

    // The tile works again afterwards.
    await tester.tap(tile, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading ad…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
  });
}
