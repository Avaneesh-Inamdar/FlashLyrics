import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';

/// Widget to display synchronized lyrics with Apple Music-style smooth scrolling
class SyncedLyricsDisplay extends StatefulWidget {
  final String lrcContent;
  final Duration currentPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;
  final double fontSize;

  const SyncedLyricsDisplay({
    super.key,
    required this.lrcContent,
    required this.currentPosition,
    this.isPlaying = false,
    this.onSeek,
    this.fontSize = 22.0,
  });

  @override
  State<SyncedLyricsDisplay> createState() => _SyncedLyricsDisplayState();
}

class _SyncedLyricsDisplayState extends State<SyncedLyricsDisplay> {
  ParsedLrc? _parsedLrc;
  int _currentLineIndex = -1;
  final ScrollController _scrollController = ScrollController();
  double _viewportPadding = 160.0;
  bool _didInitialScroll = false;
  static const Duration _syncLeadTime = Duration(milliseconds: 1200);

  // Track playback state for resuming scroll after theme change
  bool _wasPlaying = false;

  // Dynamic item height based on font size
  double get _itemHeight => widget.fontSize * 4.0;

  @override
  void initState() {
    super.initState();
    _parseLrc();
    _wasPlaying = widget.isPlaying;
  }

  @override
  void didUpdateWidget(SyncedLyricsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle theme change - rebuild to update colors
    if (oldWidget.fontSize != widget.fontSize) {
      // Font size changed
    }

    if (oldWidget.lrcContent != widget.lrcContent) {
      _didInitialScroll = false;
      _parseLrc();
    }

    // Resume auto-scroll when playback resumes after theme change
    if (_wasPlaying == false && widget.isPlaying == true) {
      // Playback resumed - ensure scrolling continues
      if (_currentLineIndex >= 0) {
        _scrollToCurrentLine(animate: true);
      }
    }
    _wasPlaying = widget.isPlaying;

    if (oldWidget.currentPosition != widget.currentPosition &&
        _parsedLrc != null) {
      _updateCurrentLine();
    }
  }

  Future<void> _parseLrc() async {
    final parsed = await LrcParser.parse(widget.lrcContent);
    if (mounted) {
      final initialIndex = parsed.getLineIndexAtTime(
        _applyLeadTime(widget.currentPosition),
      );
      setState(() {
        _parsedLrc = parsed;
        _currentLineIndex = initialIndex;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didInitialScroll) return;
        _didInitialScroll = true;
        _scrollToCurrentLine(animate: false);
      });
    }
  }

  void _updateCurrentLine() {
    if (_parsedLrc == null || !mounted) return;
    final newIndex = _parsedLrc!.getLineIndexAtTime(
      _applyLeadTime(widget.currentPosition),
    );

    if (newIndex != _currentLineIndex && mounted) {
      setState(() => _currentLineIndex = newIndex);
      _scrollToCurrentLine(animate: true);
    }
  }

  void _scrollToCurrentLine({bool animate = true}) {
    if (_currentLineIndex < 0 || !_scrollController.hasClients || !mounted)
      return;

    try {
      // Calculate target offset to center the current line
      final viewportHeight = _scrollController.position.viewportDimension;
      final centerOffset = viewportHeight / 2 - _itemHeight / 2;

      // Target offset puts current line in the center
      final targetOffset =
          (_currentLineIndex * _itemHeight) + _viewportPadding - centerOffset;

      final clampedOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      if (animate && _scrollController.hasClients) {
        // Optimized animation - faster and more responsive (200ms instead of 350ms)
        if (!_scrollController.position.isScrollingNotifier.value) {
          _scrollController.animateTo(
            clampedOffset,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
          );
        }
      } else if (_scrollController.hasClients) {
        _scrollController.jumpTo(clampedOffset);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error scrolling to current line: $e');
    }
  }

  Duration _applyLeadTime(Duration position) {
    if (position <= _syncLeadTime) return Duration.zero;
    return position - _syncLeadTime;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Track theme to force rebuild on theme change
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_parsedLrc == null) {
      return Center(child: _buildLoadingIndicator(isDark));
    }

    if (_parsedLrc!.lines.isEmpty) {
      final hintColor = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 48, color: hintColor),
            const SizedBox(height: 16),
            Text(
              'No synced lyrics available',
              style: TextStyle(
                fontSize: 15,
                color: hintColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlayColor = isDark
            ? AppTheme.surfaceColor
            : AppTheme.lightSurface;

        final centerPad = (constraints.maxHeight / 2) - (_itemHeight / 2);
        _viewportPadding = centerPad.clamp(80.0, 220.0);

        return Stack(
          children: [
            // Main lyrics list - clean minimal design without shader mask
            ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.symmetric(vertical: _viewportPadding),
              physics: const BouncingScrollPhysics(),
              itemCount: _parsedLrc!.lines.length,
              itemExtent: _itemHeight,
              itemBuilder: (context, index) => _buildLyricLine(index, isDark),
            ),
            // Simple top fade effect
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 48,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [overlayColor, overlayColor.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
            // Simple bottom fade effect
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 48,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [overlayColor, overlayColor.withValues(alpha: 0)],
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

  Widget _buildLoadingIndicator(bool isDark) {
    final indicatorColor = isDark ? AppTheme.textHint : AppTheme.lightTextHint;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(indicatorColor),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading lyrics...',
          style: TextStyle(fontSize: 14, color: indicatorColor),
        ),
      ],
    );
  }

  Widget _buildLyricLine(int index, bool isDark) {
    final line = _parsedLrc!.lines[index];
    final isCurrentLine = index == _currentLineIndex;
    final isPastLine = index < _currentLineIndex;
    final distance = (index - _currentLineIndex).abs();

    // Calculate opacity based on distance from current line
    double opacity = 1.0;
    if (!isCurrentLine) {
      opacity = (1.0 - (distance * 0.15)).clamp(0.3, 0.7);
    }

    // Scale factor for the current line
    final scale = isCurrentLine ? 1.0 : 0.88;

    return GestureDetector(
      onTap: widget.onSeek != null
          ? () => widget.onSeek!(line.timestamp)
          : null,
      child: SizedBox(
        height: _itemHeight,
        child: Center(
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: _buildLyricText(
              line,
              isCurrentLine,
              isPastLine,
              opacity,
              isDark,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricText(
    LrcLine line,
    bool isCurrentLine,
    bool isPastLine,
    double opacity,
    bool isDark,
  ) {
    final text = line.text.isEmpty ? '♪' : line.text;
    final currentFontSize = widget.fontSize;
    final inactiveFontSize = currentFontSize * 0.72;

    if (isCurrentLine) {
      // Current line - clean bold styling without gradients
      final currentLineColor = isDark
          ? AppTheme.textPrimary
          : AppTheme.lightTextPrimary;
      return Text(
            text,
            style: TextStyle(
              fontSize: currentFontSize,
              fontWeight: FontWeight.w700,
              color: currentLineColor,
              height: 1.3,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          )
          .animate()
          .scale(
            begin: const Offset(0.96, 0.96),
            end: const Offset(1.0, 1.0),
            duration: 200.ms,
            curve: Curves.easeOutCubic,
          )
          .fadeIn(duration: 150.ms);
    }

    // Inactive lines - subtle styling
    final pastLineColor = isDark
        ? AppTheme.textSecondary.withValues(alpha: 0.7)
        : AppTheme.lightTextSecondary;
    final upcomingLineColor = isDark
        ? AppTheme.textHint
        : AppTheme.lightTextHint;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        style: TextStyle(
          fontSize: inactiveFontSize,
          fontWeight: FontWeight.w500,
          color: isPastLine ? pastLineColor : upcomingLineColor,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Compact synced lyrics display for overlay mode
class CompactSyncedLyrics extends StatelessWidget {
  final String lrcContent;
  final Duration currentPosition;

  const CompactSyncedLyrics({
    super.key,
    required this.lrcContent,
    required this.currentPosition,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<ParsedLrc>(
      future: LrcParser.parse(lrcContent),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final lrc = snapshot.data!;
        final currentLine = lrc.getLineAtTime(currentPosition);
        final currentIndex = lrc.getLineIndexAtTime(currentPosition);
        final nextLine = currentIndex + 1 < lrc.lines.length
            ? lrc.lines[currentIndex + 1]
            : null;

        // Clean minimal styling
        final backgroundColor = isDark
            ? AppTheme.surfaceColor.withValues(alpha: 0.96)
            : AppTheme.lightSurface.withValues(alpha: 0.96);
        final borderColor = isDark
            ? AppTheme.surfaceLight
            : AppTheme.lightSurfaceLight;
        final textColor = isDark
            ? AppTheme.textPrimary
            : AppTheme.lightTextPrimary;
        final nextLineColor = isDark
            ? AppTheme.textSecondary
            : AppTheme.lightTextSecondary;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentLine != null)
                    Text(
                      currentLine.text.isEmpty ? '♪' : currentLine.text,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (nextLine != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      nextLine.text.isEmpty ? '♪' : nextLine.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: nextLineColor,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
