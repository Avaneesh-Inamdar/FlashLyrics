import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/utils/lrc_parser.dart';

/// Paints one shaped paragraph, so joining scripts and wrapped words keep their
/// normal layout. Only the paint layer updates on playback frames.
class KaraokeLine extends StatelessWidget {
  final LrcLine line;
  final ValueListenable<Duration> position;
  final Duration offset;
  final Duration? lineEnd;
  final TextStyle style;
  final Color color;
  final bool reduceMotion;

  const KaraokeLine({
    super.key,
    required this.line,
    required this.position,
    required this.style,
    required this.color,
    this.offset = Duration.zero,
    this.lineEnd,
    this.reduceMotion = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: style.copyWith(color: color),
        ),
        textDirection: Directionality.of(context),
        textAlign: TextAlign.center,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(minWidth: constraints.maxWidth, maxWidth: constraints.maxWidth);
      final height = painter.height;
      painter.dispose();
      return Semantics(
        label: line.text,
        child: SizedBox(
          width: constraints.maxWidth,
          height: height + 8,
          child: CustomPaint(
            painter: KaraokePainter(
              line: line,
              position: position,
              offset: offset,
              lineEnd: lineEnd,
              style: style,
              color: color,
              direction: Directionality.of(context),
              scaler: MediaQuery.textScalerOf(context),
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      );
    },
  );
}

double wordProgress(LrcWord word, Duration position, {Duration? fallbackEnd}) {
  final end = word.end ?? fallbackEnd;
  if (position < word.start) return 0;
  if (end == null || end <= word.start) return 1;
  return ((position - word.start).inMicroseconds /
          (end - word.start).inMicroseconds)
      .clamp(0.0, 1.0);
}

class KaraokePainter extends CustomPainter {
  final LrcLine line;
  final ValueListenable<Duration> position;
  final Duration offset;
  final Duration? lineEnd;
  final TextStyle style;
  final Color color;
  final TextDirection direction;
  final TextScaler scaler;
  final bool reduceMotion;

  KaraokePainter({
    required this.line,
    required this.position,
    required this.offset,
    required this.lineEnd,
    required this.style,
    required this.color,
    required this.direction,
    required this.scaler,
    required this.reduceMotion,
  }) : super(repaint: position);

  @override
  void paint(Canvas canvas, Size size) {
    final text = TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(color: color.withValues(alpha: 0.28)),
      ),
      textDirection: direction,
      textAlign: TextAlign.center,
      textScaler: scaler,
    )..layout(minWidth: size.width, maxWidth: size.width);
    text.paint(canvas, const Offset(0, 4));
    TextPainter foreground(bool glow) => TextPainter(
      text: TextSpan(
        text: line.text,
        style: style.copyWith(
          color: color,
          shadows: glow && !reduceMotion
              ? [Shadow(color: color.withValues(alpha: 0.3), blurRadius: 6)]
              : null,
        ),
      ),
      textDirection: direction,
      textAlign: TextAlign.center,
      textScaler: scaler,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final bright = foreground(false);
    final glowing = foreground(true);
    final now = position.value + offset;
    var start = 0;
    for (var i = 0; i < line.words.length; i++) {
      final word = line.words[i];
      final end = start + word.text.length;
      final fallback = i + 1 < line.words.length
          ? line.words[i + 1].start
          : lineEnd;
      final progress = wordProgress(word, now, fallbackEnd: fallback);
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      start = end;
      if (progress <= 0) continue;
      final active = progress < 1;
      final lift = active && !reduceMotion
          ? -1.5 * math.sin(math.pi * progress)
          : 0.0;
      var remaining =
          boxes.fold<double>(0, (sum, box) => sum + box.right - box.left) *
          progress;
      for (final box in boxes) {
        final width = box.right - box.left;
        final filled = remaining.clamp(0.0, width);
        remaining -= width;
        if (filled <= 0) continue;
        final rect = Rect.fromLTRB(
          box.direction == TextDirection.rtl ? box.right - filled : box.left,
          box.top + lift,
          box.direction == TextDirection.rtl ? box.right : box.left + filled,
          box.bottom + 8,
        );
        canvas.save();
        canvas.clipRect(rect);
        (active ? glowing : bright).paint(canvas, Offset(0, 4 + lift));
        canvas.restore();
      }
    }
    bright.dispose();
    glowing.dispose();
    text.dispose();
  }

  @override
  bool shouldRepaint(KaraokePainter oldDelegate) =>
      line != oldDelegate.line ||
      position != oldDelegate.position ||
      offset != oldDelegate.offset ||
      lineEnd != oldDelegate.lineEnd ||
      style != oldDelegate.style ||
      color != oldDelegate.color ||
      direction != oldDelegate.direction ||
      scaler != oldDelegate.scaler ||
      reduceMotion != oldDelegate.reduceMotion;
}
