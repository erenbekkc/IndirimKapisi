import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';

// ────────────────────────────────────────────────────────────────
// notification-messages koleksiyonuna bildirim kaydı yazar.
// Her gönderimde yeni doküman oluşturur; tıklanınca clicked=true yapar.
// ────────────────────────────────────────────────────────────────
class NotificationLogger {
  static const _collection = 'notification-messages';

  /// Bildirim gönderildiğinde çağır. Firestore doc ID döner (payload için).
  static Future<String?> logSent({
    required String uid,
    required String message,
    String source = 'unknown', // 'scheduled' | 'fcm_foreground' | 'fcm_background' | 'fcm_notification'
  }) async {
    try {
      final ref = await FirebaseFirestore.instance.collection(_collection).add({
        'uid':      uid,
        'message':  message,
        'source':   source,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'sentAt':   FieldValue.serverTimestamp(),
        'clicked':  false,
      });
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcı bildirime tıkladığında çağır.
  static Future<void> markClicked(String? docId) async {
    if (docId == null || docId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(docId)
          .update({
        'clicked':   true,
        'clickedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
