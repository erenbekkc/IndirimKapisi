import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'favorites_manager.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart' show saveUserPrefsToFirestore;

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

String _personalMessage(String markets, String cats) {
  final rnd = Random();
  final hasMkt = markets.isNotEmpty;
  final hasCat = cats.isNotEmpty;

  if (hasMkt && hasCat) {
    final templates = [
      '🔥 $markets\'da $cats indirimleri devam ediyor — kaçırma! 🛒',
      '💰 $markets\'da $cats kampanyaları sürüyor, hemen bak! 🛍️',
      '🎉 $markets\'da $cats fırsatları seni bekliyor! Bir göz at!',
      '✨ $markets\'daki $cats indirimlerini gördün mü? 🎯',
      '🤑 $markets\'da $cats kampanyaları aktif — güzel tasarruf fırsatı!',
      '😍 $markets\'da $cats kampanyaları var, sepetini hazırla! 🛒',
    ];
    return templates[rnd.nextInt(templates.length)];
  } else if (hasMkt) {
    final templates = [
      '🔥 $markets\'da indirimler devam ediyor — kaçırma! 🛒',
      '💰 $markets kampanyaları sürüyor, hemen bak! 🛍️',
      '🎉 $markets\'da harika fırsatlar var, sepetini hazırla!',
      '✨ $markets\'daki kampanyaları gördün mü? Hemen bak! 🎯',
      '🤑 $markets\'da güzel indirimler — cebini koru! 💪',
      '😍 $markets\'da kampanyalar seni bekliyor, bir göz at! 🎁',
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

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
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

    // 2) Anonymous Auth — Firestore yazmaları için gerekli
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      FirebaseCrashlytics.instance.log('Anonymous auth failed: $e');
    }

    // 3) Analytics
    try {
      FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      FirebaseCrashlytics.instance.log('Analytics init failed: $e');
    }

    // 4) ATT (iOS) — AdMob'dan önce izin iste
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

    // 5) AdMob
    try {
      await MobileAds.instance.initialize();
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'MobileAds init');
    }

    // 6) Date formatting
    try {
      await initializeDateFormatting('tr_TR', null);
    } catch (e) {
      FirebaseCrashlytics.instance.log('DateFormatting init failed: $e');
    }

    // 7) FCM background handler
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      FirebaseCrashlytics.instance.log('FCM background handler failed: $e');
    }

    // 8) Local notifications
    try {
      await _initLocalNotifications();
    } catch (e, s) {
      _initError = 'LocalNotifications init FAILED:\n$e\n$s';
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'LocalNotifications init');
      runApp(_ErrorApp(_initError!));
      return;
    }

    // 9) Favorites
    try {
      await FavoritesManager.load();
    } catch (e) {
      FirebaseCrashlytics.instance.log('FavoritesManager.load failed: $e');
    }

    // 10) Android: izin + token kaydet + topic
    if (!Platform.isIOS) {
      Future(() async {
        try {
          await FirebaseMessaging.instance.requestPermission();
          final prefs      = await SharedPreferences.getInstance();
          final markets    = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
          final categories = (prefs.getStringList('subscribed_categories') ?? []).toSet();
          await saveUserPrefsToFirestore(markets: markets, categories: categories);
        } catch (_) {}
        FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all').catchError((_) {});
      });
    }

    // 11) iOS: önce APNS token bekle, sonra FCM token kaydet + topic
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
          final markets    = (prefs.getStringList('subscribed_markets')    ?? []).toSet();
          final categories = (prefs.getStringList('subscribed_categories') ?? []).toSet();
          await saveUserPrefsToFirestore(markets: markets, categories: categories);
        } catch (_) {}
        FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all').catchError((_) {});
      });
    }

    // App ön planda iken gelen data mesajını da işle
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'campaign_notif') {
        final body = await _buildPersonalizedBody(message.data);
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
        );
      } else if (message.notification != null) {
        final n = message.notification!;
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
        );
      }
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
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    });
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
