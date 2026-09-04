import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/song.dart';
import 'lrc_parser.dart';

/// Generates a shareable image for selected lyrics lines.
/// Includes song cover art and properly centered text.
class LyricsImageGenerator {
  static Future<File?> generateLyricsImage({
    required Song song,
    required List<String> lines,
    required bool isDark,
  }) async {
    try {
      const double width = 1080.0;
      const double padding = 56.0;
      const double lineHeight = 56.0;
      const double coverSize = 160.0;
      const double headerH = 200.0;
      const double footerH = 80.0;
      final double contentH = lines.length * lineHeight;
      final double height = headerH + contentH + footerH + padding * 2;

      final ui.Image? coverImage = await _loadCoverImage(song);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Background
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = isDark ? const Color(0xFF0A0A0B) : const Color(0xFFFDFBF7),
      );

      // Accent bar
      canvas.drawRect(const Rect.fromLTWH(0, 0, 1080, 8), Paint()..color = const Color(0xFF10B981));

      // Cover art
      final double coverTop = padding + 8;
      final double coverLeft = padding;
      final RRect coverRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
        const Radius.circular(20),
      );

      if (coverImage != null) {
        canvas.save();
        canvas.clipRRect(coverRRect);
        canvas.drawImageRect(
          coverImage,
          Rect.fromLTWH(0, 0, coverImage.width.toDouble(), coverImage.height.toDouble()),
          Rect.fromLTWH(coverLeft, coverTop, coverSize, coverSize),
          Paint(),
        );
        canvas.restore();
      } else {
        canvas.drawRRect(
          coverRRect,
          Paint()..color = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFE8E4F0),
        );
      }

      // Song info
      final Color titleColor  = isDark ? Colors.white          : const Color(0xFF1A1A1A);
      final Color artistColor = isDark ? const Color(0xFFB3B3C2) : const Color(0xFF4B4B4B);
      final Color albumColor  = isDark ? const Color(0xFF7A7A8C) : const Color(0xFF8C8C8C);
      const double infoLeft = padding + coverSize + 24;
      final double infoWidth = width - infoLeft - padding;

      _drawText(canvas: canvas, text: song.title,  x: infoLeft, y: coverTop + 6,   fontSize: 40, color: titleColor,  weight: FontWeight.w700, maxWidth: infoWidth);
      _drawText(canvas: canvas, text: song.artist, x: infoLeft, y: coverTop + 66,  fontSize: 28, color: artistColor, weight: FontWeight.w500, maxWidth: infoWidth);
      if (song.album != null && song.album!.isNotEmpty) {
        _drawText(canvas: canvas, text: song.album!, x: infoLeft, y: coverTop + 108, fontSize: 22, color: albumColor, weight: FontWeight.w400, maxWidth: infoWidth);
      }

      // Divider
      canvas.drawRect(
        Rect.fromLTWH(padding, headerH + padding - 12, width - padding * 2, 2),
        Paint()..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.10),
      );

      // Lyrics lines — centered
      double y = headerH + padding + 8;
      for (final rawLine in lines) {
        final cleaned = LrcParser.stripTimeTags(rawLine);
        _drawText(
          canvas: canvas,
          text: cleaned,
          x: padding, y: y,
          fontSize: 32,
          color: isDark ? Colors.white : const Color(0xFF1A1A1A),
          weight: FontWeight.w500,
          maxWidth: width - padding * 2,
          align: TextAlign.center,
        );
        y += lineHeight;
      }

      // Footer
      final double footerY = height - footerH;
      canvas.drawRect(Rect.fromLTWH(padding, footerY - 10, width - padding * 2, 1),
          Paint()..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08));
      _drawText(canvas: canvas, text: 'Shared via FlashLyrics', x: padding, y: footerY + 20,
          fontSize: 22, color: const Color(0xFF10B981), weight: FontWeight.w600, maxWidth: 600);
      _drawText(canvas: canvas, text: '${DateTime.now().year}', x: width - padding - 80, y: footerY + 20,
          fontSize: 20, color: albumColor, weight: FontWeight.w400, maxWidth: 100);

      // Encode
      final picture = recorder.endRecording();
      final img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/flashlyrics_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return file;
    } catch (e) {
      debugPrint('LyricsImageGenerator error: $e');
      return null;
    }
  }

  static void _drawText({
    required Canvas canvas,
    required String text,
    required double x,
    required double y,
    required double fontSize,
    required Color color,
    required FontWeight weight,
    required double maxWidth,
    TextAlign align = TextAlign.left,
  }) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: align, fontSize: fontSize, fontWeight: weight, maxLines: 3, ellipsis: '\u2026',
    ))
      ..pushStyle(ui.TextStyle(color: color, fontSize: fontSize, fontWeight: weight))
      ..addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, Offset(x, y));
  }

  static Future<ui.Image?> _loadCoverImage(Song song) async {
    final url = song.artworkUrl;
    if (url == null || url.isEmpty || url.startsWith('content://')) return _fetchItunesCover(song);
    try {
      if (url.startsWith('file://') || url.startsWith('/')) {
        final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
        return _decodeBytes(await File(path).readAsBytes());
      }
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url.replaceAll('http://', 'https://')));
      final res = await req.close();
      return _decodeBytes(Uint8List.fromList(await res.expand((b) => b).toList()));
    } catch (_) {
      return _fetchItunesCover(song);
    }
  }

  static Future<ui.Image?> _fetchItunesCover(Song song) async {
    try {
      final q = Uri.encodeComponent('${song.artist} ${song.title}');
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('https://itunes.apple.com/search?term=$q&entity=song&limit=1'));
      final res = await req.close();
      final json = String.fromCharCodes(Uint8List.fromList(await res.expand((b) => b).toList()));
      final match = RegExp(r'"artworkUrl100":"([^"]+)"').firstMatch(json);
      if (match == null) return null;
      final imgUrl = match.group(1)!.replaceAll('100x100bb', '600x600bb').replaceAll('http://', 'https://');
      final imgReq = await client.getUrl(Uri.parse(imgUrl));
      final imgRes = await imgReq.close();
      return _decodeBytes(Uint8List.fromList(await imgRes.expand((b) => b).toList()));
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320, targetHeight: 320);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
