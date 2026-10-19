import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../presentation/providers/providers.dart';

final reviewServiceProvider = Provider(
  (ref) => ReviewService(ref.read(sharedPreferencesProvider)),
);

class ReviewService {
  ReviewService(
    this.prefs, {
    DateTime Function()? clock,
    Future<bool> Function(Uri)? launch,
  }) : _clock = clock ?? DateTime.now,
       _launch =
           launch ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
  final SharedPreferences prefs;
  final DateTime Function() _clock;
  final Future<bool> Function(Uri) _launch;
  bool _started = false;
  bool _shown = false;
  final Set<String> _songs = {};

  Future<void> startSession() async {
    if (_started) return;
    _started = true;
    if (!prefs.containsKey('review_first_seen')) {
      await prefs.setInt('review_first_seen', _clock().millisecondsSinceEpoch);
    }
    await prefs.setInt(
      'review_sessions',
      (prefs.getInt('review_sessions') ?? 0) + 1,
    );
  }

  void recordLyrics(String songId) {
    if (songId.isNotEmpty) _songs.add(songId);
  }

  bool get shouldPrompt {
    final now = _clock().millisecondsSinceEpoch;
    return _started &&
        !_shown &&
        prefs.getBool('review_disabled') != true &&
        (prefs.getInt('review_sessions') ?? 0) >= 3 &&
        _songs.length >= 3 &&
        now - (prefs.getInt('review_first_seen') ?? now) >=
            const Duration(days: 2).inMilliseconds &&
        now >= (prefs.getInt('review_next_prompt') ?? 0);
  }

  void markShown() => _shown = true;
  Future<void> later() async {
    _shown = true;
    await prefs.setInt(
      'review_next_prompt',
      _clock().add(const Duration(days: 14)).millisecondsSinceEpoch,
    );
  }

  Future<void> never() async {
    _shown = true;
    await prefs.setBool('review_disabled', true);
  }

  /// An explicit review button always opens Play, rather than depending on the
  /// quota-limited in-app review API, which can silently show no dialog.
  Future<bool> openReviewPage() async {
    for (final uri in [
      Uri.parse(
        'market://details?id=music.flashlyrics.app&showAllReviews=true&write_review=true',
      ),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=music.flashlyrics.app&showAllReviews=true',
      ),
    ]) {
      try {
        if (await _launch(uri)) return true;
      } catch (_) {
        /* Try browser fallback. */
      }
    }
    return false;
  }
}
