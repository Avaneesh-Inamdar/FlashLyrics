import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Square cover art for saved songs.
///
/// Library entries can hold a web URL, a `file://` path to art the music
/// player shared as a bitmap (Spotify, YouTube Music and others), a
/// `content://` URI Flutter cannot open, or nothing at all. Web and file
/// artwork are shown directly; anything missing or unreadable falls back to
/// an iTunes artwork lookup, the same fallback the now-playing card uses.
class ArtworkThumb extends StatefulWidget {
  const ArtworkThumb({
    super.key,
    required this.artworkUrl,
    required this.title,
    required this.artist,
    required this.placeholder,
    this.radius = 10,
  });

  final String? artworkUrl;
  final String title;
  final String artist;
  final Widget placeholder;
  final double radius;

  /// Looks up artwork for a song. Replaceable in tests.
  static Future<String?> Function(String artist, String title) lookup =
      _itunesLookup;

  static final Map<String, Future<String?>> _lookups = {};

  /// Clears remembered lookups (tests only).
  static void resetCache() => _lookups.clear();

  static Future<String?> _lookupOnce(String artist, String title) {
    final key = '${artist.trim().toLowerCase()}|${title.trim().toLowerCase()}';
    return _lookups.putIfAbsent(key, () => lookup(artist, title));
  }

  static Future<String?> _itunesLookup(String artist, String title) async {
    if (title.trim().isEmpty) return null;
    try {
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ).get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': '$artist $title'.trim(),
          'entity': 'song',
          'limit': 1,
        },
      );
      return parseItunesArtwork(response.data);
    } catch (_) {
      return null;
    }
  }

  /// Picks the artwork URL from an iTunes search response. iTunes serves
  /// JSON as text/javascript, so the body usually arrives as a string.
  static String? parseItunesArtwork(Object? body) {
    try {
      final data = body is String ? jsonDecode(body) : body;
      if (data is! Map) return null;
      final results = data['results'];
      if (results is! List || results.isEmpty) return null;
      final url = (results.first as Map)['artworkUrl100'];
      if (url is! String || url.isEmpty) return null;
      return url.replaceAll('100x100', '300x300');
    } catch (_) {
      return null;
    }
  }

  /// Normalises a stored artwork value into something displayable, or null
  /// when only a lookup can help.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final url = raw.trim();
    if (url.isEmpty || url.startsWith('content://')) return null;
    if (url.startsWith('file:/')) {
      return 'file://${url.replaceFirst(RegExp(r'^file:/+'), '/')}';
    }
    var cleaned = url
        .replaceAll('{w}x{h}bb', '300x300bb')
        .replaceAll('{w}x{h}', '300x300');
    if (cleaned.startsWith('http://')) {
      cleaned = cleaned.replaceFirst('http://', 'https://');
    }
    return cleaned.startsWith('https://') ? cleaned : null;
  }

  @override
  State<ArtworkThumb> createState() => _ArtworkThumbState();
}

class _ArtworkThumbState extends State<ArtworkThumb> {
  String? _url;
  bool _lookedUp = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ArtworkThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUrl != widget.artworkUrl ||
        oldWidget.title != widget.title ||
        oldWidget.artist != widget.artist) {
      _lookedUp = false;
      _resolve();
    }
  }

  void _resolve() {
    final request = ++_request;
    final stored = ArtworkThumb.normalize(widget.artworkUrl);
    if (stored == null) {
      _url = null;
      _lookUp(request);
      return;
    }
    if (stored.startsWith('file://')) {
      _url = null;
      File(Uri.parse(stored).toFilePath()).exists().then((exists) {
        if (!mounted || request != _request) return;
        if (exists) {
          setState(() => _url = stored);
        } else {
          _lookUp(request);
        }
      });
      return;
    }
    _url = stored;
  }

  void _lookUp(int request) {
    if (_lookedUp) return;
    _lookedUp = true;
    ArtworkThumb._lookupOnce(widget.artist, widget.title).then((found) {
      if (!mounted || request != _request || found == null) return;
      setState(() => _url = found);
    });
  }

  /// Called when stored artwork fails to decode or download.
  Widget _failed() {
    if (!_lookedUp) {
      final request = _request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == _request) _lookUp(request);
      });
    }
    return widget.placeholder;
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    Widget child;
    if (url == null) {
      child = widget.placeholder;
    } else if (url.startsWith('file://')) {
      child = Image.file(
        File(Uri.parse(url).toFilePath()),
        key: ValueKey(url),
        fit: BoxFit.cover,
        cacheWidth: 144,
        errorBuilder: (_, _, _) => _failed(),
      );
    } else {
      child = Image.network(
        url,
        key: ValueKey(url),
        fit: BoxFit.cover,
        cacheWidth: 144,
        errorBuilder: (_, _, _) => _failed(),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: child,
    );
  }
}
