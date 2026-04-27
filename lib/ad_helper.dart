import 'dart:io';

class AdHelper {
  // TEST ID'leri — yayına almadan önce gerçek AdMob ID'lerini gir

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Android test banner
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS test banner
    }
    throw UnsupportedError('Desteklenmeyen platform');
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-2034415381778097/2902747151'; // Android native
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/3986624511'; // iOS test native
    }
    throw UnsupportedError('Desteklenmeyen platform');
  }
}
