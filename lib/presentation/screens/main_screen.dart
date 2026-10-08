import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

import '../widgets/ad_banner_widget.dart';
import '../widgets/notification_tip.dart';

/// Main navigation screen with custom bottom navigation bar
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showNotificationTip(context, ref.read(sharedPreferencesProvider));
    });
  }
  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = ref.watch(tabIndexProvider);

    return Scaffold(
      extendBody: false,
      body: IndexedStack(index: currentIndex, children: [
        for (var i = 0; i < _screens.length; i++)
          TickerMode(enabled: i == currentIndex, child: _screens[i]),
      ]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBannerWidget(),
          _buildBottomNavigationBar(isDark, currentIndex),
        ],
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
        onDestinationSelected: (index) {
          if (index == 1 && currentIndex == 1) {
            ref.read(searchFocusTriggerProvider.notifier).state++;
          } else {
            ref.read(tabIndexProvider.notifier).setIndex(index);
          }
        },
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
