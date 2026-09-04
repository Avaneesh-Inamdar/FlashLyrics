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
  List<String> _history = [];
  static const _historyKey = 'search_history_v2';
  static const _maxHistory = 10;
  // Provider filter for manual search: null = all (use settings priority), else selected subset
  Set<String>? _selectedProviders; // null means all

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final list = prefs.getStringList(_historyKey) ?? [];
      if (mounted) setState(() => _history = list);
    } catch (_) {}
  }

  Future<void> _saveToHistory(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) return;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      var list = prefs.getStringList(_historyKey) ?? [];
      list.remove(trimmed);
      list.insert(0, trimmed);
      if (list.length > _maxHistory) list = list.sublist(0, _maxHistory);
      await prefs.setStringList(_historyKey, list);
      if (mounted) setState(() => _history = List.from(list));
    } catch (_) {}
  }

  Future<void> _clearHistory() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove(_historyKey);
      if (mounted) setState(() => _history = []);
    } catch (_) {}
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
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(
              isDark,
              surfaceLight,
              textPrimary,
              textHint,
              surfaceColor,
            ),
            _buildProviderFilter(isDark, surfaceLight, textPrimary, textHint),
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
    );
  }

  Widget _buildSearchHeader(
    bool isDark,
    Color surfaceLight,
    Color textPrimary,
    Color textHint,
    Color surfaceColor,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          if (ModalRoute.of(context)?.isFirst != true)
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
              onPressed: () {
                if (mounted && Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
          if (ModalRoute.of(context)?.isFirst != true) const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: surfaceLight, width: 1),
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
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) {}, // Handled by listener
                onSubmitted: (_) => _performSearch(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSearching ? null : _performSearch,
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(child: _buildSearchActionIcon()),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: -0.04, end: 0);
  }

  Widget _buildSearchActionIcon() {
    if (_isSearching) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return const Icon(Icons.search_rounded, color: Colors.white, size: 23);
  }

  Widget _buildProviderFilter(
    bool isDark,
    Color surfaceLight,
    Color textPrimary,
    Color textHint,
  ) {
    final settings = ref.watch(settingsProvider);
    final priority = settings.providerPriority;
    final providerNames = AppSettings.providerNames;
    final isAll = _selectedProviders == null;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    return SizedBox(
      height: 42,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        children: [
          _providerChip(
            label: 'All',
            selected: isAll,
            surfaceColor: surfaceColor,
            surfaceLight: surfaceLight,
            textPrimary: textPrimary,
            onSelected: (_) {
              setState(() => _selectedProviders = null);
              if (_searchController.text.trim().length >= 2) _performSearch();
            },
          ),
          ...priority.map((id) {
            final selected = _selectedProviders?.contains(id) ?? false;
            return _providerChip(
              label: providerNames[id]?.split(' ').first ?? id,
              selected: !isAll && selected,
              surfaceColor: surfaceColor,
              surfaceLight: surfaceLight,
              textPrimary: textPrimary,
              onSelected: (value) {
                setState(() {
                  if (_selectedProviders == null) {
                    _selectedProviders = {id};
                  } else {
                    final set = Set<String>.from(_selectedProviders!);
                    if (value) {
                      set.add(id);
                    } else {
                      set.remove(id);
                    }
                    _selectedProviders =
                        (set.isEmpty || set.length == priority.length)
                        ? null
                        : set;
                  }
                });
                if (_searchController.text.trim().length >= 2) _performSearch();
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _providerChip({
    required String label,
    required bool selected,
    required Color surfaceColor,
    required Color surfaceLight,
    required Color textPrimary,
    required ValueChanged<bool> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: onSelected,
        backgroundColor: surfaceColor,
        selectedColor: AppTheme.primaryColor.withValues(alpha: 0.12),
        side: BorderSide(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.35)
              : surfaceLight,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? AppTheme.primaryColor : textPrimary,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
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
      textHint,
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
    final hasHistory = _history.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 64,
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
          const SizedBox(height: 6),
          Text(
            'Enter a song name or "Artist - Title"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: textHint),
          ),
          if (hasHistory) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Recent searches',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _history
                  .map(
                    (h) => ActionChip(
                      label: Text(h, style: const TextStyle(fontSize: 12)),
                      avatar: Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: textHint,
                      ),
                      onPressed: () {
                        _searchController.text = h;
                        _searchController.selection =
                            TextSelection.fromPosition(
                              TextPosition(offset: h.length),
                            );
                        _performSearch();
                      },
                    ),
                  )
                  .toList(),
            ),
          ] else ...[
            const SizedBox(height: 24),
            // Quick examples
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Arijit Singh'),
                  onPressed: () {
                    _searchController.text = 'Arijit Singh';
                    _performSearch();
                  },
                ),
                ActionChip(
                  label: const Text('Believer'),
                  onPressed: () {
                    _searchController.text = 'Believer';
                    _performSearch();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
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
    Color textHint,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
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
          textHint,
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
    Color textHint,
  ) {
    return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: surfaceLight, width: 1),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectResult(result),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Album placeholder - solid, not gradient
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: AppTheme.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            result.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  result.source.replaceAll(' • Cached', ''),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                              if (result.source.contains('Cached')) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Cached',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                              if (result.isSynced) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successColor.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
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
                      color: textHint,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .animate(delay: Duration(milliseconds: index * 30))
        .fadeIn(duration: 250.ms)
        .slideX(begin: 0.05, end: 0);
  }

  Future<void> _performSearch() async {
    _debounceTimer?.cancel();
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

    // 1) Instant cache lookup - show immediately without waiting for network
    List<LyricsModel> cachedModels = [];
    try {
      final local = ref.read(lyricsLocalDataSourceProvider);
      final cachedAll = local.getAllCachedLyrics();
      final lowerQ = query.toLowerCase();
      cachedModels = cachedAll.where((m) {
        final tn = (m.trackName ?? '').toLowerCase();
        final an = (m.artistName ?? '').toLowerCase();
        final sid = m.songId.toLowerCase();
        return tn.contains(lowerQ) ||
            an.contains(lowerQ) ||
            sid.contains(lowerQ);
      }).toList();
      if (cachedModels.isNotEmpty && mounted && thisSearchId == _searchId) {
        final cachedResults = cachedModels
            .take(5)
            .map(
              (m) => SearchResult(
                title: (m.trackName?.trim().isNotEmpty == true)
                    ? m.trackName!.trim()
                    : _prettyFromSongId(m.songId, isTitle: true),
                artist: (m.artistName?.trim().isNotEmpty == true)
                    ? m.artistName!.trim()
                    : _prettyFromSongId(m.songId, isTitle: false),
                album: m.albumName,
                source: '${m.source} • Cached',
                isSynced: m.isSynced,
                lyrics: m,
              ),
            )
            .toList();
        setState(() {
          _results = cachedResults;
          _isSearching = false;
        });
        _saveToHistory(query);
      }
    } catch (_) {}

    try {
      final datasource = ref.read(lyricsRemoteDataSourceProvider);
      final settings = ref.read(settingsProvider);
      List<LyricsModel> rawResults = [];
      // Determine effective priority: selected subset or all (respect settings order)
      List<String> effectivePriority;
      if (_selectedProviders == null) {
        effectivePriority = settings.providerPriority;
      } else {
        effectivePriority = settings.providerPriority
            .where((p) => _selectedProviders!.contains(p))
            .toList();
        for (final p in _selectedProviders!) {
          if (!effectivePriority.contains(p)) effectivePriority.add(p);
        }
        if (effectivePriority.isEmpty)
          effectivePriority = settings.providerPriority;
      }
      try {
        rawResults = await datasource
            .searchByQuery(query, providerPriority: effectivePriority)
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () => <LyricsModel>[],
            );
        // Retry once with single provider fallback if empty and not due to cache
        if (rawResults.isEmpty && cachedModels.isEmpty) {
          // Quick retry with most reliable (lrclib) only
          try {
            final retry = await datasource
                .searchByQuery(query, providerPriority: ['lrclib'])
                .timeout(
                  const Duration(seconds: 8),
                  onTimeout: () => <LyricsModel>[],
                );
            if (retry.isNotEmpty) rawResults = retry;
          } catch (_) {}
        }
      } catch (e) {
        if (kDebugMode) debugPrint('searchByQuery outer error: $e');
        rawResults = [];
      }

      // Merge cached + network, then dedupe by source+songId
      final combined = <LyricsModel>[...cachedModels, ...rawResults];
      final seen = <String>{};
      final filtered = <LyricsModel>[];
      for (final m in combined) {
        if (m.plainLyrics.trim().isEmpty) continue;
        final key = '${m.source.toLowerCase()}|${m.songId}';
        if (seen.add(key)) filtered.add(m);
      }
      _saveToHistory(query);

      // Sort by synced + effective priority (respects user filter)
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

        final prio = effectivePriority;
        final ia = prio.indexOf(idFor(a));
        final ib = prio.indexOf(idFor(b));
        final pa = ia == -1 ? 999 : ia;
        final pb = ib == -1 ? 999 : ib;
        if (pa != pb) return pa.compareTo(pb);
        return 0;
      });

      final results = filtered
          .map(
            (m) => SearchResult(
              title: (m.trackName?.trim().isNotEmpty == true)
                  ? m.trackName!.trim()
                  : _prettyFromSongId(m.songId, isTitle: true),
              artist: (m.artistName?.trim().isNotEmpty == true)
                  ? m.artistName!.trim()
                  : _prettyFromSongId(m.songId, isTitle: false),
              album: m.albumName,
              source: m.source,
              isSynced: m.isSynced,
              lyrics: m,
            ),
          )
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
      final isNetwork =
          msg.contains('SocketException') ||
          msg.contains('Timeout') ||
          msg.contains('Failed host lookup');
      setState(() {
        _isSearching = false;
        _error = isNetwork
            ? 'Network issue — check connection and try again.'
            : 'Search failed. Please try again.';
      });
      if (kDebugMode) debugPrint('Search failed: $e');
    }
  }

  String _prettyFromSongId(String songId, {required bool isTitle}) {
    if (songId.isEmpty) return isTitle ? 'Unknown Song' : 'Unknown Artist';
    final parts = songId.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1)
      return isTitle ? _prettify(songId) : 'Unknown Artist';
    final raw = isTitle ? parts.sublist(1).join(' ') : parts.first;
    return _prettify(raw);
  }

  String _prettify(String raw) {
    final normalized = raw.replaceAll(RegExp(r'_+'), ' ').trim();
    if (normalized.isEmpty) return raw;
    return normalized
        .split(' ')
        .map(
          (w) =>
              w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
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
