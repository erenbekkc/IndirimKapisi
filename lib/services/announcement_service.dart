import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/settings_screen.dart' show getOrCreateUserId;

class AnnouncementData {
  final String id;
  final String title;
  final String message;
  final String type; // info | update | promo
  final String ctaText;
  final String? ctaUrl;
  final bool showOnce;

  const AnnouncementData({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.ctaText,
    this.ctaUrl,
    required this.showOnce,
  });
}

class AnnouncementService {
  static Future<AnnouncementData?> fetchIfShouldShow() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('announcement')
          .get();

      final data = doc.data();
      if (data == null) return null;

      final active = data['active'] as bool? ?? false;
      if (!active) return null;

      final id = data['id'] as String? ?? '';
      if (id.isEmpty) return null;

      // Tarih aralığı kontrolü
      final now = DateTime.now();
      final startDate = (data['startDate'] as Timestamp?)?.toDate();
      final endDate = (data['endDate'] as Timestamp?)?.toDate();
      if (startDate != null && now.isBefore(startDate)) return null;
      if (endDate != null && now.isAfter(endDate)) return null;

      // targetMaxBuild kontrolü (opsiyonel): sadece belirli build ve altına göster
      final targetMaxBuild = data['targetMaxBuild'] as int?;
      if (targetMaxBuild != null) {
        final info = await PackageInfo.fromPlatform();
        final currentBuild = int.tryParse(info.buildNumber) ?? 0;
        if (currentBuild > targetMaxBuild) return null;
      }

      // showOnce kontrolü
      final showOnce = data['showOnce'] as bool? ?? true;
      if (showOnce) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('seen_ann_$id') == true) return null;
      }

      return AnnouncementData(
        id: id,
        title: data['title'] as String? ?? '',
        message: data['message'] as String? ?? '',
        type: data['type'] as String? ?? 'info',
        ctaText: data['ctaText'] as String? ?? 'Tamam',
        ctaUrl: data['ctaUrl'] as String?,
        showOnce: showOnce,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> markAsSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_ann_$id', true);
  }

  /// event: 'shown' | 'cta_tapped' | 'dismissed'
  static Future<void> logEvent(AnnouncementData ann, String event) async {
    try {
      final uid = await getOrCreateUserId();
      await FirebaseFirestore.instance.collection('announcement-logs').add({
        'announcementId': ann.id,
        'title': ann.title,
        'type': ann.type,
        'event': event,
        'hasUrl': ann.ctaUrl != null,
        'uid': uid,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
