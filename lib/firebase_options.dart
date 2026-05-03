import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return ios;
    }
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDtZfvhn2bzNXZiFA-oQ5f5jTLFVlRnJTQ',
    appId: '1:90896881699:android:a12ead6ae5328c98df7996',
    messagingSenderId: '90896881699',
    projectId: 'indirim-takip-71bc8',
    storageBucket: 'indirim-takip-71bc8.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA6g568opMpiSL7gBezCEOkp9iwuAG0qBQ',
    appId: '1:90896881699:ios:921db9d1336226efdf7996',
    messagingSenderId: '90896881699',
    projectId: 'indirim-takip-71bc8',
    storageBucket: 'indirim-takip-71bc8.firebasestorage.app',
    iosBundleId: 'com.alp.indirimRadari',
  );
}
