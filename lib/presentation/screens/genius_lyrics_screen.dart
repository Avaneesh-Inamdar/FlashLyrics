import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/datasources/genius_lyrics_datasource.dart';
import '../../data/models/lyrics_model.dart';
import '../providers/providers.dart';

class GeniusLyricsScreen extends ConsumerStatefulWidget {
  const GeniusLyricsScreen({super.key, this.query = ''});
  final String query;
  @override
  ConsumerState<GeniusLyricsScreen> createState() => _GeniusLyricsScreenState();
}

class _GeniusLyricsScreenState extends ConsumerState<GeniusLyricsScreen> {
  late final TextEditingController _query;
  CancelToken? _request;
  List<GeniusSong> _results = [];
  LyricsModel? _preview;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.query);
  }

  @override
  void dispose() {
    _request?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _error = 'Enter a song title and artist.');
      return;
    }
    await _load(
      (token) => ref
          .read(geniusLyricsDataSourceProvider)
          .search(query, cancelToken: token),
      clearResults: true,
    );
  }

  Future<void> _select(GeniusSong song) => _load(
    (token) => ref
        .read(geniusLyricsDataSourceProvider)
        .fetch(song, cancelToken: token),
  );

  Future<void> _load(
    Future<Object> Function(CancelToken) operation, {
    bool clearResults = false,
  }) async {
    _request?.cancel();
    final request = CancelToken();
    _request = request;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      if (clearResults) _results = [];
    });
    try {
      final result = await operation(request);
      if (!mounted || !identical(_request, request) || request.isCancelled) {
        return;
      }
      setState(() {
        if (result is List<GeniusSong>) {
          _results = result;
          _searched = true;
        }
        if (result is LyricsModel) _preview = result;
      });
    } on FormatException catch (e) {
      if (mounted && identical(_request, request)) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && identical(_request, request) && !request.isCancelled) {
        setState(
          () => _error =
              'Could not reach Genius. Check your connection or open Genius below.',
        );
      }
    } finally {
      if (mounted && identical(_request, request)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openGenius() async {
    final uri = _preview?.sourceUrl == null
        ? Uri.https('genius.com', '/search', {'q': _query.text.trim()})
        : Uri.parse(_preview!.sourceUrl!);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) setState(() => _error = 'Could not open Genius.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open Genius.');
    }
  }

  Future<void> _save() async {
    final model = _preview;
    if (model == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(lyricsRepositoryProvider).cacheLyrics(model);
      if (!mounted) return;
      ref.invalidate(cachedLyricsProvider);
      ref.read(lyricsNotifierProvider.notifier).setLyricsFromModel(model);
      ref.read(tabIndexProvider.notifier).goToHome();
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save lyrics. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Search Genius')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text('A deeper catalogue.', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 12),
            const Text(
              'Look up the song on Genius, choose the right artist, and read the lyrics here.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _query,
              enabled: !_saving,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) {
                _request?.cancel();
                _request = null;
                setState(() {
                  _results = [];
                  _preview = null;
                  _error = null;
                  _loading = false;
                  _searched = false;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Song and artist',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading || _saving ? null : _search,
              icon: const Icon(Icons.search),
              label: Text(_loading ? 'Loading Genius…' : 'Search Genius'),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_searched && _results.isEmpty && !_loading && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No songs found. Try another spelling or add the artist name.',
                ),
              ),
            if (preview == null && !_loading) ...[
              const SizedBox(height: 16),
              for (final song in _results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(song.title),
                  subtitle: Text(song.artist),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : () => _select(song),
                ),
            ],
            if (preview != null && !_loading) ...[
              const SizedBox(height: 24),
              Text(preview.trackName!, style: theme.textTheme.headlineSmall),
              Text(
                '${preview.artistName} · Genius · Plain lyrics',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              SelectableText(
                preview.plainLyrics,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_saving ? 'Saving…' : 'Save offline & read'),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _preview = null),
                child: const Text('Back to results'),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openGenius,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open on Genius'),
            ),
            const SizedBox(height: 12),
            Text(
              'Lyrics from Genius are not time-synced. Some pages may be unavailable or limit access.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
