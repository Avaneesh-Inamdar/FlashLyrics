import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../providers/settings_provider.dart';

/// Policy-compliant Google AdMob Banner Ad Widget.
/// - Respects user setting toggle (enableAds)
/// - Uses test ad unit in debug mode to prevent policy violations
/// - Uses production ad unit in release mode
class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({super.key});

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _fallbackToTest = false;

  // Real Ad Unit ID provided by user
  static const String _prodAdUnitId =
      'ca-app-pub-3987982513065210/2035205150';
  // Google's official Android Banner Test Ad Unit ID
  static const String _testAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  String _getAdUnitId({required bool useTestAds}) {
    if (useTestAds || !kReleaseMode || _fallbackToTest) {
      return _testAdUnitId;
    }
    return _prodAdUnitId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndLoadAd();
      }
    });
  }

  void _checkAndLoadAd() {
    final settings = ref.read(settingsProvider);
    if (settings.enableAds && _bannerAd == null && !_isLoading) {
      _loadBanner(useTestAds: settings.useTestAds);
    }
  }

  void _loadBanner({required bool useTestAds}) {
    if (_isLoading) return;
    _isLoading = true;

    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;

    final unitId = _getAdUnitId(useTestAds: useTestAds);
    debugPrint(
      'AdBannerWidget: Loading banner with unit ID: $unitId (test: ${unitId == _testAdUnitId})',
    );

    final ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          debugPrint('AdBannerWidget: Banner loaded successfully (${loadedAd.adUnitId})');
          if (mounted) {
            setState(() {
              _bannerAd = loadedAd as BannerAd;
              _isLoaded = true;
              _isLoading = false;
            });
          } else {
            loadedAd.dispose();
          }
        },
        onAdFailedToLoad: (failedAd, error) {
          debugPrint('AdBannerWidget: Banner failed to load ($unitId): $error');
          failedAd.dispose();

          if (!mounted) return;

          // If production ad unit failed (e.g. Account not approved yet, code: 3),
          // immediately fallback to Google's official sample test ad unit.
          if (!_fallbackToTest && unitId == _prodAdUnitId) {
            debugPrint('AdBannerWidget: Falling back to Google sample/test banner ad');
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
              _isLoading = false;
              _fallbackToTest = true;
            });
            _loadBanner(useTestAds: true);
            return;
          }

          setState(() {
            _bannerAd = null;
            _isLoaded = false;
            _isLoading = false;
          });
        },
      ),
    );

    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to changes in enableAds
    ref.listen<bool>(
      settingsProvider.select((s) => s.enableAds),
      (prev, enabled) {
        if (enabled && _bannerAd == null && !_isLoading) {
          _fallbackToTest = false;
          _loadBanner(useTestAds: ref.read(settingsProvider).useTestAds);
        } else if (!enabled && _bannerAd != null) {
          setState(() {
            _bannerAd?.dispose();
            _bannerAd = null;
            _isLoaded = false;
            _isLoading = false;
          });
        }
      },
    );

    // Listen to changes in useTestAds
    ref.listen<bool>(
      settingsProvider.select((s) => s.useTestAds),
      (prev, testAds) {
        if (ref.read(settingsProvider).enableAds) {
          _fallbackToTest = false;
          _loadBanner(useTestAds: testAds);
        }
      },
    );

    final adsEnabled = ref.watch(settingsProvider.select((s) => s.enableAds));

    if (!adsEnabled || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
