import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'app_logger.dart';

/// Singleton — oturum süresini ve reklam sayısını takip eder.
///
/// Strateji:
///  • startSession() → SharedPreferences instance'ını cache'ler, önceki
///    oturumu Firestore'a gönderir, yeni oturumu başlatır.
///  • saveAndReset() → TAMAMEN SENKRON (await yok). Cache'li prefs üzerinden
///    anlık yazar; iOS arka plan kısıtlamalarından etkilenmez.
///  • _flushPending() → _keyEnd kaydedilmediyse oturumu atar (şişirilmiş
///    süre yazılmasını önler). Firestore yazımı başarısızsa key'ler korunur
///    ve bir sonraki açılışta tekrar denenir.
class SessionTracker {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  static const _keyStart     = 'st_session_start_ms';
  static const _keyEnd       = 'st_session_end_ms';
  static const _keyAds       = 'st_ads_watched';
  static const _keyCity      = 'st_city';
  static const _keyIsFirst   = 'st_is_first';
  static const _keyCityTs    = 'st_city_ts';
  static const _keyFirstDone = 'st_first_done';

  SharedPreferences? _prefs; // getInstance() sonrası cache'lenir
  int _adsThisSession = 0;

  // ── Uygulama açılınca çağrılır (soğuk başlatma + resume) ─────────────────
  void startSession() {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _prefs = prefs; // Artık saveAndReset() ve incrementAd() senkron çalışabilir

        // 1) Önceki oturumun bekleyen verisi varsa Firestore'a gönder
        await _flushPending(prefs);

        // 2) Şehri arka planda tazele (24 saatte bir)
        await _refreshCity(prefs);

        // 3) Yeni oturumu başlat
        final isFirst = prefs.getBool(_keyFirstDone) != true;
        prefs.setInt(_keyStart, DateTime.now().millisecondsSinceEpoch);
        prefs.setInt(_keyAds, 0);
        prefs.setBool(_keyIsFirst, isFirst);
        _adsThisSession = 0;
      } catch (e, s) {
        logError('SessionTracker.startSession', e, s);
      }
    });
  }

  // ── Reklam gösteriminde çağrılır ─────────────────────────────────────────
  void incrementAd() {
    _adsThisSession++;
    _prefs?.setInt(_keyAds, _adsThisSession); // Cache'li — await gereksiz
  }

  // ── Arka plana geçince çağrılır — TAMAMEN SENKRON, iOS safe ──────────────
  void saveAndReset() {
    final prefs = _prefs;
    if (prefs == null) return; // startSession henüz tamamlanmadı

    final startMs = prefs.getInt(_keyStart) ?? 0;
    if (startMs == 0) return;

    final endMs = DateTime.now().millisecondsSinceEpoch;
    final durationSecs = ((endMs - startMs) / 1000).round();

    if (durationSecs < 5) {
      prefs.remove(_keyStart);
      return;
    }

    // Senkron setInt — SharedPreferences bellek içi cache'e anında yazar,
    // disk flush'u OS tarafından yönetilir (NSUserDefaults / SharedPreferences).
    prefs.setInt(_keyEnd, endMs);
    prefs.setInt(_keyAds, _adsThisSession);
    _adsThisSession = 0;
  }

  // ── Bekleyen oturumu Firestore'a gönderir (uygulama aktifken) ────────────
  static Future<void> _flushPending(SharedPreferences prefs) async {
    final startMs = prefs.getInt(_keyStart) ?? 0;
    if (startMs == 0) return; // bekleyen yok

    final savedEnd = prefs.getInt(_keyEnd);

    // _keyEnd kaydedilmemişse (force-quit vb.) oturumu at.
    // DateTime.now() fallback kullanmak süresi şişiriyordu.
    if (savedEnd == null) {
      await prefs.remove(_keyStart);
      return;
    }

    final durationSecs = ((savedEnd - startMs) / 1000).round();

    // 5 saniyeden kısa veya 60 dakikadan uzun oturumları at.
    if (durationSecs < 5 || durationSecs > 3600) {
      await prefs.remove(_keyStart);
      await prefs.remove(_keyEnd);
      return;
    }

    final ads     = prefs.getInt(_keyAds) ?? 0;
    final city    = prefs.getString(_keyCity) ?? 'Bilinmiyor';
    final isFirst = prefs.getBool(_keyIsFirst) ?? false;
    final dateStr = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(startMs));
    final uid = prefs.getString('app_user_id');

    // Firestore yazımı başarılıysa key'leri sil, hata olursa bırak → retry.
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

    await prefs.remove(_keyStart);
    await prefs.remove(_keyEnd);

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
        prefs.setString(_keyCity, city);
        prefs.setInt(_keyCityTs, now);
      }
    } catch (_) {}
  }
}
