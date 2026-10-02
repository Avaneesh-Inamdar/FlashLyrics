import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';

/// Standardized helper to generate a consistent key for a song across the app.
String generateSongKey({String? songId, String? artist, String? title}) {
  if (artist != null && title != null && (artist.trim().isNotEmpty || title.trim().isNotEmpty)) {
    return '${artist.trim().toLowerCase()}_${title.trim().toLowerCase()}'
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
  if (songId != null && songId.trim().isNotEmpty) {
    return songId
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
  return '';
}

/// Manages per-song sync offsets stored in SharedPreferences.
/// Remembers custom lyrics timing adjustments for individual songs across sessions.
class SongOffsetNotifier extends StateNotifier<Map<String, int>> {
  static const String _storageKey = 'song_lyrics_offsets';
  final SharedPreferences _prefs;

  SongOffsetNotifier(this._prefs) : super(const {}) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(raw);
        state = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        state = const {};
      }
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_storageKey, jsonEncode(state));
  }

  /// Get custom offset for song if one has been saved.
  int? getCustomOffset(String songKey) {
    if (songKey.isEmpty) return null;
    return state[songKey];
  }

  /// Get effective offset for a song. Uses custom offset if set,
  /// otherwise falls back to the user's global default offset.
  int getEffectiveOffset({
    required String songKey,
    required int globalDefault,
  }) {
    if (songKey.isEmpty) return globalDefault;
    return state[songKey] ?? globalDefault;
  }

  /// Save offset for a specific song and persist to cache.
  Future<void> setSongOffset(String songKey, int offsetMs) async {
    if (songKey.isEmpty) return;
    final updated = Map<String, int>.from(state);
    updated[songKey] = offsetMs;
    state = updated;
    await _save();
  }

  /// Remove saved offset for a song, reverting to global default.
  Future<void> clearSongOffset(String songKey) async {
    if (songKey.isEmpty || !state.containsKey(songKey)) return;
    final updated = Map<String, int>.from(state)..remove(songKey);
    state = updated;
    await _save();
  }
}

/// Provider for per-song lyrics sync offsets
final songOffsetProvider =
    StateNotifierProvider<SongOffsetNotifier, Map<String, int>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SongOffsetNotifier(prefs);
});
