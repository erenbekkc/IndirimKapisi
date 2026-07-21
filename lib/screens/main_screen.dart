import 'dart:io';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'favoriler_screen.dart';
import 'alarmlar_screen.dart';
import 'profil_screen.dart';
import 'hakkinda_screen.dart';
import 'ai_asistan_screen.dart';
import '../session_tracker.dart';
import '../services/announcement_service.dart';
import '../widgets/announcement_dialog.dart';
import '../services/ad_config_service.dart';
import '../services/interstitial_ad_service.dart';
import '../services/native_ad_pool.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAnnouncement());
    _initAds();
  }

  Future<void> _initAds() async {
    await AdConfigService.instance.load();
    // Native reklam havuzunu preload et — widget oluşunca hazır beklesin
    if (AdConfigService.instance.config.showNative) {
      NativeAdPool.instance.initialize();
    }
    InterstitialAdService.instance.startSession();
    InterstitialAdService.instance.load();
  }

  Future<void> _checkAnnouncement() async {
    final ann = await AnnouncementService.fetchIfShouldShow();
    if (ann == null || !mounted) return;
    AnnouncementService.logEvent(ann, 'shown');
    final tappedBtn = await showDialog<AnnouncementButton>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnnouncementDialog(data: ann),
    );
    if (tappedBtn == null) return;
    final event = tappedBtn.action == 'url' ? 'cta_tapped' : 'dismissed';
    AnnouncementService.logEvent(ann, event);
    if (tappedBtn.markSeen) {
      await AnnouncementService.markAsSeen(ann.id);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SessionTracker.instance.saveAndReset();
    } else if (state == AppLifecycleState.resumed) {
      SessionTracker.instance.startSession();
      InterstitialAdService.instance.tryShow(context, 'onAppResume');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          FavorilerScreen(),
          AlarmlarScreen(),
          ProfilScreen(),
          HakkindaScreen(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiAsistanScreen()),
          );
        },
        backgroundColor: const Color(0xFFDCFCE7),
        elevation: 4,
        child: ClipOval(
          child: Image.asset(
            'assets/agent.jpeg',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          InterstitialAdService.instance.tryShow(context, 'onTabSwitch');
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration:
            Platform.isIOS ? Duration.zero : const Duration(milliseconds: 500),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.door_front_door_outlined),
            selectedIcon: Icon(Icons.door_front_door),
            label: 'Kampanyalar',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favoriler',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_outlined),
            selectedIcon: Icon(Icons.local_fire_department),
            label: 'Alarmlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Bildirimler',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline_rounded),
            selectedIcon: Icon(Icons.info_rounded),
            label: 'Hakkında',
          ),
        ],
      ),
    );
  }
}
