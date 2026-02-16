import 'package:flutter/foundation.dart';
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
  final List<String> _providerPriority;

  LyricsNotifier({
    required GetLyricsUseCase getLyricsUseCase,
    required SearchLyricsUseCase searchLyricsUseCase,
    required GetCachedLyricsUseCase getCachedLyricsUseCase,
    required List<String> providerPriority,
  }) : _getLyricsUseCase = getLyricsUseCase,
       _searchLyricsUseCase = searchLyricsUseCase,
       _getCachedLyricsUseCase = getCachedLyricsUseCase,
       _providerPriority = providerPriority,
       super(const LyricsState());

  /// Set current song and fetch lyrics
  Future<void> setSong(Song song) async {
    if (kDebugMode) {
      debugPrint('🎵 Fetching lyrics for: ${song.title} by ${song.artist}');
    }

    state = state.copyWith(currentSong: song, isLoading: true, error: null);

    try {
      // Check cache first
      final cached = await _getCachedLyricsUseCase(song.id);
      if (cached != null) {
        if (kDebugMode) debugPrint('✅ Using cached lyrics for ${song.title}');
        state = state.copyWith(lyrics: cached, isLoading: false);
        return;
      }

      // Fetch from remote with user's provider priority
      if (kDebugMode) {
        debugPrint(
          '🔄 Fetching lyrics from remote for ${song.title} (providers: $_providerPriority)',
        );
      }
      final lyrics = await _getLyricsUseCase(
        song,
        providerPriority: _providerPriority,
      );
      if (kDebugMode) {
        debugPrint('✅ Successfully fetched lyrics for ${song.title}');
      }
      state = state.copyWith(lyrics: lyrics, isLoading: false);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching lyrics: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search for lyrics manually
  Future<void> searchLyrics(String artist, String title) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final lyrics = await _searchLyricsUseCase(
        artist,
        title,
        providerPriority: _providerPriority,
      );
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
      final settings = ref.watch(settingsProvider);
      return LyricsNotifier(
        getLyricsUseCase: ref.watch(getLyricsUseCaseProvider),
        searchLyricsUseCase: ref.watch(searchLyricsUseCaseProvider),
        getCachedLyricsUseCase: ref.watch(getCachedLyricsUseCaseProvider),
        providerPriority: settings.providerPriority,
      );
    });

/// Cached lyrics list provider
final cachedLyricsProvider = FutureProvider<List<Lyrics>>((ref) async {
  final repository = ref.watch(lyricsRepositoryProvider);
  return repository.getAllCachedLyrics();
});
