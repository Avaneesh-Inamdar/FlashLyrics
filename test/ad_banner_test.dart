// ignore_for_file: invalid_use_of_protected_member, implementation_imports

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/widgets/ad_banner_widget.dart';

const _channel = 'plugins.flutter.io/google_mobile_ads';
final _codec = StandardMethodCodec(AdMessageCodec());

/// A banner load request seen by the fake ads plugin.
typedef _Load = ({int adId, String unitId});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<_Load> loads;

  setUp(() {
    loads = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_channel, (message) async {
          final call = _codec.decodeMethodCall(message);
          if (call.method == 'loadBannerAd') {
            loads.add((
              adId: call.arguments['adId'] as int,
              unitId: call.arguments['adUnitId'] as String,
            ));
          }
          return _codec.encodeSuccessEnvelope(null);
        });
  });

  /// Reports "no fill" for [load], as AdMob does when it has no ad to show.
  Future<void> failLoad(_Load load) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _channel,
            _codec.encodeMethodCall(
              MethodCall('onAdEvent', {
                'adId': load.adId,
                'eventName': 'onAdFailedToLoad',
                'loadAdError': LoadAdError(3, 'com.google.android.gms.ads',
                    'No fill.', null),
              }),
            ),
            (_) {},
          );

  Future<ProviderContainer> pumpBanner(
    WidgetTester tester,
    AdBannerWidget banner, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: banner)),
      ),
    );
    await tester.pump();
    return container;
  }

  test('release builds use the real unit, debug builds the test unit', () {
    expect(
      AdBannerWidget.unitIdFor(AdBannerWidget.mainAdUnitId, release: true),
      'ca-app-pub-3987982513065210/2035205150',
    );
    expect(
      AdBannerWidget.unitIdFor(AdBannerWidget.fullscreenAdUnitId, release: true),
      'ca-app-pub-3987982513065210/6598204417',
    );
    expect(
      AdBannerWidget.unitIdFor(AdBannerWidget.mainAdUnitId, release: false),
      'ca-app-pub-3940256099942544/6300978111',
    );
  });

  test('retries wait longer after each failure, up to 10 minutes', () {
    expect(
      [for (var n = 1; n <= 7; n++) AdBannerWidget.retryDelay(n).inMinutes],
      [1, 2, 4, 8, 10, 10, 10],
    );
  });

  testWidgets('release: a failed load retries the real unit, never test ads', (
    tester,
  ) async {
    await pumpBanner(
      tester,
      const AdBannerWidget(
        prodAdUnitId: AdBannerWidget.fullscreenAdUnitId,
        release: true,
      ),
    );
    expect(loads.map((l) => l.unitId), [AdBannerWidget.fullscreenAdUnitId]);

    await failLoad(loads.last);
    await tester.pump();
    expect(loads, hasLength(1), reason: 'no immediate reload');
    expect(find.byType(AdWidget), findsNothing);

    await tester.pump(const Duration(seconds: 59));
    expect(loads, hasLength(1));
    await tester.pump(const Duration(seconds: 2));
    expect(loads, hasLength(2));

    await failLoad(loads.last);
    await tester.pump(const Duration(seconds: 119));
    expect(loads, hasLength(2), reason: 'second retry waits 2 minutes');
    await tester.pump(const Duration(seconds: 2));
    expect(loads, hasLength(3));

    expect(
      loads.map((l) => l.unitId).toSet(),
      {AdBannerWidget.fullscreenAdUnitId},
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('release: an old saved "test ads" setting is ignored', (
    tester,
  ) async {
    // Early versions saved useTestAds=true by default.
    await pumpBanner(
      tester,
      const AdBannerWidget(release: true),
      prefs: {
        'app_settings': jsonEncode({'enableAds': true, 'useTestAds': true}),
      },
    );
    expect(loads.map((l) => l.unitId), [AdBannerWidget.mainAdUnitId]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('debug builds load only the test unit', (tester) async {
    await pumpBanner(tester, const AdBannerWidget());
    expect(loads.map((l) => l.unitId), [AdBannerWidget.testAdUnitId]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('turning ads off stops retries; turning on loads again', (
    tester,
  ) async {
    final container = await pumpBanner(
      tester,
      const AdBannerWidget(release: true),
    );
    await failLoad(loads.single);
    await tester.pump();

    container.read(settingsProvider.notifier).setEnableAds(false);
    await tester.pump(const Duration(minutes: 20));
    expect(loads, hasLength(1));

    container.read(settingsProvider.notifier).setEnableAds(true);
    await tester.pump();
    expect(loads.map((l) => l.unitId), [
      AdBannerWidget.mainAdUnitId,
      AdBannerWidget.mainAdUnitId,
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ads turned off: nothing is requested', (tester) async {
    await pumpBanner(
      tester,
      const AdBannerWidget(release: true),
      prefs: {'app_settings': jsonEncode({'enableAds': false})},
    );
    await tester.pump(const Duration(minutes: 5));
    expect(loads, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
