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
  String _normalizeText(String text) {
    // Remove common suffixes and extras from song titles
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

  /// Fetch lyrics with intelligent fallback chain
  /// Prioritizes APIs that provide synced (LRC) lyrics
  /// [providerPriority] - Optional custom priority order for providers
  Future<LyricsModel> fetchLyricsWithFallback(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    // Normalize inputs for better matching
    final cleanArtist = _normalizeText(artist);
    final cleanTitle = _normalizeText(title);
    final songId = _generateSongId(artist, title);
    final errors = <String>[];
    final priority = providerPriority ?? ApiConstants.apiPriority;

    // Try each API in priority order - first with original text
    for (final api in priority) {
      try {
        final result = await _fetchFromApi(api, artist, title, songId);
        if (result != null && result.plainLyrics.isNotEmpty) {
          return result;
        }
      } on DioException catch (e) {
        // Check for certificate errors
        if (e.type == DioExceptionType.badCertificate ||
            e.message?.contains('certificate') == true) {
          errors.add('$api: Certificate error - server SSL expired');
        } else if (e.type == DioExceptionType.connectionError) {
          errors.add('$api: Connection failed');
        } else {
          errors.add('$api: ${e.message ?? 'Unknown error'}');
        }
        continue;
      } catch (e) {
        errors.add('$api: ${e.toString()}');
        continue;
      }
    }

    // If no results, try with cleaned/normalized text (helps for Hindi/non-English)
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

    // All APIs failed - provide user-friendly error message
    final isNonLatin = RegExp(r'[^\x00-\x7F]').hasMatch('$artist$title');
    if (isNonLatin) {
      throw LyricsNotFoundException(
        message:
            'Lyrics not found for this song. Note: Hindi and other non-English lyrics may have limited availability. Try searching manually with romanized (English) spellings.',
      );
    }

    throw LyricsNotFoundException(
      message: 'Lyrics not found. Tried: ${errors.take(2).join(', ')}',
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
    String title,
  ) async {
    final songId = _generateSongId(artist, title);

    // Launch parallel requests to synced lyrics APIs
    final futures = <Future<LyricsModel?>>[];
    futures.add(_fetchFromLrclib(artist, title, songId));
    futures.add(_fetchFromTextyl(artist, title, songId));

    // Wait for all requests with a timeout
    final results = await Future.wait(
      futures.map(
        (f) => f.timeout(const Duration(seconds: 10), onTimeout: () => null),
      ),
    );

    // Return first result with synced lyrics
    for (final result in results) {
      if (result != null && result.isSynced && result.lrcLyrics != null) {
        return result;
      }
    }

    // Return first result with any lyrics
    for (final result in results) {
      if (result != null && result.plainLyrics.isNotEmpty) {
        return result;
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
}
