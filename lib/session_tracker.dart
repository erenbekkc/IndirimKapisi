import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'app_logger.dart';

/// Singleton — oturum süresini ve reklam sayısını takip eder.
///
/// Strateji: uygulama arka plana geçince (paused) oturum süresi hesaplanır ve
/// Firestore'a direkt yazılır. Firestore offline persistence sayesinde await
/// gerekmez — veri diske yazılır, uygulama kapansa bile sonraki açılışta
/// sunucuya sync edilir. Böylece iOS arka plan kısıtlamaları sorun olmaz.
class SessionTracker {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  static const _keyStart     = 'st_session_start_ms';
  static const _keyCity      = 'st_city';
  static const _keyIsFirst   = 'st_is_first';
  static const _keyCityTs    = 'st_city_ts';
  static const _keyFirstDone = 'st_first_done';
  static const _keyAds       = 'st_ads_watched';

  SharedPreferences? _prefs;
  int _adsThisSession = 0;

  // ── Uygulama açılınca çağrılır (soğuk başlatma + resume) ─────────────────
  void startSession() {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _prefs = prefs;

        // Şehri arka planda tazele (24 saatte bir)
        await _refreshCity(prefs);

        // Yeni oturumu başlat
        final isFirst = prefs.getBool(_keyFirstDone) != true;
        prefs.setInt(_keyStart, DateTime.now().millisecondsSinceEpoch);
        prefs.setBool(_keyIsFirst, isFirst);
        prefs.setInt(_keyAds, 0);
        // İlk açılışı hemen işaretle (Firestore yazımını bekleme)
        if (isFirst) prefs.setBool(_keyFirstDone, true);
        _adsThisSession = 0;
      } catch (e, s) {
        logError('SessionTracker.startSession', e, s);
      }
    });
  }

  // ── Reklam gösteriminde çağrılır ─────────────────────────────────────────
  void incrementAd() {
    _adsThisSession++;
    _prefs?.setInt(_keyAds, _adsThisSession);
  }

  // ── Arka plana geçince çağrılır — direkt Firestore'a yazar ───────────────
  void saveAndReset() {
    final prefs = _prefs;
    if (prefs == null) return;

    final startMs = prefs.getInt(_keyStart) ?? 0;
    if (startMs == 0) return;

    final endMs       = DateTime.now().millisecondsSinceEpoch;
    final durationSecs = ((endMs - startMs) / 1000).round();

    // _keyStart'ı hemen temizle — çift kayıt engellemek için
    prefs.remove(_keyStart);

    if (durationSecs < 5 || durationSecs > 3600) return;

    final uid     = prefs.getString('app_user_id');
    final city    = prefs.getString(_keyCity) ?? 'Bilinmiyor';
    final isFirst = prefs.getBool(_keyIsFirst) ?? false;
    final dateStr = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(startMs));

    // await YOK — Firestore offline persistence diske yazar,
    // uygulama kapansa bile bir sonraki açılışta sunucuya sync eder.
    FirebaseFirestore.instance.collection('user-stats').add({
      'platform':               Platform.isIOS ? 'ios' : 'android',
      'isFirstOpen':            isFirst,
      'sessionDate':            dateStr,
      'sessionDurationSeconds': durationSecs,
      'adsWatched':             _adsThisSession,
      'city':                   city,
      if (uid != null) 'uid':  uid,
      'createdAt':              FieldValue.serverTimestamp(),
    });

    _adsThisSession = 0;
  }

  // ── Şehri IP'den çeker, 24 saat cache'ler ────────────────────────────────
  static Future<void> _refreshCity(SharedPreferences prefs) async {
    final cachedAt = prefs.getInt(_keyCityTs) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - cachedAt < 86400000 && prefs.containsKey(_keyCity)) return;

    try {
      final res = await http
          .get(Uri.parse('https://ipinfo.io/json'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final city = (data['city'] as String?) ?? 'Bilinmiyor';
        prefs.setString(_keyCity, city);
        prefs.setInt(_keyCityTs, now);
      }
    } catch (_) {}
  }
}
