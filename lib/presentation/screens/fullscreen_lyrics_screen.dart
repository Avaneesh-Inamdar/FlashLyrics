import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';
import '../../data/models/lyrics_model.dart';
import '../../domain/entities/lyrics.dart';
import '../providers/providers.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/lyrics_share.dart';
import '../widgets/synced_lyrics_display.dart';

/// Lyrics-only view that fills the screen.
///
/// Hides the system bars, keeps the screen on while open and follows the
/// current song, so it can stay open across track changes. The only other
/// content is a slim header (song, text size, close) and, when ads are on,
/// a banner at the bottom.
///
/// Long-pressing a line starts a selection: tap more lines to extend it, then
/// share them as an image, the same way as on the Listening screen.
class FullscreenLyricsScreen extends ConsumerStatefulWidget {
  const FullscreenLyricsScreen({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'fullscreen-lyrics'),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const FullscreenLyricsScreen(),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  static const minFontSize = 20.0;
  static const maxFontSize = 44.0;
  static const defaultFontSize = 30.0;
  static const fontStep = 4.0;
  static const fontSizePrefKey = 'fullscreen_lyrics_font_size';

  @override
  ConsumerState<FullscreenLyricsScreen> createState() =>
      _FullscreenLyricsScreenState();
}

class _FullscreenLyricsScreenState
    extends ConsumerState<FullscreenLyricsScreen> {
  late double _fontSize;
  late final bool _keepScreenOnSetting;

  /// Lines being selected for sharing, or null when not selecting.
  _Selection? _selection;

  @override
  void initState() {
    super.initState();
    final saved = ref
        .read(sharedPreferencesProvider)
        .getDouble(FullscreenLyricsScreen.fontSizePrefKey);
    _fontSize = (saved ?? FullscreenLyricsScreen.defaultFontSize).clamp(
      FullscreenLyricsScreen.minFontSize,
      FullscreenLyricsScreen.maxFontSize,
    );
    _keepScreenOnSetting = ref.read(settingsProvider).keepScreenOn;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    // Back to the app-wide mode set in main.dart.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // The Listening screen keeps the screen on only with "Keep Screen On".
    if (!_keepScreenOnSetting) WakelockPlus.disable();
    super.dispose();
  }

  void _changeFontSize(double delta) {
    final next = (_fontSize + delta).clamp(
      FullscreenLyricsScreen.minFontSize,
      FullscreenLyricsScreen.maxFontSize,
    );
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    ref
        .read(sharedPreferencesProvider)
        .setDouble(FullscreenLyricsScreen.fontSizePrefKey, next);
  }

  void _startSelection(Lyrics lyrics, List<String> lines, int index) {
    if (index < 0 || index >= lines.length) return;
    HapticFeedback.selectionClick();
    setState(
      () => _selection = _Selection(
        lyricsId: lyrics.id,
        lines: lines,
        start: index,
        end: index,
        anchor: index,
      ),
    );
  }

  /// Same rules as the Listening screen: a line before or after the
  /// selection extends it, a line inside it narrows the selection to that
  /// line, and tapping the only selected line clears it.
  void _tapLine(int index) {
    final sel = _selection;
    if (sel == null) return;
    if (index < sel.start) {
      setState(() => _selection = sel.copyWith(start: index));
    } else if (index > sel.end) {
      setState(() => _selection = sel.copyWith(end: index));
    } else if (sel.start == sel.end) {
      _endSelection();
    } else {
      setState(() => _selection = sel.copyWith(start: index, end: index));
    }
  }

  void _endSelection() {
    if (_selection != null) setState(() => _selection = null);
  }

  Future<void> _shareSelection() async {
    final sel = _selection;
    if (sel == null) return;
    final state = ref.read(lyricsNotifierProvider);
    final lyrics = state.lyrics;
    final song = lyrics == null
        ? state.currentSong
        : songForLyrics(lyrics, state.currentSong);
    await shareLyricLines(context, song: song, lines: sel.selectedLines);
    if (mounted) _endSelection();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final song = lyricsState.currentSong;
    // A new song ends any selection made on the previous one.
    ref.listen<String?>(
      lyricsNotifierProvider.select((s) => s.lyrics?.id),
      (_, _) => _endSelection(),
    );
    final selection = _selection;

    return PopScope(
      // Back first ends a selection, then leaves full screen.
      canPop: selection == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSelection();
      },
      child: Scaffold(
        // The lyrics card colour, which the synced view's edge fades blend into.
        backgroundColor: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                title: song?.title,
                artist: song?.artist,
                canShrink: _fontSize > FullscreenLyricsScreen.minFontSize,
                canGrow: _fontSize < FullscreenLyricsScreen.maxFontSize,
                onShrink: () =>
                    _changeFontSize(-FullscreenLyricsScreen.fontStep),
                onGrow: () => _changeFontSize(FullscreenLyricsScreen.fontStep),
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: selection == null
                    ? _buildLyrics(lyricsState, isDark)
                    : _SelectableLines(
                        selection: selection,
                        fontSize: _fontSize * 0.8,
                        onTap: _tapLine,
                      ),
              ),
              if (selection != null)
                _SelectionBar(
                  count: selection.selectedLines
                      .where((line) => line.trim().isNotEmpty)
                      .length,
                  onCancel: _endSelection,
                  onShare: _shareSelection,
                ),
              const AdBannerWidget(
                prodAdUnitId: AdBannerWidget.fullscreenAdUnitId,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyrics(LyricsState state, bool isDark) {
    final lyrics = state.lyrics;
    if (lyrics == null) {
      return _Message(
        text: state.isLoading ? 'Finding lyrics…' : 'No lyrics for this song',
        loading: state.isLoading,
      );
    }

    final settings = ref.watch(settingsProvider);
    final lrc = lyrics.lrcLyrics;
    final synced =
        settings.showSyncedLyrics &&
        lyrics.isSynced &&
        lrc != null &&
        LrcParser.isValidLrc(lrc);

    if (!synced) {
      return _PlainLyrics(
        key: ValueKey('plain-${lyrics.id}'),
        lyrics: lyrics,
        fontSize: _fontSize * 0.8,
        isDark: isDark,
        onLongPress: (index, lines) => _startSelection(lyrics, lines, index),
      );
    }

    final songKey = _songKey(lyrics, state);
    final offset =
        ref.watch(songOffsetProvider.select((offsets) => offsets[songKey])) ??
        settings.lyricsSyncOffset;
    final position = ref.watch(
      mediaNotifierProvider.select((s) => s.currentPosition),
    );
    final playing = ref.watch(mediaNotifierProvider.select((s) => s.isPlaying));

    return SyncedLyricsDisplay(
      key: ValueKey('synced-${lyrics.id}'),
      lrcContent: lrc,
      currentPosition: position,
      isPlaying: playing,
      estimateWordTiming: settings.karaokeEnabled,
      fontSize: _fontSize,
      syncOffsetMs: offset,
      onSeek: (to) => ref.read(mediaNotifierProvider.notifier).seekTo(to),
      onOffsetChanged: (value) =>
          ref.read(songOffsetProvider.notifier).setSongOffset(songKey, value),
      onLineLongPress: (index, lines) => _startSelection(lyrics, lines, index),
    );
  }

  /// Same per-song offset key the Listening screen uses.
  String _songKey(Lyrics lyrics, LyricsState state) {
    final model = lyrics is LyricsModel ? lyrics : null;
    return generateSongKey(
      songId: lyrics.songId,
      artist: model?.artistName ?? state.currentSong?.artist,
      title: model?.trackName ?? state.currentSong?.title,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.artist,
    required this.canShrink,
    required this.canGrow,
    required this.onShrink,
    required this.onGrow,
    required this.onClose,
  });

  final String? title;
  final String? artist;
  final bool canShrink;
  final bool canGrow;
  final VoidCallback onShrink;
  final VoidCallback onGrow;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final secondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null)
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                if (artist != null)
                  Text(
                    artist!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Smaller text',
            onPressed: canShrink ? onShrink : null,
            icon: const Icon(Icons.text_decrease_rounded),
            color: secondary,
          ),
          IconButton(
            tooltip: 'Larger text',
            onPressed: canGrow ? onGrow : null,
            icon: const Icon(Icons.text_increase_rounded),
            color: secondary,
          ),
          IconButton(
            tooltip: 'Exit full screen',
            onPressed: onClose,
            icon: const Icon(Icons.fullscreen_exit_rounded),
            color: primary,
          ),
        ],
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({
    super.key,
    required this.lyrics,
    required this.fontSize,
    required this.isDark,
    required this.onLongPress,
  });

  final Lyrics lyrics;
  final double fontSize;
  final bool isDark;
  final void Function(int index, List<String> lines) onLongPress;

  @override
  Widget build(BuildContext context) {
    var text = lyrics.plainLyrics;
    if (text.trim().isEmpty && lyrics.lrcLyrics != null) {
      text = LrcParser.toCleanPlainText(lyrics.lrcLyrics!);
    }
    final lines = text.split('\n').map(LrcParser.stripTimeTags).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: lines[i].trim().isEmpty
                  ? null
                  : () => onLongPress(i, lines),
              child: Padding(
                padding: EdgeInsets.only(bottom: fontSize * 0.45),
                child: Text(
                  lines[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.textPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lines picked for sharing, as an inclusive range of line indexes.
class _Selection {
  const _Selection({
    required this.lyricsId,
    required this.lines,
    required this.start,
    required this.end,
    required this.anchor,
  });

  final String lyricsId;
  final List<String> lines;
  final int start;
  final int end;

  /// The long-pressed line, kept in view when selection starts.
  final int anchor;

  List<String> get selectedLines => lines.sublist(start, end + 1);

  bool contains(int index) => index >= start && index <= end;

  _Selection copyWith({int? start, int? end}) => _Selection(
    lyricsId: lyricsId,
    lines: lines,
    start: start ?? this.start,
    end: end ?? this.end,
    anchor: anchor,
  );
}

class _SelectableLines extends StatefulWidget {
  const _SelectableLines({
    required this.selection,
    required this.fontSize,
    required this.onTap,
  });

  final _Selection selection;
  final double fontSize;
  final ValueChanged<int> onTap;

  @override
  State<_SelectableLines> createState() => _SelectableLinesState();
}

class _SelectableLinesState extends State<_SelectableLines> {
  final _anchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Open with the long-pressed line in view, as it was on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _anchorKey.currentContext;
      if (anchor != null) Scrollable.ensureVisible(anchor, alignment: 0.4);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sel = widget.selection;
    final textColor = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sel.lines.length; i++)
            if (sel.lines[i].trim().isEmpty)
              SizedBox(height: widget.fontSize * 0.6)
            else
              GestureDetector(
                key: i == sel.anchor ? _anchorKey : null,
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: sel.contains(i)
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel.contains(i)
                          ? AppTheme.primaryColor.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    sel.lines[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onShare,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 line · tap more to add' : '$count lines selected',
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: count == 0 ? null : onShare,
            icon: const Icon(Icons.share_rounded, size: 18),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.loading});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
