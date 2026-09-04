import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/providers.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';

import '../widgets/ad_banner_widget.dart';

/// Main navigation screen with custom bottom navigation bar
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
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
      extendBody: true,
      body: IndexedStack(index: currentIndex, children: _screens),
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
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    // Get bottom padding to account for system navigation bar (3-button nav)
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomMargin = (bottomPadding > 0 ? bottomPadding + 8 : 24.0);

    return RepaintBoundary(
      child: Container(
        margin: EdgeInsets.fromLTRB(20, 0, 20, bottomMargin),
        height: 62,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: surfaceLight, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              index: 0,
              icon: Icons.home_rounded,
              label: 'Home',
              textHint: textHint,
              currentIndex: currentIndex,
            ),
            _buildNavItem(
              index: 1,
              icon: Icons.search_rounded,
              label: 'Search',
              textHint: textHint,
              currentIndex: currentIndex,
            ),
            _buildNavItem(
              index: 2,
              icon: Icons.library_music_rounded,
              label: 'Library',
              textHint: textHint,
              currentIndex: currentIndex,
            ),
            _buildNavItem(
              index: 3,
              icon: Icons.settings_rounded,
              label: 'Settings',
              textHint: textHint,
              currentIndex: currentIndex,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color textHint,
    required int currentIndex,
  }) {
    final isSelected = currentIndex == index;

    return GestureDetector(
      onTap: () {
        if (index == 1 && currentIndex == 1) {
          ref.read(searchFocusTriggerProvider.notifier).state++;
          return;
        }
        ref.read(tabIndexProvider.notifier).setIndex(index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 21,
              color: isSelected ? AppTheme.primaryColor : textHint,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.primaryColor : textHint,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
