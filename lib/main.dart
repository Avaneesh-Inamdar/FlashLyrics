import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Enable edge-to-edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const FlashLyricsApp(),
    ),
  );
}

/// Main app widget with proper lifecycle handling
class FlashLyricsApp extends ConsumerStatefulWidget {
  const FlashLyricsApp({super.key});

  @override
  ConsumerState<FlashLyricsApp> createState() => _FlashLyricsAppState();
}

class _FlashLyricsAppState extends ConsumerState<FlashLyricsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Add lifecycle observer to handle app state changes
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Handle app lifecycle to prevent freezing when screen is off
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App is in background or being paused - reduce activity
        if (kDebugMode) {
          debugPrint('App lifecycle: paused/inactive');
        }
        break;
      case AppLifecycleState.resumed:
        // App is back to foreground - resume normal activity
        if (kDebugMode) {
          debugPrint('App lifecycle: resumed');
        }
        // Refresh media detection when app resumes
        _refreshMediaDetection();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is being terminated or hidden - cleanup
        if (kDebugMode) {
          debugPrint('App lifecycle: detached/hidden');
        }
        break;
    }
  }

  void _refreshMediaDetection() {
    // Trigger a refresh of media detection when app resumes
    try {
      ref
          .read(mediaNotifierProvider.notifier)
          .refreshCurrentSong(refreshLyrics: false);
    } catch (e) {
      // Ignore errors - provider might not be ready
    }
  }

  ThemeMode _getThemeMode(ThemeModeOption option) {
    switch (option) {
      case ThemeModeOption.auto:
        return ThemeMode.system;
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = _getThemeMode(settings.themeMode);

    // Apply user-selected accent palette
    AppTheme.setAccentPalette(settings.accentColor);

    // Determine if dark based on theme mode and system brightness
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);

    // Update system UI style based on theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    return MaterialApp(
      title: 'FlashLyrics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainScreen(),
    );
  }
}
