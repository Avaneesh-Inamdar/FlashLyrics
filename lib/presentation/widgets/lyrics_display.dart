import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';
import '../../domain/entities/lyrics.dart';
import 'synced_lyrics_display.dart';

/// Widget to display lyrics with support for both plain and synced modes
class LyricsDisplay extends StatefulWidget {
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
  State<LyricsDisplay> createState() => _LyricsDisplayState();
}

class _LyricsDisplayState extends State<LyricsDisplay> {
  bool _showSyncedLyrics = true;

  @override
  Widget build(BuildContext context) {
    final hasSyncedLyrics =
        widget.lyrics.isSynced &&
        widget.lyrics.lrcLyrics != null &&
        LrcParser.isValidLrc(widget.lyrics.lrcLyrics!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Actions row
        if (widget.showActions) _buildActionsRow(context, hasSyncedLyrics),
        const SizedBox(height: 16),
        // Lyrics content - show synced if available and toggle is on
        if (hasSyncedLyrics && _showSyncedLyrics)
          _buildSyncedLyrics()
        else
          _buildPlainLyrics(),
        const SizedBox(height: 16),
        // Source info
        _buildSourceInfo(context),
      ],
    );
  }

  Widget _buildActionsRow(BuildContext context, bool hasSyncedLyrics) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.surfaceLight.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Synced/Plain toggle
              if (hasSyncedLyrics)
                _buildChipToggle()
              else
                const SizedBox.shrink(),
              // Action buttons
              Row(
                children: [
                  _buildActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () => _copyToClipboard(context),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: () => _copyToClipboard(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildChipToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleChip(
            label: 'Synced',
            icon: Icons.sync_rounded,
            isSelected: _showSyncedLyrics,
            onTap: () => setState(() => _showSyncedLyrics = true),
          ),
          _buildToggleChip(
            label: 'Plain',
            icon: Icons.format_align_left_rounded,
            isSelected: !_showSyncedLyrics,
            onTap: () => setState(() => _showSyncedLyrics = false),
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
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
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
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlainLyrics() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: SelectableText(
        widget.lyrics.plainLyrics,
        style: const TextStyle(
          fontSize: 18,
          height: 2.0,
          color: AppTheme.textPrimary,
          letterSpacing: 0.3,
        ),
        textAlign: TextAlign.center,
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildSyncedLyrics() {
    return Container(
      height: 450,
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SyncedLyricsDisplay(
        lrcContent: widget.lyrics.lrcLyrics!,
        currentPosition: widget.currentPosition ?? Duration.zero,
        isPlaying: widget.isPlaying,
        onSeek: widget.onSeek,
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.98, 0.98));
  }

  Widget _buildSourceInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_outlined, size: 14, color: AppTheme.textHint),
          const SizedBox(width: 6),
          Text(
            widget.lyrics.source,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textHint,
            ),
          ),
          if (widget.lyrics.isSynced) ...[
            Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppTheme.textHint.withValues(alpha: 0.5),
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
    final text = '${widget.lyrics.plainLyrics}\n\n— Sent via LyricX';
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
}
