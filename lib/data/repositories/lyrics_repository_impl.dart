import '../../domain/entities/song.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/repositories/lyrics_repository.dart';
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
  Future<Lyrics> getLyrics(Song song) async {
    // First check cache
    final cachedLyrics = _localDataSource.getCachedLyrics(song.id);
    if (cachedLyrics != null) {
      // If cached version exists but isn't synced, try to get synced version
      if (!cachedLyrics.isSynced) {
        final syncedLyrics = await _trySyncedLyrics(song.artist, song.title);
        if (syncedLyrics != null) {
          await _localDataSource.cacheLyrics(syncedLyrics);
          return syncedLyrics;
        }
      }
      return cachedLyrics;
    }

    // Try to get synced lyrics first (parallel fetch)
    var lyrics = await _trySyncedLyrics(song.artist, song.title);

    // Fall back to sequential fetch if parallel failed
    lyrics ??= await _remoteDataSource.fetchLyricsWithFallback(
      song.artist,
      song.title,
    );

    // Cache the result
    await _localDataSource.cacheLyrics(lyrics);

    return lyrics;
  }

  /// Try to fetch synced lyrics using parallel API calls
  Future<LyricsModel?> _trySyncedLyrics(String artist, String title) async {
    try {
      return await _remoteDataSource.fetchSyncedLyricsParallel(artist, title);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Lyrics> searchLyrics(String artist, String title) async {
    final songId = _generateSongId(artist, title);

    // First check cache
    final cachedLyrics = _localDataSource.getCachedLyrics(songId);
    if (cachedLyrics != null) {
      return cachedLyrics;
    }

    // Try parallel synced lyrics first
    var lyrics = await _trySyncedLyrics(artist, title);

    // Fall back to sequential fetch
    lyrics ??= await _remoteDataSource.fetchLyricsWithFallback(artist, title);

    // Cache the result
    await _localDataSource.cacheLyrics(lyrics);

    return lyrics;
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
