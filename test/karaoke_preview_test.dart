import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lyricx/core/theme/app_theme.dart';
import 'package:lyricx/presentation/widgets/karaoke_line.dart';
import 'package:lyricx/presentation/widgets/synced_lyrics_display.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets('karaoke paints partial word fill in ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final background = dark ? AppTheme.surfaceColor : AppTheme.lightSurface;
      Future<void> show(int position) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: Scaffold(
                backgroundColor: background,
                body: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 60,
                  ),
                  child: SyncedLyricsDisplay(
                    fontSize: 32,
                    currentPosition: Duration(milliseconds: position),
                    lrcContent:
                        '[00:01]<00:01>Keep <00:02>the <00:02.5>light <00:03.5>on<00:04.5>\n'
                        '[00:05]When the evening falls\n[00:08]We will find our way',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await GoogleFonts.pendingFonts();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<List<int>> capture(String phase) async {
        return (await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          if (const bool.fromEnvironment('CAPTURE_PREVIEWS')) {
            final file = File('build/previews/karaoke-$dark-$phase.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes);
          }
          image.dispose();
          return bytes;
        }))!;
      }

      await show(2600);
      final before = await capture('early');
      await show(3200);
      final after = await capture('late');
      expect(after, isNot(orderedEquals(before)));
      expect(find.byType(KaraokeLine), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
