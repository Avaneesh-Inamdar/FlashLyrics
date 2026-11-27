import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/constants/app_constants.dart';
import 'package:lyricx/core/utils/device_profile.dart';
import 'package:lyricx/core/utils/ttml_lyrics.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/app_tour_screen.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/presentation/widgets/ad_banner_widget.dart';
import 'package:lyricx/presentation/widgets/tv_pointer.dart';
import 'package:lyricx/services/update_check_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final String? Function(Uri uri) handler;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final body = handler(options.uri);
    if (body == null) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoUpdates extends UpdateCheckService {
  @override
  Future<UpdateStatus> check() async => UpdateStatus.unknown;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('version', () {
    test('is 1.5.2', () => expect(AppConstants.appVersion, '1.5.2'));
  });

  group('TTML', () {
    test('parses clock values', () {
      expect(parseTtmlTime('33.642'), 33642);
      expect(parseTtmlTime('1:02.5'), 62500);
      expect(parseTtmlTime('01:02:03.5'), 3723500);
      expect(parseTtmlTime('12.5s'), 12500);
      expect(parseTtmlTime('500ms'), 500);
      expect(parseTtmlTime('abc'), isNull);
    });

    test('flattens word spans into synced lines', () {
      const ttml =
          '<tt><body><div>'
          '<p begin="33.642" end="35.9"><span begin="33.642">Look</span> '
          '<span begin="33.9">at</span> <span begin="34">the stars</span></p>'
          '<p begin="1:05.0" end="70">Tom &amp; Jerry</p>'
          '<p begin="70" end="71">   </p>'
          '</div></body></tt>';
      expect(ttmlToLrc(ttml), '[00:33.64]Look at the stars\n[01:05.00]Tom & Jerry');
      expect(ttmlToLrc('<tt></tt>'), isNull);
    });
  });

  group('new key-free sources', () {
    test('are in the default order and Settings migrates old saved orders', () {
      expect(ApiConstants.apiPriority, containsAll(['kugou', 'betterlyrics']));
      final fresh = AppSettings.fromJson({});
      expect(fresh.providerPriority, containsAll(['kugou', 'betterlyrics']));
      final old = AppSettings.fromJson({
        'providerPriority': ['netease', 'lrclib'],
      });
      expect(old.providerPriority.take(2), ['netease', 'lrclib']);
      expect(old.providerPriority, containsAll(['kugou', 'betterlyrics']));
      expect(AppSettings.providerNames['kugou'], isNotNull);
      expect(AppSettings.providerNames['betterlyrics'], isNotNull);
    });

    LyricsRemoteDataSource source(_Adapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      return LyricsRemoteDataSource(dio);
    }

    test('KuGou: search, pick lyrics, decode base64 LRC', () async {
      final lrc = '﻿[00:01.00]Look at the stars\n[00:05.00]Look how they shine';
      final adapter = _Adapter((uri) {
        if (uri.host == 'mobileservice.kugou.com') {
          return jsonEncode({
            'data': {
              'info': [
                {
                  'hash': 'abc',
                  'songname': 'Yellow',
                  'singername': 'Coldplay',
                  'duration': 266,
                },
              ],
            },
          });
        }
        if (uri.host == 'lyrics.kugou.com' && uri.path == '/search') {
          return jsonEncode({
            'candidates': [
              {'id': '1', 'accesskey': 'k'},
            ],
          });
        }
        if (uri.host == 'lyrics.kugou.com' && uri.path == '/download') {
          return jsonEncode({'content': base64Encode(utf8.encode(lrc))});
        }
        return null;
      });
      final result = await source(
        adapter,
      ).fetchAllParallel('Coldplay', 'Yellow', providerPriority: ['kugou']);
      expect(result, isNotNull);
      expect(result!.source, 'KuGou');
      expect(result.isSynced, true);
      expect(result.plainLyrics, contains('Look at the stars'));
      expect(result.lrcLyrics, startsWith('[00:01.00]'));
    });

    test('KuGou: a different song is rejected', () async {
      final adapter = _Adapter((uri) {
        if (uri.host == 'mobileservice.kugou.com') {
          return jsonEncode({
            'data': {
              'info': [
                {'hash': 'x', 'songname': 'Other Thing', 'singername': 'Nobody'},
              ],
            },
          });
        }
        return null;
      });
      final result = await source(
        adapter,
      ).fetchAllParallel('Coldplay', 'Yellow', providerPriority: ['kugou']);
      expect(result, isNull);
    });

    test('BetterLyrics: TTML becomes synced lyrics', () async {
      final adapter = _Adapter((uri) {
        if (uri.host == 'lyrics-api.boidu.dev') {
          return jsonEncode({
            'ttml':
                '<tt><body><div><p begin="1.0" end="2.0"><span>Hello</span></p>'
                '<p begin="3.0" end="4.0"><span>World</span></p></div></body></tt>',
          });
        }
        return null;
      });
      final result = await source(
        adapter,
      ).fetchAllParallel('Adele', 'Hello', providerPriority: ['betterlyrics']);
      expect(result, isNotNull);
      expect(result!.source, 'BetterLyrics');
      expect(result.isSynced, true);
      expect(result.lrcLyrics, '[00:01.00]Hello\n[00:03.00]World');
    });

    test('search also queries the new sources', () async {
      final adapter = _Adapter((uri) {
        if (uri.host == 'lyrics-api.boidu.dev') {
          return jsonEncode({
            'ttml': '<tt><body><p begin="1.0">Line one</p></body></tt>',
          });
        }
        return null;
      });
      final results = await source(adapter).searchByQuery(
        'Adele - Hello',
        providerPriority: ['betterlyrics'],
      );
      expect(results.map((r) => r.source), contains('BetterLyrics'));
    });
  });

  group('tablet ads', () {
    test('tablets get the leaderboard, phones the small banner', () {
      expect(AdBannerWidget.sizeFor(const Size(1280, 800)), AdSize.leaderboard);
      expect(AdBannerWidget.sizeFor(const Size(800, 1280)), AdSize.leaderboard);
      expect(AdBannerWidget.sizeFor(const Size(390, 800)), AdSize.banner);
      // A narrow tablet window cannot fit 728dp.
      expect(AdBannerWidget.sizeFor(const Size(700, 1000)), AdSize.banner);
    });

    testWidgets('3-button navigation inset keeps the ad above the buttons', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await _pumpMain(tester, tv: false);
      final rail = tester.getRect(find.byType(NavigationRail));
      final pagesBottom = tester
          .getRect(find.byType(IndexedStack))
          .bottom;
      expect(pagesBottom, lessThanOrEqualTo(800 - 48));
      expect(rail.bottom, lessThanOrEqualTo(800));
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('app tour', () {
    testWidgets('shows on first run, once per version, and can be replayed', (
      tester,
    ) async {
      await _pumpMain(tester, tv: false, autoTour: true, prefs: const {});
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppTourScreen), findsOneWidget);
      expect(find.text('Welcome to FlashLyrics'), findsOneWidget);

      // Walk through every page.
      for (var i = 0; i < 10 && find.text('Next').evaluate().isNotEmpty; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text('Get started'), findsOneWidget); // reached the end
      await tester.tap(find.text('Get started'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AppTourScreen), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(appTourSeenKey), AppConstants.appVersion);
      expect(shouldShowAppTour(prefs), false);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('mentions full player, Float and the notification panel', (
      tester,
    ) async {
      await _pumpMain(tester, tv: false, autoTour: true, prefs: const {});
      await tester.pump(const Duration(milliseconds: 400));
      final seen = <String>[];
      for (var i = 0; i < 10; i++) {
        seen.addAll(
          tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .where((t) => t.isNotEmpty),
        );
        if (find.text('Next').evaluate().isEmpty) break;
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }
      final all = seen.join('\n');
      expect(all, contains('Full player mode'));
      expect(all, contains('Tap Float to show floating lyrics'));
      expect(all, contains('notification panel'));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('updating from an older version shows it again', (
      tester,
    ) async {
      await _pumpMain(
        tester,
        tv: false,
        autoTour: true,
        prefs: {appTourSeenKey: '1.5.0'},
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppTourScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('not shown again for the same version', (tester) async {
      await _pumpMain(
        tester,
        tv: false,
        autoTour: true,
        prefs: {appTourSeenKey: AppConstants.appVersion},
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppTourScreen), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('TV tour explains the pointer, not the notification Float', (
      tester,
    ) async {
      await _pumpMain(
        tester,
        tv: true,
        autoTour: true,
        prefs: const {},
        size: const Size(1280, 720),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final seen = <String>[];
      for (var i = 0; i < 10; i++) {
        seen.addAll(
          tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? ''),
        );
        if (find.text('Next').evaluate().isEmpty) break;
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }
      final all = seen.join('\n');
      expect(all, contains('Using a TV remote'));
      expect(all, isNot(contains('Lyrics over other apps')));
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('TV remote', () {
    testWidgets('D-pad leaves the rail and reaches the content', (
      tester,
    ) async {
      await _pumpMain(tester, tv: true, size: const Size(1280, 720));
      await tester.pump(const Duration(milliseconds: 400));
      // First press puts focus on the rail.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final railRect = tester.getRect(find.byType(NavigationRail));
      Rect focused() {
        final node = FocusManager.instance.primaryFocus!;
        return node.rect;
      }

      expect(railRect.overlaps(focused()), true, reason: 'starts on the rail');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        railRect.overlaps(focused()),
        false,
        reason: 'right must move into the page content',
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Settings tiles can be focused and activated with OK', (
      tester,
    ) async {
      await _pumpMain(tester, tv: true, size: const Size(1280, 720));
      await tester.tap(find.text('Settings'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final railRect = tester.getRect(find.byType(NavigationRail));
      expect(
        railRect.overlaps(FocusManager.instance.primaryFocus!.rect),
        false,
      );
      // Walk down the list; each step must land on a different control.
      final seen = <Rect>{};
      for (var i = 0; i < 6; i++) {
        seen.add(FocusManager.instance.primaryFocus!.rect);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(seen.length, greaterThan(2));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('pointer: arrows move, OK taps, Back exits', (tester) async {
      var taps = 0;
      var longPresses = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: TvPointerOverlay(
              child: Scaffold(
                body: Center(
                  child: GestureDetector(
                    onTap: () => taps++,
                    onLongPress: () => longPresses++,
                    child: Container(
                      width: 300,
                      height: 300,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // Pointer off: OK does nothing to the gesture detector.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(taps, 0);

      container.read(tvPointerActiveProvider.notifier).state = true;
      await tester.pump();
      // Starts in the centre of the screen, over the box.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1);

      // Move out of the box (centre 400,300 -> beyond x=550).
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 1, reason: 'cursor left the box');

      // Back: the pointer turns off.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(container.read(tvPointerActiveProvider), false);

      // Long press: hold OK on the box.
      container.read(tvPointerActiveProvider.notifier).state = true;
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
      await tester.pump(const Duration(milliseconds: 50));
      expect(taps, 2);
      await tester.pump(const Duration(seconds: 6));
      expect(longPresses, 0);
    });
  });
}

Future<void> _pumpMain(
  WidgetTester tester, {
  required bool tv,
  bool autoTour = false,
  Map<String, Object> prefs = const {'notification_float_tip_seen_v1': true},
  Size size = const Size(390, 800),
}) async {
  if (tester.view.physicalSize == const Size(800, 600)) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.lyricx/media'),
    (_) async => null,
  );
  messenger.setMockMessageHandler('plugins.flutter.io/google_mobile_ads', (
    m,
  ) async => const StandardMethodCodec().encodeSuccessEnvelope(null));
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage([null]),
  );
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        isTelevisionProvider.overrideWithValue(tv),
        appTourAutoShowProvider.overrideWithValue(autoTour),
        updateCheckServiceProvider.overrideWithValue(_NoUpdates()),
      ],
      child: const MaterialApp(home: MainScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}
