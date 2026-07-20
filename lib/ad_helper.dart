import 'dart:io';

class AdHelper {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-2034415381778097/6689750204'; // Android banner
    } else if (Platform.isIOS) {
      return 'ca-app-pub-2034415381778097/1898526321'; // iOS banner
    }
    throw UnsupportedError('Desteklenmeyen platform');
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-2034415381778097/2902747151'; // Android native
    } else if (Platform.isIOS) {
      return 'ca-app-pub-2034415381778097/6416355830'; // iOS native
    }
    throw UnsupportedError('Desteklenmeyen platform');
  }

  // Interstitial unit ID'leri Firestore config/ads.interstitial üzerinden yönetilir.
  // Firestore'da tanımlı değilse bu fallback değerler kullanılır.
  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-2034415381778097/9015812407';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-2034415381778097/2554611768';
    }
    throw UnsupportedError('Desteklenmeyen platform');
  }
}
