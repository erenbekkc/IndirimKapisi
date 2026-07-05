import 'dart:io';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'favoriler_screen.dart';
import 'alarmlar_screen.dart';
import 'profil_screen.dart';
import 'hakkinda_screen.dart';
import 'ai_asistan_screen.dart';
import '../session_tracker.dart';
import '../onboarding_tour.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final _fabKey    = GlobalKey();
  final _navBarKey = GlobalKey();
  OverlayEntry? _tourEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTour());
  }

  @override
  void dispose() {
    _tourEntry?.remove();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _maybeStartTour() async {
    if (!await OnboardingTour.shouldShow()) return;
    if (!mounted) return;
    _showTour();
  }

  void _showTour() {
    final steps = [
      // 1 ── Karşılama
      const TourStep(
        title: 'İndirim Kapısı\'na Hoş Geldiniz! 🎉',
        description:
            'Size en iyi indirimleri ve kampanyaları bulmanıza yardımcı olacak kısa bir tur sunuyoruz. Hazır mısınız?',
        goToTab: 0,
      ),

      // 2 ── Kampanya listesi
      TourStep(
        key: HomeScreen.campaignListKey,
        title: '🛒 Kampanyalar',
        description:
            'Güncel indirim ve kampanyaları buradan takip edin. Her gün güncellenen fırsatlar sizi bekliyor!',
        goToTab: 0,
      ),

      // 3 ── Filtre çubukları
      TourStep(
        key: HomeScreen.filterBarKey,
        title: '🔍 Filtreleyin',
        description:
            'Market ve kategoriye göre filtreleyin. Yalnızca takip ettiğiniz marketlerin kampanyalarını görün.',
        goToTab: 0,
        spotPadding: 6,
      ),

      // 4 ── Bildirimler sekmesi
      TourStep(
        key: _navBarKey,
        title: '🔔 Bildirimler',
        description:
            'Hangi market ve kategorileri takip ettiğinizi buradan seçin. Her gün size özel indirim bildirimi alın, fırsatları kaçırmayın!',
        goToTab: 3,
        spotPadding: 4,
      ),

      // 5 ── Favoriler sekmesi
      TourStep(
        key: _navBarKey,
        title: '❤️ Favoriler',
        description:
            'Kampanya kartlarındaki kalp ikonuna dokunarak favorilere ekleyin. Toplam tasarruf potansiyelinizi Favoriler sekmesinde görün!',
        goToTab: 1,
        spotPadding: 4,
      ),

      // 6 ── AI asistan FAB
      TourStep(
        key: _fabKey,
        title: '🤖 Yapay Zeka Asistanı',
        description:
            'Robot butonuna dokunun ya da arama çubuğunu kullanın. "BİM\'de bu hafta ne var?" gibi sorular sorabilirsiniz. İyi alışverişler! 🎉',
        goToTab: 0,
      ),
    ];

    _tourEntry = OverlayEntry(
      builder: (_) => TourOverlay(
        steps: steps,
        onChangeTab: (tab) {
          if (mounted) setState(() => _currentIndex = tab);
        },
        onDone: () {
          _tourEntry?.remove();
          _tourEntry = null;
        },
      ),
    );

    Overlay.of(context).insert(_tourEntry!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SessionTracker.instance.saveAndReset();
    } else if (state == AppLifecycleState.resumed) {
      SessionTracker.instance.startSession();
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
        key: _fabKey,
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
        key: _navBarKey,
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
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
