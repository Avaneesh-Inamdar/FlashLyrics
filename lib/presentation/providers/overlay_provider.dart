import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/media_detection_service.dart';
import 'media_provider.dart';
import 'settings_provider.dart';
import 'lyrics_provider.dart';

class OverlayState {
  final bool hasPermission;
  final bool isEnabled;
  final bool isShowing;

  const OverlayState({
    this.hasPermission = false,
    this.isEnabled = false,
    this.isShowing = false,
  });

  OverlayState copyWith({bool? hasPermission, bool? isEnabled, bool? isShowing}) =>
      OverlayState(
        hasPermission: hasPermission ?? this.hasPermission,
        isEnabled: isEnabled ?? this.isEnabled,
        isShowing: isShowing ?? this.isShowing,
      );
}

class OverlayNotifier extends StateNotifier<OverlayState> {
  final MediaDetectionService _service;
  final Ref _ref;
  String? _lastPushedSongId;
  String? _lastPushedLyricsId;
  int? _lastPushedOffset;
  bool? _lastPushedSeekEnabled;

  OverlayNotifier(this._service, this._ref) : super(const OverlayState()) {
    _init();
  }

  Future<void> _init() async {
    await checkPermission();
    // Listen to settings change
    _ref.listen<AppSettings>(settingsProvider, (prev, next) async {
      if (prev?.floatingLyricsEnabled != next.floatingLyricsEnabled) {
        state = state.copyWith(isEnabled: next.floatingLyricsEnabled);
        if (!next.floatingLyricsEnabled && state.isShowing) {
          hide();
        }
      }
      // If sync offset or seek mode changed while overlay is showing, push updated lyrics
      final offsetChanged = prev?.lyricsSyncOffset != next.lyricsSyncOffset;
      final seekChanged = prev?.floatingOverlaySeekEnabled != next.floatingOverlaySeekEnabled;
      if ((offsetChanged || seekChanged) && state.isShowing && state.isEnabled) {
        final lyricsState = _ref.read(lyricsNotifierProvider);
        final song = lyricsState.currentSong;
        final lyrics = lyricsState.lyrics;
        final newSeek = next.floatingOverlaySeekEnabled;
        if (song != null && lyrics != null) {
          // Avoid duplicate if already pushed with this offset/seek
          if (_lastPushedSongId == song.id &&
              _lastPushedLyricsId == lyrics.id &&
              _lastPushedOffset == next.lyricsSyncOffset &&
              _lastPushedSeekEnabled == newSeek) {
            return;
          }
          if (kDebugMode) {
            debugPrint(
              '🔄 Overlay settings changed offset ${prev?.lyricsSyncOffset} -> ${next.lyricsSyncOffset} seek $seekChanged, updating overlay',
            );
          }
          try {
            await _service.showOverlay(
              title: song.title,
              artist: song.artist,
              lyrics: lyrics.plainLyrics,
              currentLine: '',
              lrcLyrics: lyrics.lrcLyrics ?? '',
              syncOffsetMs: next.lyricsSyncOffset,
              enableSeek: newSeek,
            );
            _lastPushedSongId = song.id;
            _lastPushedLyricsId = lyrics.id;
            _lastPushedOffset = next.lyricsSyncOffset;
            _lastPushedSeekEnabled = newSeek;
            // Keep cache in sync
            await MediaDetectionService.cacheOverlayLyricsStatic(
              title: song.title,
              artist: song.artist,
              lrcLyrics: lyrics.lrcLyrics ?? '',
              plainLyrics: lyrics.plainLyrics,
              syncOffsetMs: next.lyricsSyncOffset,
              enableSeek: newSeek,
            );
          } catch (e) {
            if (kDebugMode) debugPrint('Overlay offset/seek update failed: $e');
          }
        } else if (song != null) {
          // No lyrics yet but offset/seek changed — update cache so native picks it up
          try {
            await MediaDetectionService.cacheOverlayLyricsStatic(
              title: song.title,
              artist: song.artist,
              lrcLyrics: lyrics?.lrcLyrics ?? '',
              plainLyrics: lyrics?.plainLyrics ?? '',
              syncOffsetMs: next.lyricsSyncOffset,
              enableSeek: newSeek,
            );
          } catch (_) {}
          // Also push placeholder overlay with new seek mode if placeholder is showing
          try {
            await _service.showOverlay(
              title: song.title,
              artist: song.artist,
              lyrics: lyrics?.plainLyrics ?? '',
              currentLine: lyrics == null ? 'Waiting for lyrics...' : '',
              lrcLyrics: lyrics?.lrcLyrics ?? '',
              syncOffsetMs: next.lyricsSyncOffset,
              enableSeek: newSeek,
            );
            _lastPushedSeekEnabled = newSeek;
          } catch (_) {}
        }
      }
    });
    state = state.copyWith(isEnabled: _ref.read(settingsProvider).floatingLyricsEnabled);

    // Auto-update overlay when song / lyrics change while floating lyrics is enabled
    _ref.listen<LyricsState>(lyricsNotifierProvider, (prev, next) async {
      if (!state.isEnabled) return;
      final song = next.currentSong;
      if (song == null) return;

      final prevSongId = prev?.currentSong?.id;
      final nextSongId = song.id;
      final prevLyricsId = prev?.lyrics?.id;
      final nextLyricsId = next.lyrics?.id;
      final prevError = prev?.error;
      final nextError = next.error;
      final wasLoading = prev?.isLoading ?? false;
      final isLoading = next.isLoading;

      final songChanged = prevSongId != nextSongId;
      final lyricsChanged = prevLyricsId != nextLyricsId;
      final errorChanged = prevError != nextError;
      final loadingChanged = wasLoading != isLoading;

      // If nothing meaningful changed, skip
      if (!songChanged && !lyricsChanged && !errorChanged && !loadingChanged) {
        return;
      }

      // Deduplicate identical pushes (same song, same lyrics, same offset & seek mode)
      final currentOffset = _ref.read(settingsProvider).lyricsSyncOffset;
      final currentSeek = _ref.read(settingsProvider).floatingOverlaySeekEnabled;
      if (!songChanged &&
          !lyricsChanged &&
          _lastPushedSongId == nextSongId &&
          _lastPushedLyricsId == nextLyricsId &&
          _lastPushedOffset == currentOffset &&
          _lastPushedSeekEnabled == currentSeek) {
        return;
      }

      // Case 1: lyrics not yet available (fetching or error)
      if (next.lyrics == null) {
        // Only push placeholder when song changed or loading/error state changed
        if (songChanged || errorChanged || loadingChanged) {
          String placeholder;
          if (isLoading) {
            placeholder = 'Fetching lyrics...';
          } else if (nextError != null) {
            placeholder = 'No lyrics found';
          } else {
            placeholder = 'Waiting for lyrics...';
          }
          if (kDebugMode) {
            debugPrint(
              '🔄 Overlay auto-update (placeholder): $placeholder for ${song.title} (songChanged=$songChanged, loading=$isLoading, error=$nextError)',
            );
          }
          try {
            await _service.showOverlay(
              title: song.title,
              artist: song.artist,
              lyrics: '',
              currentLine: placeholder,
              lrcLyrics: '',
              syncOffsetMs: currentOffset,
              enableSeek: currentSeek,
            );
            _lastPushedSongId = nextSongId;
            _lastPushedLyricsId = null;
            _lastPushedOffset = currentOffset;
            _lastPushedSeekEnabled = currentSeek;
            // Update cache so native notification path also reflects new song
            await MediaDetectionService.cacheOverlayLyricsStatic(
              title: song.title,
              artist: song.artist,
              lrcLyrics: '',
              plainLyrics: '',
              syncOffsetMs: currentOffset,
              enableSeek: currentSeek,
            );
          } catch (e) {
            if (kDebugMode) debugPrint('Overlay placeholder update failed: $e');
          }
        }
        return;
      }

      // Case 2: have lyrics — push new content
      final lyrics = next.lyrics!;
      // Extra dedup: if already pushed this exact combo, skip
      if (_lastPushedSongId == nextSongId &&
          _lastPushedLyricsId == lyrics.id &&
          _lastPushedOffset == currentOffset &&
          _lastPushedSeekEnabled == currentSeek) {
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '🔄 Overlay auto-update: ${song.title} by ${song.artist} (songChanged=$songChanged, lyricsChanged=$lyricsChanged) seek=$currentSeek',
        );
      }

      try {
        await _service.showOverlay(
          title: song.title,
          artist: song.artist,
          lyrics: lyrics.plainLyrics,
          currentLine: '',
          lrcLyrics: lyrics.lrcLyrics ?? '',
          syncOffsetMs: currentOffset,
          enableSeek: currentSeek,
        );
        _lastPushedSongId = nextSongId;
        _lastPushedLyricsId = lyrics.id;
        _lastPushedOffset = currentOffset;
        _lastPushedSeekEnabled = currentSeek;
        await MediaDetectionService.cacheOverlayLyricsStatic(
          title: song.title,
          artist: song.artist,
          lrcLyrics: lyrics.lrcLyrics ?? '',
          plainLyrics: lyrics.plainLyrics,
          syncOffsetMs: currentOffset,
          enableSeek: currentSeek,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Overlay auto-update failed: $e');
      }
    });
  }

  Future<void> checkPermission() async {
    final has = await MediaDetectionService.checkOverlayPermission();
    state = state.copyWith(hasPermission: has);
  }

  Future<void> requestPermission() async {
    await MediaDetectionService.requestOverlayPermission();
    // Re-check after delay (user returns from settings)
    Future.delayed(const Duration(seconds: 1), () => checkPermission());
  }

  Future<bool> show({required String title, required String artist, required String plainLyrics, String currentLine = '', String lrcLyrics = '', int syncOffsetMs = 0, bool? enableSeek}) async {
    if (!state.hasPermission) {
      await requestPermission();
      return false;
    }
    final seek = enableSeek ?? _ref.read(settingsProvider).floatingOverlaySeekEnabled;
    final ok = await _service.showOverlay(title: title, artist: artist, lyrics: plainLyrics, currentLine: currentLine, lrcLyrics: lrcLyrics, syncOffsetMs: syncOffsetMs, enableSeek: seek);
    if (ok) {
      state = state.copyWith(isShowing: true);
      // Track what we just pushed to avoid duplicate auto-updates
      try {
        final cur = _ref.read(lyricsNotifierProvider);
        _lastPushedSongId = cur.currentSong?.id;
        _lastPushedLyricsId = cur.lyrics?.id;
      } catch (_) {}
      _lastPushedOffset = syncOffsetMs;
      _lastPushedSeekEnabled = seek;
      // Also keep cache in sync
      try {
        await MediaDetectionService.cacheOverlayLyricsStatic(
          title: title,
          artist: artist,
          lrcLyrics: lrcLyrics,
          plainLyrics: plainLyrics,
          syncOffsetMs: syncOffsetMs,
          enableSeek: seek,
        );
      } catch (_) {}
    }
    return ok;
  }

  Future<void> hide() async {
    await _service.hideOverlay();
    state = state.copyWith(isShowing: false);
    _lastPushedSongId = null;
    _lastPushedLyricsId = null;
    _lastPushedOffset = null;
    _lastPushedSeekEnabled = null;
  }

  Future<void> updateCurrentLine(String current, String next) async {
    if (!state.isShowing) return;
    await _service.updateOverlayLyrics(current, next);
  }
}

final overlayProvider = StateNotifierProvider<OverlayNotifier, OverlayState>((ref) {
  final svc = ref.watch(mediaDetectionServiceProvider);
  return OverlayNotifier(svc, ref);
});

// Helper provider to auto-update overlay when lyrics + position change
// Kept for backward compatibility — now the real auto-update logic lives inside
// OverlayNotifier's listeners. This provider simply ensures lyrics changes are observed
// if any widget watches it (no-op if not watched).
final overlayLyricsUpdaterProvider = Provider<void>((ref) {
  final overlayState = ref.watch(overlayProvider);
  if (!overlayState.isShowing || !overlayState.isEnabled) return;
  final lyricsState = ref.watch(lyricsNotifierProvider);
  final lyrics = lyricsState.lyrics;
  if (lyrics == null) return;
  // Watch position to trigger rebuilds for any legacy widget that still relies on this provider
  ref.watch(mediaNotifierProvider.select((s) => s.currentPosition));
  // The actual overlay content update is now handled automatically inside OverlayNotifier
  // via its lyrics listener, so no manual update is needed here.
});
