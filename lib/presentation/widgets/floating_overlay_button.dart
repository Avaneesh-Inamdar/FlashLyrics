import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';
import '../providers/media_provider.dart';
import '../providers/lyrics_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/overlay_provider.dart';
import '../../services/media_detection_service.dart';

/// Small floating button that appears when music is playing
/// Allows user to show lyrics in system overlay window without opening app
class FloatingLyricsButton extends ConsumerStatefulWidget {
  const FloatingLyricsButton({super.key});

  @override
  ConsumerState<FloatingLyricsButton> createState() => _FloatingLyricsButtonState();
}

class _FloatingLyricsButtonState extends ConsumerState<FloatingLyricsButton> {
  ParsedLrc? _parsed;
  String? _lastLrc;

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaNotifierProvider);
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final settings = ref.watch(settingsProvider);
    final overlay = ref.watch(overlayProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Only show when there's a song and lyrics
    final hasSong = lyricsState.currentSong != null && lyricsState.lyrics != null;
    if (!hasSong) return const SizedBox.shrink();

    // Prepare LRC parsing for current line preview (native now handles realtime sync, so Flutter just shows initial)
    final lrcContent = lyricsState.lyrics?.lrcLyrics;
    if (lrcContent != null && lrcContent != _lastLrc) {
      _lastLrc = lrcContent;
      LrcParser.parse(lrcContent).then((p) {
        if (mounted) setState(() => _parsed = p);
      });
    }
    // No Flutter-driven overlay updates needed - native service syncs in realtime via MediaSessionManager
    // We keep parsing only for Show button preview

    final song = lyricsState.currentSong!;
    final lyrics = lyricsState.lyrics!;

    // If floating feature disabled, show prompt to enable
    if (!settings.floatingLyricsEnabled) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.picture_in_picture_alt_rounded, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Floating lyrics', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary)),
                  Text('Show lyrics over other apps', style: TextStyle(fontSize: 11, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary)),
                ],
              ),
            ),
            Switch(
              value: false,
              onChanged: (v) async {
                if (!overlay.hasPermission) {
                  final granted = await _requestOverlayWithDialog(context);
                  if (!granted) return;
                  await ref.read(overlayProvider.notifier).checkPermission();
                }
                ref.read(settingsProvider.notifier).setFloatingLyricsEnabled(true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floating lyrics enabled. Tap the button to show overlay.')));
                }
              },
            ),
          ],
        ),
      );
    }

    // When enabled, show action row
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.layers_rounded, color: AppTheme.primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(overlay.isShowing ? 'Overlay active' : 'Show over other apps',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary)),
          ),
          if (!overlay.hasPermission)
            TextButton(
              onPressed: () async {
                final ok = await _requestOverlayWithDialog(context);
                if (ok) await ref.read(overlayProvider.notifier).checkPermission();
              },
              child: const Text('Allow'),
            )
          else if (!overlay.isShowing)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              onPressed: () async {
                final current = _getCurrentLine(media.currentPosition, settings.lyricsSyncOffset);
                final ok = await ref.read(overlayProvider.notifier).show(
                      title: song.title,
                      artist: song.artist,
                      plainLyrics: lyrics.plainLyrics,
                      currentLine: current,
                      lrcLyrics: lyrics.lrcLyrics ?? '',
                      syncOffsetMs: settings.lyricsSyncOffset,
                      enableSeek: settings.floatingOverlaySeekEnabled,
                    );
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to show overlay. Check permission.')));
                }
              },
              child: const Text('Show'),
            )
          else
            OutlinedButton(
              onPressed: () => ref.read(overlayProvider.notifier).hide(),
              child: const Text('Hide'),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.picture_in_picture_alt_rounded, size: 20, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
            tooltip: 'PiP mode',
            onPressed: () async {
              final svc = ref.read(mediaDetectionServiceProvider);
              await svc.enterPipMode();
            },
          ),
        ],
      ),
    );
  }

  String _getCurrentLine(Duration pos, int offset) {
    if (_parsed == null) return '';
    final adj = pos + Duration(milliseconds: offset + 800);
    final idx = _parsed!.getLineIndexAtTime(adj);
    if (idx >= 0 && idx < _parsed!.lines.length) return _parsed!.lines[idx].text;
    return '';
  }

  Future<bool> _requestOverlayWithDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow overlay?'),
        content: const Text('FlashLyrics needs "Display over other apps" permission to show floating lyrics while you use other music apps. You will be taken to system settings to enable it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
        ],
      ),
    );
    if (confirmed == true) {
      await MediaDetectionService.requestOverlayPermission();
      // Wait a bit then re-check
      await Future.delayed(const Duration(seconds: 1));
      final has = await MediaDetectionService.checkOverlayPermission();
      return has;
    }
    return false;
  }
}
