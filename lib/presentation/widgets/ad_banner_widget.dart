import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/utils/device_profile.dart';
import '../providers/settings_provider.dart';

/// Policy-compliant Google AdMob banner.
/// - Shown only while the user has ads turned on (enableAds)
/// - Release builds request only the real ad unit; debug builds only
///   Google's test unit
/// - When no ad loads, nothing is shown and the same unit is retried later
class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({
    super.key,
    this.prodAdUnitId = mainAdUnitId,
    this.fallbackAdUnitId,
    @visibleForTesting this.release = kReleaseMode,
  });

  /// Banner under the bottom navigation bar.
  static const String mainAdUnitId = 'ca-app-pub-3987982513065210/2035205150';

  /// Banner under full-screen lyrics.
  static const String fullscreenAdUnitId =
      'ca-app-pub-3987982513065210/6598204417';

  /// Google's official Android banner test unit.
  static const String testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  /// Production unit used in release builds.
  final String prodAdUnitId;

  /// Real unit tried right away when [prodAdUnitId] has no ad to show.
  final String? fallbackAdUnitId;

  /// Whether this is a release build. Only tests change it.
  final bool release;

  static String unitIdFor(String prodAdUnitId, {bool release = kReleaseMode}) =>
      release ? prodAdUnitId : testAdUnitId;

  /// Tablets get the 728x90 leaderboard when it fits: the small 320x50 banner
  /// has far fewer advertisers on large screens.
  static AdSize sizeFor(Size screen) =>
      screen.shortestSide >= 600 && screen.width >= 740
      ? AdSize.leaderboard
      : AdSize.banner;

  /// How long to wait before retrying after [failures] failed loads in a
  /// row: 1, 2, 4 and 8 minutes, then every 10 minutes.
  static Duration retryDelay(int failures) {
    final doubling = 1 << (failures - 1).clamp(0, 4); // 1, 2, 4, 8, 16
    return Duration(minutes: min(doubling, 10));
  }

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _loading = false;
  int _failures = 0;
  Timer? _retry;
  bool _useFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted || _loading || _bannerAd != null) return;
    if (!ref.read(settingsProvider).enableAds) return;
    // Ads are not served on TV.
    if (ref.read(isTelevisionProvider)) return;
    _retry?.cancel();
    _loading = true;

    final fallback = widget.fallbackAdUnitId;
    final unitId = AdBannerWidget.unitIdFor(
      _useFallback && fallback != null ? fallback : widget.prodAdUnitId,
      release: widget.release,
    );
    BannerAd(
      adUnitId: unitId,
      size: AdBannerWidget.sizeFor(MediaQuery.sizeOf(context)),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _loading = false;
          if (!mounted || !ref.read(settingsProvider).enableAds) {
            ad.dispose();
            return;
          }
          _failures = 0;
          setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _loading = false;
          if (!mounted) return;
          if (fallback != null && !_useFallback) {
            // This unit has no ad (common on tablets): try the other one now.
            _useFallback = true;
            _load();
            return;
          }
          _useFallback = false;
          _failures++;
          final delay = AdBannerWidget.retryDelay(_failures);
          debugPrint(
            'AdBannerWidget: no ad from $unitId (${error.code}: '
            '${error.message}); retrying in ${delay.inMinutes} min',
          );
          _retry = Timer(delay, _load);
        },
      ),
    ).load();
  }

  void _clear() {
    _retry?.cancel();
    _retry = null;
    _failures = 0;
    if (_bannerAd != null) {
      _bannerAd!.dispose();
      setState(() => _bannerAd = null);
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(settingsProvider.select((s) => s.enableAds), (_, on) {
      if (on) {
        _failures = 0;
        _load();
      } else {
        _clear();
      }
    });

    final adsEnabled = ref.watch(settingsProvider.select((s) => s.enableAds));
    final ad = _bannerAd;
    if (!adsEnabled || ad == null) return const SizedBox.shrink();

    return Container(
      alignment: Alignment.center,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: AdWidget(ad: ad),
    );
  }
}
