import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/settings_screen.dart' show getOrCreateUserId;

class FavouriteLogger {
  static const _col = 'user-favourites';

  static Future<void> logAdded({
    required String campaignId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final uid = await getOrCreateUserId();

      // İndirim oranını hesapla
      double? discountRate;
      final type = data['campaignType'] as String?;
      if (type == 'priceDiscount') {
        final old = (data['oldPrice'] as num?)?.toDouble() ?? 0;
        final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
        if (old > 0) discountRate = (old - newP) / old * 100;
      } else if (type == 'secondDiscount') {
        discountRate = (data['discountRate'] as num?)?.toDouble();
      } else if (type == 'buyOneGetOne') {
        discountRate = 50.0;
      }

      await FirebaseFirestore.instance.collection(_col).add({
        'uid': uid,
        'campaignId': campaignId,
        'marketId': data['marketId'] ?? '',
        'marketName': data['marketName'] ?? '',
        'categoryId': data['categoryId'] ?? '',
        'categoryName': data['categoryName'] ?? '',
        'productName': data['product'] ?? data['title'] ?? '',
        'campaignType': type ?? '',
        'oldPrice': data['oldPrice'],
        'newPrice': data['newPrice'],
        'productPrice': data['productPrice'],
        'discountRate': discountRate,
        'startDate': data['startDate'],
        'endDate': data['endDate'],
        'platform': Platform.isIOS ? 'ios' : 'android',
        'favouritedAt': FieldValue.serverTimestamp(),
        'active': true,
        'removedAt': null,
      });
    } catch (_) {}
  }

  static Future<void> logRemoved(String campaignId) async {
    try {
      final uid = await getOrCreateUserId();
      final snap = await FirebaseFirestore.instance
          .collection(_col)
          .where('uid', isEqualTo: uid)
          .where('campaignId', isEqualTo: campaignId)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();
      for (final doc in snap.docs) {
        unawaited(doc.reference.update({
          'active': false,
          'removedAt': FieldValue.serverTimestamp(),
        }));
      }
    } catch (_) {}
  }

  /// Süresi dolmuş favorileri pasif yapar. FavorilerScreen açılışında çağrılır.
  static Future<void> updateExpired() async {
    try {
      final uid = await getOrCreateUserId();
      final now = DateTime.now();
      final snap = await FirebaseFirestore.instance
          .collection(_col)
          .where('uid', isEqualTo: uid)
          .where('active', isEqualTo: true)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasWork = false;
      for (final doc in snap.docs) {
        final endDate = (doc.data()['endDate'] as Timestamp?)?.toDate();
        if (endDate == null) continue;
        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
        final today = DateTime(now.year, now.month, now.day);
        if (endDay.isBefore(today)) {
          batch.update(doc.reference, {'active': false});
          hasWork = true;
        }
      }
      if (hasWork) await batch.commit();
    } catch (_) {}
  }
}
