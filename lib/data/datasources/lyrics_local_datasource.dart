import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lyrics_model.dart';

/// Local data source for caching lyrics
class LyricsLocalDataSource {
  static const String _lyricsCacheKey = 'lyrics_cache';
  final SharedPreferences _prefs;

  LyricsLocalDataSource(this._prefs);

  /// Get cached lyrics by song ID
  LyricsModel? getCachedLyrics(String songId) {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return null;

    try {
      final Map<String, dynamic> cache = jsonDecode(cachedData);
      if (cache.containsKey(songId)) {
        return LyricsModel.fromJson(cache[songId] as Map<String, dynamic>);
      }
    } catch (e) {
      // Cache corrupted, clear it
      _clearCache();
    }
    return null;
  }

  /// Save lyrics to cache with LRU eviction (max ~3MB / 100 entries)
  Future<void> cacheLyrics(LyricsModel lyrics) async {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    Map<String, dynamic> cache = {};

    if (cachedData != null) {
      try {
        cache = jsonDecode(cachedData) as Map<String, dynamic>;
      } catch (e) {
        cache = {};
      }
    }

    // LRU: move existing to end (newest)
    cache.remove(lyrics.songId);
    cache[lyrics.songId] = lyrics.toJson();

    // Enforce limits: max 100 entries, max ~3MB
    const maxEntries = 100;
    const maxBytes = 3 * 1024 * 1024;
    // Evict oldest if over entry limit
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
    // Evict until under byte limit
    String encoded = jsonEncode(cache);
    while (encoded.length > maxBytes && cache.length > 20) {
      cache.remove(cache.keys.first);
      encoded = jsonEncode(cache);
    }
    await _prefs.setString(_lyricsCacheKey, encoded);
  }

  /// Get all cached lyrics
  List<LyricsModel> getAllCachedLyrics() {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return [];

    try {
      final Map<String, dynamic> cache = jsonDecode(cachedData);
      return cache.values
          .map((e) => LyricsModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Delete cached lyrics
  Future<void> deleteCachedLyrics(String lyricsId) async {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return;

    try {
      final Map<String, dynamic> cache = jsonDecode(cachedData);
      cache.remove(lyricsId);
      await _prefs.setString(_lyricsCacheKey, jsonEncode(cache));
    } catch (e) {
      // Ignore errors
    }
  }

  /// Search through cached lyrics (now includes track/artist names)
  List<LyricsModel> searchCachedLyrics(String query) {
    final allLyrics = getAllCachedLyrics();
    final lowerQuery = query.toLowerCase();
    return allLyrics.where((lyrics) {
      return lyrics.plainLyrics.toLowerCase().contains(lowerQuery) ||
          lyrics.songId.toLowerCase().contains(lowerQuery) ||
          (lyrics.trackName?.toLowerCase().contains(lowerQuery) ?? false) ||
          (lyrics.artistName?.toLowerCase().contains(lowerQuery) ?? false) ||
          (lyrics.albumName?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// Clear all cache (public)
  Future<void> clearAllCache() async {
    await _prefs.remove(_lyricsCacheKey);
  }

  /// Clear all cache (internal wrapper)
  Future<void> _clearCache() async {
    await clearAllCache();
  }

  /// Delete by songId (alias for deleteCachedLyrics)
  Future<void> deleteBySongId(String songId) async {
    await deleteCachedLyrics(songId);
  }

  /// Get cache entry count
  int getCacheCount() {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return 0;
    try {
      final Map<String, dynamic> cache = jsonDecode(cachedData);
      return cache.length;
    } catch (_) {
      return 0;
    }
  }

  /// Get cache size in bytes
  int getCacheSize() {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return 0;
    return cachedData.length;
  }

  /// Get cache size formatted
  String getCacheSizeFormatted() {
    final bytes = getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
