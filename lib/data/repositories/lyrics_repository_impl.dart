import '../../domain/entities/song.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../core/errors/exceptions.dart';
import '../datasources/lyrics_remote_datasource.dart';
import '../datasources/lyrics_local_datasource.dart';
import '../models/lyrics_model.dart';

/// Implementation of lyrics repository
/// Prioritizes synced lyrics from multiple API sources
class LyricsRepositoryImpl implements LyricsRepository {
  final LyricsRemoteDataSource _remoteDataSource;
  final LyricsLocalDataSource _localDataSource;

  LyricsRepositoryImpl({
    required LyricsRemoteDataSource remoteDataSource,
    required LyricsLocalDataSource localDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource;

  @override
  Future<Lyrics> getLyrics(Song song, {List<String>? providerPriority}) async {
    // Generate consistent songId from artist/title (same as searchLyrics)
    final songId = _generateSongId(song.artist, song.title);

    // Check cache only if it matches the exact song
    final cachedLyrics = _localDataSource.getCachedLyrics(songId);
    if (cachedLyrics != null) {
      // Return cached synced lyrics immediately
      if (cachedLyrics.isSynced) return cachedLyrics;
      // Return cached unsynced, but don't block - upgrade can happen next time
      return cachedLyrics;
    }

    // ONE parallel blast of ALL APIs at once (no sequential fallback nonsense)
    final lyrics = await _remoteDataSource.fetchAllParallel(
      song.artist,
      song.title,
    );

    if (lyrics != null && lyrics.plainLyrics.isNotEmpty) {
      await _localDataSource.cacheLyrics(lyrics);
      return lyrics;
    }

    throw LyricsNotFoundException(
      message: 'Lyrics not found for "${song.title}" by "${song.artist}"',
    );
  }

  @override
  Future<Lyrics> searchLyrics(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    final songId = _generateSongId(artist, title);

    // First check cache
    final cachedLyrics = _localDataSource.getCachedLyrics(songId);
    if (cachedLyrics != null) {
      return cachedLyrics;
    }

    // ONE parallel blast of ALL APIs
    final lyrics = await _remoteDataSource.fetchAllParallel(artist, title);

    if (lyrics != null && lyrics.plainLyrics.isNotEmpty) {
      await _localDataSource.cacheLyrics(lyrics);
      return lyrics;
    }

    throw LyricsNotFoundException(
      message: 'Lyrics not found for "$title" by "$artist"',
    );
  }

  /// Search LRCLIB for lyrics matches
  Future<List<Lyrics>> searchOnline(String query) async {
    return _remoteDataSource.searchLrclib(query);
  }

  @override
  Future<Lyrics?> getCachedLyrics(String songId) async {
    return _localDataSource.getCachedLyrics(songId);
  }

  @override
  Future<void> cacheLyrics(Lyrics lyrics) async {
    if (lyrics is LyricsModel) {
      await _localDataSource.cacheLyrics(lyrics);
      return;
    }
    await _localDataSource.cacheLyrics(LyricsModel.fromEntity(lyrics));
  }

  @override
  Future<List<Lyrics>> getAllCachedLyrics() async {
    return _localDataSource.getAllCachedLyrics();
  }

  @override
  Future<void> deleteCachedLyrics(String lyricsId) async {
    await _localDataSource.deleteCachedLyrics(lyricsId);
  }

  @override
  Future<List<Lyrics>> searchCachedLyrics(String query) async {
    return _localDataSource.searchCachedLyrics(query);
  }

  String _generateSongId(String artist, String title) {
    return '${artist}_$title'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }
}
