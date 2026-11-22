import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';

/// Whether the on-screen pointer (a "mouse" driven by the remote's D-pad) is
/// on. TV only.
final tvPointerActiveProvider = StateProvider<bool>((ref) => false);

/// A pointer for things the D-pad cannot focus, such as individual lyric lines.
///
/// While it is on, the arrow keys move a cursor, holding an arrow speeds it up,
/// the select / OK button taps (hold it for a long press), pushing the cursor
/// against the top or bottom edge scrolls, and Back turns the pointer off.
/// Menu toggles it from anywhere.
class TvPointerOverlay extends ConsumerStatefulWidget {
  const TvPointerOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TvPointerOverlay> createState() => _TvPointerOverlayState();
}

class _TvPointerOverlayState extends ConsumerState<TvPointerOverlay> {
  static const double _baseStep = 12;
  static const double _maxStep = 56;
  static const double _edge = 36;

  final ValueNotifier<Offset> _position = ValueNotifier(Offset.zero);
  Size _size = Size.zero;
  bool _placed = false;
  int _repeat = 0;
  int _pointerId = 0;
  int? _downPointer;
  Timer? _hint;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hint?.cancel();
    _position.dispose();
    super.dispose();
  }

  bool get _active => ref.read(tvPointerActiveProvider);

  void _setActive(bool on) =>
      ref.read(tvPointerActiveProvider.notifier).state = on;

  /// Side effects of the pointer turning on / off, however it was toggled.
  void _activeChanged(bool on) {
    _hint?.cancel();
    if (on) {
      setState(() => _showHint = true);
      _hint = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showHint = false);
      });
    } else {
      _release();
      if (_showHint) setState(() => _showHint = false);
    }
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) _setActive(!_active);
      return true;
    }
    if (!_active) return false;

    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _setActive(false);
      return true;
    }

    if (_isSelect(key)) {
      if (event is KeyDownEvent) {
        _press();
      } else if (event is KeyUpEvent) {
        _release();
      }
      return true;
    }

    final delta = _direction(key);
    if (delta == null) return false;
    if (event is KeyDownEvent) {
      _repeat = 0;
    } else if (event is KeyRepeatEvent) {
      _repeat++;
    } else {
      return true;
    }
    final step = math.min(_maxStep, _baseStep + _repeat * 4.0);
    _move(delta * step);
    return true;
  }

  static bool _isSelect(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  static Offset? _direction(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return const Offset(0, -1);
    if (key == LogicalKeyboardKey.arrowDown) return const Offset(0, 1);
    if (key == LogicalKeyboardKey.arrowLeft) return const Offset(-1, 0);
    if (key == LogicalKeyboardKey.arrowRight) return const Offset(1, 0);
    return null;
  }

  int get _viewId => View.maybeOf(context)?.viewId ?? 0;

  void _move(Offset by) {
    if (_size.isEmpty) return;
    final old = _position.value;
    final next = Offset(
      (old.dx + by.dx).clamp(0.0, _size.width - 1),
      (old.dy + by.dy).clamp(0.0, _size.height - 1),
    );
    _position.value = next;
    if (_downPointer != null) {
      GestureBinding.instance.handlePointerEvent(
        PointerMoveEvent(
          viewId: _viewId,
          pointer: _downPointer!,
          position: next,
          delta: next - old,
        ),
      );
      return;
    }
    // Pushing against the top / bottom edge scrolls whatever is underneath.
    if (by.dy != 0 && (next.dy <= _edge || next.dy >= _size.height - _edge)) {
      final pushingUp = by.dy < 0 && next.dy <= _edge;
      final pushingDown = by.dy > 0 && next.dy >= _size.height - _edge;
      if (pushingUp || pushingDown) {
        GestureBinding.instance.handlePointerEvent(
          PointerScrollEvent(
            viewId: _viewId,
            position: next,
            scrollDelta: Offset(0, pushingDown ? 140 : -140),
          ),
        );
      }
    }
  }

  void _press() {
    if (_downPointer != null) return;
    final id = 7000 + (++_pointerId);
    _downPointer = id;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        viewId: _viewId,
        pointer: id,
        position: _position.value,
      ),
    );
  }

  void _release() {
    final id = _downPointer;
    if (id == null) return;
    _downPointer = null;
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(viewId: _viewId, pointer: id, position: _position.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(tvPointerActiveProvider);
    ref.listen<bool>(tvPointerActiveProvider, (_, on) => _activeChanged(on));
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (!_placed && !_size.isEmpty) {
          _placed = true;
          _position.value = Offset(_size.width / 2, _size.height / 2);
        }
        return Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (active)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<Offset>(
                    valueListenable: _position,
                    builder: (context, pos, _) => CustomPaint(
                      painter: _CursorPainter(pos),
                    ),
                  ),
                ),
              ),
            if (active && _showHint)
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text(
                          'Pointer on · arrows move · OK taps (hold = long '
                          'press) · edges scroll · Back exits',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CursorPainter extends CustomPainter {
  _CursorPainter(this.position);

  final Offset position;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(position.dx, position.dy)
      ..lineTo(position.dx, position.dy + 30)
      ..lineTo(position.dx + 8, position.dy + 23)
      ..lineTo(position.dx + 14, position.dy + 36)
      ..lineTo(position.dx + 20, position.dy + 33)
      ..lineTo(position.dx + 14, position.dy + 21)
      ..lineTo(position.dx + 24, position.dy + 21)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(path, Paint()..color = AppTheme.primaryLight);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CursorPainter old) => old.position != position;
}

/// Rail / header button that turns the pointer on or off.
class TvPointerButton extends ConsumerWidget {
  const TvPointerButton({super.key, this.extended = true});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(tvPointerActiveProvider);
    void toggle() =>
        ref.read(tvPointerActiveProvider.notifier).state = !active;
    if (!extended) {
      return IconButton(
        tooltip: 'Pointer',
        isSelected: active,
        icon: const Icon(Icons.mouse_outlined),
        selectedIcon: const Icon(Icons.mouse),
        onPressed: toggle,
      );
    }
    return TextButton.icon(
      onPressed: toggle,
      icon: Icon(active ? Icons.mouse : Icons.mouse_outlined),
      label: Text(active ? 'Pointer on' : 'Pointer'),
    );
  }
}
