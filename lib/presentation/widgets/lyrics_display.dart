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
import '../providers/media_provider.dart';
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
  bool _isShareSelectionMode = false;
  int? _selectedStart;
  int? _selectedEnd;
  final ScrollController _plainLyricsScrollController = ScrollController();
  int? _currentLineIndexForScroll; // Target plain line to scroll to when entering share mode
  // Keys for each plain lyric line to enable precise scroll to current playback position
  List<GlobalKey> _lineKeys = [];

  @override
  void dispose() {
    _plainLyricsScrollController.dispose();
    super.dispose();
  }

  bool get _hasSelection => _selectedStart != null && _selectedEnd != null;

  int get _selectedCount {
    if (!_hasSelection) return 0;
    return (_selectedEnd! - _selectedStart! + 1).abs();
  }

  List<String> _plainLyricsLines() {
    return widget.lyrics.plainLyrics.split('\n');
  }

  void _ensureLineKeys(int count) {
    if (_lineKeys.length != count) {
      _lineKeys = List.generate(count, (_) => GlobalKey());
    }
  }

  void _clearSelection() {
    if (!_hasSelection) return;
    setState(() {
      _selectedStart = null;
      _selectedEnd = null;
    });
  }

  void _exitShareMode() {
    _clearSelection();
    setState(() {
      _isShareSelectionMode = false;
      _currentLineIndexForScroll = null;
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
      _exitShareMode();
      _lineKeys = [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final showSyncedLyrics =
        settings.showSyncedLyrics && !_isShareSelectionMode;

    final hasSyncedLyrics =
        widget.lyrics.isSynced &&
        widget.lyrics.lrcLyrics != null &&
        LrcParser.isValidLrc(widget.lyrics.lrcLyrics!);

    // Show synced lyrics when available AND setting is enabled AND not in share mode
    final useSyncedLyrics = hasSyncedLyrics && showSyncedLyrics;

    return Stack(
      children: [
        Column(
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
        ),
        // Floating share button when lines are selected
        if (_hasSelection && !showSyncedLyrics)
          _buildFloatingShareButton(context),
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
                  // Show cancel button when in share mode (plain lyrics view with synced available)
                  if (_isShareSelectionMode || (hasSyncedLyrics && !showSyncedLyrics))
                    _buildActionButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: _exitShareMode,
                    ),
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

    _ensureLineKeys(lines.length);

    return Container(
      height: 500, // Fixed height to make it scrollable
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: ListView.builder(
        controller: _plainLyricsScrollController,
        cacheExtent: 5000,
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          final isEmpty = line.trim().isEmpty;
          final isSelected =
              _hasSelection &&
              index >= _selectedStart! &&
              index <= _selectedEnd!;
          final isTargetLine = _currentLineIndexForScroll != null && index == _currentLineIndexForScroll;

          if (isEmpty) {
            return SizedBox(key: _lineKeys[index], height: 14);
          }

          return Container(
            key: _lineKeys[index],
            child: GestureDetector(
              onTap: () => _updateSelection(index),
              onLongPress: () => _shareSingleLine(context, line),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withValues(alpha: 0.15)
                      : isTargetLine
                          ? AppTheme.successColor.withValues(alpha: 0.10)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.35))
                      : isTargetLine
                          ? Border.all(color: AppTheme.successColor.withValues(alpha: 0.25))
                          : null,
                ),
                child: Column(
                  children: [
                    if (isTargetLine && !_hasSelection)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: AppTheme.successColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('Now playing • ${_formatDuration(widget.currentPosition)}', style: TextStyle(fontSize: 11, color: AppTheme.successColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    Text(
                      line,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.7,
                        fontWeight: isTargetLine ? FontWeight.w700 : FontWeight.w500,
                        color: textColor,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0:00';
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildFloatingShareButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Positioned(
      bottom: 80,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(30),
        color: AppTheme.primaryColor,
        child: InkWell(
          onTap: () => _shareToClipboard(context),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.share_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Share (${_selectedCount.toString()})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.8, 0.8)),
    );
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
        onOffsetChanged: (newOffset) {
          ref.read(settingsProvider.notifier).setLyricsSyncOffset(newOffset);
        },
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

      // Clear selection and exit share mode after sharing
      if (!mounted) return;
      _exitShareMode();
    } catch (e) {
      // Restore state even on error
      if (mounted) {
        _exitShareMode();
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

  Future<void> _handleShareTap(BuildContext context, bool showSyncedLyrics) async {
    if (_hasSelection) {
      await _shareToClipboard(context);
      return;
    }

    // Switch to local share selection mode without altering user's global settings
    setState(() {
      _isShareSelectionMode = true;
    });

    if (widget.lyrics.isSynced && widget.lyrics.lrcLyrics != null) {
      await _calculateCurrentLineIndex();
      _scrollToCurrentLine();
    }

    final pos = widget.currentPosition ?? ref.read(mediaNotifierProvider).currentPosition;
    final posLabel = _formatDuration(pos);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_currentLineIndexForScroll != null
              ? 'Scrolled to $posLabel — tap lines to select, share button to create image'
              : 'Tap lines to select, long-press to share single line'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.surfaceLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  Future<void> _calculateCurrentLineIndex() async {
    final lrc = widget.lyrics.lrcLyrics;
    final pos = widget.currentPosition ?? ref.read(mediaNotifierProvider).currentPosition;
    if (lrc == null || pos == Duration.zero) return;
    
    try {
      final parsedLrc = await LrcParser.parse(lrc);
      if (!mounted) return;
      
      // Replicate synced display's lead time (800ms + user offset) to find the
      // same line the user currently sees highlighted at playback position
      final settings = ref.read(settingsProvider);
      final lead = const Duration(milliseconds: 800) + Duration(milliseconds: settings.lyricsSyncOffset);
      final adjusted = pos + lead;
      final currentIndex = parsedLrc.getLineIndexAtTime(adjusted);
      if (currentIndex < 0 || currentIndex >= parsedLrc.lines.length) return;

      final currentText = parsedLrc.lines[currentIndex].text.trim();
      final plainLines = _plainLyricsLines();
      int plainIndex = -1;

      if (currentText.isNotEmpty) {
        // 1. Exact match (trimmed)
        plainIndex = plainLines.indexWhere((l) => l.trim() == currentText);
        // 2. Case-insensitive exact match
        if (plainIndex == -1) {
          plainIndex = plainLines.indexWhere((l) => l.trim().toLowerCase() == currentText.toLowerCase());
        }
        // 3. Substring match
        if (plainIndex == -1) {
          final lower = currentText.toLowerCase();
          plainIndex = plainLines.indexWhere((l) => l.trim().toLowerCase().contains(lower) || lower.contains(l.trim().toLowerCase()));
        }
        // 4. Normalized match (ignoring punctuation)
        if (plainIndex == -1) {
          final normCurrent = currentText.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
          if (normCurrent.isNotEmpty) {
            plainIndex = plainLines.indexWhere((l) {
              final normL = l.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
              return normL == normCurrent || normL.contains(normCurrent) || normCurrent.contains(normL);
            });
          }
        }
      }

      // Fallback: proportional mapping if text not found (e.g., plain vs lrc mismatch)
      if (plainIndex == -1) {
        final ratio = parsedLrc.lines.isEmpty ? 0.0 : currentIndex / parsedLrc.lines.length;
        plainIndex = (ratio * plainLines.length).round().clamp(0, plainLines.length - 1);
        // Skip empty lines near target
        int offset = 0;
        while (plainIndex + offset < plainLines.length && plainLines[plainIndex + offset].trim().isEmpty) offset++;
        if (plainIndex + offset < plainLines.length) plainIndex += offset;
      }

      if (plainIndex >= 0 && mounted) {
        setState(() {
          _currentLineIndexForScroll = plainIndex;
          // Auto-select the current line so user sees it and can immediately share or extend
          _selectedStart = plainIndex;
          _selectedEnd = plainIndex;
        });
      }
    } catch (e) {
      // Ignore parsing errors
    }
  }
  
  void _scrollToCurrentLine() {
    if (_currentLineIndexForScroll == null) return;
    final target = _currentLineIndexForScroll!;
    _ensureLineKeys(_plainLyricsLines().length);
    if (target >= _lineKeys.length) return;
    
    // Wait for plain ListView to be mounted, then use ensureVisible for pixel-perfect scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Extra frame to ensure layout is complete
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final key = _lineKeys[target];
        final ctx = key.currentContext;
        if (ctx != null) {
          try {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              alignment: 0.35, // Show target near top third, with context above/below
            );
            return;
          } catch (_) {
            // Fall through to offset-based scroll
          }
        }
        // Fallback: offset-based scroll if GlobalKey not yet attached
        if (!_plainLyricsScrollController.hasClients) return;
        // Estimate 48px per line (padding + text)
        const est = 48.0;
        final offset = (target * est - 100).clamp(0.0, _plainLyricsScrollController.position.maxScrollExtent);
        _plainLyricsScrollController.animateTo(offset, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      });
    });
  }

  Future<void> _shareSingleLine(BuildContext context, String line) async {
    // Get current song from lyrics provider
    final lyricsState = ref.read(lyricsNotifierProvider);
    final currentSong = lyricsState.currentSong;

    if (currentSong == null || line.trim().isEmpty) return;

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
        lines: [line],
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
            '${currentSong.title} - ${currentSong.artist}\n\n$line\n\n— Shared via FlashLyrics';
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
