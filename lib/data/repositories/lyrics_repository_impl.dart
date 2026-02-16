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
    // First check cache
    final cachedLyrics = _localDataSource.getCachedLyrics(song.id);
    if (cachedLyrics != null) {
      // If cached version exists but isn't synced, try to get synced version
      if (!cachedLyrics.isSynced) {
        final syncedLyrics = await _trySyncedLyrics(
          song.artist,
          song.title,
          providerPriority: providerPriority,
        );
        if (syncedLyrics != null) {
          await _localDataSource.cacheLyrics(syncedLyrics);
          return syncedLyrics;
        }
      }
      return cachedLyrics;
    }

    // Try to get synced lyrics first (parallel fetch)
    var lyrics = await _trySyncedLyrics(
      song.artist,
      song.title,
      providerPriority: providerPriority,
    );

    // Fall back to sequential fetch if parallel failed
    if (lyrics == null) {
      lyrics = await _remoteDataSource.fetchLyricsWithFallback(
        song.artist,
        song.title,
        providerPriority: providerPriority,
      );
    }

    // If still no lyrics or empty, try intelligent search fallback
    if (lyrics == null || lyrics.plainLyrics.isEmpty) {
      lyrics = await _trySearchFallback(
        song.artist,
        song.title,
        providerPriority: providerPriority,
      );
    }

    // If still no lyrics, throw exception
    if (lyrics == null) {
      throw LyricsNotFoundException(
        message: 'Lyrics not found for "${song.title}" by "${song.artist}"',
      );
    }

    await _localDataSource.cacheLyrics(lyrics);
    return lyrics;
  }

  /// Try to fetch synced lyrics using parallel API calls
  Future<LyricsModel?> _trySyncedLyrics(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    try {
      return await _remoteDataSource.fetchSyncedLyricsParallel(
        artist,
        title,
        providerPriority: providerPriority,
      );
    } catch (e) {
      return null;
    }
  }

  /// Intelligent search fallback - tries multiple search strategies
  Future<LyricsModel?> _trySearchFallback(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    try {
      // Try LRCLIB search first (most comprehensive)
      final searchResults = await _remoteDataSource.searchLrclib(
        '$artist $title',
      );

      if (searchResults.isNotEmpty) {
        // Return the first result (most relevant)
        return searchResults.first;
      }

      // Try with just the title if artist search failed
      if (artist.isNotEmpty) {
        final titleOnlyResults = await _remoteDataSource.searchLrclib(title);
        if (titleOnlyResults.isNotEmpty) {
          return titleOnlyResults.first;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
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

    // Try parallel synced lyrics first
    var lyrics = await _trySyncedLyrics(
      artist,
      title,
      providerPriority: providerPriority,
    );

    // Fall back to sequential fetch
    lyrics ??= await _remoteDataSource.fetchLyricsWithFallback(
      artist,
      title,
      providerPriority: providerPriority,
    );

    // If still no lyrics, try intelligent search fallback
    if (lyrics == null || lyrics.plainLyrics.isEmpty) {
      lyrics = await _trySearchFallback(
        artist,
        title,
        providerPriority: providerPriority,
      );
    }

    // Cache and return the result
    if (lyrics != null) {
      await _localDataSource.cacheLyrics(lyrics);
      return lyrics;
    }

    // Throw proper exception if no lyrics found
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
