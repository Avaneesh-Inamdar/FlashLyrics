import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/device_profile.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/app_tour_screen.dart';
import 'presentation/widgets/tv_focus_ring.dart';
import 'presentation/widgets/tv_pointer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isTv = await DeviceProfile.detectTelevision();

  // Google Mobile Ads does not serve TV, so it is not started there.
  if (!isTv) MobileAds.instance.initialize();

  // Optimize image cache for RAM (limit to 50 images, 20MB)
  PaintingBinding.instance.imageCache.maximumSize = 50;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 << 20;

  // Enable high-refresh-rate input resampling and vsync for 90/120Hz displays
  GestureBinding.instance.resamplingEnabled = true;

  // Phones stay in portrait; tablets and TVs can rotate / use landscape.
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  final screen = view == null
      ? Size.zero
      : view.physicalSize / view.devicePixelRatio;
  await SystemChrome.setPreferredOrientations(
    DeviceProfile.orientationsFor(DeviceProfile.formFactor(screen, isTv: isTv)),
  );

  // Enable edge-to-edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        isTelevisionProvider.overrideWithValue(isTv),
        appTourAutoShowProvider.overrideWithValue(true),
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
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (kDebugMode) debugPrint('App lifecycle: paused/inactive/hidden - reducing polling');
        // Reduce polling frequency when backgrounded to save RAM/battery, but keep detection alive
        try {
          ref.read(mediaDetectionServiceProvider).setBackgroundMode(true);
        } catch (_) {}
        break;
      case AppLifecycleState.resumed:
        if (kDebugMode) debugPrint('App lifecycle: resumed');
        try {
          ref.read(mediaDetectionServiceProvider).setBackgroundMode(false);
        } catch (_) {}
        _refreshMediaDetection();
        break;
      case AppLifecycleState.detached:
        if (kDebugMode) debugPrint('App lifecycle: detached');
        try {
          ref.read(mediaDetectionServiceProvider).setBackgroundMode(true);
        } catch (_) {}
        break;
    }
  }

  void _refreshPermissions() {
    ref.invalidate(hasNotificationAccessProvider);
    ref.invalidate(hasOverlayPermissionProvider);
    try {
      ref.read(overlayProvider.notifier).checkPermission();
    } catch (_) {}
    try {
      ref.read(mediaNotifierProvider.notifier).checkPermissions();
    } catch (_) {}
  }

  void _refreshMediaDetection() {
    // Back from the system settings screens: re-read the permission state so
    // Settings and the Listening screen stop showing "Grant" right away.
    _refreshPermissions();
    // Android can take a moment to bind the notification listener after the
    // user grants access, so look once more shortly after.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _refreshPermissions();
    });
    // Trigger a refresh of media detection when app resumes
    try {
      ref
          .read(mediaNotifierProvider.notifier)
          .refreshCurrentSong(refreshLyrics: false);
    } catch (e) {
      // Ignore errors - provider might not be ready
    }
  }

  /// Ten-foot UI: slightly larger text and a clearly visible focus highlight
  /// so the remote's D-pad always shows where the selection is.
  static Widget _tvBuilder(BuildContext context, Widget? child) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: const TextScaler.linear(1.15)),
      child: Theme(
        data: theme.copyWith(
          focusColor: AppTheme.primaryColor.withValues(alpha: 0.35),
          visualDensity: VisualDensity.comfortable,
        ),
        child: TvPointerOverlay(
          child: TvFocusRing(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
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
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'FlashLyrics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: ref.watch(isTelevisionProvider) ? _tvBuilder : null,
      home: const MainScreen(),
    );
  }
}
