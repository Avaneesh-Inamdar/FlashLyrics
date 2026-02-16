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

  /// ChartLyrics - Free API, no auth required
  static const String chartLyricsApi = 'https://api.chartlyrics.com/apiv1';

  /// NetEase Music - Free API (popular in Asia, supports Chinese)
  static const String netEaseApi = 'https://music.163.com/api/search/get';

  /// Genius Lyrics (requires auth token but has free tier)
  static const String geniusSearchApi = 'https://api.genius.com/search';

  /// Happi.dev API (requires API key but has free tier)
  static const String happiApi = 'https://api.happi.dev/v1/music';

  /// AudD API - Audio fingerprinting for song recognition (FastLyrics method)
  static const String audDApi = 'https://api.audd.io/';

  /// Enable audio recognition for song identification
  static const bool enableAudioRecognition = true;

  /// Ordered list of APIs to try (priority order)
  /// Prioritizes synced lyrics sources first
  static const List<String> apiPriority = [
    'lrclib', // ⭐ Best for synced lyrics (LRC format)
    'textyl', // ⭐ Good synced lyrics backup
    'chartlyrics', // ⭐ Free, no auth, plain lyrics
    'lyrics.ovh', // Plain lyrics fallback
    'lyrist', // Additional fallback
    'netease', // Supports Chinese/Asian songs
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

  static const String appName = 'FlashLyrics';
  static const String appVersion = '1.01';

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
