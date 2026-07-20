import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config_service.dart';
import '../ad_helper.dart';

class InterstitialAdService {
  InterstitialAdService._();
  static final instance = InterstitialAdService._();

  InterstitialAd? _ad;
  bool _isLoaded = false;
  DateTime? _lastShownAt;
  DateTime? _sessionStartAt;

  void startSession() {
    _sessionStartAt ??= DateTime.now();
  }

  void load() {
    final cfg = AdConfigService.instance.config;
    if (!cfg.showInterstitial) return;

    final unitId = (Platform.isIOS
        ? cfg.interstitialIosUnitId
        : cfg.interstitialAndroidUnitId)
        ?.isNotEmpty == true
        ? (Platform.isIOS ? cfg.interstitialIosUnitId! : cfg.interstitialAndroidUnitId!)
        : AdHelper.interstitialAdUnitId;
    if (unitId.isEmpty) return;

    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoaded = true;
          _ad!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _ad = null;
              _isLoaded = false;
              load(); // Bir sonraki için hemen yükle
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _ad = null;
              _isLoaded = false;
            },
          );
        },
        onAdFailedToLoad: (_) {
          _isLoaded = false;
        },
      ),
    );
  }

  /// [trigger]: 'onTabSwitch' | 'onAppResume'
  /// Gereken koşullar sağlanıyorsa reklamı gösterir.
  bool tryShow(Object context, String trigger) {
    final cfg = AdConfigService.instance.config;
    if (!cfg.showInterstitial || !_isLoaded || _ad == null) return false;

    // Trigger aktif mi?
    final triggers = cfg.triggers;
    final triggerEnabled = trigger == 'onTabSwitch'
        ? triggers.onTabSwitch
        : trigger == 'onAppResume'
            ? triggers.onAppResume
            : false;
    if (!triggerEnabled) return false;

    // Minimum oturum süresi geçti mi?
    final sessionStart = _sessionStartAt;
    if (sessionStart != null && triggers.minSessionSeconds > 0) {
      final elapsed = DateTime.now().difference(sessionStart).inSeconds;
      if (elapsed < triggers.minSessionSeconds) return false;
    }

    // Cooldown geçti mi?
    final lastShown = _lastShownAt;
    if (lastShown != null && triggers.cooldownSeconds > 0) {
      final sinceLastShown = DateTime.now().difference(lastShown).inSeconds;
      if (sinceLastShown < triggers.cooldownSeconds) return false;
    }

    _lastShownAt = DateTime.now();
    _ad!.show();
    return true;
  }
}
