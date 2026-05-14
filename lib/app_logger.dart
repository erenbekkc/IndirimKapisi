import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _istanbulTime() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 3));
  return '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';
}

/// Hataları Firestore app_logs koleksiyonuna yazar.
/// Her alan ayrı filtrelenebilir şekilde tasarlandı.
///
/// [location] → hatanın gerçekleştiği fonksiyon/ekran
/// [error]    → exception nesnesi
/// [stack]    → stack trace
/// [context]  → ek bağlam (ör: {'markets': [...], 'action': 'toggle'})
Future<void> logError(
  String location,
  Object error, [
  StackTrace? stack,
  Map<String, dynamic>? context,
]) async {
  try {
    SharedPreferences? prefs;
    try { prefs = await SharedPreferences.getInstance(); } catch (_) {}

    final uid                = prefs?.getString('app_user_id');
    final subscribedMarkets  = prefs?.getStringList('subscribed_markets');
    final subscribedCategories = prefs?.getStringList('subscribed_categories');

    String? fcmToken;
    try { fcmToken = await FirebaseMessaging.instance.getToken(); } catch (_) {}

    final fullStack    = stack?.toString() ?? '';
    final stackSummary = fullStack.split('\n').take(6).join(' | ');

    await FirebaseFirestore.instance.collection('app_logs').add({
      // Teşhis için kritik alanlar
      'location':     location,
      'errorType':    error.runtimeType.toString(),
      'errorMessage': error.toString(),
      'stackSummary': stackSummary,
      'stackFull':    fullStack.length > 2000 ? '${fullStack.substring(0, 2000)}...' : fullStack,

      // Kullanıcı bilgisi
      'uid':      uid,
      'fcmToken': fcmToken,

      // Kullanıcı tercihleri (bildirim sorunlarını teşhis etmek için)
      'subscribedMarkets':    subscribedMarkets,
      'subscribedCategories': subscribedCategories,

      // Cihaz bilgisi
      'platform':  Platform.isIOS ? 'ios' : 'android',
      'osVersion': Platform.operatingSystemVersion,

      // Zaman — saniye hassasiyetiyle İstanbul saati
      'timestamp':         FieldValue.serverTimestamp(),
      'localTimeIstanbul': _istanbulTime(),

      // Ek bağlam (çağıran tarafından geçilir)
      if (context != null) ...context,
    });
  } catch (_) {
    // Logger kendisi hata verirse sessiz geç
  }
}
