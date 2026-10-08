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
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/search_screen.dart';
import 'package:lyricx/presentation/screens/main_screen.dart';
import 'package:lyricx/presentation/screens/genius_lyrics_screen.dart';

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

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        'search and Genius fit $width in ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          for (final entry in <String, Widget>{
            if (width == 390) 'listening': const MainScreen(),
            'search': const SearchScreen(),
            'genius': const GeniusLyricsScreen(query: 'Artist - Song'),
          }.entries) {
            final key = GlobalKey();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
                child: RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                    home: entry.value,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                      ),
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
            await tester.runAsync(() => GoogleFonts.pendingFonts());
            for (var frame = 0; frame < 8; frame++) {
              await tester.pump(const Duration(milliseconds: 200));
            }
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('CAPTURE_PREVIEWS') &&
                width == 390) {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final output = File(
                  'build/previews/${entry.key}-${dark ? 'dark' : 'light'}.png',
                );
                await output.parent.create(recursive: true);
                await output.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        },
      );
    }
  }
}
