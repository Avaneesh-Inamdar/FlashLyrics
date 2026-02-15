import '../entities/song.dart';
import '../entities/lyrics.dart';
import '../repositories/lyrics_repository.dart';

/// Use case for getting lyrics for a song
class GetLyricsUseCase {
  final LyricsRepository _repository;

  GetLyricsUseCase(this._repository);

  Future<Lyrics> call(Song song, {List<String>? providerPriority}) =>
      _repository.getLyrics(song, providerPriority: providerPriority);
}

/// Use case for searching lyrics
class SearchLyricsUseCase {
  final LyricsRepository _repository;

  SearchLyricsUseCase(this._repository);

  Future<Lyrics> call(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) => _repository.searchLyrics(
    artist,
    title,
    providerPriority: providerPriority,
  );
}

/// Use case for getting cached lyrics
class GetCachedLyricsUseCase {
  final LyricsRepository _repository;

  GetCachedLyricsUseCase(this._repository);

  Future<Lyrics?> call(String songId) => _repository.getCachedLyrics(songId);
}

/// Use case for getting all cached lyrics
class GetAllCachedLyricsUseCase {
  final LyricsRepository _repository;

  GetAllCachedLyricsUseCase(this._repository);

  Future<List<Lyrics>> call() => _repository.getAllCachedLyrics();
}

/// Use case for searching cached lyrics
class SearchCachedLyricsUseCase {
  final LyricsRepository _repository;

  SearchCachedLyricsUseCase(this._repository);

  Future<List<Lyrics>> call(String query) =>
      _repository.searchCachedLyrics(query);
}
