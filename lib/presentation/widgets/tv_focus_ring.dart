import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/app_theme.dart';

/// Draws a clear outline around whatever currently has keyboard / D-pad
/// focus, so a TV remote always shows where the selection is. Used only on
/// TV, where Material's own focus overlays are too faint to see from a couch.
class TvFocusRing extends StatefulWidget {
  const TvFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<TvFocusRing> {
  final ValueNotifier<Rect?> _rect = ValueNotifier<Rect?>(null);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    if (!mounted) return;
    final node = FocusManager.instance.primaryFocus;
    Rect? next;
    if (node != null && node is! FocusScopeNode && node.context != null) {
      final box = node.context!.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final overlay = context.findRenderObject();
        if (overlay is RenderBox) {
          final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
          next = topLeft & box.size;
        }
      }
    }
    if (next != _rect.value) _rect.value = next;
  }

  @override
  void dispose() {
    _rect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(painter: _RingPainter(_rect)),
        ),
      ),
    ],
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.rect) : super(repaint: rect);

  final ValueNotifier<Rect?> rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect.value;
    if (r == null || r.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = AppTheme.primaryLight,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.rect != rect;
}
