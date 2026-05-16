import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'app_logger.dart';

/// Singleton — oturum süresini ve reklam sayısını takip eder.
///
/// Strateji: arka plana geçince veriyi sadece SharedPreferences'a yazar
/// (disk yazımı — hızlı, asla kesilmez). Uygulama bir sonraki açılışında
/// bekleyen veriyi Firestore'a gönderir (uygulama aktifken → güvenli).
class SessionTracker {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  static const _keyStart   = 'st_session_start_ms';
  static const _keyAds     = 'st_ads_watched';
  static const _keyCity    = 'st_city';
  static const _keyIsFirst = 'st_is_first';
  static const _keyCityTs  = 'st_city_ts';
  static const _keyFirstDone = 'st_first_done';

  int _adsThisSession = 0;

  // ── Uygulama açılınca çağrılır (soğuk başlatma + resume) ─────────────────
  void startSession() {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();

        // 1) Önceki oturumun bekleyen verisi varsa Firestore'a gönder
        await _flushPending(prefs);

        // 2) Şehri arka planda tazele
        await _refreshCity(prefs);

        // 3) Yeni oturumu başlat — başlangıç zamanını diske kaydet
        final isFirst = prefs.getBool(_keyFirstDone) != true;
        await prefs.setInt(_keyStart, DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt(_keyAds, 0);
        await prefs.setBool(_keyIsFirst, isFirst);
        _adsThisSession = 0;
      } catch (e, s) {
        logError('SessionTracker.startSession', e, s);
      }
    });
  }

  // ── Reklam gösteriminde çağrılır ─────────────────────────────────────────
  void incrementAd() {
    _adsThisSession++;
    // SharedPreferences'a da yaz ki uygulama kill olursa kaybolmasın
    SharedPreferences.getInstance()
        .then((p) => p.setInt(_keyAds, _adsThisSession))
        .catchError((_) {});
  }

  // ── Arka plana geçince çağrılır — sadece disk yazımı, Firestore YOK ──────
  void saveAndReset() {
    // Async OLMAYAN kısım: sadece SharedPreferences'a yaz (mikrosaniye)
    SharedPreferences.getInstance().then((prefs) async {
      final startMs = prefs.getInt(_keyStart) ?? 0;
      if (startMs == 0) return;
      final durationSecs =
          ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000).round();
      if (durationSecs < 5) {
        await prefs.remove(_keyStart); // çok kısa — temizle
        return;
      }
      // Bitiş zamanını da kaydet ki sonraki açılışta hesaplayabilelim
      await prefs.setInt(_keyAds, _adsThisSession);
      // _keyStart zaten ayarlı — pending olarak bırak, flush açılışta olur
      _adsThisSession = 0;
    }).catchError((_) {});
  }

  // ── Bekleyen oturumu Firestore'a gönderir (uygulama aktifken) ────────────
  static Future<void> _flushPending(SharedPreferences prefs) async {
    final startMs = prefs.getInt(_keyStart) ?? 0;
    if (startMs == 0) return; // bekleyen yok

    final durationSecs =
        ((DateTime.now().millisecondsSinceEpoch - startMs) / 1000).round();
    final ads     = prefs.getInt(_keyAds) ?? 0;
    final city    = prefs.getString(_keyCity) ?? 'Bilinmiyor';
    final isFirst = prefs.getBool(_keyIsFirst) ?? false;
    final dateStr = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(startMs));

    // Bekleyen kaydı temizle (başarılı olsun ya da olmasın, tekrar yazma)
    await prefs.remove(_keyStart);

    if (durationSecs < 5) return;

    final uid = prefs.getString('app_user_id');

    await FirebaseFirestore.instance.collection('user-stats').add({
      'platform':               Platform.isIOS ? 'ios' : 'android',
      'isFirstOpen':            isFirst,
      'sessionDate':            dateStr,
      'sessionDurationSeconds': durationSecs,
      'adsWatched':             ads,
      'city':                   city,
      if (uid != null) 'uid':  uid,
      'createdAt':              FieldValue.serverTimestamp(),
    });

    // İlk açılış başarıyla kaydedildi
    if (isFirst) await prefs.setBool(_keyFirstDone, true);
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
        await prefs.setString(_keyCity, city);
        await prefs.setInt(_keyCityTs, now);
      }
    } catch (_) {}
  }
}
