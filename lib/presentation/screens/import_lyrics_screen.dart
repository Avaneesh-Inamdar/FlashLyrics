import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/lyrics_import.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/song_key.dart';
import '../../data/models/lyrics_model.dart';
import '../../domain/entities/song.dart';
import '../../services/lyrics_file_service.dart';
import '../providers/providers.dart';

class ImportLyricsScreen extends ConsumerStatefulWidget {
  const ImportLyricsScreen({super.key, this.song});
  final Song? song;
  @override
  ConsumerState<ImportLyricsScreen> createState() => _ImportLyricsScreenState();
}

class _ImportLyricsScreenState extends ConsumerState<ImportLyricsScreen> {
  late final _title = TextEditingController(text: widget.song?.title);
  late final _artist = TextEditingController(text: widget.song?.artist);
  final _text = TextEditingController();
  LyricsModel? _preview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _text.dispose();
    super.dispose();
  }

  void _invalidate(String _) => setState(() {
    _preview = null;
    _error = null;
  });

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await ref.read(lyricsFileServiceProvider).pickText();
      if (!mounted || text == null) return;
      final meta = LyricsImport.metadata(text);
      setState(() {
        _text.text = text;
        if (_title.text.trim().isEmpty) _title.text = meta['ti'] ?? '';
        if (_artist.text.trim().isEmpty) _artist.text = meta['ar'] ?? '';
        _preview = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the file. Try another file or paste the lyrics.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare({bool save = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final original = widget.song;
      final same =
          original != null &&
          songKey(original.artist, original.title) ==
              songKey(_artist.text, _title.text);
      final song = Song(
        id: songKey(_artist.text, _title.text),
        title: _title.text,
        artist: _artist.text,
        album: same ? original.album : null,
        artworkUrl: same ? original.artworkUrl : null,
      );
      var model = await LyricsImport.parse(_text.text, song);
      if (!mounted) return;
      setState(() => _preview = model);
      if (!save) return;
      final repository = ref.read(lyricsRepositoryProvider);
      final existing = await repository.getCachedLyrics(model.songId);
      if (!mounted) return;
      if (existing != null) {
        if (existing is LyricsModel && (model.artworkUrl?.isEmpty ?? true)) {
          model = model.copyWith(artworkUrl: existing.artworkUrl);
        }
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace saved lyrics?'),
            content: Text(
              'Use these lyrics for “${model.trackName}” by ${model.artistName}? This replaces the lyrics saved for this song.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      await repository.cacheLyrics(model);
      if (!mounted) return;
      ref
          .read(lyricsNotifierProvider.notifier)
          .setLyricsFromModel(model, cache: false);
      ref.read(tabIndexProvider.notifier).goToHome();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your lyrics are saved on this device.')),
      );
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save lyrics. Your existing lyrics have been kept. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Import lyrics')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Bring your own lyrics',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose a .lrc or .txt file, or paste below. Saved only on this device for the song you choose.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('import-title'),
            controller: _title,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Song title'),
            onChanged: _invalidate,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('import-artist'),
            controller: _artist,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Artist'),
            onChanged: _invalidate,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose lyrics file'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('import-text'),
            controller: _text,
            enabled: !_busy,
            minLines: 7,
            maxLines: 14,
            maxLength: LyricsImport.maxBytes,
            decoration: const InputDecoration(
              labelText: 'Lyrics',
              alignLabelWithHint: true,
              hintText: '[00:12.50]First line\n[00:16.00]Next line',
            ),
            onChanged: _invalidate,
          ),
          const Text(
            'Line timing: [00:12.50]Lyrics\nWord timing: [00:12.50]<00:12.50>First <00:13.00>word\nWithout timestamps, lyrics are saved as plain text.',
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                key: const Key('import-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_preview != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _preview!.isSynced
                          ? 'Timed lyrics · ${_preview!.lines.length} lines'
                          : 'Plain lyrics · ${_preview!.lines.length} lines',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LrcParser.toCleanPlainText(
                        _preview!.plainLyrics,
                      ).split('\n').take(6).join('\n'),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _prepare(),
                child: const Text('Preview'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _prepare(save: true),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save for this song'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Your import is kept during automatic lookups. To use online lyrics again, delete this song from Library.',
          ),
        ],
      ),
    ),
  );
}
