import 'dart:async';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import '../../core/utils/song_key.dart';
import '../models/lyrics_model.dart';

class GeniusSong {
  const GeniusSong({
    required this.title,
    required this.artist,
    required this.url,
  });
  final String title;
  final String artist;
  final Uri url;
}

/// Best-effort access to Genius's public website, not its authenticated API.
/// Website markup/endpoints can change; failed access is never bypassed.
class GeniusLyricsDataSource {
  GeniusLyricsDataSource(this.dio);
  final Dio dio;

  static Uri validateSongUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'genius.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !RegExp(r'^/[^/]+-lyrics$', caseSensitive: false).hasMatch(uri.path)) {
      throw const FormatException('This is not a Genius song page.');
    }
    return Uri(scheme: 'https', host: 'genius.com', path: uri.path);
  }

  Options _options(ResponseType type) => Options(
    responseType: type,
    followRedirects: false,
    receiveTimeout: const Duration(seconds: 8),
    validateStatus: (_) => true,
    headers: {
      'User-Agent': 'FlashLyrics/1.4.2',
      'Accept': 'application/json, text/html',
    },
  );

  void _checkStatus(int? status) {
    if (status == 403 || status == 429) {
      throw const FormatException(
        'Genius is limiting access right now. Try again later or open Genius.',
      );
    }
    if (status != 200) {
      throw const FormatException(
        'Genius is unavailable right now. Try again later.',
      );
    }
  }

  Future<List<GeniusSong>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (query.trim().isEmpty) return [];
    final response = await dio.get<dynamic>(
      'https://genius.com/api/search/song',
      queryParameters: {'q': query.trim()},
      options: _options(ResponseType.json),
      cancelToken: cancelToken,
    );
    _checkStatus(response.statusCode);
    return parseSearch(response.data);
  }

  static List<GeniusSong> parseSearch(dynamic data) {
    final response = data is Map ? data['response'] : null;
    final sections = response is Map ? response['sections'] : null;
    if (sections is! List) {
      throw const FormatException(
        'Genius returned an unreadable search response.',
      );
    }
    final songs = <GeniusSong>[];
    final seen = <String>{};
    for (final section in sections) {
      final hits = section is Map ? section['hits'] : null;
      if (hits is! List) continue;
      for (final hit in hits) {
        if (hit is! Map || hit['type'] != 'song') continue;
        final result = hit['result'];
        if (result is! Map) continue;
        final title = result['title'];
        final artistData = result['primary_artist'];
        final artist = artistData is Map ? artistData['name'] : null;
        final url = result['url'];
        if (title is! String ||
            title.trim().isEmpty ||
            artist is! String ||
            artist.trim().isEmpty ||
            url is! String) {
          continue;
        }
        try {
          final uri = validateSongUrl(url);
          if (seen.add(uri.toString())) {
            songs.add(
              GeniusSong(title: title.trim(), artist: artist.trim(), url: uri),
            );
          }
        } on FormatException {
          continue;
        }
      }
    }
    return songs.take(10).toList();
  }

  Future<LyricsModel> fetch(GeniusSong song, {CancelToken? cancelToken}) async {
    final uri = validateSongUrl(song.url.toString());
    final response = await dio.get<String>(
      uri.toString(),
      options: _options(ResponseType.plain),
      cancelToken: cancelToken,
    );
    _checkStatus(response.statusCode);
    return parsePage(response.data ?? '', song);
  }

  static LyricsModel parsePage(String page, GeniusSong song) {
    final uri = validateSongUrl(song.url.toString());
    if (page.length > 3000000) {
      throw const FormatException('This page is too large to read.');
    }
    final document = html.parse(page);
    final canonical = document
        .querySelector('meta[property="og:url"]')
        ?.attributes['content'];
    if (canonical != null && validateSongUrl(canonical) != uri) {
      throw const FormatException('Genius returned a different song page.');
    }
    final containers = document.querySelectorAll(
      '[data-lyrics-container="true"]',
    );
    final blocks = <String>[];
    for (final container in containers) {
      // Preserve linked annotation words and line breaks; discard controls/ads.
      for (final unwanted in container.querySelectorAll(
        'script, style, button, [hidden], [aria-hidden="true"], [data-exclude-from-selection="true"]',
      )) {
        unwanted.remove();
      }
      final buffer = StringBuffer();
      void read(dom.Node node) {
        if (node is dom.Text) {
          buffer.write(node.data);
        } else if (node is dom.Element) {
          if (node.localName == 'br') {
            buffer.writeln();
          } else {
            for (final child in node.nodes) {
              read(child);
            }
            if (node.localName == 'p') buffer.writeln();
          }
        }
      }

      read(container);
      final text = buffer
          .toString()
          .replaceAll('\u00a0', ' ')
          .split('\n')
          .map((line) => line.trimRight())
          .join('\n')
          .trim();
      if (text.isNotEmpty) blocks.add(text);
    }
    final text = blocks.join('\n\n');
    if (text.isEmpty || text.length > 100000) {
      throw const FormatException(
        'No readable lyrics on this Genius page. Open Genius to check the song.',
      );
    }
    return LyricsModel(
      id: 'genius_${DateTime.now().microsecondsSinceEpoch}',
      songId: songKey(song.artist, song.title),
      plainLyrics: text,
      isSynced: false,
      source: 'Genius',
      sourceUrl: uri.toString(),
      fetchedAt: DateTime.now(),
      artistName: song.artist,
      trackName: song.title,
    );
  }

  static bool matches(GeniusSong song, String artist, String title) {
    String normalized(String value) => value.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true),
      '',
    );
    return normalized(artist).isNotEmpty &&
        normalized(title).isNotEmpty &&
        normalized(song.artist) == normalized(artist) &&
        normalized(song.title) == normalized(title);
  }

  /// Bound the entire fallback, including both search and page download.
  Future<LyricsModel?> findExact(
    String artist,
    String title, {
    Duration budget = const Duration(seconds: 4),
  }) async {
    if (artist.trim().isEmpty || title.trim().isEmpty) return null;
    final token = CancelToken();
    final deadline = Timer(
      budget,
      () => token.cancel('Genius fallback deadline'),
    );
    try {
      final hits = await search('$artist $title', cancelToken: token);
      for (final hit in hits) {
        if (!matches(hit, artist, title)) continue;
        final result = await fetch(hit, cancelToken: token);
        if (token.isCancelled) return null;
        return LyricsModel(
          id: result.id,
          songId: songKey(artist, title),
          plainLyrics: result.plainLyrics,
          isSynced: false,
          source: result.source,
          sourceUrl: result.sourceUrl,
          fetchedAt: result.fetchedAt,
          artistName: result.artistName,
          trackName: result.trackName,
          isMatchVerified: true,
        );
      }
    } catch (_) {
      // Normal providers and cached lyrics remain usable if Genius changes.
    } finally {
      deadline.cancel();
    }
    return null;
  }
}
