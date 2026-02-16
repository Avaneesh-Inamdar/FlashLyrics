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
  Future<LyricsModel> fetchLyricsWithFallback(
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

    // Strategy 1: Try with original text
    for (final api in priority) {
      try {
        final result = await _fetchFromApi(api, artist, title, songId);
        if (result != null && result.plainLyrics.isNotEmpty) {
          return result;
        }
        errors.add('$api: No lyrics found');
      } on DioException catch (e) {
        // Check for certificate errors
        if (e.type == DioExceptionType.badCertificate ||
            e.message?.contains('certificate') == true) {
          errors.add('$api: SSL certificate expired');
        } else if (e.type == DioExceptionType.connectionError) {
          errors.add('$api: Connection failed');
        } else if (e.response?.statusCode == 404) {
          errors.add('$api: Not found');
        } else {
          errors.add('$api: Network error');
        }
        continue;
      } catch (e) {
        errors.add('$api: Failed');
        continue;
      }
    }

    // Strategy 2: Try with cleaned/normalized text (helps for Hindi/non-English)
    if (cleanArtist != artist || cleanTitle != title) {
      for (final api in priority) {
        try {
          final result = await _fetchFromApi(
            api,
            cleanArtist,
            cleanTitle,
            songId,
          );
          if (result != null && result.plainLyrics.isNotEmpty) {
            return result;
          }
        } catch (e) {
          continue; // Silently continue, we already recorded errors above
        }
      }
    }

    // Strategy 3: For Hindi songs, try with just the title (artist info for Hindi songs is often incomplete)
    if (isNonLatin) {
      for (final api in priority) {
        try {
          final result = await _fetchFromApi(api, '', title, songId);
          if (result != null && result.plainLyrics.isNotEmpty) {
            return result;
          }
        } catch (e) {
          continue;
        }
      }

      // Try with cleaned title only
      if (cleanTitle != title) {
        for (final api in priority) {
          try {
            final result = await _fetchFromApi(api, '', cleanTitle, songId);
            if (result != null && result.plainLyrics.isNotEmpty) {
              return result;
            }
          } catch (e) {
            continue;
          }
        }
      }
    }

    // All APIs failed - provide user-friendly error message
    if (isNonLatin) {
      throw LyricsNotFoundException(
        message:
            'Lyrics not found. Hindi and non-English songs have limited availability. Try searching manually with English/romanized spellings.',
      );
    }

    // Show simplified error for English songs
    throw LyricsNotFoundException(
      message:
          'Lyrics not found for "$title" by "$artist". Try searching manually.',
    );
  }

  /// Search all APIs for lyrics - used for manual search
  /// Returns a map of provider name to results
  Future<Map<String, LyricsModel?>> searchAllProviders(
    String artist,
    String title,
  ) async {
    final songId = _generateSongId(artist, title);
    final results = <String, LyricsModel?>{};

    await Future.wait(
      ApiConstants.apiPriority.map((api) async {
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

    // Wait for all requests with a timeout
    final results = await Future.wait(
      futures.map(
        (f) => f.timeout(const Duration(seconds: 10), onTimeout: () => null),
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
  /// Combines LRCLIB search with direct fetches from other APIs
  Future<List<LyricsModel>> searchByQuery(String query) async {
    final results = <LyricsModel>[];
    final seenIds = <String>{};

    // 1. Search LRCLIB (proper search API)
    try {
      final lrclibResults = await searchLrclib(query);
      for (final result in lrclibResults) {
        if (!seenIds.contains(result.songId)) {
          seenIds.add(result.songId);
          results.add(result);
        }
      }
    } catch (_) {}

    // 2. Try to parse query as "artist - title" or "title by artist"
    String? guessedArtist;
    String? guessedTitle;

    // Try "artist - title" format
    if (query.contains(' - ')) {
      final parts = query.split(' - ');
      if (parts.length == 2) {
        guessedArtist = parts[0].trim();
        guessedTitle = parts[1].trim();
      }
    }
    // Try "title by artist" format
    else if (query.toLowerCase().contains(' by ')) {
      final byIndex = query.toLowerCase().lastIndexOf(' by ');
      guessedTitle = query.substring(0, byIndex).trim();
      guessedArtist = query.substring(byIndex + 4).trim();
    }

    // 3. If we have artist/title, try other providers
    if (guessedArtist != null && guessedTitle != null) {
      final songId = _generateSongId(guessedArtist, guessedTitle);

      // Try Textyl
      try {
        final textylResult = await _fetchFromTextyl(
          guessedArtist,
          guessedTitle,
          songId,
        );
        if (textylResult != null &&
            textylResult.plainLyrics.isNotEmpty &&
            !seenIds.contains(textylResult.songId)) {
          seenIds.add(textylResult.songId);
          results.add(
            LyricsModel(
              id: textylResult.id,
              songId: textylResult.songId,
              plainLyrics: textylResult.plainLyrics,
              lrcLyrics: textylResult.lrcLyrics,
              isSynced: textylResult.isSynced,
              source: 'Textyl',
              fetchedAt: textylResult.fetchedAt,
              artistName: guessedArtist,
              trackName: guessedTitle,
            ),
          );
        }
      } catch (_) {}

      // Try lyrics.ovh
      try {
        final ovhResult = await _fetchFromLyricsOvh(
          guessedArtist,
          guessedTitle,
          songId,
        );
        if (ovhResult != null &&
            ovhResult.plainLyrics.isNotEmpty &&
            !seenIds.contains(ovhResult.songId)) {
          seenIds.add(ovhResult.songId);
          results.add(
            LyricsModel(
              id: ovhResult.id,
              songId: ovhResult.songId,
              plainLyrics: ovhResult.plainLyrics,
              lrcLyrics: ovhResult.lrcLyrics,
              isSynced: false,
              source: 'lyrics.ovh',
              fetchedAt: ovhResult.fetchedAt,
              artistName: guessedArtist,
              trackName: guessedTitle,
            ),
          );
        }
      } catch (_) {}

      // Try Lyrist
      try {
        final lyristResult = await _fetchFromLyrist(
          guessedArtist,
          guessedTitle,
          songId,
        );
        if (lyristResult != null &&
            lyristResult.plainLyrics.isNotEmpty &&
            !seenIds.contains(lyristResult.songId)) {
          seenIds.add(lyristResult.songId);
          results.add(
            LyricsModel(
              id: lyristResult.id,
              songId: lyristResult.songId,
              plainLyrics: lyristResult.plainLyrics,
              lrcLyrics: lyristResult.lrcLyrics,
              isSynced: false,
              source: 'Lyrist',
              fetchedAt: lyristResult.fetchedAt,
              artistName: guessedArtist,
              trackName: guessedTitle,
            ),
          );
        }
      } catch (_) {}
    }

    // 4. Also try query as just a title (common search pattern)
    if (results.isEmpty) {
      final songId = _generateSongId('', query);

      // Try searching with query as title and various common artist patterns
      for (final provider in ['textyl', 'lyrics.ovh', 'lyrist']) {
        try {
          LyricsModel? result;
          if (provider == 'textyl') {
            // Textyl takes a combined query
            result = await _fetchFromTextyl('', query, songId);
          }
          if (result != null &&
              result.plainLyrics.isNotEmpty &&
              !seenIds.contains(result.songId)) {
            seenIds.add(result.songId);
            results.add(
              LyricsModel(
                id: result.id,
                songId: result.songId,
                plainLyrics: result.plainLyrics,
                lrcLyrics: result.lrcLyrics,
                isSynced: result.isSynced,
                source: 'Textyl',
                fetchedAt: result.fetchedAt,
                artistName: result.artistName,
                trackName: query,
              ),
            );
            break; // Found a result
          }
        } catch (_) {}
      }
    }

    return results;
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
