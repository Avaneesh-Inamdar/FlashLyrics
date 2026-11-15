import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded ad the user can choose to watch from Settings to support
/// development. Nothing is unlocked by it; it is purely a way to say thanks.
class SupportAd {
  SupportAd._();

  /// Production rewarded ad unit for FlashLyrics.
  static const prodUnitId = 'ca-app-pub-3987982513065210/5885312023';

  /// Google's official Android rewarded test unit.
  static const testUnitId = 'ca-app-pub-3940256099942544/5224354917';

  /// Debug builds and the "test ads" setting never request real ads.
  static String unitId({required bool useTestAds}) =>
      useTestAds || !kReleaseMode ? testUnitId : prodUnitId;

  static bool _busy = false;

  /// Loads and shows one rewarded ad, with a loading dialog while it loads
  /// and a message afterwards. Repeated taps while busy are ignored.
  static Future<void> watch(
    BuildContext context, {
    required bool useTestAds,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    void say(String text) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(text)));
    }

    var dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 20),
                Expanded(child: Text('Loading ad…')),
              ],
            ),
          ),
        ),
      ).whenComplete(() => dialogOpen = false),
    );

    try {
      final loaded = Completer<RewardedAd?>();
      var abandoned = false;
      await RewardedAd.load(
        adUnitId: unitId(useTestAds: useTestAds),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (abandoned || loaded.isCompleted) {
              ad.dispose();
            } else {
              loaded.complete(ad);
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint('SupportAd: failed to load: $error');
            if (!loaded.isCompleted) loaded.complete(null);
          },
        ),
      );
      final ad = await loaded.future.timeout(
        timeout,
        onTimeout: () {
          abandoned = true;
          return null;
        },
      );
      if (dialogOpen) navigator.pop();

      if (ad == null) {
        say('No ad is available right now. Please try again later.');
        return;
      }

      var rewarded = false;
      final closed = Completer<void>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!closed.isCompleted) closed.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('SupportAd: failed to show: $error');
          ad.dispose();
          if (!closed.isCompleted) closed.complete();
        },
      );
      await ad.show(onUserEarnedReward: (_, _) => rewarded = true);
      await closed.future;
      say(
        rewarded
            ? 'Thank you for supporting FlashLyrics! ❤️'
            : 'Thanks for trying! Watch the full ad to support FlashLyrics.',
      );
    } catch (e) {
      debugPrint('SupportAd: $e');
      if (dialogOpen) navigator.pop();
      say('No ad is available right now. Please try again later.');
    } finally {
      _busy = false;
    }
  }
}
