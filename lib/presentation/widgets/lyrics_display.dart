import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/lyrics_image_generator.dart';
import '../../domain/entities/lyrics.dart';
import '../providers/lyrics_provider.dart';
import '../providers/settings_provider.dart';
import 'synced_lyrics_display.dart';

/// Widget to display lyrics with support for both plain and synced modes
class LyricsDisplay extends ConsumerStatefulWidget {
  final Lyrics lyrics;
  final bool showActions;
  final Duration? currentPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;

  const LyricsDisplay({
    super.key,
    required this.lyrics,
    this.showActions = true,
    this.currentPosition,
    this.isPlaying = false,
    this.onSeek,
  });

  @override
  ConsumerState<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends ConsumerState<LyricsDisplay> {
  double _syncedFontSize = 22.0; // Default size for synced lyrics
  bool _showSizeSlider = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final showSyncedLyrics = settings.showSyncedLyrics;

    final hasSyncedLyrics =
        widget.lyrics.isSynced &&
        widget.lyrics.lrcLyrics != null &&
        LrcParser.isValidLrc(widget.lyrics.lrcLyrics!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Actions row
        if (widget.showActions)
          _buildActionsRow(context, hasSyncedLyrics, showSyncedLyrics),
        // Font size slider (only for synced lyrics)
        if (hasSyncedLyrics && showSyncedLyrics && _showSizeSlider)
          _buildFontSizeSlider(),
        const SizedBox(height: 16),
        // Lyrics content - show synced if available and toggle is on
        if (hasSyncedLyrics && showSyncedLyrics)
          _buildSyncedLyrics()
        else
          _buildPlainLyrics(),
        const SizedBox(height: 16),
        // Source info
        _buildSourceInfo(context),
      ],
    );
  }

  Widget _buildFontSizeSlider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surfaceLight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.text_fields, size: 18, color: textSecondary),
          const SizedBox(width: 12),
          Text(
            'Aa',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textHint,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: surfaceLight,
                thumbColor: AppTheme.primaryLight,
                overlayColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _syncedFontSize,
                min: 14,
                max: 32,
                divisions: 6,
                onChanged: (value) {
                  setState(() => _syncedFontSize = value);
                },
              ),
            ),
          ),
          Text(
            'Aa',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildActionsRow(
    BuildContext context,
    bool hasSyncedLyrics,
    bool showSyncedLyrics,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: isDark ? 0.7 : 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: surfaceLight.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasSyncedLyrics) _buildChipToggle(showSyncedLyrics),
              if (hasSyncedLyrics) const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasSyncedLyrics && showSyncedLyrics)
                    _buildActionButton(
                      icon: _showSizeSlider
                          ? Icons.text_fields
                          : Icons.format_size_rounded,
                      label: 'Size',
                      onTap: () {
                        setState(() => _showSizeSlider = !_showSizeSlider);
                      },
                      isActive: _showSizeSlider,
                    ),
                  _buildActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () => _copyToClipboard(context),
                  ),
                  _buildActionButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: () => _shareToClipboard(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildChipToggle(bool showSyncedLyrics) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return Container(
      decoration: BoxDecoration(
        color: surfaceLight.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleChip(
            label: 'Synced',
            icon: Icons.sync_rounded,
            isSelected: showSyncedLyrics,
            onTap: () =>
                ref.read(settingsProvider.notifier).setShowSyncedLyrics(true),
          ),
          _buildToggleChip(
            label: 'Plain',
            icon: Icons.format_align_left_rounded,
            isSelected: !showSyncedLyrics,
            onTap: () =>
                ref.read(settingsProvider.notifier).setShowSyncedLyrics(false),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? AppTheme.primaryLight : textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive ? AppTheme.primaryLight : textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlainLyrics() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final cardGradient = isDark
        ? AppTheme.cardGradient
        : AppTheme.lightCardGradient;
    final borderColor = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final shadow = isDark
        ? <BoxShadow>[]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor.withValues(alpha: 0.5)),
        boxShadow: shadow,
      ),
      child: SelectableText(
        widget.lyrics.plainLyrics,
        style: TextStyle(
          fontSize: 18,
          height: 1.85,
          fontWeight: FontWeight.w500,
          color: textColor,
          letterSpacing: 0.3,
        ),
        textAlign: TextAlign.center,
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildSyncedLyrics() {
    // Dynamic height based on font size (larger fonts need more space)
    final dynamicHeight = 400 + (_syncedFontSize - 14) * 8;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardGradient = isDark
        ? AppTheme.cardGradient
        : AppTheme.lightCardGradient;
    final borderColor = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return Container(
      height: dynamicHeight.clamp(400.0, 600.0),
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SyncedLyricsDisplay(
        lrcContent: widget.lyrics.lrcLyrics!,
        currentPosition: widget.currentPosition ?? Duration.zero,
        isPlaying: widget.isPlaying,
        onSeek: widget.onSeek,
        fontSize: _syncedFontSize,
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.98, 0.98));
  }

  Widget _buildSourceInfo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_outlined, size: 14, color: textHint),
          const SizedBox(width: 6),
          Text(
            widget.lyrics.source,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textHint,
            ),
          ),
          if (widget.lyrics.isSynced) ...[
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: textHint.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.successColor.withValues(alpha: 0.2),
                    AppTheme.successColor.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.successColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 12,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Synced',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 500.ms, delay: 200.ms);
  }

  void _copyToClipboard(BuildContext context) {
    final text = '${widget.lyrics.plainLyrics}\n\n— Sent via FlashLyrics';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.successColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            const Text('Lyrics copied to clipboard'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareToClipboard(BuildContext context) async {
    // Get current song from lyrics provider
    final lyricsState = ref.read(lyricsNotifierProvider);
    final currentSong = lyricsState.currentSong;

    if (currentSong == null) {
      // Fallback to text sharing if no song info
      final formattedLyrics = '''${widget.lyrics.plainLyrics}

— Shared via FlashLyrics''';
      Share.share(formattedLyrics);
      return;
    }

    // Show loading indicator
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Creating lyrics image...'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      // Generate lyrics image
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final imageFile = await LyricsImageGenerator.generateLyricsImage(
        song: currentSong,
        lyrics: widget.lyrics,
        isDark: isDark,
      );

      if (imageFile != null && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();

        // Share the image
        await Share.shareXFiles(
          [XFile(imageFile.path)],
          text:
              '${currentSong.title} - ${currentSong.artist}\n\nShared from FlashLyrics',
        );
      } else if (context.mounted) {
        // Fallback to text if image generation failed
        ScaffoldMessenger.of(context).clearSnackBars();
        final formattedLyrics =
            '''${currentSong.title} - ${currentSong.artist}

${widget.lyrics.plainLyrics}

— Shared via FlashLyrics''';
        Share.share(formattedLyrics);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Error sharing: $e')),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
