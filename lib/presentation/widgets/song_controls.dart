import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';

/// Song controls with seek bar and play/pause + next/previous
/// Works with any media app via MediaSession transport controls
class SongControls extends StatelessWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  const SongControls({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.isPlaying,
    required this.onSeek,
    required this.onPlayPause,
    this.onNext,
    this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    final progress = totalDuration.inMilliseconds == 0
        ? 0.0
        : (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0);

    // Clean minimal design - no heavy blur for performance
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surfaceLight, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(currentPosition.formatted,
                  style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w500)),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppTheme.primaryColor,
                    inactiveTrackColor: surfaceLight,
                    thumbColor: AppTheme.primaryColor,
                    overlayColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    trackShape: const RoundedRectSliderTrackShape(),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (v) {
                      final pos = Duration(milliseconds: (v * totalDuration.inMilliseconds).round());
                      onSeek(pos);
                    },
                  ),
                ),
              ),
              Text(totalDuration.formatted,
                  style: TextStyle(
                      fontSize: 12,
                      color: textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous
              _ControlButton(
                icon: Icons.skip_previous_rounded,
                onPressed: onPrevious,
                size: 22,
                isPrimary: false,
                tooltip: 'Previous',
              ),
              const SizedBox(width: 14),
              // Play/Pause - primary
              _ControlButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onPressed: onPlayPause,
                size: 28,
                isPrimary: true,
                tooltip: isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 14),
              // Next
              _ControlButton(
                icon: Icons.skip_next_rounded,
                onPressed: onNext,
                size: 22,
                isPrimary: false,
                tooltip: 'Next',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(isPlaying ? 'Playing' : 'Paused',
              style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool isPrimary;
  final String tooltip;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    required this.isPrimary,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

    if (isPrimary) {
      return Material(
        color: AppTheme.primaryColor,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      );
    }

    return Material(
      color: isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: textPrimary, size: size),
        ),
      ),
    );
  }
}
