import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../services/media_detection_service.dart';
import 'lyrics_provider.dart';

/// State for media detection
class MediaState {
  final bool hasPermission;
  final bool isServiceRunning;
  final bool isListening;
  final Song? currentSong;
  final bool isPlaying;
  final String? error;
  final Duration currentPosition;
  final Duration currentDuration;

  const MediaState({
    this.hasPermission = false,
    this.isServiceRunning = false,
    this.isListening = false,
    this.currentSong,
    this.isPlaying = false,
    this.error,
    this.currentPosition = Duration.zero,
    this.currentDuration = Duration.zero,
  });

  MediaState copyWith({
    bool? hasPermission,
    bool? isServiceRunning,
    bool? isListening,
    Song? currentSong,
    bool? clearSong,
    bool? isPlaying,
    String? error,
    Duration? currentPosition,
    Duration? currentDuration,
  }) {
    return MediaState(
      hasPermission: hasPermission ?? this.hasPermission,
      isServiceRunning: isServiceRunning ?? this.isServiceRunning,
      isListening: isListening ?? this.isListening,
      currentSong: clearSong == true ? null : (currentSong ?? this.currentSong),
      isPlaying: isPlaying ?? this.isPlaying,
      error: error,
      currentPosition: currentPosition ?? this.currentPosition,
      currentDuration: currentDuration ?? this.currentDuration,
    );
  }
}

/// Media detection state notifier
class MediaNotifier extends StateNotifier<MediaState> {
  final MediaDetectionService _service;
  final LyricsNotifier _lyricsNotifier;
  StreamSubscription? _songSubscription;
  StreamSubscription? _playbackSubscription;
  StreamSubscription? _positionSubscription;
  Timer? _lyricsRetryTimer;
  int _lyricsRetries = 0;
  late final void Function() _removeLyricsListener;

  MediaNotifier({
    required MediaDetectionService service,
    required LyricsNotifier lyricsNotifier,
  }) : _service = service,
       _lyricsNotifier = lyricsNotifier,
       super(const MediaState()) {
    if (kDebugMode) debugPrint('🟢 MediaNotifier CREATED');
    _removeLyricsListener = _lyricsNotifier.addListener(
      (_) => _scheduleLyricsRecovery(),
      fireImmediately: false,
    );
    _initialize();
  }

  Future<void> _initialize() async {
    if (kDebugMode) debugPrint('🟢 MediaNotifier._initialize() called');
    await checkPermissions();
  }

  /// Check if permissions are granted
  Future<void> checkPermissions() async {
    final hasPermission = await MediaDetectionService.checkNotificationAccess();
    final isRunning = await MediaDetectionService.isServiceRunning();
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        '🔑 checkPermissions: hasPermission=$hasPermission, isRunning=$isRunning, isListening=${state.isListening}',
      );
    }

    state = state.copyWith(
      hasPermission: hasPermission,
      isServiceRunning: isRunning,
    );

    // Auto-start listening if permission granted
    if (hasPermission && !state.isListening) {
      if (kDebugMode) debugPrint('🔑 Auto-starting listening...');
      startListening();
    }
  }

  /// Request notification access permission
  Future<void> requestPermission() async {
    await MediaDetectionService.requestNotificationAccess();
  }

  /// Get current playing song
  Future<Song?> getCurrentSong() async {
    return await _service.getCurrentPlayingSong();
  }

  /// Force refresh for current song and lyrics
  Future<void> refreshCurrentSong({bool refreshLyrics = true}) async {
    final song = await _service.getCurrentPlayingSong();
    if (song == null) return;

    state = state.copyWith(
      currentSong: song,
      isPlaying: _service.isPlaying,
      currentPosition: _service.currentPosition,
      currentDuration: _service.currentDuration,
    );

    if (refreshLyrics) {
      // Explicit refresh also upgrades cached line lyrics to word timings.
      await _lyricsNotifier.setSong(song, forceRefresh: true);
    }
  }

  /// Start listening for media updates
  Future<void> startListening() async {
    if (kDebugMode) debugPrint('▶️ MediaNotifier.startListening() called');

    _songSubscription?.cancel();
    _songSubscription = _service.songStream.listen(_onSongDetected);

    _playbackSubscription?.cancel();
    _playbackSubscription = _service.playbackStream.listen(_onPlaybackChanged);

    _positionSubscription?.cancel();
    _positionSubscription = _service.positionStream.listen(_onPositionUpdate);

    _service.startListening();
    state = state.copyWith(isListening: true);

    // Try to get the currently playing song on startup
    final currentSong = await _service.getCurrentPlayingSong();
    if (currentSong != null) {
      _onSongDetected(currentSong);
      // Get initial position
      state = state.copyWith(
        currentPosition: _service.currentPosition,
        currentDuration: _service.currentDuration,
      );
    }
  }

  /// Stop listening
  void stopListening() {
    _lyricsRetryTimer?.cancel();
    _lyricsRetryTimer = null;
    _service.stopListening();
    _songSubscription?.cancel();
    _playbackSubscription?.cancel();
    _positionSubscription?.cancel();
    state = state.copyWith(isListening: false);
  }

  void _onSongDetected(Song song) {
    // Only update if song changed
    if (state.currentSong?.id != song.id) {
      _lyricsRetryTimer?.cancel();
      _lyricsRetryTimer = null;
      _lyricsRetries = 0;
      if (kDebugMode) {
        debugPrint('🎵 New song detected: ${song.title} by ${song.artist}');
      }

      // setSong clears old lyrics and coalesces an existing lookup.

      // Reset position for new song
      state = state.copyWith(
        currentSong: song,
        isPlaying: true,
        currentPosition: Duration.zero,
        currentDuration: song.duration ?? Duration.zero,
      );

      // Auto-fetch lyrics for detected song
      if (kDebugMode) {
        debugPrint('🔍 Initiating lyrics fetch for detected song...');
      }
      _lyricsNotifier.setSong(song);
    }
    _scheduleLyricsRecovery();
  }

  bool get _needsLyricsRecovery {
    if (!mounted || !state.isListening || !state.isPlaying) return false;
    final lyrics = _lyricsNotifier.state;
    return state.currentSong != null &&
        lyrics.currentSong?.id == state.currentSong!.id &&
        !lyrics.isLoading && lyrics.lyrics == null && lyrics.error != null;
  }

  // A transient failure during an ad must not leave the same song stuck.
  // Keep retries bounded, and never replace a manual search selection.
  void _scheduleLyricsRecovery() {
    if (!_needsLyricsRecovery) {
      _lyricsRetryTimer?.cancel();
      _lyricsRetryTimer = null;
      return;
    }
    if (_lyricsRetryTimer != null || _lyricsRetries >= 2) return;
    _lyricsRetryTimer = Timer(Duration(seconds: _lyricsRetries == 0 ? 2 : 5), () {
      _lyricsRetryTimer = null;
      if (!_needsLyricsRecovery) return;
      _lyricsRetries++;
      _lyricsNotifier.setSong(state.currentSong!);
    });
  }

  void _onPlaybackChanged(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
    _scheduleLyricsRecovery();
  }

  void _onPositionUpdate(PlaybackPosition position) {
    state = state.copyWith(
      currentPosition: position.position,
      currentDuration: position.duration,
      isPlaying: position.isPlaying,
    );
    _scheduleLyricsRecovery();
  }

  /// Seek to a specific position in the current song
  Future<bool> seekTo(Duration position) async {
    return await _service.seekTo(position);
  }

  /// Play or pause the current song
  Future<bool> setPlaying(bool playing) async {
    return await _service.setPlaying(playing);
  }

  Future<bool> skipToNext() => _service.skipToNext();
  Future<bool> skipToPrevious() => _service.skipToPrevious();
  Future<bool> showLyricsOverlay({required String title, required String artist, required String lyrics, String currentLine = '', String lrcLyrics = '', int syncOffsetMs = 0}) =>
      _service.showOverlay(title: title, artist: artist, lyrics: lyrics, currentLine: currentLine, lrcLyrics: lrcLyrics, syncOffsetMs: syncOffsetMs);
  Future<bool> hideLyricsOverlay() => _service.hideOverlay();
  Future<bool> updateOverlayLyrics(String current, String next) => _service.updateOverlayLyrics(current, next);

  @override
  void dispose() {
    _removeLyricsListener();
    _lyricsRetryTimer?.cancel();
    _songSubscription?.cancel();
    _playbackSubscription?.cancel();
    _positionSubscription?.cancel();
    // Do NOT dispose the service here — its lifecycle is managed by mediaDetectionServiceProvider
    super.dispose();
  }
}

/// Media detection service provider
final mediaDetectionServiceProvider = Provider<MediaDetectionService>((ref) {
  final service = MediaDetectionService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Media state provider
final mediaNotifierProvider = StateNotifierProvider<MediaNotifier, MediaState>((
  ref,
) {
  final service = ref.watch(mediaDetectionServiceProvider);
  final lyricsNotifier = ref.watch(lyricsNotifierProvider.notifier);
  return MediaNotifier(service: service, lyricsNotifier: lyricsNotifier);
});

/// Permission status provider
final hasNotificationAccessProvider = FutureProvider<bool>((ref) async {
  return MediaDetectionService.checkNotificationAccess();
});

/// Overlay permission provider
final hasOverlayPermissionProvider = FutureProvider<bool>((ref) async {
  return MediaDetectionService.checkOverlayPermission();
});
