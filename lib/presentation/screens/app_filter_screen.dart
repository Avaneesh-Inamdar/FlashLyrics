import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../services/media_detection_service.dart';
import '../providers/media_provider.dart';
import '../providers/settings_provider.dart';

/// Screen for configuring per-app Blacklist or Whitelist for media detection.
class AppFilterScreen extends ConsumerStatefulWidget {
  const AppFilterScreen({super.key});

  @override
  ConsumerState<AppFilterScreen> createState() => _AppFilterScreenState();
}

class _AppFilterScreenState extends ConsumerState<AppFilterScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<InstalledAppInfo> _installedApps = const [];
  bool _loadingApps = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    final apps = await MediaDetectionService.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _installedApps = apps;
      _loadingApps = false;
    });
  }

  Future<void> _refreshDetection() async {
    try {
      await ref
          .read(mediaNotifierProvider.notifier)
          .refreshCurrentSong(refreshLyrics: false);
    } catch (_) {}
  }

  Future<void> _showAddPackageDialog(bool isBlacklist) async {
    final controller = TextEditingController();
    final pkg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBlacklist ? 'Blacklist Package' : 'Whitelist Package'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. org.leetzone.android.yatsewidgetfree',
            labelText: 'Android Package Name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pkg != null && pkg.isNotEmpty) {
      final settings = ref.read(settingsProvider);
      final list = isBlacklist ? settings.blacklistedApps : settings.whitelistedApps;
      if (!list.contains(pkg)) {
        await ref
            .read(settingsProvider.notifier)
            .toggleAppInFilter(pkg, isBlacklist: isBlacklist);
        await _refreshDetection();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = settings.appFilterMode;
    final isBlacklist = mode == AppFilterMode.blacklist;
    final selectedList =
        isBlacklist ? settings.blacklistedApps : settings.whitelistedApps;
    final selectedSet = selectedList.toSet();

    // Merge installed apps with any manually-added/uninstalled packages still in selectedSet
    final knownPackages = _installedApps.map((e) => e.packageName).toSet();
    final mergedApps = <InstalledAppInfo>[
      ..._installedApps,
      for (final pkg in selectedList)
        if (!knownPackages.contains(pkg))
          InstalledAppInfo(packageName: pkg, appName: pkg),
    ];

    final q = _query.trim().toLowerCase();
    final filteredApps = mergedApps.where((app) {
      if (q.isEmpty) return true;
      return app.appName.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final aSel = selectedSet.contains(a.packageName) ? 0 : 1;
        final bSel = selectedSet.contains(b.packageName) ? 0 : 1;
        if (aSel != bSel) return aSel.compareTo(bSel);
        if (a.isSeenMedia != b.isSeenMedia) {
          return a.isSeenMedia ? -1 : 1;
        }
        return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
      });

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'App Filter',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
        actions: [
          if (mode != AppFilterMode.off) ...[
            IconButton(
              tooltip: 'Add package manually',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _showAddPackageDialog(isBlacklist),
            ),
            if (selectedList.isNotEmpty)
              IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .clearAppFilterList(isBlacklist: isBlacklist);
                  await _refreshDetection();
                },
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _buildModeCard(context, settings, isDark),
          ),
          if (mode == AppFilterMode.off)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'All supported music & media apps are detected.\n\nSwitch to Blacklist to ignore specific apps (like video players or TV remotes), or Whitelist to only detect selected apps.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.lightTextSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search apps or package name...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (!isBlacklist && selectedList.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Whitelist is empty — no apps will be detected until you select at least one app below.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            Expanded(
              child: _loadingApps
                  ? const Center(child: CircularProgressIndicator())
                  : filteredApps.isEmpty
                      ? Center(
                          child: Text(
                            'No matching apps found',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadApps,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: filteredApps.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final app = filteredApps[index];
                              final isSelected =
                                  selectedSet.contains(app.packageName);
                              return Material(
                                color: isDark
                                    ? Colors.white.withValues(
                                        alpha: isSelected ? 0.10 : 0.04)
                                    : Colors.black.withValues(
                                        alpha: isSelected ? 0.08 : 0.03),
                                borderRadius: BorderRadius.circular(14),
                                child: CheckboxListTile(
                                  value: isSelected,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          app.appName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (app.isSeenMedia)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.18),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            'Detected',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    app.packageName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppTheme.textHint
                                          : AppTheme.lightTextHint,
                                    ),
                                  ),
                                  onChanged: (_) async {
                                    await ref
                                        .read(settingsProvider.notifier)
                                        .toggleAppInFilter(
                                          app.packageName,
                                          isBlacklist: isBlacklist,
                                        );
                                    await _refreshDetection();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    AppSettings settings,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter Mode',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppFilterMode>(
              segments: const [
                ButtonSegment(
                  value: AppFilterMode.off,
                  label: Text('All'),
                  icon: Icon(Icons.all_inclusive_rounded, size: 18),
                ),
                ButtonSegment(
                  value: AppFilterMode.blacklist,
                  label: Text('Blacklist'),
                  icon: Icon(Icons.block_rounded, size: 18),
                ),
                ButtonSegment(
                  value: AppFilterMode.whitelist,
                  label: Text('Whitelist'),
                  icon: Icon(Icons.check_circle_outline_rounded, size: 18),
                ),
              ],
              selected: {settings.appFilterMode},
              onSelectionChanged: (selection) async {
                final next = selection.first;
                await ref.read(settingsProvider.notifier).setAppFilterMode(next);
                await _refreshDetection();
              },
            ),
          ),
        ],
      ),
    );
  }
}
