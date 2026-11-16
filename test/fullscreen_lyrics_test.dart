import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/theme/app_theme.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/fullscreen_lyrics_screen.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/presentation/widgets/ad_banner_widget.dart';
import 'package:lyricx/presentation/widgets/synced_lyrics_display.dart';
import 'package:lyricx/services/media_detection_service.dart';
import 'media_recovery_test.dart' show PlaybackService, RecoveryRemote;

const _lrc = '''[00:01.00]First line of the song
[00:04.00]Second line of the song
[00:07.00]Third line of the song
[00:10.00]Fourth line of the song''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> mediaCalls;
  late List<MethodCall> systemCalls;
  late List<String> adMessages;

  setUp(() {
    mediaCalls = [];
    systemCalls = [];
    adMessages = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.lyricx/media'),
      (call) async {
        mediaCalls.add(call);
        return call.method == 'seekTo' ? true : null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      systemCalls.add(call);
      return null;
    });
    messenger.setMockMessageHandler('plugins.flutter.io/google_mobile_ads', (
      message,
    ) async {
      adMessages.add(
        String.fromCharCodes(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        ),
      );
      return const StandardMethodCodec().encodeSuccessEnvelope(null);
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<(ProviderContainer, PlaybackService)> pumpApp(
    WidgetTester tester, {
    LyricsModel? lyrics,
    Map<String, Object> prefs = const {},
    bool lyricsAvailable = true,
  }) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    SharedPreferences.setMockInitialValues({
      'notification_float_tip_seen_v1': true,
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    final service = PlaybackService();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(shared),
        mediaDetectionServiceProvider.overrideWithValue(service),
        lyricsRemoteDataSourceProvider.overrideWithValue(
          RecoveryRemote()..failures = 0,
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      service.dispose();
    });
    await container.read(mediaNotifierProvider.notifier).startListening();
    // With no song playing there is nothing to look up lyrics for.
    if (lyricsAvailable) {
      service.songs.add(
        const Song(id: 'song', title: 'Test song', artist: 'Artist'),
      );
    }
    await tester.pump();
    if (lyrics != null) {
      container.read(lyricsNotifierProvider.notifier).setLyricsFromModel(lyrics);
    }
    service.positions.add(
      const PlaybackPosition(
        position: Duration(milliseconds: 4500),
        duration: Duration(minutes: 3),
        isPlaying: true,
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const MainScreen(),
        ),
      ),
    );
    await tester.runAsync(() async {
      await GoogleFonts.pendingFonts();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 1));
    return (container, service);
  }

  LyricsModel model({bool synced = true}) => LyricsModel(
    id: synced ? 'synced' : 'plain',
    songId: 'song',
    plainLyrics:
        'First line of the song\nSecond line of the song\nThird line of the song',
    lrcLyrics: synced ? _lrc : null,
    isSynced: synced,
    source: 'LRCLIB',
    fetchedAt: DateTime(2026),
    trackName: 'Test song',
    artistName: 'Artist',
  );

  Future<void> openFullscreen(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Full screen lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Lyrics are parsed off the UI thread.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FullscreenLyricsScreen), findsOneWidget);
  }

  Future<void> leave(WidgetTester tester) async {
    // Unmount to stop the lyrics ticker and pending timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('lyrics fill the screen; app chrome and nav bar are hidden', (
    tester,
  ) async {
    await pumpApp(tester, lyrics: model());
    expect(find.byType(NavigationBar), findsOneWidget);
    final normalHeight = tester
        .getSize(find.byType(SyncedLyricsDisplay))
        .height;

    await openFullscreen(tester);
    // The Listening screen underneath is no longer on screen.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Playback controls'), findsNothing);
    expect(find.text('Copy'), findsNothing);

    final lyricsBox = tester.getSize(find.byType(SyncedLyricsDisplay));
    expect(lyricsBox.height, greaterThan(800 * 0.8));
    expect(lyricsBox.height, greaterThan(normalHeight * 1.5));
    expect(find.text('Test song'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(
      find.text('Second line of the song', findRichText: true),
      findsWidgets,
    );

    // System bars are hidden while open.
    final modes = systemCalls
        .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
        .map((c) => c.arguments as String)
        .toList();
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    await leave(tester);
  });

  testWidgets('full-screen banner uses its own ad unit (test unit in debug)', (
    tester,
  ) async {
    await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    final banner = tester.widget<AdBannerWidget>(
      find.descendant(
        of: find.byType(FullscreenLyricsScreen),
        matching: find.byType(AdBannerWidget),
      ),
    );
    expect(banner.prodAdUnitId, 'ca-app-pub-3987982513065210/6598204417');
    expect(AdBannerWidget.fullscreenAdUnitId, banner.prodAdUnitId);
    // The main banner keeps its original unit.
    expect(
      const AdBannerWidget().prodAdUnitId,
      'ca-app-pub-3987982513065210/2035205150',
    );
    final loads = adMessages.where((m) => m.contains('loadBannerAd')).toList();
    expect(loads, isNotEmpty);
    for (final load in loads) {
      expect(load, contains('ca-app-pub-3940256099942544/6300978111'));
      expect(load, isNot(contains('3987982513065210')));
    }
    await leave(tester);
  });

  testWidgets('no banner in full screen when ads are turned off', (
    tester,
  ) async {
    final (container, _) = await pumpApp(tester, lyrics: model());
    container.read(settingsProvider.notifier).setEnableAds(false);
    await openFullscreen(tester);
    adMessages.clear();
    await tester.pump(const Duration(seconds: 1));
    expect(adMessages.where((m) => m.contains('loadBannerAd')), isEmpty);
    await leave(tester);
  });

  testWidgets('exit returns to the Listening screen and restores the system bars', (
    tester,
  ) async {
    await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    systemCalls.clear();
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FullscreenLyricsScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Playback controls'), findsOneWidget);
    final modes = systemCalls
        .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
        .map((c) => c.arguments as String);
    expect(modes, contains('SystemUiMode.edgeToEdge'));

    // System back also closes it.
    await openFullscreen(tester);
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FullscreenLyricsScreen), findsNothing);
    await leave(tester);
  });

  testWidgets('tap-to-seek and sync offset work in full screen', (tester) async {
    final (container, _) = await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    final display = tester.widget<SyncedLyricsDisplay>(
      find.byType(SyncedLyricsDisplay),
    );
    expect(display.isPlaying, isTrue);
    expect(display.currentPosition, const Duration(milliseconds: 4500));
    display.onSeek!(const Duration(seconds: 7));
    await tester.pump();
    final seek = mediaCalls.lastWhere((c) => c.method == 'seekTo');
    expect((seek.arguments as Map)['position'], 7000);

    display.onOffsetChanged!(300);
    await tester.pump();
    expect(container.read(songOffsetProvider).values, contains(300));
    expect(
      tester.widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
          .syncOffsetMs,
      300,
    );
    await leave(tester);
  });

  testWidgets('text size buttons change, limit and remember the size', (
    tester,
  ) async {
    final (container, _) = await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    double size() => tester
        .widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
        .fontSize;
    expect(size(), FullscreenLyricsScreen.defaultFontSize);

    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    expect(size(), 34);
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byTooltip('Larger text'), warnIfMissed: false);
      await tester.pump();
    }
    expect(size(), FullscreenLyricsScreen.maxFontSize);
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Smaller text'), warnIfMissed: false);
      await tester.pump();
    }
    expect(size(), FullscreenLyricsScreen.minFontSize);
    await tester.tap(find.byTooltip('Larger text'));
    await tester.pump();
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getDouble(FullscreenLyricsScreen.fontSizePrefKey), 24);
    await leave(tester);
  });

  testWidgets('remembered text size is used next time', (tester) async {
    await pumpApp(
      tester,
      lyrics: model(),
      prefs: {FullscreenLyricsScreen.fontSizePrefKey: 38.0},
    );
    await openFullscreen(tester);
    expect(
      tester
          .widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
          .fontSize,
      38,
    );
    await leave(tester);
  });

  testWidgets('plain lyrics are shown large when there are no timestamps', (
    tester,
  ) async {
    await pumpApp(tester, lyrics: model(synced: false));
    await openFullscreen(tester);
    expect(find.byType(SyncedLyricsDisplay), findsNothing);
    final line = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(FullscreenLyricsScreen),
            matching: find.text('Second line of the song'),
          )
          .first,
    );
    expect(line.style!.fontSize, FullscreenLyricsScreen.defaultFontSize * 0.8);
    await leave(tester);
  });

  testWidgets('follows song changes and shows a message without lyrics', (
    tester,
  ) async {
    final (container, _) = await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    container.read(lyricsNotifierProvider.notifier).setLyricsFromModel(
      LyricsModel(
        id: 'next',
        songId: 'next',
        plainLyrics: 'A brand new song',
        isSynced: false,
        source: 'LRCLIB',
        fetchedAt: DateTime(2026),
        trackName: 'Next song',
        artistName: 'Someone',
      ),
    );
    await tester.pump();
    expect(find.text('Next song'), findsOneWidget);
    expect(find.text('A brand new song'), findsOneWidget);

    container.read(lyricsNotifierProvider.notifier).clear();
    await tester.pump();
    expect(find.text('No lyrics for this song'), findsOneWidget);
    // Header and exit stay available.
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('tapping an earlier or later line seeks there', (tester) async {
    await pumpApp(tester, lyrics: model());
    await openFullscreen(tester);
    // Position 4.5 s: "Second line" is current; tap the lines around it.
    Future<int> seekAfterTapping(String text) async {
      mediaCalls.clear();
      await tester.tap(find.text(text, findRichText: true).first);
      await tester.pump();
      final seek = mediaCalls.lastWhere((c) => c.method == 'seekTo');
      return (seek.arguments as Map)['position'] as int;
    }

    expect(await seekAfterTapping('First line of the song'), 1000);
    expect(await seekAfterTapping('Third line of the song'), 7000);
    await leave(tester);
  });

  group('long-press to select and share', () {
    late List<MethodCall> shareCalls;

    setUp(() {
      shareCalls = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shareCalls.add(call);
          return 'dev.fluttercommunity.plus/share/unavailable';
        },
      );
    });

    Finder line(String text) => find.text(text, findRichText: true).first;
    String barText(WidgetTester tester) => tester
        .widgetList<Text>(find.textContaining(RegExp(r'^\d+ line')))
        .first
        .data!;

    for (final synced in [true, false]) {
      testWidgets('${synced ? 'synced' : 'plain'}: long-press selects, taps extend and narrow', (
        tester,
      ) async {
        await pumpApp(tester, lyrics: model(synced: synced));
        await openFullscreen(tester);
        expect(find.text('Share'), findsNothing);

        mediaCalls.clear();
        await tester.longPress(line('Second line of the song'));
        await tester.pump(const Duration(milliseconds: 300));
        // Long-press selects instead of seeking.
        expect(mediaCalls.where((c) => c.method == 'seekTo'), isEmpty);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(barText(tester), '1 line · tap more to add');
        // The selection view replaces the live lyrics while picking lines.
        expect(find.byType(SyncedLyricsDisplay), findsNothing);

        await tester.tap(line('Third line of the song'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(barText(tester), '2 lines selected');
        await tester.tap(line('First line of the song'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(barText(tester), '3 lines selected');
        // A line inside the range narrows the selection to it.
        await tester.tap(line('Second line of the song'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(barText(tester), '1 line · tap more to add');
        // Tapping the only selected line ends selection.
        await tester.tap(line('Second line of the song'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Share'), findsNothing);
        if (synced) expect(find.byType(SyncedLyricsDisplay), findsOneWidget);
        await leave(tester);
      });
    }

    testWidgets('Back and Cancel end the selection before leaving full screen', (
      tester,
    ) async {
      await pumpApp(tester, lyrics: model());
      await openFullscreen(tester);
      await tester.longPress(line('Second line of the song'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Share'), findsNothing);
      expect(find.byType(FullscreenLyricsScreen), findsOneWidget);
      // The live lyrics view is back and parses its lines again.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(line('Second line of the song'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Share'), findsNothing);
      expect(find.byType(FullscreenLyricsScreen), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a new song ends the selection', (tester) async {
      final (container, _) = await pumpApp(tester, lyrics: model());
      await openFullscreen(tester);
      await tester.longPress(line('Second line of the song'));
      await tester.pump(const Duration(milliseconds: 300));
      container.read(lyricsNotifierProvider.notifier).setLyricsFromModel(
        LyricsModel(
          id: 'next',
          songId: 'next',
          plainLyrics: 'A brand new song',
          isSynced: false,
          source: 'LRCLIB',
          fetchedAt: DateTime(2026),
          trackName: 'Next song',
          artistName: 'Someone',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Share'), findsNothing);
      expect(find.text('A brand new song'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('Share sends exactly the selected lines', (tester) async {
      await pumpApp(tester, lyrics: model(synced: false));
      await openFullscreen(tester);
      await tester.longPress(line('Second line of the song'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(line('Third line of the song'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Share'));
      // Image rendering and sharing run real async work.
      for (var i = 0; i < 20 && shareCalls.isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(shareCalls, hasLength(1));
      final args = shareCalls.single.arguments as Map;
      final text = args['text'] as String;
      expect(text, contains('Test song - Artist'));
      if (shareCalls.single.method == 'share') {
        // Text fallback: the selected lines only.
        expect(text, contains('Second line of the song\nThird line of the song'));
        expect(text, isNot(contains('First line')));
      } else {
        expect(shareCalls.single.method, 'shareFiles');
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Share'), findsNothing);
      await leave(tester);
    });
  });

  testWidgets('no full-screen button until lyrics are loaded', (tester) async {
    await pumpApp(tester, lyricsAvailable: false);
    expect(find.byTooltip('Full screen lyrics'), findsNothing);
    await leave(tester);
  });
}
