import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';

/// Theme mode options
enum ThemeModeOption { auto, light, dark }

/// App settings state
class AppSettings {
  final double fontSize;
  final bool autoRefresh;
  final bool showSyncedLyrics;
  final ThemeModeOption themeMode;
  final List<String> providerPriority;
  final String accentColor;

  const AppSettings({
    this.fontSize = 18.0,
    this.autoRefresh = true,
    this.showSyncedLyrics = true,
    this.themeMode = ThemeModeOption.auto,
    this.accentColor = 'emerald',
    this.providerPriority = const [
      'lrclib',
      'textyl',
      'chartlyrics',
      'lyrics.ovh',
      'lyrist',
      'netease',
    ],
  });

  /// Get theme mode display name
  String get themeModeLabel {
    switch (themeMode) {
      case ThemeModeOption.auto:
        return 'System';
      case ThemeModeOption.light:
        return 'Light';
      case ThemeModeOption.dark:
        return 'Dark';
    }
  }

  /// Available providers with display names
  static const Map<String, String> providerNames = {
    'lrclib': 'LRCLIB (Synced)',
    'textyl': 'Textyl (Synced)',
    'chartlyrics': 'ChartLyrics',
    'lyrics.ovh': 'Lyrics.ovh',
    'lyrist': 'Lyrist',
    'netease': 'NetEase Music',
  };

  /// Accent color options
  static const Map<String, String> accentColorNames = {
    'emerald': 'Emerald',
    'cobalt': 'Cobalt',
    'orchard': 'Orchard',
    'amber': 'Amber',
    'crimson': 'Crimson',
  };

  AppSettings copyWith({
    double? fontSize,
    bool? autoRefresh,
    bool? showSyncedLyrics,
    ThemeModeOption? themeMode,
    List<String>? providerPriority,
    String? accentColor,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      showSyncedLyrics: showSyncedLyrics ?? this.showSyncedLyrics,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      providerPriority: providerPriority ?? this.providerPriority,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'autoRefresh': autoRefresh,
    'showSyncedLyrics': showSyncedLyrics,
    'themeMode': themeMode.name,
    'accentColor': accentColor,
    'providerPriority': providerPriority,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    ThemeModeOption parseThemeMode(dynamic value) {
      if (value is String) {
        return ThemeModeOption.values.firstWhere(
          (e) => e.name == value,
          orElse: () => ThemeModeOption.auto,
        );
      }
      // Migration from old boolean format
      if (value is bool || json['darkTheme'] is bool) {
        final isDark = (value as bool?) ?? (json['darkTheme'] as bool?) ?? true;
        return isDark ? ThemeModeOption.dark : ThemeModeOption.light;
      }
      return ThemeModeOption.auto;
    }

    return AppSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      autoRefresh: json['autoRefresh'] as bool? ?? true,
      showSyncedLyrics: json['showSyncedLyrics'] as bool? ?? true,
      themeMode: parseThemeMode(json['themeMode']),
      accentColor: json['accentColor'] as String? ?? 'emerald',
      providerPriority:
          (json['providerPriority'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [
            'lrclib',
            'textyl',
            'chartlyrics',
            'lyrics.ovh',
            'lyrist',
            'netease',
          ],
    );
  }

  /// Font size presets
  static const Map<String, double> fontSizePresets = {
    'Small': 14.0,
    'Medium': 18.0,
    'Large': 22.0,
    'Extra Large': 26.0,
  };

  String get fontSizeLabel {
    for (final entry in fontSizePresets.entries) {
      if (entry.value == fontSize) return entry.key;
    }
    return 'Custom';
  }

  String get accentColorLabel => accentColorNames[accentColor] ?? 'Custom';
}

/// Settings state notifier
class SettingsNotifier extends StateNotifier<AppSettings> {
  static const String _settingsKey = 'app_settings';
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(const AppSettings()) {
    _loadSettings();
  }

  void _loadSettings() {
    final data = _prefs.getString(_settingsKey);
    if (data != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(data));
      } catch (e) {
        // Use defaults if corrupted
        state = const AppSettings();
      }
    }
  }

  Future<void> _saveSettings() async {
    await _prefs.setString(_settingsKey, jsonEncode(state.toJson()));
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size);
    _saveSettings();
  }

  void setAutoRefresh(bool value) {
    state = state.copyWith(autoRefresh: value);
    _saveSettings();
  }

  void setShowSyncedLyrics(bool value) {
    state = state.copyWith(showSyncedLyrics: value);
    _saveSettings();
  }

  void setThemeMode(ThemeModeOption mode) {
    state = state.copyWith(themeMode: mode);
    _saveSettings();
  }

  void setAccentColor(String key) {
    state = state.copyWith(accentColor: key);
    _saveSettings();
  }

  void setProviderPriority(List<String> priority) {
    state = state.copyWith(providerPriority: priority);
    _saveSettings();
  }

  void moveProviderUp(int index) {
    if (index <= 0) return;
    final newList = List<String>.from(state.providerPriority);
    final item = newList.removeAt(index);
    newList.insert(index - 1, item);
    setProviderPriority(newList);
  }

  void moveProviderDown(int index) {
    if (index >= state.providerPriority.length - 1) return;
    final newList = List<String>.from(state.providerPriority);
    final item = newList.removeAt(index);
    newList.insert(index + 1, item);
    setProviderPriority(newList);
  }

  void resetToDefaults() {
    state = const AppSettings();
    _saveSettings();
  }
}

/// Settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});
