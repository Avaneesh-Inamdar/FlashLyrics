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

  MediaNotifier({
    required MediaDetectionService service,
    required LyricsNotifier lyricsNotifier,
  }) : _service = service,
       _lyricsNotifier = lyricsNotifier,
       super(const MediaState()) {
    _initialize();
  }

  Future<void> _initialize() async {
    await checkPermissions();
  }

  /// Check if permissions are granted
  Future<void> checkPermissions() async {
    final hasPermission = await MediaDetectionService.checkNotificationAccess();
    final isRunning = await MediaDetectionService.isServiceRunning();

    state = state.copyWith(
      hasPermission: hasPermission,
      isServiceRunning: isRunning,
    );

    // Auto-start listening if permission granted
    if (hasPermission && !state.isListening) {
      startListening();
    }
  }

  /// Request notification access permission
  Future<void> requestPermission() async {
    await MediaDetectionService.requestNotificationAccess();
  }

  /// Start listening for media updates
  Future<void> startListening() async {
    _service.startListening();

    _songSubscription?.cancel();
    _songSubscription = _service.songStream.listen(_onSongDetected);

    _playbackSubscription?.cancel();
    _playbackSubscription = _service.playbackStream.listen(_onPlaybackChanged);

    _positionSubscription?.cancel();
    _positionSubscription = _service.positionStream.listen(_onPositionUpdate);

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
    _service.stopListening();
    _songSubscription?.cancel();
    _playbackSubscription?.cancel();
    _positionSubscription?.cancel();
    state = state.copyWith(isListening: false);
  }

  void _onSongDetected(Song song) {
    // Only update if song changed
    if (state.currentSong?.id != song.id) {
      if (kDebugMode)
        debugPrint('🎵 New song detected: ${song.title} by ${song.artist}');

      // IMPORTANT: Clear old lyrics first to prevent mixing
      _lyricsNotifier.clear();

      // Reset position for new song
      state = state.copyWith(
        currentSong: song,
        isPlaying: true,
        currentPosition: Duration.zero,
        currentDuration: song.duration ?? Duration.zero,
      );

      // Auto-fetch lyrics for detected song
      if (kDebugMode)
        debugPrint('🔍 Initiating lyrics fetch for detected song...');
      _lyricsNotifier.setSong(song);
    }
  }

  void _onPlaybackChanged(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  void _onPositionUpdate(PlaybackPosition position) {
    state = state.copyWith(
      currentPosition: position.position,
      currentDuration: position.duration,
      isPlaying: position.isPlaying,
    );
  }

  @override
  void dispose() {
    stopListening();
    _service.dispose();
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
