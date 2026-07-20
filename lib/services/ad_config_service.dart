import 'package:cloud_firestore/cloud_firestore.dart';

class InterstitialTriggers {
  final bool onTabSwitch;
  final bool onAppResume;
  final int minSessionSeconds;
  final int cooldownSeconds;

  const InterstitialTriggers({
    this.onTabSwitch = false,
    this.onAppResume = false,
    this.minSessionSeconds = 60,
    this.cooldownSeconds = 300,
  });

  factory InterstitialTriggers.fromMap(Map<String, dynamic> m) {
    return InterstitialTriggers(
      onTabSwitch: m['onTabSwitch'] as bool? ?? false,
      onAppResume: m['onAppResume'] as bool? ?? false,
      minSessionSeconds: (m['minSessionSeconds'] as num?)?.toInt() ?? 60,
      cooldownSeconds: (m['cooldownSeconds'] as num?)?.toInt() ?? 300,
    );
  }
}

class AdConfig {
  final bool enabled;
  final bool banner;
  final bool native;
  final bool interstitialEnabled;
  final String? interstitialAndroidUnitId;
  final String? interstitialIosUnitId;
  final InterstitialTriggers triggers;

  const AdConfig({
    this.enabled = true,
    this.banner = true,
    this.native = true,
    this.interstitialEnabled = false,
    this.interstitialAndroidUnitId,
    this.interstitialIosUnitId,
    this.triggers = const InterstitialTriggers(),
  });

  bool get showBanner => enabled && banner;
  bool get showNative => enabled && native;
  bool get showInterstitial => enabled && interstitialEnabled;
}

class AdConfigService {
  AdConfigService._();
  static final instance = AdConfigService._();

  AdConfig _config = const AdConfig();
  AdConfig get config => _config;

  Future<void> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('ads')
          .get();
      final data = doc.data();
      if (data == null) return;

      final enabled = data['enabled'] as bool? ?? true;
      final banner = data['banner'] as bool? ?? true;
      final native = data['native'] as bool? ?? true;

      final interstitialMap = data['interstitial'] as Map<String, dynamic>?;
      final interstitialEnabled = interstitialMap?['enabled'] as bool? ?? false;
      final androidId = interstitialMap?['androidUnitId'] as String?;
      final iosId = interstitialMap?['iosUnitId'] as String?;
      final triggersMap = interstitialMap?['triggers'] as Map<String, dynamic>?;
      final triggers = triggersMap != null
          ? InterstitialTriggers.fromMap(triggersMap)
          : const InterstitialTriggers();

      _config = AdConfig(
        enabled: enabled,
        banner: banner,
        native: native,
        interstitialEnabled: interstitialEnabled,
        interstitialAndroidUnitId: androidId,
        interstitialIosUnitId: iosId,
        triggers: triggers,
      );
    } catch (_) {
      // Hata olursa mevcut config korunur (default: reklamlar açık, interstitial kapalı)
    }
  }
}
