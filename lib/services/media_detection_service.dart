import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/models/song_model.dart';
import '../domain/entities/song.dart';

/// Service for detecting currently playing media from other apps.
/// Uses Android's NotificationListenerService via Method/Event channels.
class MediaDetectionService {
  static const MethodChannel _methodChannel = MethodChannel('com.lyricx/media');
  static const EventChannel _eventChannel = EventChannel(
    'com.lyricx/media_events',
  );

  StreamSubscription? _subscription;
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

      _currentSong = song;
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
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      _handleMediaEvent,
      onError: _handleError,
    );
  }

  /// Stop listening for media updates
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _handleMediaEvent(dynamic event) {
    if (event is! Map) return;

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
        _playbackController.add(false);
        _positionController.add(
          PlaybackPosition(
            position: Duration.zero,
            duration: _currentDuration,
            isPlaying: false,
          ),
        );
        break;
    }
  }

  void _handlePositionUpdate(Map event) {
    final position = event['position'] as int? ?? 0;
    final duration = event['duration'] as int? ?? 0;
    final isPlaying = event['isPlaying'] as bool? ?? false;

    _currentPosition = Duration(milliseconds: position);
    _currentDuration = Duration(milliseconds: duration);
    _isPlaying = isPlaying;

    _positionController.add(
      PlaybackPosition(
        position: _currentPosition,
        duration: _currentDuration,
        isPlaying: isPlaying,
      ),
    );
  }

  void _handleMediaUpdate(Map event) {
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

    _songController.add(song);
    _playbackController.add(isPlaying);

    // Also emit initial position when song changes
    _positionController.add(
      PlaybackPosition(
        position: _currentPosition,
        duration: _currentDuration,
        isPlaying: isPlaying,
      ),
    );
  }

  void _handleError(dynamic error) {
    if (kDebugMode) debugPrint('Media detection error: $error');
  }

  /// Dispose resources
  void dispose() {
    stopListening();
    _songController.close();
    _playbackController.close();
    _positionController.close();
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
