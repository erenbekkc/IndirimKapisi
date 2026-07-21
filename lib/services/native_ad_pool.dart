import 'dart:math' as math;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../ad_helper.dart';
import '../session_tracker.dart';

/// Merkezi native reklam havuzu.
/// Reklamları önceden yükler ve widget istediğinde hazır verir.
/// Show Rate'i artırmak için tasarlanmıştır.
class NativeAdPool {
  NativeAdPool._();
  static final instance = NativeAdPool._();

  static const int _poolSize = 5;
  static const int _maxBackoffSeconds = 32;

  final List<NativeAd> _ready = [];
  // Token → callback: bekleyen widget istekleri (insertion order korunur)
  final Map<int, void Function(NativeAd)> _waiters = {};
  // Yüklenmekte olan ad'lara referans — GC'nin toplamaması için
  final Set<NativeAd> _loadingAds = {};
  int _loading = 0;
  int _nextToken = 0;
  bool _initialized = false;
  bool _disposed = false;

  // ── Public API ─────────────────────────────────────────────────────

  /// Uygulama başlarken bir kez çağrılır. Havuzu preload eder.
  void initialize() {
    if (_initialized || _disposed) return;
    _initialized = true;
    _fillPool();
  }

  /// Reklam iste.
  /// Havuzda hazır reklam varsa [onReady] hemen çağrılır ve -1 döner.
  /// Yoksa kuyrukta bekletilir, yüklenince çağrılır; iptal için token döner.
  int request(void Function(NativeAd) onReady) {
    if (_disposed) return -1;

    final ad = _takeSync();
    if (ad != null) {
      onReady(ad);
      return -1; // Anında servis edildi, token gerekmez
    }

    // Kuyrukta beklet
    final token = _nextToken++;
    _waiters[token] = onReady;
    _fillPool(); // Yükleme zaten devam ediyordur, eksikse yeni başlat
    return token;
  }

  /// Bekleyen isteği iptal et (widget dispose olduğunda çağrılır).
  void cancelRequest(int token) {
    _waiters.remove(token);
  }

  /// Widget, reklamı gösteremeden dispose olursa geri ver.
  /// Reklam henüz AdWidget'a girmemişse yeniden kullanılabilir.
  void returnUnused(NativeAd ad) {
    if (_disposed) {
      ad.dispose();
      return;
    }
    if (_waiters.isNotEmpty) {
      final firstKey = _waiters.keys.first;
      final cb = _waiters.remove(firstKey)!;
      cb(ad);
    } else {
      _ready.add(ad);
    }
  }

  /// Uygulama kapanırken çağrılır. Tüm havuzu temizler.
  void dispose() {
    _disposed = true;
    for (final ad in _ready) ad.dispose();
    for (final ad in _loadingAds) ad.dispose();
    _ready.clear();
    _loadingAds.clear();
    _waiters.clear();
  }

  // ── Internal ───────────────────────────────────────────────────────

  /// Havuzu minimum pool size'a tamamla.
  void _fillPool() {
    if (_disposed) return;
    final needed = _poolSize - _ready.length - _loading;
    for (int i = 0; i < needed; i++) {
      _loadOne();
    }
  }

  /// Tek bir reklam yükle. Hata durumunda exponential backoff uygula.
  void _loadOne({int attempt = 0}) {
    if (_disposed) return;
    _loading++;

    // late ile referans yakala — GC'nin callback gelmeden toplamasını engelle
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: AdHelper.nativeAdUnitId,
      factoryId: 'campaignCardAd',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          _loadingAds.remove(ad);
          _loading--;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _onAdReady(ad);
        },
        onAdImpression: (_) => SessionTracker.instance.incrementAd(),
        onAdFailedToLoad: (_, error) {
          _loadingAds.remove(ad);
          _loading--;
          ad.dispose();
          if (_disposed) return;

          FirebaseCrashlytics.instance.log(
            'NativeAdPool failed (attempt=$attempt): '
            'code=${error.code} msg=${error.message}',
          );

          // Bekleyen widget varsa hemen retry — backoff sadece havuz dolduğunda
          if (_waiters.isNotEmpty) {
            _loadOne(attempt: attempt + 1);
          } else {
            // Exponential backoff: 1s → 2s → 4s → ... → max 32s
            final delaySecs = math.min(1 << attempt, _maxBackoffSeconds);
            Future.delayed(Duration(seconds: delaySecs), () {
              _loadOne(attempt: attempt + 1);
            });
          }
        },
      ),
    );
    _loadingAds.add(ad); // Referansı tut, GC'den koru
    ad.load();
  }

  /// Havuzdan senkron olarak reklam al. Havuz boşsa null döner.
  NativeAd? _takeSync() {
    if (_ready.isEmpty) return null;
    final ad = _ready.removeAt(0);
    _fillPool(); // Eksilen yeri hemen doldurmaya başla
    return ad;
  }

  /// Yüklenen reklamı bekleyen widget varsa ver, yoksa havuza ekle.
  void _onAdReady(NativeAd ad) {
    if (_waiters.isNotEmpty) {
      final firstKey = _waiters.keys.first;
      final cb = _waiters.remove(firstKey)!;
      cb(ad);
      _fillPool(); // Bir reklam verildi, havuzu tekrar doldur
    } else {
      _ready.add(ad);
    }
  }
}
