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

  /// Save lyrics to cache
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

    // Store with songId as key
    cache[lyrics.songId] = lyrics.toJson();
    await _prefs.setString(_lyricsCacheKey, jsonEncode(cache));
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

  /// Search through cached lyrics
  List<LyricsModel> searchCachedLyrics(String query) {
    final allLyrics = getAllCachedLyrics();
    final lowerQuery = query.toLowerCase();

    return allLyrics.where((lyrics) {
      return lyrics.plainLyrics.toLowerCase().contains(lowerQuery) ||
          lyrics.songId.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Clear all cache
  Future<void> _clearCache() async {
    await _prefs.remove(_lyricsCacheKey);
  }

  /// Get cache size
  int getCacheSize() {
    final cachedData = _prefs.getString(_lyricsCacheKey);
    if (cachedData == null) return 0;
    return cachedData.length;
  }
}
