import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../presentation/providers/providers.dart';

final supportPromptServiceProvider = Provider(
  (ref) => SupportPromptService(ref.read(sharedPreferencesProvider)),
);

/// Settings item the support prompt sends the user to. Settings scrolls to
/// it and briefly highlights it, then clears this back to null.
enum SupportHighlight { adsToggle, watchAd }

final settingsHighlightProvider = StateProvider<SupportHighlight?>(
  (ref) => null,
);

/// "FlashLyrics is free" reminder shown when the app opens, at most once a
/// day. Never on the first day, so new users only see the setup tip.
class SupportPromptService {
  SupportPromptService(this.prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences prefs;
  final DateTime Function() _clock;
  bool _checked = false;

  static const _next = 'support_prompt_next';
  static const _disabled = 'support_prompt_disabled';
  static const gap = Duration(days: 1);

  /// True at most once per app run, when a day has passed since the last
  /// prompt (or since the first launch).
  bool shouldShowOnOpen() {
    if (_checked) return false;
    _checked = true;
    if (prefs.getBool(_disabled) == true) return false;
    final now = _clock();
    final next = prefs.getInt(_next);
    if (next == null) {
      prefs.setInt(_next, now.add(gap).millisecondsSinceEpoch);
      return false;
    }
    return now.millisecondsSinceEpoch >= next;
  }

  /// "OK" or "Remind me later": ask again tomorrow.
  Future<void> snooze() =>
      prefs.setInt(_next, _clock().add(gap).millisecondsSinceEpoch);

  /// "No thanks": stop asking.
  Future<void> never() => prefs.setBool(_disabled, true);
}
