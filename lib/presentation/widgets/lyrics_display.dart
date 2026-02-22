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
  int? _selectedStart;
  int? _selectedEnd;

  // Track theme to force rebuild on theme change
  Brightness? _lastBrightness;

  bool get _hasSelection => _selectedStart != null && _selectedEnd != null;

  int get _selectedCount {
    if (!_hasSelection) return 0;
    return (_selectedEnd! - _selectedStart! + 1).abs();
  }

  List<String> _plainLyricsLines() {
    return widget.lyrics.plainLyrics.split('\n');
  }

  void _clearSelection() {
    if (!_hasSelection) return;
    setState(() {
      _selectedStart = null;
      _selectedEnd = null;
    });
  }

  void _updateSelection(int index) {
    if (!_hasSelection) {
      setState(() {
        _selectedStart = index;
        _selectedEnd = index;
      });
      return;
    }

    final start = _selectedStart!;
    final end = _selectedEnd!;

    if (index < start) {
      setState(() {
        _selectedStart = index;
        _selectedEnd = end;
      });
      return;
    }

    if (index > end) {
      setState(() {
        _selectedStart = start;
        _selectedEnd = index;
      });
      return;
    }

    if (start == end && index == start) {
      _clearSelection();
      return;
    }

    setState(() {
      _selectedStart = index;
      _selectedEnd = index;
    });
  }

  List<String> _getSelectedLines(List<String> lines) {
    if (!_hasSelection) return const [];
    final start = _selectedStart!;
    final end = _selectedEnd!;
    final safeStart = start.clamp(0, lines.length - 1);
    final safeEnd = end.clamp(0, lines.length - 1);
    return lines.sublist(safeStart, safeEnd + 1);
  }

  @override
  void didUpdateWidget(covariant LyricsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics.id != widget.lyrics.id ||
        oldWidget.lyrics.plainLyrics != widget.lyrics.plainLyrics) {
      _clearSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for theme changes - this ensures rebuild on theme change
    final themeBrightness = Theme.of(context).brightness;

    // Force complete rebuild when theme changes
    final themeChanged =
        _lastBrightness != null && _lastBrightness != themeBrightness;
    if (themeChanged || _lastBrightness == null) {
      _lastBrightness = themeBrightness;
      // Force rebuild by calling setState in post frame callback
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    final settings = ref.watch(settingsProvider);
    final showSyncedLyrics = settings.showSyncedLyrics;

    final hasSyncedLyrics =
        widget.lyrics.isSynced &&
        widget.lyrics.lrcLyrics != null &&
        LrcParser.isValidLrc(widget.lyrics.lrcLyrics!);

    // Show synced lyrics when available AND setting is enabled
    // Setting can be temporarily toggled off for line selection (share as image)
    final useSyncedLyrics = hasSyncedLyrics && showSyncedLyrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Actions row
        if (widget.showActions)
          _buildActionsRow(context, hasSyncedLyrics, showSyncedLyrics),
        // Font size slider (only for synced lyrics)
        if (hasSyncedLyrics && _showSizeSlider) _buildFontSizeSlider(),
        const SizedBox(height: 16),
        // Lyrics content - show synced if available, otherwise plain
        if (useSyncedLyrics) _buildSyncedLyrics() else _buildPlainLyrics(),
        const SizedBox(height: 16),
        // Source info
        _buildSourceInfo(context),
      ],
    );
  }

  Widget _buildFontSizeSlider() {
    // Only show if we have synced lyrics
    final hasSyncedLyrics =
        widget.lyrics.isSynced &&
        widget.lyrics.lrcLyrics != null &&
        LrcParser.isValidLrc(widget.lyrics.lrcLyrics!);

    if (!hasSyncedLyrics) return const SizedBox.shrink();

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
              // Show synced indicator (synced is always preferred now)
              if (hasSyncedLyrics) _buildSyncedIndicator(),
              if (hasSyncedLyrics) const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasSyncedLyrics)
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
                    label: _hasSelection
                        ? 'Share (${_selectedCount.toString()})'
                        : 'Share',
                    onTap: () => _handleShareTap(context, showSyncedLyrics),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildSyncedIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.successColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_rounded, size: 14, color: AppTheme.successColor),
          const SizedBox(width: 6),
          Text(
            'Synced Lyrics Available',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.successColor,
            ),
          ),
        ],
      ),
    );
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
          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: textSecondary.withValues(alpha: 0.25)),
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
    bool isEnabled = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final disabledColor = textSecondary.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
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
                color: isActive
                    ? AppTheme.primaryLight
                    : (isEnabled ? textSecondary : disabledColor),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? AppTheme.primaryLight
                      : (isEnabled ? textSecondary : disabledColor),
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
    final lines = _plainLyricsLines();

    // Clean minimal styling - no gradients
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final backgroundColor = isDark
        ? AppTheme.surfaceColor
        : AppTheme.lightSurface;
    final borderColor = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          final isEmpty = line.trim().isEmpty;
          final isSelected =
              _hasSelection &&
              index >= _selectedStart! &&
              index <= _selectedEnd!;

          if (isEmpty) {
            return const SizedBox(height: 14);
          }

          return GestureDetector(
            onTap: () => _updateSelection(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      )
                    : null,
              ),
              child: Text(
                line,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.7,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildSyncedLyrics() {
    // Dynamic height based on font size (larger fonts need more space)
    final dynamicHeight = 400 + (_syncedFontSize - 14) * 8;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);

    // Clean minimal styling - no gradients
    final backgroundColor = isDark
        ? AppTheme.surfaceColor
        : AppTheme.lightSurface;
    final borderColor = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return Container(
      height: dynamicHeight.clamp(400.0, 600.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: SyncedLyricsDisplay(
        lrcContent: widget.lyrics.lrcLyrics!,
        currentPosition: widget.currentPosition ?? Duration.zero,
        isPlaying: widget.isPlaying,
        onSeek: widget.onSeek,
        fontSize: _syncedFontSize,
        syncOffsetMs: settings.lyricsSyncOffset,
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
                color: AppTheme.successColor.withValues(alpha: 0.15),
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
    if (!_hasSelection) return;

    // Get current song from lyrics provider
    final lyricsState = ref.read(lyricsNotifierProvider);
    final currentSong = lyricsState.currentSong;

    final selectedLines = _getSelectedLines(_plainLyricsLines());

    if (currentSong == null || selectedLines.isEmpty) {
      // Fallback to text sharing if no song info
      final formattedLyrics = '''${selectedLines.join('\n')}

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
        lines: selectedLines,
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
            '${currentSong.title} - ${currentSong.artist}\n\n${selectedLines.join('\n')}\n\n— Shared via FlashLyrics';
        Share.share(formattedLyrics);
      }

      // Restore synced lyrics view and clear selection after sharing
      if (!mounted) return;
      _clearSelection();
      ref.read(settingsProvider.notifier).setShowSyncedLyrics(true);
    } catch (e) {
      // Restore state even on error
      if (mounted) {
        _clearSelection();
        ref.read(settingsProvider.notifier).setShowSyncedLyrics(true);
      }
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

  void _handleShareTap(BuildContext context, bool showSyncedLyrics) {
    if (_hasSelection) {
      _shareToClipboard(context);
      return;
    }

    if (showSyncedLyrics) {
      ref.read(settingsProvider.notifier).setShowSyncedLyrics(false);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tap lyric lines to select and share'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
