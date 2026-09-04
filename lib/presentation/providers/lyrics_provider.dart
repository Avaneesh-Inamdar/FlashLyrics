import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/exceptions.dart';
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

  /// Use [clearLyrics] = true to explicitly set lyrics to null
  LyricsState copyWith({
    Song? currentSong,
    Lyrics? lyrics,
    bool? isLoading,
    String? error,
    bool clearLyrics = false,
  }) {
    return LyricsState(
      currentSong: currentSong ?? this.currentSong,
      lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
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
  int _latestSearchId = 0; // Track latest search to prevent race conditions
  int _latestSongRequestId = 0;

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
  Future<void> setSong(Song song, {bool forceRefresh = false}) async {
    final requestId = ++_latestSongRequestId;
    if (kDebugMode) {
      debugPrint('🎵 Fetching lyrics for: ${song.title} by ${song.artist}');
    }

    state = state.copyWith(
      currentSong: song,
      isLoading: true,
      error: null,
      clearLyrics: true,
    );

    try {
      // Check cache first unless forced refresh (Unicode-aware songId to avoid Hindi collisions)
      final rawId = '${song.artist.trim()}_${song.title.trim()}'
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '_');
      String songId;
      try {
        songId = rawId
            .replaceAll(RegExp(r'[^\p{L}\p{N}_]+', unicode: true), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
      } catch (_) {
        songId = rawId
            .replaceAll(
              RegExp(r'[^a-zA-Z0-9_\u0900-\u097F\u4E00-\u9FFF]+'),
              '_',
            )
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
      }
      if (songId.isEmpty)
        songId = '${song.artist}_${song.title}'.hashCode.toString();
      if (!forceRefresh) {
        final cached = await _getCachedLyricsUseCase(songId);
        if (cached != null) {
          bool cacheValid = true;
          // Only LyricsModel has artistName/trackName for verification
          if (cached is LyricsModel) {
            // Older cache entries predate metadata verification. Refresh them
            // once rather than allowing an old wrong match to stay pinned.
            if (!cached.isMatchVerified) cacheValid = false;
            final cArtist = cached.artistName ?? '';
            final cTitle = cached.trackName ?? '';
            if (cArtist.isNotEmpty && cTitle.isNotEmpty) {
              final reqA = song.artist.toLowerCase().trim();
              final reqT = song.title.toLowerCase().trim();
              final ca = cArtist.toLowerCase().trim();
              final ct = cTitle.toLowerCase().trim();
              final titleMatch =
                  ct.contains(reqT) || reqT.contains(ct) || ct == reqT;
              bool artistMatch = true;
              if (reqA.isNotEmpty && ca.isNotEmpty) {
                if (!(ca.contains(reqA) || reqA.contains(ca))) {
                  final reqWords = reqA
                      .split(RegExp(r'\s+'))
                      .where((w) => w.length > 2)
                      .toSet();
                  final cWords = ca
                      .split(RegExp(r'[\s,/&]+'))
                      .where((w) => w.length > 2)
                      .toSet();
                  if (reqWords.intersection(cWords).isEmpty)
                    artistMatch = false;
                }
              }
              if (!titleMatch || !artistMatch) {
                cacheValid = false;
                if (kDebugMode)
                  debugPrint(
                    '⚠️ Cached mismatch for ${song.title} (cached: $cTitle by $cArtist), refetching',
                  );
              }
            }
          }
          if (cacheValid) {
            if (kDebugMode)
              debugPrint('✅ Using cached lyrics for ${song.title}');
            if (requestId != _latestSongRequestId) return;
            state = state.copyWith(lyrics: cached, isLoading: false);
            return;
          }
        }
      }

      // Fetch from remote with user's provider priority and overall timeout
      if (kDebugMode) {
        debugPrint(
          '🔄 Fetching lyrics from remote for ${song.title} (providers: $_providerPriority, force: $forceRefresh)',
        );
      }
      final lyrics =
          await _getLyricsUseCase(
            song,
            providerPriority: _providerPriority,
          ).timeout(
            const Duration(seconds: 22),
            onTimeout: () => throw TimeoutException(
              'Lyrics fetch timed out. Try searching manually.',
            ),
          );
      if (kDebugMode) {
        debugPrint('✅ Successfully fetched lyrics for ${song.title}');
      }
      // Media callbacks overlap during skips.  An older response must never
      // overwrite lyrics for the song that is now playing.
      if (requestId != _latestSongRequestId) return;
      state = state.copyWith(lyrics: lyrics, isLoading: false);
    } catch (e) {
      if (requestId != _latestSongRequestId) return;
      if (kDebugMode) debugPrint('❌ Error fetching lyrics: $e');
      if (e is LyricsNotFoundException) {
        state = state.copyWith(
          isLoading: false,
          error: 'Lyrics not found',
          clearLyrics: true,
        );
        return;
      }
      if (e is TimeoutException) {
        state = state.copyWith(
          isLoading: false,
          error: 'Took too long to fetch lyrics. Try searching manually.',
          clearLyrics: true,
        );
        return;
      }
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search for lyrics manually
  Future<void> searchLyrics(String artist, String title) async {
    final searchId = ++_latestSearchId; // Track this search request
    state = state.copyWith(isLoading: true, error: null, clearLyrics: true);

    try {
      final lyrics =
          await _searchLyricsUseCase(
            artist,
            title,
            providerPriority: _providerPriority,
          ).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('Manual search timed out'),
          );

      // Only update state if this is still the latest search
      if (searchId == _latestSearchId) {
        state = state.copyWith(
          lyrics: lyrics,
          isLoading: false,
          currentSong: Song(
            id: lyrics.songId,
            title: title,
            artist: artist,
            album: null,
          ),
        );
      }
    } catch (e) {
      // Only update state if this is still the latest search
      if (searchId == _latestSearchId) {
        if (e is TimeoutException) {
          state = state.copyWith(
            isLoading: false,
            error: 'Search timed out. Try again.',
            clearLyrics: true,
          );
        } else if (e is LyricsNotFoundException) {
          state = state.copyWith(
            isLoading: false,
            error: 'No lyrics found for "$title" by "$artist"',
            clearLyrics: true,
          );
        } else {
          state = state.copyWith(
            isLoading: false,
            error: 'Search error: ${e.toString()}',
            clearLyrics: true,
          );
        }
      }
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
      final providerPriority = ref.watch(
        settingsProvider.select((settings) => settings.providerPriority),
      );
      return LyricsNotifier(
        getLyricsUseCase: ref.watch(getLyricsUseCaseProvider),
        searchLyricsUseCase: ref.watch(searchLyricsUseCaseProvider),
        getCachedLyricsUseCase: ref.watch(getCachedLyricsUseCaseProvider),
        providerPriority: providerPriority,
      );
    });

/// Cached lyrics list provider
final cachedLyricsProvider = FutureProvider<List<Lyrics>>((ref) async {
  final repository = ref.watch(lyricsRepositoryProvider);
  return repository.getAllCachedLyrics();
});
