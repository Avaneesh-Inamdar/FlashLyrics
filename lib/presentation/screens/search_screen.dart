import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/lyrics_model.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';

/// Search screen with simplified song name input and visual results
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSearching = false;
  List<SearchResult> _results = [];
  String? _error;
  String _lastQuery = '';
  int _searchId = 0; // Track search requests to cancel stale ones
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    setState(() {}); // Update UI for clear button

    if (query.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _results = [];
        _error = null;
        _lastQuery = '';
      });
      return;
    }

    if (query.length < 2) {
      // Too short, don't search yet
      _debounceTimer?.cancel();
      return;
    }

    // Debounce: cancel previous timer and wait 450ms before searching
    _lastQuery = query;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _searchController.text.trim() == query) {
        _performSearch();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(searchFocusTriggerProvider, (previous, next) {
      if (previous != next && mounted) {
        _focusNode.requestFocus();
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? AppTheme.backgroundColor
        : AppTheme.lightBackground;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.backgroundGradient
              : AppTheme.lightBackgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildSearchHeader(isDark, surfaceLight, textPrimary, textHint),
              Expanded(
                child: _buildContent(
                  isDark,
                  surfaceColor,
                  surfaceLight,
                  textPrimary,
                  textSecondary,
                  textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHeader(
    bool isDark,
    Color surfaceLight,
    Color textPrimary,
    Color textHint,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // Show back button only when used as a route (not a tab)
          if (ModalRoute.of(context)?.isFirst != true)
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () {
                if (mounted && Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceLight.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: surfaceLight, width: 1.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    style: TextStyle(color: textPrimary, fontSize: 16),
                    // Fix backspace selecting whole word issue
                    enableInteractiveSelection: true,
                    mouseCursor: SystemMouseCursors.text,
                    decoration: InputDecoration(
                      hintText: 'Search for a song...',
                      hintStyle: TextStyle(color: textHint),
                      prefixIcon: Icon(Icons.search_rounded, color: textHint),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, color: textHint),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _results = [];
                                  _error = null;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {}, // Handled by listener
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSearching ? null : _performSearch,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _isSearching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildContent(
    bool isDark,
    Color surfaceColor,
    Color surfaceLight,
    Color textPrimary,
    Color textSecondary,
    Color textHint,
  ) {
    if (_isSearching) {
      return _buildLoadingState(textSecondary);
    }

    if (_error != null) {
      return _buildErrorState(textPrimary, textSecondary, surfaceLight);
    }

    if (_results.isEmpty && _searchController.text.isEmpty) {
      return _buildEmptyState(textSecondary, textHint);
    }

    if (_results.isEmpty && _searchController.text.isNotEmpty) {
      return _buildNoResultsState(textPrimary, textSecondary, surfaceLight);
    }

    return _buildResultsList(
      isDark,
      surfaceColor,
      surfaceLight,
      textPrimary,
      textSecondary,
    );
  }

  Widget _buildLoadingState(Color textSecondary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          Text(
            'Searching across all providers...',
            style: TextStyle(color: textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textSecondary, Color textHint) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 80,
            color: textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Search for lyrics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a song name to find lyrics',
            style: TextStyle(fontSize: 14, color: textHint),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildErrorState(
    Color textPrimary,
    Color textSecondary,
    Color surfaceLight,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Search failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _performSearch,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(
    Color textPrimary,
    Color textSecondary,
    Color surfaceLight,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.music_off_rounded,
                size: 48,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildResultsList(
    bool isDark,
    Color surfaceColor,
    Color surfaceLight,
    Color textPrimary,
    Color textSecondary,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultCard(
          result,
          index,
          isDark,
          surfaceColor,
          surfaceLight,
          textPrimary,
          textSecondary,
        );
      },
    );
  }

  Widget _buildResultCard(
    SearchResult result,
    int index,
    bool isDark,
    Color surfaceColor,
    Color surfaceLight,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      surfaceColor.withValues(alpha: 0.8),
                      surfaceLight.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: surfaceLight.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectResult(result),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Album art placeholder or actual image
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryColor.withValues(alpha: 0.3),
                                  AppTheme.primaryDark.withValues(alpha: 0.5),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  result.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        result.source,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryLight,
                                        ),
                                      ),
                                    ),
                                    if (result.isSynced) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.successColor
                                              .withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.sync_rounded,
                                              size: 10,
                                              color: AppTheme.successColor,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'Synced',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.successColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: textSecondary,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
        .animate(delay: Duration(milliseconds: index * 50))
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.1, end: 0);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    if (query.length < 2) {
      setState(() => _error = 'Type at least 2 characters');
      return;
    }

    final thisSearchId = ++_searchId;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final datasource = ref.read(lyricsRemoteDataSourceProvider);
      final settings = ref.read(settingsProvider);
      // Use the unified, priority-aware search that handles both parsed and free-form queries
      // Timeout after 14s to avoid hanging indefinitely on slow networks
      List<LyricsModel> rawResults = [];
      try {
        rawResults = await datasource
            .searchByQuery(query, providerPriority: settings.providerPriority)
            .timeout(const Duration(seconds: 14), onTimeout: () => <LyricsModel>[]);
      } catch (e) {
        if (kDebugMode) debugPrint('searchByQuery outer error: $e');
        rawResults = [];
      }

      // Filter empties and dedupe by source+songId (keep different provider variants)
      final seen = <String>{};
      final filtered = <LyricsModel>[];
      for (final m in rawResults) {
        if (m.plainLyrics.isEmpty) continue;
        final key = '${m.source.toLowerCase()}|${m.songId}';
        if (seen.add(key)) filtered.add(m);
      }

      // Results already sorted by datasource (synced + priority), but ensure local priority order
      filtered.sort((a, b) {
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
        final prio = settings.providerPriority;
        final ia = prio.indexOf(idFor(a));
        final ib = prio.indexOf(idFor(b));
        final pa = ia == -1 ? 999 : ia;
        final pb = ib == -1 ? 999 : ib;
        if (pa != pb) return pa.compareTo(pb);
        return 0;
      });

      final results = filtered
          .map((m) => SearchResult(
                title: (m.trackName?.trim().isNotEmpty == true) ? m.trackName!.trim() : _prettyFromSongId(m.songId, isTitle: true),
                artist: (m.artistName?.trim().isNotEmpty == true) ? m.artistName!.trim() : _prettyFromSongId(m.songId, isTitle: false),
                album: m.albumName,
                source: m.source,
                isSynced: m.isSynced,
                lyrics: m,
              ))
          .toList();

      if (!mounted || thisSearchId != _searchId) return;
      setState(() {
        _results = results;
        _isSearching = false;
        if (_results.isEmpty) {
          _error = null; // Show no-results state instead of error banner
        }
      });
    } catch (e) {
      if (!mounted || thisSearchId != _searchId) return;
      // Network errors are shown as no-results with retry, not scary stacktrace
      final msg = e.toString();
      final isNetwork = msg.contains('SocketException') || msg.contains('Timeout') || msg.contains('Failed host lookup');
      setState(() {
        _isSearching = false;
        _error = isNetwork ? 'Network issue — check connection and try again.' : 'Search failed. Please try again.';
      });
      if (kDebugMode) debugPrint('Search failed: $e');
    }
  }

  String _prettyFromSongId(String songId, {required bool isTitle}) {
    if (songId.isEmpty) return isTitle ? 'Unknown Song' : 'Unknown Artist';
    final parts = songId.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return isTitle ? _prettify(songId) : 'Unknown Artist';
    final raw = isTitle ? parts.sublist(1).join(' ') : parts.first;
    return _prettify(raw);
  }

  String _prettify(String raw) {
    final normalized = raw.replaceAll(RegExp(r'_+'), ' ').trim();
    if (normalized.isEmpty) return raw;
    return normalized.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  void _selectResult(SearchResult result) {
    // Use the lyrics
    ref.read(lyricsNotifierProvider.notifier).setLyricsFromModel(result.lyrics);

    // Navigate to home: either pop if this is a pushed route, or switch tab
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      // We're on the search tab in bottom nav, switch to home tab
      ref.read(tabIndexProvider.notifier).goToHome();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.successColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Loaded: ${result.title}')),
          ],
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.surfaceLight
            : AppTheme.lightSurfaceLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class SearchResult {
  final String title;
  final String artist;
  final String? album;
  final String source;
  final bool isSynced;
  final LyricsModel lyrics;

  SearchResult({
    required this.title,
    required this.artist,
    this.album,
    required this.source,
    required this.isSynced,
    required this.lyrics,
  });
}
