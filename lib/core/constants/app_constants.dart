/// API endpoints for lyrics fetching
class ApiConstants {
  ApiConstants._();

  /// Primary lyrics API (lyrics.ovh) - plain lyrics
  static const String lyricsOvhApi = 'https://api.lyrics.ovh/v1';

  /// LRCLIB API - synced lyrics (LRC format)
  static const String lrclibApi = 'https://lrclib.net/api/get';
  static const String lrclibSearchApi = 'https://lrclib.net/api/search';

  /// Textyl API - synced lyrics
  static const String textylApi = 'https://api.textyl.co/api/lyrics';

  /// Lyrics.ovh alternative
  static const String lyristApi = 'https://lyrist.vercel.app/api';

  /// Happi.dev API (requires API key but has free tier)
  static const String happiApi = 'https://api.happi.dev/v1/music';

  /// Ordered list of APIs to try (priority order)
  static const List<String> apiPriority = [
    'lrclib', // Best for synced lyrics
    'textyl', // Good synced lyrics backup
    'lyrics.ovh', // Plain lyrics fallback
    'lyrist', // Additional fallback
  ];

  /// Timeout durations
  static const Duration connectionTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 12);

  /// Retry configuration
  static const int maxRetries = 2;
  static const Duration retryDelay = Duration(milliseconds: 500);
}

/// App constants
class AppConstants {
  AppConstants._();

  static const String appName = 'LyricX';
  static const String appVersion = '1.0.0';

  /// Cache keys
  static const String lyricsCacheKey = 'lyrics_cache';
  static const String settingsCacheKey = 'settings_cache';
  static const String lastSongCacheKey = 'last_song';

  /// Cache duration (7 days)
  static const Duration cacheDuration = Duration(days: 7);

  /// Debounce duration for search
  static const Duration searchDebounce = Duration(milliseconds: 500);

  /// Media detection interval
  static const Duration mediaDetectionInterval = Duration(milliseconds: 500);
}

/// Permission constants
class PermissionConstants {
  PermissionConstants._();

  static const String notificationListener =
      'android.permission.BIND_NOTIFICATION_LISTENER_SERVICE';
  static const String overlayPermission =
      'android.permission.SYSTEM_ALERT_WINDOW';
  static const String foregroundService =
      'android.permission.FOREGROUND_SERVICE';
  static const String postNotifications =
      'android.permission.POST_NOTIFICATIONS';
}
