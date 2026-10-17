import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lyrics_model.dart';

/// Stores lyrics using the existing on-device cache format.
class LyricsLocalDataSource {
  static const String _lyricsCacheKey = 'lyrics_cache';
  final SharedPreferences _prefs;
  final void Function()? onChanged;
  Future<void> _pendingWrite = Future<void>.value();

  LyricsLocalDataSource(this._prefs, {this.onChanged});

  Map<String, dynamic> _readCache() {
    try {
      final raw = _prefs.getString(_lyricsCacheKey);
      return raw == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  LyricsModel? _decode(dynamic entry) {
    try {
      if (entry is! Map) return null;
      return LyricsModel.fromJson(Map<String, dynamic>.from(entry));
    } catch (_) {
      // One damaged entry must not erase every other saved song.
      return null;
    }
  }

  LyricsModel? getCachedLyrics(String songId) => _decode(_readCache()[songId]);

  Future<void> _write(Future<void> Function() operation) {
    final result = _pendingWrite.then((_) => operation());
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> cacheLyrics(LyricsModel lyrics) => _write(() async {
    if (lyrics.songId.isEmpty ||
        (lyrics.plainLyrics.trim().isEmpty &&
            (lyrics.lrcLyrics?.trim().isEmpty ?? true)))
      return;
    final cache = _readCache();
    cache.remove(lyrics.songId);
    cache[lyrics.songId] = lyrics.toJson();
    while (cache.length > 100) {
      cache.remove(cache.keys.first);
    }
    var encoded = jsonEncode(cache);
    while (utf8.encode(encoded).length > 3 * 1024 * 1024 && cache.length > 20) {
      cache.remove(cache.keys.first);
      encoded = jsonEncode(cache);
    }
    if (!await _prefs.setString(_lyricsCacheKey, encoded)) {
      throw StateError('Could not save lyrics on this device');
    }
    onChanged?.call();
  });

  List<LyricsModel> getAllCachedLyrics() =>
      _readCache().values.map(_decode).whereType<LyricsModel>().toList();

  Future<void> deleteCachedLyrics(String songId) => _write(() async {
    final cache = _readCache()..remove(songId);
    if (!await _prefs.setString(_lyricsCacheKey, jsonEncode(cache))) {
      throw StateError('Could not update saved lyrics');
    }
    onChanged?.call();
  });

  List<LyricsModel> searchCachedLyrics(String query) {
    final lower = query.toLowerCase();
    return getAllCachedLyrics()
        .where(
          (lyrics) =>
              lyrics.plainLyrics.toLowerCase().contains(lower) ||
              lyrics.songId.toLowerCase().contains(lower) ||
              (lyrics.trackName?.toLowerCase().contains(lower) ?? false) ||
              (lyrics.artistName?.toLowerCase().contains(lower) ?? false) ||
              (lyrics.albumName?.toLowerCase().contains(lower) ?? false),
        )
        .toList();
  }

  Future<void> clearAllCache() => _write(() async {
    if (!await _prefs.remove(_lyricsCacheKey))
      throw StateError('Could not clear saved lyrics');
    onChanged?.call();
  });

  Future<void> deleteBySongId(String songId) => deleteCachedLyrics(songId);
  int getCacheCount() => getAllCachedLyrics().length;
  int getCacheSize() =>
      utf8.encode(_prefs.getString(_lyricsCacheKey) ?? '').length;
  String getCacheSizeFormatted() {
    final bytes = getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
