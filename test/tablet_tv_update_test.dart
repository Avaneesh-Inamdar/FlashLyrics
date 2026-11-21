import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/utils/device_profile.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/presentation/widgets/update_available_dialog.dart';
import 'package:lyricx/services/update_check_service.dart';

class _FakeUpdates extends UpdateCheckService {
  _FakeUpdates(this.status);
  final UpdateStatus status;
  int calls = 0;
  @override
  Future<UpdateStatus> check() async {
    calls++;
    return status;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpdateCheckService', () {
    test('reports an available update', () async {
      final s = UpdateCheckService(
        query: () async => {'available': true, 'versionCode': 22},
      );
      expect(await s.check(), UpdateStatus.available);
    });
    test('reports up to date', () async {
      final s = UpdateCheckService(query: () async => {'available': false});
      expect(await s.check(), UpdateStatus.upToDate);
    });
    test('unknown when Play fails, answers nothing or times out', () async {
      expect(
        await UpdateCheckService(query: () async => throw StateError('x'))
            .check(),
        UpdateStatus.unknown,
      );
      expect(
        await UpdateCheckService(query: () async => null).check(),
        UpdateStatus.unknown,
      );
      expect(
        await UpdateCheckService(
          query: () => Future.delayed(const Duration(seconds: 5)),
          timeout: const Duration(milliseconds: 50),
        ).check(),
        UpdateStatus.unknown,
      );
    });
  });

  group('update notice', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('tells the user to download from the Play Store', (
      tester,
    ) async {
      final ctx = await pumpHost(tester);
      Uri? opened;
      final shown = maybeShowUpdateNotice(
        ctx,
        service: _FakeUpdates(UpdateStatus.available),
        openUrl: (u) async {
          opened = u;
          return true;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsOneWidget);
      expect(find.textContaining('download it from the Play Store'),
          findsOneWidget);
      await tester.tap(find.text('Open Play Store'));
      await tester.pumpAndSettle();
      expect(opened.toString(), playStoreUrl);
      expect(playStoreUrl, contains('id=music.flashlyrics.app'));
      expect(find.text('New version available'), findsNothing);
      expect(await shown, true);
    });

    testWidgets('Later just closes it', (tester) async {
      final ctx = await pumpHost(tester);
      var opened = false;
      final shown = maybeShowUpdateNotice(
        ctx,
        service: _FakeUpdates(UpdateStatus.available),
        openUrl: (_) async => opened = true,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('New version available'), findsNothing);
      expect(opened, false);
      expect(await shown, true);
    });

    for (final status in [UpdateStatus.upToDate, UpdateStatus.unknown]) {
      testWidgets('nothing is shown when $status', (tester) async {
        final ctx = await pumpHost(tester);
        final shown = await maybeShowUpdateNotice(
          ctx,
          service: _FakeUpdates(status),
        );
        await tester.pumpAndSettle();
        expect(shown, false);
        expect(find.text('New version available'), findsNothing);
      });
    }
  });

  group('DeviceProfile', () {
    test('form factor', () {
      expect(DeviceProfile.formFactor(const Size(390, 800), isTv: false),
          FormFactor.phone);
      expect(DeviceProfile.formFactor(const Size(800, 1280), isTv: false),
          FormFactor.tablet);
      expect(DeviceProfile.formFactor(const Size(1280, 800), isTv: false),
          FormFactor.tablet);
      expect(DeviceProfile.formFactor(const Size(960, 540), isTv: true),
          FormFactor.tv);
    });
    test('phones stay portrait; tablets and TV rotate', () {
      expect(DeviceProfile.orientationsFor(FormFactor.phone),
          [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      for (final f in [FormFactor.tablet, FormFactor.tv]) {
        expect(DeviceProfile.orientationsFor(f),
            contains(DeviceOrientation.landscapeLeft));
      }
    });
  });

  group('MainScreen layouts', () {
    late List<String> adMessages;

    Future<void> pumpMain(
      WidgetTester tester, {
      required Size size,
      bool tv = false,
      _FakeUpdates? updates,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      adMessages = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.lyricx/media'),
        (_) async => null,
      );
      messenger.setMockMessageHandler('plugins.flutter.io/google_mobile_ads', (
        m,
      ) async {
        adMessages.add(String.fromCharCodes(m!.buffer.asUint8List()));
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      });
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      SharedPreferences.setMockInitialValues({
        'notification_float_tip_seen_v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            isTelevisionProvider.overrideWithValue(tv),
            updateCheckServiceProvider.overrideWithValue(
              updates ?? _FakeUpdates(UpdateStatus.unknown),
            ),
          ],
          child: const MaterialApp(home: MainScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('phone: bottom navigation bar, no rail', (tester) async {
      await pumpMain(tester, size: const Size(390, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('tablet: navigation rail, no bottom bar, tabs switch', (
      tester,
    ) async {
      await pumpMain(tester, size: const Size(1280, 800));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('PERMISSIONS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('tablet portrait 800 wide also gets the rail', (tester) async {
      await pumpMain(tester, size: const Size(800, 1280));
      expect(find.byType(NavigationRail), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('TV: extended rail, no ads, no support section', (
      tester,
    ) async {
      await pumpMain(tester, size: const Size(960, 540), tv: true);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, true);
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SUPPORT DEVELOPMENT'), findsNothing);
      expect(find.text('Watch an Ad to Support'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      expect(adMessages.where((m) => m.contains('loadBannerAd')), isEmpty);
    });

    testWidgets('phone and tablet still show the support section', (
      tester,
    ) async {
      await pumpMain(tester, size: const Size(1280, 800));
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SUPPORT DEVELOPMENT'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('checks Play shortly after opening and shows the notice', (
      tester,
    ) async {
      final updates = _FakeUpdates(UpdateStatus.available);
      await pumpMain(tester, size: const Size(390, 800), updates: updates);
      expect(find.text('New version available'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 300));
      expect(updates.calls, 1);
      expect(find.text('New version available'), findsOneWidget);
      expect(find.text('Open Play Store'), findsOneWidget);
    });

    testWidgets('no notice when already up to date', (tester) async {
      final updates = _FakeUpdates(UpdateStatus.upToDate);
      await pumpMain(tester, size: const Size(390, 800), updates: updates);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 300));
      expect(updates.calls, 1);
      expect(find.text('New version available'), findsNothing);
    });
  });
}

