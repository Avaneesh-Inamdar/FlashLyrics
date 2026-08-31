import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/song.dart';

/// Generates a shareable image for selected lyrics lines
class LyricsImageGenerator {
  static Future<File?> generateLyricsImage({
    required Song song,
    required List<String> lines,
    required bool isDark,
  }) async {
    try {
      final width = 1080.0;
      final padding = 48.0;
      final lineHeight = 52.0;
      final headerHeight = 160.0;
      final footerHeight = 80.0;
      final contentHeight = lines.length * lineHeight;
      final height = headerHeight + contentHeight + footerHeight + padding * 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();

      // Background gradient approximation - solid dark/light
      final bgColor = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFFDFBF7);
      canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paint..color = bgColor);

      // Accent bar at top
      final accentPaint = Paint()..color = const Color(0xFF10B981);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1080, 8), accentPaint);

      // Helper to draw text
      void drawText(String text, double x, double y, double fontSize, Color color, FontWeight weight, {double maxWidth = 900}) {
        final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: TextAlign.left,
          fontSize: fontSize,
          fontWeight: weight,
        ))
          ..pushStyle(ui.TextStyle(color: color, fontSize: fontSize, fontWeight: weight))
          ..addText(text);
        final paragraph = builder.build();
        paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
        canvas.drawParagraph(paragraph, Offset(x, y));
      }

      // Song header
      drawText(song.title, padding, padding + 20, 42, isDark ? Colors.white : const Color(0xFF1A1A1A), FontWeight.w700);
      drawText(song.artist, padding, padding + 80, 28, isDark ? const Color(0xFFB3B3C2) : const Color(0xFF4B4B4B), FontWeight.w500);
      if (song.album != null && song.album!.isNotEmpty) {
        drawText(song.album!, padding, padding + 115, 22, isDark ? const Color(0xFF7A7A8C) : const Color(0xFF8C8C8C), FontWeight.w400);
      }

      // Divider
      final dividerPaint = Paint()..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
      canvas.drawRect(Rect.fromLTWH(padding, headerHeight + padding - 10, width - padding * 2, 2), dividerPaint);

      // Lyrics lines
      double y = headerHeight + padding;
      for (final line in lines) {
        final text = line.trim().isEmpty ? '♪' : line.trim();
        drawText(text, padding, y, 30, isDark ? Colors.white : const Color(0xFF1A1A1A), FontWeight.w500);
        y += lineHeight;
      }

      // Footer branding
      final footerY = height - footerHeight;
      final footerDivider = Paint()..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
      canvas.drawRect(Rect.fromLTWH(padding, footerY - 10, width - padding * 2, 1), footerDivider);
      drawText('Shared via FlashLyrics', padding, footerY + 16, 22, const Color(0xFF10B981), FontWeight.w600);
      drawText('${DateTime.now().year}', width - padding - 80, footerY + 16, 20, isDark ? const Color(0xFF7A7A8C) : const Color(0xFF8C8C8C), FontWeight.w400);

      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final fileName = 'flashlyrics_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('LyricsImageGenerator error: $e');
      return null;
    }
  }
}
