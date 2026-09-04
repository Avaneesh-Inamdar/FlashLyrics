import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import '../widgets/lyrics_display.dart';

/// Library screen with multi-select delete
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  void _toggleSelect(String songId) {
    setState(() {
      if (_selected.contains(songId)) {
        _selected.remove(songId);
      } else {
        _selected.add(songId);
      }
    });
  }

  void _enterSelection(String songId) {
    setState(() => _selected.add(songId));
  }

  void _clearSelection() => setState(() => _selected.clear());

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? 'song' : 'songs'}?'),
        content: Text('Remove $count cached ${count == 1 ? 'lyric' : 'lyrics'} from offline storage? You can fetch them again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(lyricsRepositoryProvider);
    for (final id in _selected.toList()) {
      try {
        await repo.deleteCachedLyrics(id);
      } catch (_) {}
    }
    _clearSelection();
    ref.invalidate(cachedLyricsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $count ${count == 1 ? 'song' : 'songs'}')));
    }
  }

  Future<void> _confirmDeleteSingle(dynamic lyrics) async {
    final songId = lyrics.songId as String?;
    if (songId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cached lyrics?'),
        content: const Text('Remove this song from offline storage?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(lyricsRepositoryProvider).deleteCachedLyrics(songId);
      ref.invalidate(cachedLyricsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted from cache')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all cached lyrics?'),
        content: const Text('This will delete all offline lyrics. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor), onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear All')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final local = ref.read(lyricsLocalDataSourceProvider);
      await local.clearAllCache();
      _clearSelection();
      ref.invalidate(cachedLyricsProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All cached lyrics cleared')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to clear: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedLyricsAsync = ref.watch(cachedLyricsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: _selectionMode
            ? Text('${_selected.length} selected', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppTheme.lightTextPrimary))
            : Text('Library', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppTheme.lightTextPrimary)),
        leading: _selectionMode
            ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clearSelection)
            : null,
        actions: _selectionMode
            ? [
                IconButton(icon: const Icon(Icons.select_all_rounded), tooltip: 'Select all', onPressed: () {
                  final list = cachedLyricsAsync.maybeWhen(data: (l) => l, orElse: () => <dynamic>[]);
                  setState(() {
                    if (_selected.length == list.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(list.map((e) => (e as dynamic).songId as String));
                    }
                  });
                }),
                IconButton(icon: const Icon(Icons.delete_rounded), color: AppTheme.errorColor, tooltip: 'Delete selected', onPressed: _deleteSelected),
              ]
            : [
                cachedLyricsAsync.maybeWhen(
                  data: (list) => list.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.delete_sweep_rounded), tooltip: 'Clear all cache', onPressed: _confirmClearAll)
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
      ),
      body: cachedLyricsAsync.when(
        data: (lyricsList) {
          if (lyricsList.isEmpty) return _buildEmptyState(context, isDark);
          return _buildLyricsList(context, lyricsList, isDark);
        },
        loading: () => _buildLoadingState(isDark),
        error: (e, _) => _buildErrorState(e.toString(), isDark),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 60,
          height: 60,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight)),
          child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor)),
        ),
        const SizedBox(height: 16),
        Text('Loading library...', style: TextStyle(fontSize: 14, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary)),
      ]),
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.errorColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.error_outline_rounded, size: 40, color: AppTheme.errorColor)),
          const SizedBox(height: 16),
          Text('Error loading library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary)),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary)),
        ]),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 96, height: 96, decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.12), shape: BoxShape.circle, border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2))), child: Icon(Icons.library_music_rounded, size: 48, color: AppTheme.primaryColor)),
          const SizedBox(height: 24),
          Text('Your library is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary)),
          const SizedBox(height: 8),
          Text('Lyrics you view will be saved here for offline access', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary)),
        ]),
      ),
    );
  }

  Widget _buildLyricsList(BuildContext context, List<dynamic> lyricsList, bool isDark) {
    final sortedList = List<dynamic>.from(lyricsList)..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: sortedList.length,
      itemBuilder: (context, index) {
        final lyrics = sortedList[index];
        final songId = lyrics.songId as String? ?? '';
        final isSelected = _selected.contains(songId);
        return _buildLyricsCard(context, lyrics, index, isDark, isSelected);
      },
    );
  }

  Widget _buildLyricsCard(BuildContext context, dynamic lyrics, int index, bool isDark, bool isSelected) {
    final rawTitle = lyrics.trackName as String?;
    final rawArtist = lyrics.artistName as String?;
    final fallbackTitle = _fallbackTitleFromSongId(lyrics.songId as String?);
    final fallbackArtist = _fallbackArtistFromSongId(lyrics.songId as String?);
    final title = _normalizeLabel(rawTitle, fallbackTitle);
    final artist = _normalizeLabel(rawArtist, fallbackArtist);
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withValues(alpha: isDark ? 0.15 : 0.10) : surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? AppTheme.primaryColor : surfaceLight, width: isSelected ? 1.5 : 1),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (_selectionMode) {
                  _toggleSelect(lyrics.songId as String);
                } else {
                  _showLyricsDetails(context, lyrics);
                }
              },
              onLongPress: () => _enterSelection(lyrics.songId as String),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Checkbox when in selection mode, else icon
                    _selectionMode
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isSelected ? AppTheme.primaryColor : textHint, width: 1.5),
                            ),
                            child: isSelected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.music_note_rounded, color: AppTheme.primaryColor, size: 22),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(artist, style: TextStyle(fontSize: 12, color: textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(children: [
                          if (lyrics.isSynced)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(color: AppTheme.successColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.sync_rounded, size: 10, color: AppTheme.successColor), const SizedBox(width: 3), Text('Synced', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.successColor))]),
                            ),
                          if (lyrics.isSynced) const SizedBox(width: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: surfaceLight.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)), child: Text(lyrics.source, style: TextStyle(fontSize: 10, color: textHint))),
                        ]),
                      ]),
                    ),
                    if (!_selectionMode)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: Icon(Icons.delete_outline_rounded, color: textHint, size: 18), tooltip: 'Delete', constraints: const BoxConstraints.tightFor(width: 32, height: 32), padding: EdgeInsets.zero, onPressed: () => _confirmDeleteSingle(lyrics)),
                        Icon(Icons.chevron_right_rounded, color: textHint, size: 18),
                      ])
                    else
                      Icon(Icons.drag_indicator_rounded, color: textHint, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeLabel(String? value, String fallback) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  String _fallbackTitleFromSongId(String? songId) {
    if (songId == null || songId.trim().isEmpty) return 'Unknown Song';
    final parts = songId.split('_').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length <= 1) return _prettifySongId(songId);
    return _prettifySongId(parts.sublist(1).join(' '));
  }

  String _fallbackArtistFromSongId(String? songId) {
    if (songId == null || songId.trim().isEmpty) return 'Unknown Artist';
    final parts = songId.split('_').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length <= 1) return 'Unknown Artist';
    return _prettifySongId(parts.first);
  }

  String _prettifySongId(String raw) {
    final normalized = raw.replaceAll(RegExp(r'_+'), ' ').trim();
    if (normalized.isEmpty) return raw;
    return normalized.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  void _showLyricsDetails(BuildContext context, dynamic lyrics) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: (isDark ? AppTheme.textHint : AppTheme.lightTextHint).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            LyricsDisplay(lyrics: lyrics),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete from cache'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor),
                onPressed: () async {
                  Navigator.pop(context);
                  _confirmDeleteSingle(lyrics);
                },
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
