import '../entities/song.dart';
import '../entities/lyrics.dart';

/// Repository interface for lyrics operations
abstract class LyricsRepository {
  /// Fetch lyrics for a song
  Future<Lyrics> getLyrics(Song song, {List<String>? providerPriority});

  /// Search lyrics by artist and title
  Future<Lyrics> searchLyrics(
    String artist,
    String title, {
    List<String>? providerPriority,
  });

  /// Get cached lyrics for a song
  Future<Lyrics?> getCachedLyrics(String songId);

  /// Save lyrics to cache
  Future<void> cacheLyrics(Lyrics lyrics);

  /// Get all cached lyrics
  Future<List<Lyrics>> getAllCachedLyrics();

  /// Delete cached lyrics
  Future<void> deleteCachedLyrics(String lyricsId);

  /// Search through cached lyrics
  Future<List<Lyrics>> searchCachedLyrics(String query);
}
