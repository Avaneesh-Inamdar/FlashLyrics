import 'dart:async';
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

  const MediaState({
    this.hasPermission = false,
    this.isServiceRunning = false,
    this.isListening = false,
    this.currentSong,
    this.isPlaying = false,
    this.error,
  });

  MediaState copyWith({
    bool? hasPermission,
    bool? isServiceRunning,
    bool? isListening,
    Song? currentSong,
    bool? isPlaying,
    String? error,
  }) {
    return MediaState(
      hasPermission: hasPermission ?? this.hasPermission,
      isServiceRunning: isServiceRunning ?? this.isServiceRunning,
      isListening: isListening ?? this.isListening,
      currentSong: currentSong ?? this.currentSong,
      isPlaying: isPlaying ?? this.isPlaying,
      error: error,
    );
  }
}

/// Media detection state notifier
class MediaNotifier extends StateNotifier<MediaState> {
  final MediaDetectionService _service;
  final LyricsNotifier _lyricsNotifier;
  StreamSubscription? _songSubscription;
  StreamSubscription? _playbackSubscription;

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

    state = state.copyWith(isListening: true);

    // Try to get the currently playing song on startup
    final currentSong = await _service.getCurrentPlayingSong();
    if (currentSong != null) {
      _onSongDetected(currentSong);
    }
  }

  /// Stop listening
  void stopListening() {
    _service.stopListening();
    _songSubscription?.cancel();
    _playbackSubscription?.cancel();
    state = state.copyWith(isListening: false);
  }

  void _onSongDetected(Song song) {
    // Only update if song changed
    if (state.currentSong?.id != song.id) {
      state = state.copyWith(currentSong: song, isPlaying: true);
      // Auto-fetch lyrics for detected song
      _lyricsNotifier.setSong(song);
    }
  }

  void _onPlaybackChanged(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
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
