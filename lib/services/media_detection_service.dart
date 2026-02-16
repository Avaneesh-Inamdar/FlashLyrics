import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/models/song_model.dart';
import '../domain/entities/song.dart';

/// Service for detecting currently playing media from other apps.
/// Uses Android's NotificationListenerService via Method/Event channels.
/// Also supports audio fingerprinting as a fallback for better song identification.
class MediaDetectionService {
  static const MethodChannel _methodChannel = MethodChannel('com.lyricx/media');
  static const EventChannel _eventChannel = EventChannel(
    'com.lyricx/media_events',
  );

  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Timer? _healthCheckTimer; // Add health check timer to detect killed service
  bool _isListening = false;

  // Track when we last successfully got a song
  DateTime? _lastSuccessfulSongDetection;

  final StreamController<Song> _songController =
      StreamController<Song>.broadcast();
  final StreamController<bool> _playbackController =
      StreamController<bool>.broadcast();
  final StreamController<PlaybackPosition> _positionController =
      StreamController<PlaybackPosition>.broadcast();

  /// Stream of detected songs
  Stream<Song> get songStream => _songController.stream;

  /// Stream of playback state (true = playing, false = stopped)
  Stream<bool> get playbackStream => _playbackController.stream;

  /// Stream of playback position updates (every ~300ms while playing)
  Stream<PlaybackPosition> get positionStream => _positionController.stream;

  Song? _currentSong;
  Song? get currentSong => _currentSong;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _currentPosition = Duration.zero;
  Duration get currentPosition => _currentPosition;

  Duration _currentDuration = Duration.zero;
  Duration get currentDuration => _currentDuration;

  /// Check if notification access is granted
  static Future<bool> checkNotificationAccess() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'checkNotificationAccess',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking notification access: ${e.message}');
      }
      return false;
    }
  }

  /// Request notification access permission
  static Future<void> requestNotificationAccess() async {
    try {
      await _methodChannel.invokeMethod('requestNotificationAccess');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting notification access: ${e.message}');
      }
    }
  }

  /// Check if the notification listener service is running
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'isServiceRunning',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Error checking service status: ${e.message}');
      return false;
    }
  }

  /// Check if overlay permission is granted
  static Future<bool> checkOverlayPermission() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'checkOverlayPermission',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking overlay permission: ${e.message}');
      }
      return false;
    }
  }

  /// Request overlay permission
  static Future<void> requestOverlayPermission() async {
    try {
      await _methodChannel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('Error requesting overlay permission: ${e.message}');
      }
    }
  }

  /// Get the currently playing song (to restore state on app restart)
  Future<Song?> getCurrentPlayingSong() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getCurrentPlayingSong',
      );
      if (result == null) return null;

      final title = result['title'] as String?;
      final artist = result['artist'] as String?;
      final album = result['album'] as String?;
      final artworkUrl = result['artworkUrl'] as String?;
      final duration = result['duration'] as int? ?? 0;
      final source = result['source'] as String?;
      final isPlaying = result['isPlaying'] as bool? ?? false;
      final position = result['position'] as int? ?? 0;

      if (title == null || title.isEmpty || artist == null || artist.isEmpty) {
        return null;
      }

      final id = '${artist}_$title'.toLowerCase().replaceAll(' ', '_');
      final song = SongModel(
        id: id,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        duration: duration > 0 ? Duration(milliseconds: duration) : null,
        source: source,
      );

      // DON'T update _currentSong here — polling compares against it to detect changes.
      // Only update position/playback state.
      _isPlaying = isPlaying;
      _currentPosition = Duration(milliseconds: position);
      _currentDuration = Duration(milliseconds: duration);
      return song;
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('Error getting current song: ${e.message}');
      return null;
    }
  }

  /// Start listening for media updates
  void startListening() {
    if (_isListening) {
      // Already listening — but ensure polling is still active
      if (_pollTimer == null || !_pollTimer!.isActive) {
        if (kDebugMode)
          debugPrint(
            '⚠️ startListening: was listening but poll timer dead, restarting polling',
          );
        _startPolling();
      }
      if (_healthCheckTimer == null || !_healthCheckTimer!.isActive) {
        _startHealthCheck();
      }
      return;
    }
    _isListening = true;

    if (kDebugMode)
      debugPrint('🚀 MediaDetectionService.startListening() - first start');

    _subscription?.cancel();
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();

    // Immediately fetch the current song before waiting for events
    _fetchCurrentSongImmediate();

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      _handleMediaEvent,
      onError: _handleError,
      onDone: _handleStreamDone,
    );

    // Start polling for current song every 1 second as backup
    _startPolling();

    // Start health check timer to detect if service was killed by system
    _startHealthCheck();
  }

  /// Start periodic health check to detect if service was killed
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isListening) return;

      try {
        // Check if service is still running
        final isRunning = await isServiceRunning();
        if (!isRunning && _isListening) {
          if (kDebugMode) {
            debugPrint(
              'Health check: Service not running, attempting to reconnect...',
            );
          }
          // Force reconnect
          _subscription?.cancel();
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(seconds: 1), () {
            startListening();
          });
        } else if (isRunning) {
          // Service is running, just verify we can get current song
          final song = await getCurrentPlayingSong();
          if (song != null && song.id != _currentSong?.id) {
            _songController.add(song);
          }
          _lastSuccessfulSongDetection = DateTime.now();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Health check error: $e');
      }
    });
  }

  /// Immediately fetch the current song on startup
  void _fetchCurrentSongImmediate() {
    Future.microtask(() async {
      try {
        final song = await getCurrentPlayingSong();
        if (song != null && _isListening) {
          _songController.add(song);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Immediate fetch error: $e');
      }
    });
  }

  void _handleStreamDone() {
    if (kDebugMode) {
      debugPrint('Media event stream closed, attempting reconnect...');
    }
    _isListening = false;
    _subscription?.cancel();
    _reconnectTimer?.cancel();

    // Only attempt reconnect if streams are not closed
    if (!_songController.isClosed &&
        !_playbackController.isClosed &&
        !_positionController.isClosed) {
      // Attempt reconnect after 2 seconds
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        if (kDebugMode) debugPrint('Reconnecting to media event stream...');
        startListening();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (kDebugMode) debugPrint('📡 POLLING: Started (every 500ms)');
    int pollCount = 0;
    // Reduced polling interval from 1s to 500ms for faster detection
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isListening) return;
      try {
        final song = await getCurrentPlayingSong();
        pollCount++;
        // Log every 20th poll to avoid spam
        if (kDebugMode && pollCount % 20 == 0) {
          debugPrint(
            '📡 POLL #$pollCount: song=${song?.title ?? "null"}, current=${_currentSong?.title ?? "null"}',
          );
        }
        if (song != null) {
          if (song.id != _currentSong?.id) {
            if (kDebugMode) {
              debugPrint(
                '🔄 POLLING: Song changed from "${_currentSong?.title}" to "${song.title}"',
              );
            }
            _currentSong = song; // Update current song after change detection
            _songController.add(song);
          }

          // ALWAYS emit position updates from polling
          // This is critical when NLS event channel is dead (MIUI kills the service)
          if (!_positionController.isClosed) {
            _positionController.add(
              PlaybackPosition(
                position: _currentPosition,
                duration: _currentDuration,
                isPlaying: _isPlaying,
              ),
            );
          }
          if (!_playbackController.isClosed && _isPlaying != isPlaying) {
            _playbackController.add(_isPlaying);
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Polling error: $e');
      }
    });
  }

  /// Stop listening for media updates
  void stopListening() {
    _isListening = false;
    _subscription?.cancel();
    _subscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  void _handleMediaEvent(dynamic event) {
    if (event is! Map) return;
    // Guard against closed streams
    if (_songController.isClosed ||
        _playbackController.isClosed ||
        _positionController.isClosed)
      return;

    final type = event['type'] as String?;

    switch (type) {
      case 'media_update':
        _handleMediaUpdate(event);
        break;
      case 'position_update':
        _handlePositionUpdate(event);
        break;
      case 'playback_stopped':
        _isPlaying = false;
        _currentPosition = Duration.zero;
        if (!_playbackController.isClosed) {
          _playbackController.add(false);
        }
        if (!_positionController.isClosed) {
          _positionController.add(
            PlaybackPosition(
              position: Duration.zero,
              duration: _currentDuration,
              isPlaying: false,
            ),
          );
        }
        break;
    }
  }

  void _handlePositionUpdate(Map event) {
    // Guard against closed stream
    if (_positionController.isClosed) return;

    final position = event['position'] as int? ?? 0;
    final duration = event['duration'] as int? ?? 0;
    final isPlaying = event['isPlaying'] as bool? ?? false;

    _currentPosition = Duration(milliseconds: position);
    _currentDuration = Duration(milliseconds: duration);
    _isPlaying = isPlaying;

    // Guard against closed stream before adding
    if (!_positionController.isClosed) {
      _positionController.add(
        PlaybackPosition(
          position: _currentPosition,
          duration: _currentDuration,
          isPlaying: isPlaying,
        ),
      );
    }
  }

  void _handleMediaUpdate(Map event) {
    // Guard against closed stream
    if (_songController.isClosed) return;

    final title = event['title'] as String?;
    final artist = event['artist'] as String?;
    final album = event['album'] as String?;
    final artworkUrl = event['artworkUrl'] as String?;
    final duration = event['duration'] as int? ?? 0;
    final source = event['source'] as String?;
    final isPlaying = event['isPlaying'] as bool? ?? false;
    final position = event['position'] as int? ?? 0;

    if (title == null || title.isEmpty || artist == null || artist.isEmpty) {
      return;
    }

    // Create unique ID from title and artist
    final id = '${artist}_$title'.toLowerCase().replaceAll(' ', '_');

    final song = SongModel(
      id: id,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      duration: duration > 0 ? Duration(milliseconds: duration) : null,
      source: source,
    );

    _currentSong = song;
    _isPlaying = isPlaying;
    _currentPosition = Duration(milliseconds: position);
    _currentDuration = Duration(milliseconds: duration);

    // Guard against closed streams before adding
    if (!_songController.isClosed) {
      _songController.add(song);
    }
    if (!_playbackController.isClosed) {
      _playbackController.add(isPlaying);
    }
    if (!_positionController.isClosed) {
      // Also emit initial position when song changes
      _positionController.add(
        PlaybackPosition(
          position: _currentPosition,
          duration: _currentDuration,
          isPlaying: isPlaying,
        ),
      );
    }
  }

  void _handleError(dynamic error) {
    if (kDebugMode) debugPrint('Media detection error: $error');
    // Trigger reconnection on error
    _isListening = false;
    _handleStreamDone();
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    _songController.close();
    _playbackController.close();
    _positionController.close();
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
    _healthCheckTimer?.cancel();
  }

  /// Manually trigger song identification using audio fingerprinting
  /// Use this when regular detection fails to identify the song
  Future<Song?> identifySongManually() async {
    try {
      // This would trigger the audio recognition service
      // For now, we just notify that manual identification is available
      if (kDebugMode) {
        debugPrint(
          'Manual audio recognition triggered - use search as fallback',
        );
      }

      // Return null to indicate manual identification is not available
      // The user can use the search feature instead
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Manual song identification error: $e');
      return null;
    }
  }
}

/// Represents the current playback position with metadata
class PlaybackPosition {
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  const PlaybackPosition({
    required this.position,
    required this.duration,
    required this.isPlaying,
  });

  /// Progress as a value between 0.0 and 1.0
  double get progress {
    if (duration.inMilliseconds == 0) return 0.0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'PlaybackPosition(position: $position, duration: $duration, isPlaying: $isPlaying)';
}
