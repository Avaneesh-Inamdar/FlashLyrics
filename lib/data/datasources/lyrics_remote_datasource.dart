import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/exceptions.dart';
import '../models/lyrics_model.dart';

/// Remote data source for fetching lyrics from multiple APIs
/// Implements a fallback chain prioritizing synced lyrics sources
class LyricsRemoteDataSource {
  final Dio _dio;

  LyricsRemoteDataSource(this._dio);

  /// Clean and normalize text for better search results
  /// Handles Hindi, special characters, and common metadata issues
  String _normalizeText(String text, {bool isNonLatin = false}) {
    // For non-Latin text (Hindi, Chinese, etc.), be more conservative with normalization
    if (isNonLatin) {
      // Just normalize quotes and collapse whitespace for non-Latin text
      var cleaned = text
          .replaceAll(RegExp(r'[""„]'), '"') // Normalize quotes
          .replaceAll(
            RegExp(
              r'['
              ']',
            ),
            "'",
          ) // Normalize apostrophes
          .trim();
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      return cleaned;
    }

    // Aggressive normalization for Latin text
    var cleaned = text
        .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ') // Remove parentheses content
        .replaceAll(RegExp(r'\s*\[.*?\]\s*'), ' ') // Remove brackets content
        .replaceAll(
          RegExp(
            r'\s*-\s*(Official|Audio|Video|Lyrics|HD|HQ|4K).*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\s*\|\s*.*$'),
          '',
        ) // Remove pipe and everything after
        .replaceAll(RegExp(r'[""„]'), '"') // Normalize quotes
        .replaceAll(
          RegExp(
            r'['
            ']',
          ),
          "'",
        ) // Normalize apostrophes
        .trim();

    // Collapse multiple whitespace
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned;
  }

  /// Check if text contains non-Latin characters (Hindi, Chinese, etc.)
  bool _containsNonLatin(String text) {
    // Match Devanagari (Hindi), Chinese, Japanese, Korean, Arabic, etc.
    return RegExp(
      r'[\u0900-\u097F\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF\u0600-\u06FF]',
    ).hasMatch(text);
  }

  /// Fetch lyrics with intelligent fallback chain
  /// Prioritizes APIs that provide synced (LRC) lyrics
  /// [providerPriority] - Optional custom priority order for providers
  Future<LyricsModel?> fetchLyricsWithFallback(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    // Check if this is a non-English song upfront
    final isNonLatin = _containsNonLatin('$artist$title');

    // Normalize inputs for better matching
    final cleanArtist = _normalizeText(artist, isNonLatin: isNonLatin);
    final cleanTitle = _normalizeText(title, isNonLatin: isNonLatin);
    final songId = _generateSongId(artist, title);
    final errors = <String>[];

    // For non-Latin songs, prioritize NetEase which has better Asian music support
    List<String> priority;
    if (isNonLatin) {
      priority = [
        'netease',
        'lrclib',
        'textyl',
        'lyrics.ovh',
        'lyrist',
        'chartlyrics',
      ];
    } else {
      priority = providerPriority ?? ApiConstants.apiPriority;
    }

    // Strategy 1: Try with original text (FAST)
    for (final api in priority) {
      try {
        final result = await _fetchFromApi(
          api,
          artist,
          title,
          songId,
        ).timeout(const Duration(seconds: 6));
        if (result != null && result.plainLyrics.isNotEmpty) {
          return result;
        }
        errors.add('$api: No lyrics found');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          errors.add('$api: Not found');
        } else {
          errors.add('$api: Network error');
        }
        continue;
      } catch (e) {
        continue;
      }
    }

    // Strategy 2: Try with cleaned/normalized text (helps for Hindi/special characters)
    // But only if it's different from original
    if (cleanArtist != artist || cleanTitle != title) {
      for (final api in priority) {
        try {
          final result = await _fetchFromApi(
            api,
            cleanArtist,
            cleanTitle,
            songId,
          ).timeout(const Duration(seconds: 5));
          if (result != null && result.plainLyrics.isNotEmpty) {
            return result;
          }
        } catch (e) {
          continue;
        }
      }
    }

    // Strategy 3: For non-Latin songs, try with just title (artist data often incomplete)
    if (isNonLatin && title.isNotEmpty) {
      for (final api in priority) {
        try {
          final result = await _fetchFromApi(
            api,
            '',
            title,
            songId,
          ).timeout(const Duration(seconds: 5));
          if (result != null && result.plainLyrics.isNotEmpty) {
            return result;
          }
        } catch (e) {
          continue;
        }
      }
    }

    // Strategy 4: Try LRCLIB search (fuzzy matching, works for partial/mismatched metadata)
    final searchQueries = <String>{
      '$artist $title'.trim(),
      '$cleanArtist $cleanTitle'.trim(),
      title.trim(),
      cleanTitle.trim(),
    }..removeWhere((q) => q.isEmpty);

    for (final query in searchQueries) {
      try {
        final searchResults = await searchLrclib(
          query,
        ).timeout(const Duration(seconds: 5));
        for (final result in searchResults) {
          if (result.plainLyrics.isNotEmpty) {
            return result;
          }
        }
      } catch (_) {
        continue;
      }
    }

    // All strategies exhausted
    return null;
  }

  /// Search all APIs for lyrics - used for manual search
  /// Returns a map of provider name to results
  /// Respects optional [providerPriority] — only queries those providers
  Future<Map<String, LyricsModel?>> searchAllProviders(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    final effective = providerPriority ?? ApiConstants.apiPriority;
    final songId = _generateSongId(artist, title);
    final results = <String, LyricsModel?>{};

    await Future.wait(
      effective.map((api) async {
        try {
          results[api] = await _fetchFromApi(api, artist, title, songId);
        } catch (e) {
          results[api] = null;
        }
      }),
    );

    return results;
  }

  /// Route to appropriate API handler
  Future<LyricsModel?> _fetchFromApi(
    String api,
    String artist,
    String title,
    String songId,
  ) async {
    switch (api) {
      case 'lrclib':
        return await _fetchFromLrclib(artist, title, songId);
      case 'textyl':
        return await _fetchFromTextyl(artist, title, songId);
      case 'lyrics.ovh':
        return await _fetchFromLyricsOvh(artist, title, songId);
      case 'lyrist':
        return await _fetchFromLyrist(artist, title, songId);
      case 'chartlyrics':
        return await _fetchFromChartLyrics(artist, title, songId);
      case 'netease':
        return await _fetchFromNetEase(artist, title, songId);
      default:
        return null;
    }
  }

  /// Fetch from LRCLIB - Best source for synced lyrics
  /// API: https://lrclib.net/api/get?track_name={title}&artist_name={artist}
  Future<LyricsModel?> _fetchFromLrclib(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.lrclibApi,
        queryParameters: {'track_name': title, 'artist_name': artist},
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final plainLyrics = data['plainLyrics'] as String? ?? '';
        final syncedLyrics = data['syncedLyrics'] as String?;

        if (plainLyrics.isEmpty &&
            (syncedLyrics == null || syncedLyrics.isEmpty)) {
          return null;
        }

        return LyricsModel(
          id: '${songId}_${DateTime.now().millisecondsSinceEpoch}',
          songId: songId,
          plainLyrics: plainLyrics.isNotEmpty
              ? plainLyrics
              : _extractPlainFromLrc(syncedLyrics ?? ''),
          lrcLyrics: syncedLyrics,
          isSynced: syncedLyrics != null && syncedLyrics.isNotEmpty,
          source: 'LRCLIB',
          fetchedAt: DateTime.now(),
          artistName: artist.isNotEmpty ? artist : null,
          trackName: title.isNotEmpty ? title : null,
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Search LRCLIB for multiple matches
  Future<List<LyricsModel>> searchLrclib(String query) async {
    try {
      final response = await _dio.get(
        ApiConstants.lrclibSearchApi,
        queryParameters: {'q': query},
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> results = response.data as List<dynamic>;
        return results.map((data) {
          final map = data as Map<String, dynamic>;
          final artist = map['artistName'] as String? ?? '';
          final title = map['trackName'] as String? ?? '';
          final album = map['albumName'] as String?;
          final songId = _generateSongId(artist, title);

          return LyricsModel(
            id: '${songId}_${map['id']}',
            songId: songId,
            plainLyrics: map['plainLyrics'] as String? ?? '',
            lrcLyrics: map['syncedLyrics'] as String?,
            isSynced: map['syncedLyrics'] != null,
            source: 'LRCLIB',
            fetchedAt: DateTime.now(),
            artistName: artist,
            trackName: title,
            albumName: album,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch from Textyl - Another synced lyrics source
  /// API: https://api.textyl.co/api/lyrics?q={artist} {title}
  Future<LyricsModel?> _fetchFromTextyl(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.textylApi,
        queryParameters: {'q': '$artist $title'},
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        // Textyl returns an array of lyric lines with timestamps
        final List<dynamic> lines = response.data as List<dynamic>;

        if (lines.isEmpty) return null;

        // Convert to LRC format and plain text
        final lrcBuffer = StringBuffer();
        final plainBuffer = StringBuffer();

        for (final line in lines) {
          if (line is Map<String, dynamic>) {
            final seconds = (line['seconds'] as num?)?.toDouble() ?? 0;
            final text = line['lyrics'] as String? ?? '';

            // Convert seconds to LRC timestamp [mm:ss.xx]
            final minutes = (seconds / 60).floor();
            final secs = seconds % 60;
            final timestamp =
                '[${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(2).padLeft(5, '0')}]';

            lrcBuffer.writeln('$timestamp$text');
            plainBuffer.writeln(text);
          }
        }

        final lrcLyrics = lrcBuffer.toString().trim();
        final plainLyrics = plainBuffer.toString().trim();

        if (plainLyrics.isEmpty) return null;

        return LyricsModel(
          id: '${songId}_${DateTime.now().millisecondsSinceEpoch}',
          songId: songId,
          plainLyrics: plainLyrics,
          lrcLyrics: lrcLyrics,
          isSynced: true,
          source: 'Textyl',
          fetchedAt: DateTime.now(),
          artistName: artist.isNotEmpty ? artist : null,
          trackName: title.isNotEmpty ? title : null,
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Fetch from lyrics.ovh - Plain lyrics only
  /// API: https://api.lyrics.ovh/v1/{artist}/{title}
  Future<LyricsModel?> _fetchFromLyricsOvh(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      final encodedArtist = Uri.encodeComponent(artist);
      final encodedTitle = Uri.encodeComponent(title);

      final response = await _dio.get(
        '${ApiConstants.lyricsOvhApi}/$encodedArtist/$encodedTitle',
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final lyrics = data['lyrics'] as String?;

        if (lyrics == null || lyrics.isEmpty) return null;

        return LyricsModel(
          id: '${songId}_${DateTime.now().millisecondsSinceEpoch}',
          songId: songId,
          plainLyrics: lyrics.trim(),
          lrcLyrics: null,
          isSynced: false,
          source: 'lyrics.ovh',
          fetchedAt: DateTime.now(),
          artistName: artist.isNotEmpty ? artist : null,
          trackName: title.isNotEmpty ? title : null,
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Fetch from Lyrist - Alternative plain lyrics source
  /// API: https://lyrist.vercel.app/api/{artist}/{title}
  Future<LyricsModel?> _fetchFromLyrist(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      final encodedArtist = Uri.encodeComponent(artist);
      final encodedTitle = Uri.encodeComponent(title);

      final response = await _dio.get(
        '${ApiConstants.lyristApi}/$encodedArtist/$encodedTitle',
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final lyrics = data['lyrics'] as String?;

        if (lyrics == null || lyrics.isEmpty) return null;

        return LyricsModel(
          id: '${songId}_${DateTime.now().millisecondsSinceEpoch}',
          songId: songId,
          plainLyrics: lyrics.trim(),
          lrcLyrics: null,
          isSynced: false,
          source: 'Lyrist',
          fetchedAt: DateTime.now(),
          artistName: artist.isNotEmpty ? artist : null,
          trackName: title.isNotEmpty ? title : null,
        );
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Parallel fetch from multiple synced lyrics APIs
  /// Returns the first successful result with synced lyrics
  Future<LyricsModel?> fetchSyncedLyricsParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    final songId = _generateSongId(artist, title);
    final isNonLatin = _containsNonLatin('$artist$title');
    final cleanArtist = _normalizeText(artist, isNonLatin: isNonLatin);
    final cleanTitle = _normalizeText(title, isNonLatin: isNonLatin);

    // Launch parallel requests to synced lyrics APIs
    final futures = <Future<LyricsModel?>>[];
    final seen = <String>{};
    void addFetch(String a, String t) {
      final key = '$a|$t';
      if (!seen.add(key)) return;
      futures.add(_fetchFromLrclib(a, t, songId));
      futures.add(_fetchFromTextyl(a, t, songId));
    }

    addFetch(artist, title);
    if (cleanArtist != artist || cleanTitle != title) {
      addFetch(cleanArtist, cleanTitle);
    }
    if (isNonLatin) {
      addFetch('', title);
      if (cleanTitle != title) {
        addFetch('', cleanTitle);
      }
    }

    // Wait for all requests with a timeout per request
    final results = await Future.wait(
      futures.map(
        (f) => f.timeout(const Duration(seconds: 12), onTimeout: () => null),
      ),
    );

    // FIXED: Prioritize synced lyrics over unsynced
    // First, check for synced lyrics
    for (final result in results) {
      if (result != null && result.isSynced && result.lrcLyrics != null) {
        return result;
      }
    }

    // Try LRCLIB search fallback for synced lyrics (helps for metadata mismatches)
    final searchQueries = <String>{
      '$artist $title'.trim(),
      '$cleanArtist $cleanTitle'.trim(),
      title.trim(),
      cleanTitle.trim(),
    }..removeWhere((q) => q.isEmpty);

    final searchSynced = await _searchSyncedLrclib(searchQueries);
    if (searchSynced != null) {
      return searchSynced;
    }

    // If no synced lyrics found, return any result with lyrics
    for (final result in results) {
      if (result != null && result.plainLyrics.isNotEmpty) {
        return result;
      }
    }

    return null;
  }

  Future<LyricsModel?> _searchSyncedLrclib(Set<String> queries) async {
    for (final query in queries) {
      if (query.trim().isEmpty) continue;
      final searchResults = await searchLrclib(query);
      for (final result in searchResults) {
        if (result.isSynced &&
            result.lrcLyrics != null &&
            result.lrcLyrics!.isNotEmpty) {
          return result;
        }
      }
    }
    return null;
  }

  /// MAIN ENTRY POINT: Fetch lyrics from ALL APIs in parallel
  /// Returns the best result (synced > plain), null if nothing found
  /// Now respects [providerPriority] — results are ranked by priority, not insertion order.
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    final songId = _generateSongId(artist, title);
    final isNonLatin = _containsNonLatin('$artist$title');
    final cleanArtist = _normalizeText(artist, isNonLatin: isNonLatin);
    final cleanTitle = _normalizeText(title, isNonLatin: isNonLatin);

    // Determine effective priority: user order or default, with non-Latin boost for NetEase
    List<String> effectivePriority = providerPriority ?? ApiConstants.apiPriority;
    // Clone to avoid mutating caller's list
    effectivePriority = List<String>.from(effectivePriority);
    if (isNonLatin && effectivePriority.contains('netease')) {
      // Move netease to front for non-Latin songs, preserving relative order otherwise
      effectivePriority.remove('netease');
      effectivePriority.insert(0, 'netease');
    }
    // Ensure all needed providers are considered; if priority is truncated, add missing defaults at end
    // (user may have reordered a subset)
    for (final p in ApiConstants.apiPriority) {
      if (!effectivePriority.contains(p)) effectivePriority.add(p);
    }

    final futures = <Future<LyricsModel?>>[];
    final seen = <String>{};

    Future<LyricsModel?> fetchForProvider(String provider, String a, String t, String sid) {
      switch (provider) {
        case 'lrclib':
          return _fetchFromLrclib(a, t, sid);
        case 'textyl':
          return _fetchFromTextyl(a, t, sid);
        case 'chartlyrics':
          return _fetchFromChartLyrics(a, t, sid);
        case 'lyrics.ovh':
          return _fetchFromLyricsOvh(a, t, sid);
        case 'lyrist':
          return _fetchFromLyrist(a, t, sid);
        case 'netease':
          return _fetchFromNetEase(a, t, sid);
        default:
          return Future.value(null);
      }
    }

    void addForVariation(String a, String t) {
      final key = '${a.toLowerCase()}|${t.toLowerCase()}';
      if (!seen.add(key)) return;
      final sid = _generateSongId(a, t);
      for (final provider in effectivePriority) {
        futures.add(_safeFetch(() => fetchForProvider(provider, a, t, sid)));
      }
    }

    // Variation 1: Original text
    addForVariation(artist, title);
    // Variation 2: Cleaned/normalized text
    addForVariation(cleanArtist, cleanTitle);
    // Variation 3: Title only (helps for many songs)
    addForVariation('', title);
    if (cleanTitle != title) addForVariation('', cleanTitle);

    // LRCLIB search (fuzzy matching) — only if lrclib is in priority and enabled
    if (effectivePriority.contains('lrclib')) {
      final searchQueries = <String>{
        '$artist $title'.trim(),
        '$cleanArtist $cleanTitle'.trim(),
        title.trim(),
        cleanTitle.trim(),
      }..removeWhere((q) => q.isEmpty);

      for (final query in searchQueries) {
        futures.add(
          _safeFetch(() async {
            final results = await searchLrclib(query);
            LyricsModel? bestPlain;
            for (final r in results) {
              if (r.isSynced && r.lrcLyrics != null && r.plainLyrics.isNotEmpty) {
                return r;
              }
              bestPlain ??= (r.plainLyrics.isNotEmpty ? r : null);
            }
            return bestPlain;
          }),
        );
      }
    }

    // Fire ALL at once with 15 second timeout per call
    final results = await Future.wait(
      futures.map(
        (f) => f.timeout(const Duration(seconds: 15), onTimeout: () => null),
      ),
    );

    // Rank results by (synced first) then provider priority
    int providerIndexFor(LyricsModel m) {
      final src = m.source.toLowerCase();
      String id;
      if (src.contains('lrclib')) id = 'lrclib';
      else if (src.contains('textyl')) id = 'textyl';
      else if (src.contains('chartlyrics')) id = 'chartlyrics';
      else if (src.contains('lyrics.ovh') || src == 'lyrics.ovh') id = 'lyrics.ovh';
      else if (src.contains('lyrist')) id = 'lyrist';
      else if (src.contains('netease')) id = 'netease';
      else id = src;
      final idx = effectivePriority.indexOf(id);
      return idx == -1 ? 999 : idx;
    }

    final valid = results.where((r) => r != null && r.plainLyrics.isNotEmpty).cast<LyricsModel>().toList();
    if (valid.isEmpty) return null;

    valid.sort((a, b) {
      // Synced first
      if (a.isSynced != b.isSynced) return a.isSynced ? -1 : 1;
      // Then by priority index
      final ia = providerIndexFor(a);
      final ib = providerIndexFor(b);
      if (ia != ib) return ia.compareTo(ib);
      return 0;
    });

    return valid.first;
  }

  /// Wraps any fetch in try-catch so it never throws, just returns null
  Future<LyricsModel?> _safeFetch(Future<LyricsModel?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }

  /// Generate consistent song ID
  String _generateSongId(String artist, String title) {
    return '${artist}_$title'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  /// Extract plain text from LRC format
  String _extractPlainFromLrc(String lrc) {
    final lines = lrc.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      // Remove timestamp [mm:ss.xx] from beginning
      final text = line
          .replaceAll(RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\]'), '')
          .trim();
      if (text.isNotEmpty && !text.startsWith('[')) {
        buffer.writeln(text);
      }
    }

    return buffer.toString().trim();
  }

  /// Search across all providers for lyrics using a free-form query
  /// Improved robustness: handles single-string queries, normalizes, and uses
  /// provider priority when ranking. No longer throws on transient network errors.
  Future<List<LyricsModel>> searchByQuery(String query, {List<String>? providerPriority}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final results = <LyricsModel>[];
    // Deduplicate by songId+source to keep different provider variants
    final seen = <String>{};

    String dedupeKey(LyricsModel m) => '${m.source.toLowerCase()}|${m.songId}';

    // Normalize the query
    final normalizedQuery = _normalizeText(q);

    // Parse artist/title from query - support multiple separators
    String? guessedArtist;
    String? guessedTitle;

    if (q.contains(' - ')) {
      final parts = q.split(' - ');
      if (parts.length >= 2) {
        guessedArtist = parts.first.trim();
        guessedTitle = parts.sublist(1).join(' - ').trim();
      }
    } else if (q.contains(' — ')) {
      final parts = q.split(' — ');
      if (parts.length >= 2) {
        guessedArtist = parts.first.trim();
        guessedTitle = parts.sublist(1).join(' — ').trim();
      }
    } else if (q.toLowerCase().contains(' by ')) {
      final byIndex = q.toLowerCase().lastIndexOf(' by ');
      guessedTitle = q.substring(0, byIndex).trim();
      guessedArtist = q.substring(byIndex + 4).trim();
    } else if (q.contains('/')) {
      final parts = q.split('/');
      if (parts.length == 2) {
        guessedArtist = parts[0].trim();
        guessedTitle = parts[1].trim();
      }
    }

    // If we couldn't parse, treat whole query as title and also try as combined
    final effectivePriority = providerPriority ?? ApiConstants.apiPriority;

    // Launch all searches in parallel for maximum speed
    final futures = <Future<void>>[];

    // 1. Always search LRCLIB with the query (most reliable) — unless user disabled lrclib
    if (effectivePriority.contains('lrclib')) {
      futures.add(_searchLrclibAndAddResultsSafe(q, results, seen, dedupeKey));
      if (normalizedQuery != q && normalizedQuery.isNotEmpty) {
        futures.add(_searchLrclibAndAddResultsSafe(normalizedQuery, results, seen, dedupeKey));
      }
    }

    // Helper to add fetches for a given artist/title pair across all enabled providers
    void addFetchesFor(String a, String t) {
      final sid = _generateSongId(a, t);
      for (final provider in effectivePriority) {
        switch (provider) {
          case 'textyl':
            futures.add(_fetchAndAddTextyl(a, t, sid, results, seen, dedupeKey));
            break;
          case 'lyrics.ovh':
            futures.add(_fetchAndAddLyricsOvh(a, t, sid, results, seen, dedupeKey));
            break;
          case 'lyrist':
            futures.add(_fetchAndAddLyrist(a, t, sid, results, seen, dedupeKey));
            break;
          case 'chartlyrics':
            futures.add(_fetchAndAddChartLyrics(a, t, sid, results, seen, dedupeKey));
            break;
          case 'netease':
            futures.add(_fetchAndAddNetEase(a, t, sid, results, seen, dedupeKey));
            break;
          case 'lrclib':
            // Direct lrclib get is already covered via fetchAllParallel logic, but add here too for parsed queries
            futures.add(_fetchAndAddLrclib(a, t, sid, results, seen, dedupeKey));
            break;
        }
      }
    }

    // 2. If we have artist/title, search all providers in parallel with multiple variations
    if (guessedArtist != null && guessedTitle != null && guessedArtist.isNotEmpty && guessedTitle.isNotEmpty) {
      addFetchesFor(guessedArtist, guessedTitle);

      // Also try normalized versions
      final cleanArtist = _normalizeText(guessedArtist);
      final cleanTitle = _normalizeText(guessedTitle);
      if (cleanArtist != guessedArtist || cleanTitle != guessedTitle) {
        addFetchesFor(cleanArtist, cleanTitle);
      }
      // Title-only fallback
      addFetchesFor('', guessedTitle);
      if (cleanTitle != guessedTitle) addFetchesFor('', cleanTitle);
    } else {
      // No parseable artist/title: try query as title-only for each provider
      // This helps when user types just song name like "Believer"
      addFetchesFor('', q);
      if (normalizedQuery != q) addFetchesFor('', normalizedQuery);
      // Also try query as combined artist+title for providers that use q param (Textyl)
      if (effectivePriority.contains('textyl')) {
        final sid = _generateSongId('', q);
        futures.add(_fetchAndAddTextyl('', q, sid, results, seen, dedupeKey));
      }
    }

    // Wait for all parallel searches to complete (with timeout)
    await Future.wait(
      futures.map(
        (f) => f.timeout(const Duration(seconds: 10), onTimeout: () {}),
      ),
    );

    // Sort results: synced first, then by provider priority, then by plain length (longer = more complete)
    results.sort((a, b) {
      if (a.isSynced != b.isSynced) return a.isSynced ? -1 : 1;
      String idFor(LyricsModel m) {
        final s = m.source.toLowerCase();
        if (s.contains('lrclib')) return 'lrclib';
        if (s.contains('textyl')) return 'textyl';
        if (s.contains('chartlyrics')) return 'chartlyrics';
        if (s.contains('lyrics.ovh')) return 'lyrics.ovh';
        if (s.contains('lyrist')) return 'lyrist';
        if (s.contains('netease')) return 'netease';
        return s;
      }
      final ia = effectivePriority.indexOf(idFor(a));
      final ib = effectivePriority.indexOf(idFor(b));
      final pa = ia == -1 ? 999 : ia;
      final pb = ib == -1 ? 999 : ib;
      if (pa != pb) return pa.compareTo(pb);
      // Longer lyrics often more complete
      return b.plainLyrics.length.compareTo(a.plainLyrics.length);
    });

    return results;
  }

  Future<void> _searchLrclibAndAddResultsSafe(
    String query,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final lrclibResults = await searchLrclib(query);
      for (final result in lrclibResults) {
        if (result.plainLyrics.isEmpty) continue;
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  /// Legacy wrapper for older callers
  Future<void> _searchLrclibAndAddResults(
    String query,
    List<LyricsModel> results,
    Set<String> seenIds,
  ) async {
    return _searchLrclibAndAddResultsSafe(query, results, seenIds, (m) => m.songId);
  }

  Future<void> _fetchAndAddTextyl(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromTextyl(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndAddLyricsOvh(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromLyricsOvh(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndAddLyrist(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromLyrist(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndAddChartLyrics(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromChartLyrics(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndAddNetEase(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromNetEase(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAndAddLrclib(
    String artist,
    String title,
    String songId,
    List<LyricsModel> results,
    Set<String> seen,
    String Function(LyricsModel) keyFn,
  ) async {
    try {
      final result = await _fetchFromLrclib(artist, title, songId);
      if (result != null && result.plainLyrics.isNotEmpty) {
        final key = keyFn(result);
        if (!seen.contains(key)) {
          seen.add(key);
          results.add(result);
        }
      }
    } catch (_) {}
  }

  /// Fetch from ChartLyrics - Free API, no authentication required
  /// API: https://www.chartlyrics.com/api.aspx
  Future<LyricsModel?> _fetchFromChartLyrics(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.chartLyricsApi}/search',
        queryParameters: {
          'artist': artist.isEmpty ? ' ' : artist,
          'song': title,
        },
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;

        // ChartLyrics returns a list of results
        final List<dynamic> results =
            data['GetLyricsResult'] as List<dynamic>? ?? [];

        if (results.isNotEmpty) {
          final lyricData = results[0] as Map<String, dynamic>;
          final lyricId = lyricData['LyricId'] as int?;

          if (lyricId != null && lyricId > 0) {
            // Fetch the actual lyrics using the lyric ID
            final lyricResponse = await _dio.get(
              '${ApiConstants.chartLyricsApi}/Lyric/$lyricId',
              options: Options(
                sendTimeout: ApiConstants.connectionTimeout,
                receiveTimeout: ApiConstants.receiveTimeout,
              ),
            );

            if (lyricResponse.statusCode == 200 && lyricResponse.data != null) {
              final lyricContent = lyricResponse.data as Map<String, dynamic>;
              final lyrics = lyricContent['Lyric'] as String? ?? '';

              if (lyrics.isNotEmpty) {
                return LyricsModel(
                  id: '${songId}_chartlyrics_$lyricId',
                  songId: songId,
                  plainLyrics: lyrics,
                  lrcLyrics: null,
                  isSynced: false,
                  source: 'ChartLyrics',
                  fetchedAt: DateTime.now(),
                  artistName: lyricData['Artist'] as String?,
                  trackName: lyricData['Song'] as String?,
                );
              }
            }
          }
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      // ChartLyrics may 404 often, silently continue
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch from NetEase Music - free API supporting Chinese and international songs
  /// Works well for Asian music (Chinese, Japanese, Korean, etc.)
  Future<LyricsModel?> _fetchFromNetEase(
    String artist,
    String title,
    String songId,
  ) async {
    try {
      // First search for the song
      final searchResponse = await _dio.get(
        'https://music.163.com/api/search/song',
        queryParameters: {'keywords': '$artist $title', 'limit': 1},
        options: Options(
          sendTimeout: ApiConstants.connectionTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
          contentType: 'application/x-www-form-urlencoded',
        ),
      );

      if (searchResponse.statusCode == 200 && searchResponse.data != null) {
        final data = searchResponse.data as Map<String, dynamic>;
        final result = data['result'] as Map<String, dynamic>?;
        final songs = result?['songs'] as List<dynamic>? ?? [];

        if (songs.isNotEmpty) {
          final song = songs[0] as Map<String, dynamic>;
          final songNetEaseId = song['id'] as int?;

          if (songNetEaseId != null && songNetEaseId > 0) {
            // Fetch lyrics using song ID
            try {
              final lyricsResponse = await _dio.get(
                'https://music.163.com/api/song/lyric',
                queryParameters: {'id': songNetEaseId, 'lv': -1},
                options: Options(
                  sendTimeout: ApiConstants.connectionTimeout,
                  receiveTimeout: ApiConstants.receiveTimeout,
                ),
              );

              if (lyricsResponse.statusCode == 200 &&
                  lyricsResponse.data != null) {
                final lyricsData = lyricsResponse.data as Map<String, dynamic>;
                final lrc = lyricsData['lrc'] as Map<String, dynamic>?;
                final lyrics = lrc?['lyric'] as String? ?? '';

                if (lyrics.isNotEmpty) {
                  final songName = song['name'] as String? ?? title;
                  final artistName =
                      ((song['artists'] as List<dynamic>?)?[0]
                              as Map<dynamic, dynamic>?)?['name']
                          as String? ??
                      artist;

                  return LyricsModel(
                    id: '${songId}_netease_$songNetEaseId',
                    songId: songId,
                    plainLyrics: lyrics,
                    lrcLyrics: null,
                    isSynced: false,
                    source: 'NetEase Music',
                    fetchedAt: DateTime.now(),
                    artistName: artistName,
                    trackName: songName,
                  );
                }
              }
            } catch (e) {
              // Lyrics fetch failed but search succeeded
              return null;
            }
          }
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      // NetEase may be slow or blocked, return null gracefully
      return null;
    } catch (e) {
      return null;
    }
  }
}
