import '../datasources/genius_lyrics_datasource.dart';
import '../../core/utils/song_key.dart';
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
  final GeniusLyricsDataSource? _geniusDataSource;

  LyricsRepositoryImpl({
    required LyricsRemoteDataSource remoteDataSource,
    required LyricsLocalDataSource localDataSource,
    GeniusLyricsDataSource? geniusDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource,
       _geniusDataSource = geniusDataSource;

  @override
  Future<Lyrics> getLyrics(Song song, {List<String>? providerPriority, bool forceRefresh = false}) async {
    // Generate consistent songId from artist/title (same as searchLyrics)

    // Check cache only if it matches the exact song
    final cachedLyrics = _findCached(artist: song.artist, title: song.title);
    if (!forceRefresh && cachedLyrics != null) {
      // Return cached synced lyrics immediately
      if (cachedLyrics.isSynced) return cachedLyrics;
      // Return cached unsynced, but don't block - upgrade can happen next time
      return cachedLyrics;
    }

    // ONE parallel blast of ALL APIs at once, respecting user provider priority
    var lyrics = await _remoteDataSource.fetchAllParallel(
      song.artist,
      song.title,
      providerPriority: providerPriority,
    );

    lyrics ??= await _geniusDataSource?.findExact(song.artist, song.title);

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

    // First check cache
    final cachedLyrics = _findCached(artist: artist, title: title);
    if (cachedLyrics != null) {
      return cachedLyrics;
    }

    // ONE parallel blast of ALL APIs
    var lyrics = await _remoteDataSource.fetchAllParallel(
      artist,
      title,
      providerPriority: providerPriority,
    );

    lyrics ??= await _geniusDataSource?.findExact(artist, title);

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

  LyricsModel? _findCached({required String artist, required String title}) {
    final key = songKey(artist, title);
    final exact = _localDataSource.getCachedLyrics(key);
    if (exact != null) return exact;
    // Recover legacy entries by metadata without trusting colliding old keys.
    for (final entry in _localDataSource.getAllCachedLyrics()) {
      if (entry.artistName != null && entry.trackName != null &&
          songKey(entry.artistName!, entry.trackName!) == key) return entry;
    }
    return null;
  }
}
