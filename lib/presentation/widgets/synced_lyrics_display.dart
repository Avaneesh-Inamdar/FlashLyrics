import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';

/// Widget to display synchronized lyrics with beautiful highlighting
class SyncedLyricsDisplay extends StatefulWidget {
  final String lrcContent;
  final Duration currentPosition;
  final bool isPlaying;
  final ValueChanged<Duration>? onSeek;

  const SyncedLyricsDisplay({
    super.key,
    required this.lrcContent,
    required this.currentPosition,
    this.isPlaying = false,
    this.onSeek,
  });

  @override
  State<SyncedLyricsDisplay> createState() => _SyncedLyricsDisplayState();
}

class _SyncedLyricsDisplayState extends State<SyncedLyricsDisplay>
    with SingleTickerProviderStateMixin {
  ParsedLrc? _parsedLrc;
  int _currentLineIndex = -1;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _glowController;

  static const double _itemHeight = 56.0;
  static const double _highlightedItemHeight = 72.0;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _parseLrc();
  }

  @override
  void didUpdateWidget(SyncedLyricsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lrcContent != widget.lrcContent) {
      _parseLrc();
    }
    if (oldWidget.currentPosition != widget.currentPosition &&
        _parsedLrc != null) {
      _updateCurrentLine();
    }
  }

  Future<void> _parseLrc() async {
    final parsed = await LrcParser.parse(widget.lrcContent);
    if (mounted) {
      setState(() {
        _parsedLrc = parsed;
        _updateCurrentLine();
      });
    }
  }

  void _updateCurrentLine() {
    if (_parsedLrc == null) return;
    final newIndex = _parsedLrc!.getLineIndexAtTime(widget.currentPosition);
    if (newIndex != _currentLineIndex) {
      setState(() => _currentLineIndex = newIndex);
      _scrollToCurrentLine();
    }
  }

  void _scrollToCurrentLine() {
    if (_currentLineIndex < 0 || !_scrollController.hasClients) return;
    final targetOffset =
        (_currentLineIndex * _itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (_highlightedItemHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_parsedLrc == null) {
      return Center(child: _buildLoadingIndicator());
    }

    if (_parsedLrc!.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off_rounded,
              size: 48,
              color: AppTheme.textHint.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No synced lyrics available',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textHint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Main lyrics list
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.12, 0.88, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 120),
            physics: const BouncingScrollPhysics(),
            itemCount: _parsedLrc!.lines.length,
            itemBuilder: (context, index) => _buildLyricLine(index),
          ),
        ),
        // Top gradient overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.surfaceColor,
                    AppTheme.surfaceColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom gradient overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 80,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppTheme.surfaceColor,
                    AppTheme.surfaceColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(
              AppTheme.primaryColor.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading lyrics...',
          style: TextStyle(fontSize: 14, color: AppTheme.textHint),
        ),
      ],
    );
  }

  Widget _buildLyricLine(int index) {
    final line = _parsedLrc!.lines[index];
    final isCurrentLine = index == _currentLineIndex;
    final isPastLine = index < _currentLineIndex;
    final distance = (index - _currentLineIndex).abs();

    // Calculate opacity based on distance from current line
    double opacity = 1.0;
    if (!isCurrentLine) {
      opacity = (1.0 - (distance * 0.15)).clamp(0.3, 0.8);
    }

    return GestureDetector(
      onTap: widget.onSeek != null
          ? () => widget.onSeek!(line.timestamp)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: isCurrentLine ? 18 : 12,
        ),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            return Container(
              decoration: isCurrentLine
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(
                            alpha: 0.15 + (_glowController.value * 0.1),
                          ),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    )
                  : null,
              child: child,
            );
          },
          child: _buildLyricText(line, isCurrentLine, isPastLine, opacity),
        ),
      ),
    );
  }

  Widget _buildLyricText(
    LrcLine line,
    bool isCurrentLine,
    bool isPastLine,
    double opacity,
  ) {
    final text = line.text.isEmpty ? '♪' : line.text;

    if (isCurrentLine) {
      return ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                AppTheme.primaryLight,
                AppTheme.primaryColor,
                AppTheme.accentColor,
              ],
            ).createShader(bounds),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.4,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          )
          .animate(onPlay: (c) => c.forward())
          .scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1.0, 1.0),
            duration: 250.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 200.ms);
    }

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: isPastLine
            ? AppTheme.textHint.withValues(alpha: opacity * 0.6)
            : AppTheme.textSecondary.withValues(alpha: opacity),
        height: 1.5,
      ),
      textAlign: TextAlign.center,
      child: Text(text, textAlign: TextAlign.center),
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

        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.surfaceColor.withValues(alpha: 0.9),
                    AppTheme.surfaceColor.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentLine != null)
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppTheme.primaryLight, AppTheme.primaryColor],
                      ).createShader(bounds),
                      child: Text(
                        currentLine.text.isEmpty ? '♪' : currentLine.text,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (nextLine != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      nextLine.text.isEmpty ? '♪' : nextLine.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textHint,
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
