import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_profile.dart';
import '../widgets/update_available_dialog.dart';
import '../providers/providers.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

import '../widgets/ad_banner_widget.dart';
import '../widgets/notification_tip.dart';
import '../widgets/tv_pointer.dart';
import 'app_tour_screen.dart';
import '../widgets/review_prompt.dart';
import '../../services/review_service.dart';
import '../../services/support_prompt_service.dart';
import '../widgets/support_prompt.dart';

/// Main navigation screen with custom bottom navigation bar
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  Timer? _reviewTimer;
  Timer? _supportTimer;
  Timer? _updateTimer;
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(reviewServiceProvider).startSession());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      if (ref.read(appTourAutoShowProvider) && shouldShowAppTour(prefs)) {
        // The tour already explains the Float action, so skip the tip.
        prefs.setBool(notificationTipSeenKey, true);
        unawaited(showAppTour(context, prefs));
      } else {
        showNotificationTip(context, prefs);
      }
      // On a TV the remote starts on the navigation rail.
      if (ref.read(isTelevisionProvider)) {
        FocusScope.of(context).nextFocus();
      }
    });
    // The daily support reminder is about ads, which are not shown on TV.
    if (!ref.read(isTelevisionProvider)) {
      _supportTimer = Timer(const Duration(seconds: 3), _maybeShowSupportPrompt);
    }
    _updateTimer = Timer(const Duration(seconds: 5), _checkForUpdate);
  }

  /// Once per app start: if Google Play has a newer version, tell the user
  /// to download it from the Play Store (never while another dialog is up).
  Future<void> _checkForUpdate() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        (state != null && state != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    await maybeShowUpdateNotice(
      context,
      service: ref.read(updateCheckServiceProvider),
    );
  }

  /// Daily "FlashLyrics is free" reminder, only when nothing else is on screen.
  void _maybeShowSupportPrompt() {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (ref.read(supportPromptServiceProvider).shouldShowOnOpen()) {
      // One prompt per session: skip the rating prompt this time.
      ref.read(reviewServiceProvider).markShown();
      unawaited(showSupportPrompt(context, ref));
    }
  }

  @override
  void dispose() {
    _reviewTimer?.cancel();
    _supportTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  void _scheduleReview() {
    final service = ref.read(reviewServiceProvider);
    if (!service.shouldPrompt || _reviewTimer?.isActive == true) return;
    _reviewTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
          ModalRoute.of(context)?.isCurrent != true || ref.read(tabIndexProvider) != 0) return;
      unawaited(showReviewPrompt(context, service));
    });
  }
  final List<Widget> _screens = const [
    HomeScreen(),
    AdaptiveWidth(child: SearchScreen()),
    AdaptiveWidth(child: LibraryScreen()),
    AdaptiveWidth(child: SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen<LyricsState>(lyricsNotifierProvider, (_, next) {
      if (next.lyrics != null && !next.isLoading) {
        ref.read(reviewServiceProvider).recordLyrics(next.lyrics!.songId);
        _scheduleReview();
      }
    });
    ref.listen<int>(tabIndexProvider, (_, next) { if (next == 0) _scheduleReview(); });
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = ref.watch(tabIndexProvider);
    final wide = DeviceProfile.useRail(MediaQuery.sizeOf(context).width);

    final pages = IndexedStack(index: currentIndex, children: [
      for (var i = 0; i < _screens.length; i++)
        // Hidden tabs must not take part in D-pad focus traversal.
        ExcludeFocus(
          excluding: i != currentIndex,
          child: TickerMode(enabled: i == currentIndex, child: _screens[i]),
        ),
    ]);

    if (wide) {
      // Tablets and TVs: navigation rail on the side, ad banner (phones and
      // tablets only) under the content.
      return Scaffold(
        extendBody: false,
        body: Row(
          children: [
            _buildRail(isDark, currentIndex),
            VerticalDivider(
              width: 1,
              color: isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight,
            ),
            Expanded(
              // Keep content and the ad clear of the 3-button navigation bar.
              child: SafeArea(
                left: false,
                child: Column(
                  children: [
                    Expanded(child: pages),
                    const AdBannerWidget(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: false,
      body: pages,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerWidget(),
          _buildBottomNavigationBar(isDark, currentIndex),
        ],
      ),
    );
  }

  void _select(int index, int currentIndex) {
    if (index == 1 && currentIndex == 1) {
      ref.read(searchFocusTriggerProvider.notifier).state++;
    } else {
      ref.read(tabIndexProvider.notifier).setIndex(index);
    }
  }

  Widget _buildRail(bool isDark, int currentIndex) {
    final tv = ref.watch(isTelevisionProvider);
    // A plain traversal group (not a FocusScope): a FocusScope would trap the
    // D-pad on the rail so the remote could never reach the content.
    return FocusTraversalGroup(
      child: SafeArea(
      right: false,
      child: NavigationRail(
        trailing: tv
            ? const Padding(
                padding: EdgeInsets.only(top: 12),
                child: TvPointerButton(),
              )
            : null,
        selectedIndex: currentIndex,
        extended: tv,
        minExtendedWidth: 200,
        labelType: tv ? NavigationRailLabelType.none : NavigationRailLabelType.all,
        backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
        indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.16),
        onDestinationSelected: (index) => _select(index, currentIndex),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.graphic_eq),
            label: Text('Listening'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.search),
            label: Text('Search'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.library_music_outlined),
            label: Text('Library'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.tune),
            label: Text('Settings'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(bool isDark, int currentIndex) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        backgroundColor: isDark
            ? AppTheme.backgroundColor
            : AppTheme.lightBackground,
        indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.16),
        onDestinationSelected: (index) => _select(index, currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.graphic_eq),
            label: 'Listening',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            label: 'Library',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
