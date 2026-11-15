import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../services/support_prompt_service.dart';

/// Wraps a Settings tile so the support prompt can point at it: when
/// [settingsHighlightProvider] names [target], the tile scrolls into view and
/// glows a few times.
class SupportHighlightTarget extends ConsumerStatefulWidget {
  const SupportHighlightTarget({
    super.key,
    required this.target,
    required this.child,
  });

  final SupportHighlight target;
  final Widget child;

  @override
  ConsumerState<SupportHighlightTarget> createState() =>
      _SupportHighlightTargetState();
}

class _SupportHighlightTargetState extends ConsumerState<SupportHighlightTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(settingsHighlightProvider) == widget.target) _start();
  }

  void _start() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(settingsHighlightProvider.notifier).state = null;
      await Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 350),
      );
      if (!mounted) return;
      try {
        await _glow.forward(from: 0).orCancel;
        for (var i = 0; i < 2 && mounted; i++) {
          await _glow.reverse().orCancel;
          await _glow.forward().orCancel;
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) await _glow.reverse().orCancel;
      } on TickerCanceled {
        // Disposed mid-animation.
      }
    });
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SupportHighlight?>(settingsHighlightProvider, (_, next) {
      if (next == widget.target) _start();
    });
    return AnimatedBuilder(
      animation: _glow,
      child: widget.child,
      builder: (context, child) {
        final t = _glow.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppTheme.primaryColor.withValues(alpha: 0.18 * t),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.9 * t),
              width: 2,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
