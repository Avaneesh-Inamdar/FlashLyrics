// Captures actual app widgets with NCS artwork and an illustrative timing fixture.
// flutter test test/readme_screenshots_test.dart --dart-define=CAPTURE_README=true
import 'dart:convert';
import 'dart:async';
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
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/presentation/widgets/song_card.dart';
import 'package:lyricx/services/media_detection_service.dart';
import 'media_recovery_test.dart' show PlaybackService, RecoveryRemote;

const demoLrc = '[00:05]<00:05>On <00:06>and <00:07.5>on<00:08.5>';

LyricsModel demoLyrics(String title, String artist, {bool synced = true}) =>
    LyricsModel(
      id: title,
      songId: title,
      trackName: title,
      artistName: artist,
      plainLyrics: 'On and on',
      lrcLyrics: synced ? demoLrc : null,
      isSynced: synced,
      source: 'LRCLIB',
      fetchedAt: DateTime(2026, 10, 12),
    );

class ReadmeRemote extends RecoveryRemote {
  @override
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async => demoLyrics(title, artist);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    testWidgets('README captures current ${dark ? 'dark' : 'light'} app', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.lyricx/media'),
        (_) async => true,
      );
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
      SharedPreferences.setMockInitialValues({
        'notification_float_tip_seen_v1': true,
        'app_settings': jsonEncode(
          const AppSettings(enableAds: false).toJson(),
        ),
      });
      final service = PlaybackService();
      final samples = [
        demoLyrics('On & On', 'Cartoon, Jéja · Daniel Levi'),
        demoLyrics('Heroes Tonight', 'Janji · Johnning'),
        demoLyrics('Invincible', 'DEAF KEV', synced: false),
      ];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          mediaDetectionServiceProvider.overrideWithValue(service),
          lyricsRemoteDataSourceProvider.overrideWithValue(ReadmeRemote()),
          cachedLyricsProvider.overrideWith((ref) async => samples),
        ],
      );
      await tester.pump();
      await container.read(mediaNotifierProvider.notifier).startListening();
      final song = Song(
        id: 'On & On',
        title: 'On & On',
        artist: 'Cartoon, Jéja · Daniel Levi',
        source: 'Spotify',
        artworkUrl: Uri.file(
          File('docs/screenshots/artwork/on-and-on.jpg').absolute.path,
        ).toString(),
      );
      service.songs.add(song);
      await tester.pump();
      await container.read(lyricsNotifierProvider.notifier).setSong(song);
      service.positions.add(
        const PlaybackPosition(
          position: Duration(milliseconds: 7200),
          duration: Duration(minutes: 3, seconds: 42),
          isPlaying: false,
        ),
      );
      await tester.pump();
      final key = GlobalKey();
      await tester.runAsync(() async {
        final provider = FileImage(
          File('docs/screenshots/artwork/on-and-on.jpg').absolute,
        );
        final loaded = Completer<void>();
        final stream = provider.resolve(const ImageConfiguration());
        final listener = ImageStreamListener(
          (_, _) => loaded.complete(),
          onError: (Object error, StackTrace? stack) =>
              loaded.completeError(error, stack),
        );
        stream.addListener(listener);
        await loaded.future.timeout(const Duration(seconds: 5));
        stream.removeListener(listener);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: const MainScreen(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: 24, bottom: 24)),
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
      await container.read(lyricsNotifierProvider.notifier).setSong(song);
      for (final entry in {
        0: 'listening',
        2: 'library',
        3: 'settings',
      }.entries) {
        container.read(tabIndexProvider.notifier).setIndex(entry.key);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (entry.key == 0) {
          final cover = find.descendant(
            of: find.byType(SongCard),
            matching: find.byType(RawImage),
          );
          for (var attempt = 0; attempt < 20; attempt++) {
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            });
            await tester.pump();
            if (cover.evaluate().isNotEmpty &&
                tester.widget<RawImage>(cover).image != null)
              break;
          }
          expect(cover, findsOneWidget);
          expect(
            tester.widget<RawImage>(cover).image,
            isNotNull,
            reason:
                'README must contain decoded cover art, never a placeholder',
          );
          service.positions.add(
            const PlaybackPosition(
              position: Duration(milliseconds: 7000),
              duration: Duration(minutes: 3, seconds: 28),
              isPlaying: true,
            ),
          );
          service.playback.add(true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 40));
          expect(find.text('Live'), findsOneWidget);
          expect(find.text('Idle'), findsNothing);
          expect(
            find.byKey(const ValueKey('word-synced-line')),
            findsOneWidget,
          );
        }
        if (const bool.fromEnvironment('CAPTURE_README')) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'docs/screenshots/${entry.value}-${dark ? 'dark' : 'light'}${entry.key == 0 ? '-v2' : ''}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          if (entry.key == 0) {
            await tester.tap(find.text('Playback controls'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.byType(Slider), findsWidgets);
            await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'docs/screenshots/playback-${dark ? 'dark' : 'light'}-v2.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      service.dispose();
    });
  }
}
