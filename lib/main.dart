import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'favorites_manager.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart' show saveUserPrefsToFirestore, getOrCreateUserId;
import 'app_logger.dart';
import 'notification_logger.dart';
import 'session_tracker.dart';

final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();

// ────────────────────────────────────────────────────────────────
// Arka plan FCM handler — app kapalıyken de çalışır
// Cloud Function'dan gelen sessiz data mesajını alır,
// kullanıcının tercihlerine göre kişisel bildirim gösterir.
// ────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (message.data['type'] != 'campaign_notif') return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  final body = await _buildPersonalizedBody(message.data);

  final uid   = await getOrCreateUserId();
  final docId = await NotificationLogger.logSent(
    uid: uid, message: body, source: 'fcm_background',
  );

  await plugin.show(
    777,
    '🛒 İndirim Kapısı',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'indirim_radari_channel',
        'İndirim Bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: docId,
  );
}

// Kullanıcının SharedPreferences tercihleriyle eşleştirip mesaj üretir
Future<String> _buildPersonalizedBody(Map<String, dynamic> data) async {
  try {
    final prefs         = await SharedPreferences.getInstance();
    final subMarkets    = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
    final subCategories = (prefs.getStringList('subscribed_categories') ?? []).toSet();
    final total         = int.tryParse(data['total'] ?? '0') ?? 0;

    final List<dynamic> marketsRaw    = jsonDecode(data['markets']    ?? '[]');
    final List<dynamic> categoriesRaw = jsonDecode(data['categories'] ?? '[]');

    // Kullanıcının takip ettiği marketleri eşleştir
    final matchedMarkets = marketsRaw
        .where((m) => subMarkets.contains(m['id'] as String))
        .map((m) => m['name'] as String)
        .toList();

    // Kullanıcının takip ettiği kategorileri eşleştir
    final matchedCats = categoriesRaw
        .where((c) => subCategories.contains(c['id'] as String))
        .map((c) => c['name'] as String)
        .toList();

    final hasMarket = matchedMarkets.isNotEmpty;
    final hasCat    = matchedCats.isNotEmpty;

    if (hasMarket || hasCat) {
      // Kişisel mesaj — max 2 market, max 2 kategori
      final mStr = _joinMax2(matchedMarkets);
      final cStr = _joinMax2(matchedCats);
      return _personalMessage(mStr, cStr);
    } else {
      // Genel mesaj — tercih seçmemiş kullanıcılar
      return _generalMessage(total);
    }
  } catch (_) {
    return '🛒 Yeni indirim fırsatları seni bekliyor!';
  }
}

String _joinMax2(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names[0];
  return '${names[0]} ve ${names[1]}';
}

/// Türkçe ek uyumu: ismin son sesli harfine ve son harfin sertliğine göre
/// '-da/-de/-ta/-te' lokasyon ekini döner.
/// Birden fazla kelimede (ör. "BİM ve Migros") son kelimeye bakılır.
String _locativeSuffix(String name) {
  final lastWord = name.split(' ').last;
  final lastChar = lastWord.isNotEmpty ? lastWord[lastWord.length - 1] : '';

  // Rakamla bitiyorsa Türkçe okunuşuna göre ek
  const digitSuffixes = {
    '0': 'da',  // sıfır → ı
    '1': 'de',  // bir   → i
    '2': 'de',  // iki   → i
    '3': 'te',  // üç    → ü, sert
    '4': 'te',  // dört  → ö, sert
    '5': 'te',  // beş   → e, sert
    '6': 'ta',  // altı  → ı
    '7': 'de',  // yedi  → i
    '8': 'de',  // sekiz → i
    '9': 'da',  // dokuz → u
  };
  if (digitSuffixes.containsKey(lastChar)) return digitSuffixes[lastChar]!;

  const backVowels  = {'a', 'ı', 'o', 'u', 'A', 'I', 'O', 'U'};
  const frontVowels = {'e', 'i', 'ö', 'ü', 'E', 'İ', 'Ö', 'Ü'};
  const voiceless   = {'ç', 'f', 'h', 'k', 'p', 's', 'ş', 't',
                        'Ç', 'F', 'H', 'K', 'P', 'S', 'Ş', 'T'};

  bool isBack = true;
  for (int i = lastWord.length - 1; i >= 0; i--) {
    final ch = lastWord[i];
    if (backVowels.contains(ch))  { isBack = true;  break; }
    if (frontVowels.contains(ch)) { isBack = false; break; }
  }

  final isVoiceless = voiceless.contains(lastChar);
  if (isBack) return isVoiceless ? 'ta' : 'da';
  return isVoiceless ? 'te' : 'de';
}

String _personalMessage(String markets, String cats) {
  final rnd  = Random();
  final hasMkt = markets.isNotEmpty;
  final hasCat = cats.isNotEmpty;
  final mSuf = _locativeSuffix(markets); // ek uyumu: da/de/ta/te

  if (hasMkt && hasCat) {
    final templates = [
      '🔥 $markets\'$mSuf $cats indirimleri devam ediyor — kaçırma! 🛒',
      '💰 $markets\'$mSuf $cats kampanyaları sürüyor, hemen bak! 🛍️',
      '🎉 $markets\'$mSuf $cats fırsatları seni bekliyor! Bir göz at!',
      '✨ $markets\'${mSuf}ki $cats indirimlerini gördün mü? 🎯',
      '🤑 $markets\'$mSuf $cats kampanyaları aktif — güzel tasarruf fırsatı!',
      '😍 $markets\'$mSuf $cats kampanyaları var, sepetini hazırla! 🛒',
    ];
    return templates[rnd.nextInt(templates.length)];
  } else if (hasMkt) {
    final templates = [
      '🔥 $markets\'$mSuf indirimler devam ediyor — kaçırma! 🛒',
      '💰 $markets kampanyaları sürüyor, hemen bak! 🛍️',
      '🎉 $markets\'$mSuf harika fırsatlar var, sepetini hazırla!',
      '✨ $markets\'${mSuf}ki kampanyaları gördün mü? Hemen bak! 🎯',
      '🤑 $markets\'$mSuf güzel indirimler — cebini koru! 💪',
      '😍 $markets\'$mSuf kampanyalar seni bekliyor, bir göz at! 🎁',
    ];
    return templates[rnd.nextInt(templates.length)];
  } else {
    final templates = [
      '🔥 $cats kategorisinde indirimler devam ediyor — kaçırma! 🛒',
      '💰 $cats kampanyaları sürüyor, hemen bak! 🛍️',
      '🎉 $cats alanında fırsatlar seni bekliyor! Bir göz at!',
      '✨ $cats indirimlerini gördün mü? Hemen incele! 🎯',
      '🤑 $cats kategorisinde güzel kampanyalar aktif! 💪',
      '😍 $cats indirimlerini kaçırma, hemen bak! 🎁',
    ];
    return templates[rnd.nextInt(templates.length)];
  }
}

String _generalMessage(int total) {
  final rnd = Random();
  final templates = [
    '🔥 $total aktif kampanya seni bekliyor — hemen incele! 🛒',
    '💰 $total fırsat aktif! Alışveriş listeni hazırla 🛍️',
    '🎉 $total indirim şu an aktif, kaçırma! Hemen bak!',
    '✨ Harika fırsatlar var! $total kampanya seni bekliyor 🎯',
    '🤑 $total kampanya aktif — cebini koru, indirimlerini kaçırma! 💪',
    '🌟 Merhaba! $total harika kampanya var, bir göz atmaya değer 👀',
    '😍 $total indirim aktif! Sepetini güzelce doldur! 🛒',
  ];
  return templates[rnd.nextInt(templates.length)];
}

Future<void> _logAppOpen() async {
  try {
    final uid = await getOrCreateUserId();
    final platform = Platform.isIOS ? 'ios' : 'android';
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await FirebaseFirestore.instance.collection('daily_stats').doc(dateStr).set({
      '${platform}Opens':       FieldValue.increment(1),
      '${platform}UniqueUsers': FieldValue.arrayUnion([uid]),
      'date': dateStr,
    }, SetOptions(merge: true));
  } catch (e, s) {
    logError('_logAppOpen', e, s);
  }
}

Future<void> _logNotifClick() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await FirebaseFirestore.instance.collection('daily_stats').doc(dateStr).set({
      '${platform}NotifClicks': FieldValue.increment(1),
      'date': dateStr,
    }, SetOptions(merge: true));
  } catch (e, s) {
    logError('_logNotifClick', e, s);
  }
}

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: (response) {
      _logNotifClick();
      NotificationLogger.markClicked(response.payload);
    },
  );

  const androidChannel = AndroidNotificationChannel(
    'indirim_radari_channel',
    'İndirim Bildirimleri',
    description: 'Market kampanya bildirimleri',
    importance: Importance.high,
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    String? _initError;

    // 1) Firebase
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e, s) {
      _initError = 'Firebase.initializeApp FAILED:\n$e\n$s';
      runApp(_ErrorApp(_initError!));
      return;
    }

    // Crashlytics artık hazır
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // 2) Analytics
    try {
      FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      FirebaseCrashlytics.instance.log('Analytics init failed: $e');
    }

    // 3) FCM background handler — runApp öncesi kayıt edilmeli
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      FirebaseCrashlytics.instance.log('FCM background handler failed: $e');
    }

    // 4-8) Arka plan initleri — runApp'i bloke etme, paralelde çalıştır
    Future(() async {
      // ATT (iOS) — AdMob'dan önce izin iste
      if (Platform.isIOS) {
        try {
          final status = await AppTrackingTransparency.trackingAuthorizationStatus;
          if (status == TrackingStatus.notDetermined) {
            await Future.delayed(const Duration(milliseconds: 200));
            await AppTrackingTransparency.requestTrackingAuthorization();
          }
        } catch (e) {
          FirebaseCrashlytics.instance.log('ATT request failed: $e');
        }
      }

      // AdMob — ağır init, arka planda yapılır; SplashScreen'in 1 sn beklemesi yeterli
      try {
        await MobileAds.instance.initialize();
      } catch (e, s) {
        FirebaseCrashlytics.instance.recordError(e, s, reason: 'MobileAds init');
      }
    });

    // Date formatting + Notifications + Favorites — hızlı, paralelde çalıştır
    await Future.wait([
      initializeDateFormatting('tr_TR', null).catchError((e) {
        FirebaseCrashlytics.instance.log('DateFormatting init failed: $e');
      }),
      _initLocalNotifications().catchError((e, s) {
        FirebaseCrashlytics.instance.recordError(e, s, reason: 'LocalNotifications init');
      }),
      FavoritesManager.load().catchError((e) {
        FirebaseCrashlytics.instance.log('FavoritesManager.load failed: $e');
      }),
    ]);

    // 9) Android: izin + token kaydet + topic (sadece token değişmişse Firestore'a yaz)
    if (!Platform.isIOS) {
      Future(() async {
        try {
          await FirebaseMessaging.instance.requestPermission();
          final prefs      = await SharedPreferences.getInstance();
          final newToken   = await FirebaseMessaging.instance.getToken();
          final savedToken = prefs.getString('fcm_token_saved');
          if (newToken != null && newToken != savedToken) {
            final markets    = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
            final categories = (prefs.getStringList('subscribed_categories') ?? []).toSet();
            await saveUserPrefsToFirestore(markets: markets, categories: categories);
            await prefs.setString('fcm_token_saved', newToken);
          }
        } catch (e, s) {
          logError('startup_android_saveUserPrefs', e, s);
        }
        FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all').catchError((_) {});
      });
    }

    // 10) iOS: önce APNS token bekle, sonra FCM token kaydet + topic (sadece token değişmişse)
    if (Platform.isIOS) {
      Future(() async {
        try {
          await FirebaseMessaging.instance.requestPermission();
          // APNS token hazır olana kadar bekle (maks 30 sn)
          for (int i = 0; i < 30; i++) {
            final apns = await FirebaseMessaging.instance.getAPNSToken();
            if (apns != null) break;
            await Future.delayed(const Duration(seconds: 1));
          }
          // APNS hazır — FCM token artık geçerli
          final prefs      = await SharedPreferences.getInstance();
          final newToken   = await FirebaseMessaging.instance.getToken();
          final savedToken = prefs.getString('fcm_token_saved');
          if (newToken != null && newToken != savedToken) {
            final markets    = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
            final categories = (prefs.getStringList('subscribed_categories') ?? []).toSet();
            await saveUserPrefsToFirestore(markets: markets, categories: categories);
            await prefs.setString('fcm_token_saved', newToken);
          }
        } catch (e, s) {
          logError('startup_ios_saveUserPrefs', e, s);
        }
        FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all').catchError((_) {});
      });
    }

    // App ön planda iken gelen data mesajını da işle
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'campaign_notif') {
        final body  = await _buildPersonalizedBody(message.data);
        final uid   = await getOrCreateUserId();
        final docId = await NotificationLogger.logSent(
          uid: uid, message: body, source: 'fcm_foreground',
        );
        localNotifications.show(
          777,
          '🛒 İndirim Kapısı',
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'indirim_radari_channel',
              'İndirim Bildirimleri',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: docId,
        );
      } else if (message.notification != null) {
        final n     = message.notification!;
        final uid   = await getOrCreateUserId();
        final docId = await NotificationLogger.logSent(
          uid: uid,
          message: n.body ?? n.title ?? '',
          source: 'fcm_notification',
        );
        localNotifications.show(
          n.hashCode,
          n.title,
          n.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'indirim_radari_channel',
              'İndirim Bildirimleri',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: docId,
        );
      }
    });

    // Bildirime tıklama — arka planda iken
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _logNotifClick());
    // Bildirime tıklama — uygulama kapalıyken
    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) _logNotifClick();
    });

    runApp(const IndirimRadariApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp(this.message);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future(() => _logAppOpen());
    SessionTracker.instance.startSession();
    Future.delayed(const Duration(seconds: 1), () => _checkVersionAndNavigate());
  }

  Future<void> _checkVersionAndNavigate() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Image.asset('assets/acilis.jpeg', fit: BoxFit.cover),
      ),
    );
  }
}

class IndirimRadariApp extends StatelessWidget {
  const IndirimRadariApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'İndirim Kapısı',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('tr', 'TR'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16A34A),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16A34A),
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 1.5,
          margin: EdgeInsets.zero,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black26,
          indicatorColor: const Color(0xFFDCFCE7),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF16A34A),
              );
            }
            return const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF));
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF16A34A));
            }
            return const IconThemeData(color: Color(0xFF9CA3AF));
          }),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
