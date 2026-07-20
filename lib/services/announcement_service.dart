import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/settings_screen.dart' show getOrCreateUserId;

class AnnouncementButton {
  final String text;
  final String action;   // 'url' | 'dismiss'
  final String? urlAndroid;
  final String? urlIos;
  final bool markSeen;

  const AnnouncementButton({
    required this.text,
    required this.action,
    this.urlAndroid,
    this.urlIos,
    required this.markSeen,
  });

  String? get resolvedUrl => Platform.isIOS ? urlIos : urlAndroid;

  factory AnnouncementButton.fromMap(Map<String, dynamic> m) {
    return AnnouncementButton(
      text: m['text'] as String? ?? '',
      action: m['action'] as String? ?? 'dismiss',
      urlAndroid: m['urlAndroid'] as String?,
      urlIos: m['urlIos'] as String?,
      markSeen: m['markSeen'] as bool? ?? true,
    );
  }
}

class AnnouncementData {
  final String id;
  final String title;
  final String message;
  final String type; // info | update | promo
  final bool showOnce;
  final List<AnnouncementButton> buttons;

  const AnnouncementData({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.showOnce,
    required this.buttons,
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

      // targetMaxBuild kontrolü
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

      // Butonları parse et — yoksa tek "Tamam" butonu
      final rawButtons = data['buttons'] as List<dynamic>?;
      final buttons = rawButtons != null && rawButtons.isNotEmpty
          ? rawButtons
              .map((b) => AnnouncementButton.fromMap(b as Map<String, dynamic>))
              .toList()
          : [const AnnouncementButton(text: 'Tamam', action: 'dismiss', markSeen: true)];

      return AnnouncementData(
        id: id,
        title: data['title'] as String? ?? '',
        message: data['message'] as String? ?? '',
        type: data['type'] as String? ?? 'info',
        showOnce: showOnce,
        buttons: buttons,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> markAsSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_ann_$id', true);
  }

  static Future<void> logEvent(AnnouncementData ann, String event) async {
    try {
      final uid = await getOrCreateUserId();
      await FirebaseFirestore.instance.collection('announcement-logs').add({
        'announcementId': ann.id,
        'title': ann.title,
        'type': ann.type,
        'event': event,
        'uid': uid,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
