import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Quick offset adjuster for syncing lyrics timing
/// Allows user to nudge lyrics earlier/later in 100ms steps or via slider
class QuickOffsetAdjuster extends StatefulWidget {
  final int currentOffset;
  final Duration currentPosition;
  final Duration? nextLyricTime;
  final ValueChanged<int> onOffsetChanged;
  final VoidCallback onClose;

  const QuickOffsetAdjuster({
    super.key,
    required this.currentOffset,
    required this.currentPosition,
    required this.nextLyricTime,
    required this.onOffsetChanged,
    required this.onClose,
  });

  @override
  State<QuickOffsetAdjuster> createState() => _QuickOffsetAdjusterState();
}

class _QuickOffsetAdjusterState extends State<QuickOffsetAdjuster> {
  late int _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.currentOffset;
  }

  void _apply() {
    widget.onOffsetChanged(_offset);
  }

  String _formatOffset(int ms) {
    if (ms == 0) return '0 ms (default)';
    final sign = ms > 0 ? '+' : '';
    return '$sign${ms} ms';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sync Offset', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary)),
                                  Text('Adjust if lyrics are early/late', style: TextStyle(fontSize: 12, color: textSecondary)),
                                ],
                              ),
                            ),
                            IconButton(icon: Icon(Icons.close_rounded, color: textSecondary), onPressed: widget.onClose),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(_formatOffset(_offset), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.primaryLight)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(() => _offset -= 100),
                              icon: Icon(Icons.remove_circle_outline, color: textSecondary),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: AppTheme.primaryColor,
                                  inactiveTrackColor: surfaceLight,
                                  thumbColor: AppTheme.primaryLight,
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                ),
                                child: Slider(
                                  value: _offset.clamp(-2000, 2000).toDouble(),
                                  min: -2000,
                                  max: 2000,
                                  divisions: 40,
                                  label: _formatOffset(_offset),
                                  onChanged: (v) => setState(() => _offset = v.round()),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _offset += 100),
                              icon: Icon(Icons.add_circle_outline, color: textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _offset = 0);
                                },
                                child: const Text('Reset'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _apply,
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                                child: const Text('Apply', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
