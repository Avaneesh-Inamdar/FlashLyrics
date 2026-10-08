import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/theme/app_theme.dart';
import 'package:lyricx/core/utils/word_lyrics.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/services/media_detection_service.dart';
import 'media_recovery_test.dart' show PlaybackService, RecoveryRemote;
import 'word_lyrics_test.dart' show wordFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('lyrics visible without scrolling, width $width, dark $dark', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
        SharedPreferences.setMockInitialValues({
          'notification_float_tip_seen_v1': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final service = PlaybackService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            mediaDetectionServiceProvider.overrideWithValue(service),
            lyricsRemoteDataSourceProvider.overrideWithValue(
              RecoveryRemote()..failures = 0,
            ),
          ],
        );
        final media = container.read(mediaNotifierProvider.notifier);
        await tester.pump();
        await media.startListening();
        service.songs.add(
          const Song(id: 'song', title: 'Test song', artist: 'Artist'),
        );
        await tester.pump();
        container
            .read(lyricsNotifierProvider.notifier)
            .setLyricsFromModel(
              LyricsModel(
                id: 'words',
                songId: 'song',
                plainLyrics: 'Hello दुनिया\nNext line',
                lrcLyrics: wordSyncedLrc({'lyricsfile': wordFixture}),
                isSynced: true,
                source: 'LRCLIB',
                fetchedAt: DateTime(2026),
                trackName: 'Test song',
                artistName: 'Artist',
              ),
            );
        service.positions.add(
          const PlaybackPosition(
            position: Duration(milliseconds: 1700),
            duration: Duration(minutes: 3),
            isPlaying: false,
          ),
        );
        await tester.pump();
        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                debugShowCheckedModeBanner: false,
                home: const MainScreen(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 24),
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await GoogleFonts.pendingFonts();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
        final active = find.byKey(const ValueKey('word-synced-line'));
        expect(active, findsOneWidget);
        expect(
          tester.getRect(active).bottom,
          lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
        );
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('build/previews/home142-$width-$dark.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        service.dispose();
      });
    }
  }
}
