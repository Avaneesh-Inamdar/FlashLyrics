import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';

/// Song controls with seek bar and play/pause
class SongControls extends StatelessWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final bool isPlaying;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;

  const SongControls({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.isPlaying,
    required this.onSeek,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

    final progress = totalDuration.inMilliseconds == 0
        ? 0.0
        : (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: surfaceLight.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(currentPosition.formatted, style: TextStyle(fontSize: 12, color: textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: AppTheme.primaryColor,
                        inactiveTrackColor: surfaceLight,
                        thumbColor: AppTheme.primaryLight,
                        overlayColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
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
                  Text(totalDuration.formatted, style: TextStyle(fontSize: 12, color: textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: textPrimary, size: 28),
                    onPressed: onPlayPause,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                      padding: const EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(isPlaying ? 'Playing' : 'Paused', style: TextStyle(fontSize: 13, color: textSecondary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
