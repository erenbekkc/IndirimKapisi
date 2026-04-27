import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzData;
import 'main.dart';

// ────────────────────────────────────────────────────────────────
// Bildirim mantığı:
//  • Her uygulama açılışında kontrol eder
//  • Son bildirimden en az 2 gün geçmişse bugün 14:00'a bildirim planlar
//  • (1 gün bildirim, 1 gün boş = 2 günde 1 ritim)
//  • İçerik: takip edilen marketlerdeki + kategorilerdeki AKTİF kampanyaların
//    market ve kategori adlarını özetleyen sıcak, emoji'li mesaj
// ────────────────────────────────────────────────────────────────

class NotificationScheduler {
  static const _lastSentDateKey = 'last_notif_sent_date'; // "yyyy-MM-dd"
  static const _notifHour = 14;
  static const _notifId   = 777;

  static Future<void> scheduleIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now   = DateTime.now();
      final today = _dateStr(now);

      // Bugün zaten bildirim planlandıysa çık
      final lastSentDate = prefs.getString(_lastSentDateKey) ?? '';
      if (lastSentDate == today) return;

      // Son gönderimden 2 gün geçmedi mi?
      if (lastSentDate.isNotEmpty) {
        final last = DateTime.tryParse(lastSentDate);
        if (last != null && now.difference(last).inDays < 2) return;
      }

      // ── Kullanıcı abonelikleri ──────────────────────────────
      final subscribedMarketTopics   = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
      final subscribedCategoryTopics = (prefs.getStringList('subscribed_categories') ?? []).toSet();
      if (subscribedMarketTopics.isEmpty) return;

      // ── Firestore: market + kategori tabloları ──────────────
      final marketsSnap    = await FirebaseFirestore.instance.collection('markets').get();
      final categoriesSnap = await FirebaseFirestore.instance.collection('categories').get();

      final marketByTopic   = <String, String>{}; // topicKey → marketId
      final marketNameById  = <String, String>{}; // marketId → name
      for (final doc in marketsSnap.docs) {
        final d  = doc.data();
        final tk = d['topicKey'] as String? ?? doc.id;
        marketByTopic[tk]  = doc.id;
        marketNameById[doc.id] = d['name'] as String? ?? '';
      }

      final categoryByTopic   = <String, String>{}; // topicKey → categoryId
      final categoryNameById  = <String, String>{}; // categoryId → name
      for (final doc in categoriesSnap.docs) {
        final d  = doc.data();
        final tk = d['topicKey'] as String? ?? doc.id;
        categoryByTopic[tk]   = doc.id;
        categoryNameById[doc.id] = d['name'] as String? ?? '';
      }

      // Abone olunan market + kategori ID kümesi
      final subMarketIds    = <String>{};
      for (final tk in subscribedMarketTopics) {
        final id = marketByTopic[tk];
        if (id != null) subMarketIds.add(id);
      }
      final subCategoryIds = <String>{};
      for (final tk in subscribedCategoryTopics) {
        final id = categoryByTopic[tk];
        if (id != null) subCategoryIds.add(id);
      }
      if (subMarketIds.isEmpty) return;

      // ── Aktif kampanyaları çek ──────────────────────────────
      final todayStart = DateTime(now.year, now.month, now.day);
      final snap = await FirebaseFirestore.instance
          .collection('campaigns')
          .orderBy('endDate')
          .get();

      final matchedMarketIds   = <String>{};
      final matchedCategoryIds = <String>{};

      for (final doc in snap.docs) {
        final data     = doc.data();
        final endDate  = (data['endDate'] as Timestamp?)?.toDate();
        if (endDate == null) continue;
        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
        if (endDay.isBefore(todayStart)) continue; // süresi dolmuş

        final startDate = (data['startDate'] as Timestamp?)?.toDate();
        if (startDate != null && startDate.isAfter(now)) continue; // henüz başlamadı

        final marketId   = data['marketId']   as String? ?? '';
        final categoryId = data['categoryId'] as String? ?? '';

        // Market eşleşmesi
        if (!subMarketIds.contains(marketId)) continue;

        // Kategori filtresi: abone varsa eşleşmeli; abone yoksa market yeterli
        if (subCategoryIds.isNotEmpty && !subCategoryIds.contains(categoryId)) continue;

        if (marketId.isNotEmpty)   matchedMarketIds.add(marketId);
        if (categoryId.isNotEmpty) matchedCategoryIds.add(categoryId);
      }

      if (matchedMarketIds.isEmpty) return;

      // ── Mesaj oluştur ───────────────────────────────────────
      final marketNames   = matchedMarketIds
          .map((id) => marketNameById[id] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      final categoryNames = matchedCategoryIds
          .map((id) => categoryNameById[id] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final body = _buildMessage(marketNames, categoryNames);

      // ── 14:00'a planla ─────────────────────────────────────
      tzData.initializeTimeZones();
      final istanbul = tz.getLocation('Europe/Istanbul');
      var schedDt = tz.TZDateTime(istanbul, now.year, now.month, now.day, _notifHour, 0);
      final nowTz = tz.TZDateTime.from(now, istanbul);
      // 14:00 geçmişse yarın 14:00'a planla (ama bugünü kaydet ki ritim bozulmasın)
      if (schedDt.isBefore(nowTz)) {
        schedDt = tz.TZDateTime(istanbul, now.year, now.month, now.day + 1, _notifHour, 0);
      }

      await localNotifications.zonedSchedule(
        _notifId,
        '🛒 İndirim Kapısı',
        body,
        schedDt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'indirim_radari_channel',
            'İndirim Bildirimleri',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      // Bugünü kaydet
      await prefs.setString(_lastSentDateKey, today);
    } catch (_) {
      // Bildirim opsiyonel — hata sessizce geçilir
    }
  }

  // ── Sıcak + emoji'li mesaj şablonları ─────────────────────
  static String _buildMessage(List<String> markets, List<String> categories) {
    final rnd = Random();
    String pick(List<String> list) => list[rnd.nextInt(list.length)];

    final mStr = _joinNames(markets,   max: 3);
    final cStr = _joinNames(categories, max: 3);

    final hasCats = cStr.isNotEmpty;

    final templates = hasCats
        ? [
            '🔥 $mStr\'da $cStr indirimleri devam ediyor — kaçırma!',
            '💰 $mStr\'da $cStr kampanyaları sürüyor, hemen bak! 🛒',
            '🎉 Bu hafta $mStr\'da $cStr fırsatları var, sepetini doldur!',
            '🚀 $mStr\'dan $cStr indirimleri geldi — sen de kazan!',
            '⚡ $mStr\'da $cStr indirimlerini görmedin mi? Hemen incele! 🛍️',
            '🏷️ $cStr fırsatları $mStr\'da seni bekliyor — kaçırma! 🎁',
            '👀 $mStr\'da $cStr kampanyaları bitmeden yetiş!',
          ]
        : [
            '🔥 $mStr\'da indirimler devam ediyor — kaçırma! 🛒',
            '💰 $mStr kampanyaları sürüyor, hemen bak!',
            '🎉 $mStr\'da bu hafta harika fırsatlar var!',
            '🚀 $mStr\'dan yeni indirimler geldi — sen de kazan!',
            '⚡ $mStr\'da kampanyalar bitmeden yetiş! 🏷️',
            '👀 $mStr\'da takip ettiğin indirimler devam ediyor!',
          ];

    return pick(templates);
  }

  static String _joinNames(List<String> names, {int max = 3}) {
    if (names.isEmpty) return '';
    final limited = names.take(max).toList();
    if (limited.length == 1) return limited.first;
    final last  = limited.last;
    final rest  = limited.sublist(0, limited.length - 1);
    return '${rest.join(', ')} ve $last';
  }

  static String _dateStr(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
