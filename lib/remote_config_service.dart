import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Firebase Remote Config üzerinden uygulama ayarlarını yönetir.
/// Firebase Console'dan build almadan değiştirilebilir:
///   ad_frequency → her kaç indirim kartından sonra reklam çıkar (varsayılan: 5)
class RemoteConfigService {
  RemoteConfigService._();
  static final instance = RemoteConfigService._();

  static const _adFrequencyKey    = 'ad_frequency';
  static const _defaultAdFrequency = 5;

  final _rc = FirebaseRemoteConfig.instance;

  Future<void> init() async {
    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout:          const Duration(seconds: 10),
      minimumFetchInterval:  const Duration(hours: 1),
    ));
    await _rc.setDefaults(const {_adFrequencyKey: _defaultAdFrequency});
    try {
      await _rc.fetchAndActivate();
    } catch (_) {
      // Ağ hatası vb. — varsayılan değer kullanılır
    }
  }

  /// Her kaç indirim kartından sonra reklam kartı çıkacak.
  int get adFrequency {
    final val = _rc.getInt(_adFrequencyKey);
    return val > 0 ? val : _defaultAdFrequency;
  }
}
