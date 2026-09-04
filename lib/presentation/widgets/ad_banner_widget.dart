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

  // Real Ad Unit ID provided by user
  static const String _prodAdUnitId = 'ca-app-pub-3987982513065210/2035205150';
  // Google's official Android Banner Test Ad Unit ID to prevent account suspension during development
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  String get _adUnitId => kReleaseMode ? _prodAdUnitId : _testAdUnitId;

  @override
  void initState() {
    super.initState();
    _checkAndLoadAd();
  }

  void _checkAndLoadAd() {
    final adsEnabled = ref.read(settingsProvider).enableAds;
    if (adsEnabled && _bannerAd == null) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;

    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load: $error');
          ad.dispose();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adsEnabled = ref.watch(settingsProvider.select((s) => s.enableAds));

    if (!adsEnabled) {
      if (_bannerAd != null) {
        _bannerAd?.dispose();
        _bannerAd = null;
        _isLoaded = false;
      }
      return const SizedBox.shrink();
    }

    if (_bannerAd == null) {
      _loadBanner();
    }

    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
