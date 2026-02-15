import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/song.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/usecases/lyrics_usecases.dart';
import '../../data/models/lyrics_model.dart';
import 'providers.dart';

/// State for lyrics
class LyricsState {
  final Song? currentSong;
  final Lyrics? lyrics;
  final bool isLoading;
  final String? error;

  const LyricsState({
    this.currentSong,
    this.lyrics,
    this.isLoading = false,
    this.error,
  });

  LyricsState copyWith({
    Song? currentSong,
    Lyrics? lyrics,
    bool? isLoading,
    String? error,
  }) {
    return LyricsState(
      currentSong: currentSong ?? this.currentSong,
      lyrics: lyrics ?? this.lyrics,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Lyrics state notifier
class LyricsNotifier extends StateNotifier<LyricsState> {
  final GetLyricsUseCase _getLyricsUseCase;
  final SearchLyricsUseCase _searchLyricsUseCase;
  final GetCachedLyricsUseCase _getCachedLyricsUseCase;

  LyricsNotifier({
    required GetLyricsUseCase getLyricsUseCase,
    required SearchLyricsUseCase searchLyricsUseCase,
    required GetCachedLyricsUseCase getCachedLyricsUseCase,
  }) : _getLyricsUseCase = getLyricsUseCase,
       _searchLyricsUseCase = searchLyricsUseCase,
       _getCachedLyricsUseCase = getCachedLyricsUseCase,
       super(const LyricsState());

  /// Set current song and fetch lyrics
  Future<void> setSong(Song song) async {
    state = state.copyWith(currentSong: song, isLoading: true, error: null);

    try {
      // Check cache first
      final cached = await _getCachedLyricsUseCase(song.id);
      if (cached != null) {
        state = state.copyWith(lyrics: cached, isLoading: false);
        return;
      }

      // Fetch from remote
      final lyrics = await _getLyricsUseCase(song);
      state = state.copyWith(lyrics: lyrics, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search for lyrics manually
  Future<void> searchLyrics(String artist, String title) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final lyrics = await _searchLyricsUseCase(artist, title);
      state = state.copyWith(lyrics: lyrics, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Set lyrics directly from a LyricsModel (from search results)
  void setLyricsFromModel(LyricsModel model) {
    // Create a song from the search result metadata
    final song = Song(
      id: model.songId,
      title: model.trackName ?? 'Unknown Song',
      artist: model.artistName ?? 'Unknown Artist',
      album: model.albumName,
      source: 'Search',
    );

    final lyrics = Lyrics(
      id: model.id,
      songId: model.songId,
      plainLyrics: model.plainLyrics,
      lrcLyrics: model.lrcLyrics,
      isSynced: model.isSynced,
      source: model.source,
      fetchedAt: model.fetchedAt,
    );

    state = LyricsState(
      currentSong: song,
      lyrics: lyrics,
      isLoading: false,
      error: null,
    );
  }

  /// Clear lyrics
  void clear() {
    state = const LyricsState();
  }
}

/// Lyrics state notifier provider
final lyricsNotifierProvider =
    StateNotifierProvider<LyricsNotifier, LyricsState>((ref) {
      return LyricsNotifier(
        getLyricsUseCase: ref.watch(getLyricsUseCaseProvider),
        searchLyricsUseCase: ref.watch(searchLyricsUseCaseProvider),
        getCachedLyricsUseCase: ref.watch(getCachedLyricsUseCaseProvider),
      );
    });

/// Cached lyrics list provider
final cachedLyricsProvider = FutureProvider<List<Lyrics>>((ref) async {
  final repository = ref.watch(lyricsRepositoryProvider);
  return repository.getAllCachedLyrics();
});
