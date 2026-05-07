import 'dart:io';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'favoriler_screen.dart';
import 'alarmlar_screen.dart';
import 'profil_screen.dart';
import 'hakkinda_screen.dart';
import 'ai_asistan_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

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
        backgroundColor: Colors.transparent,
        elevation: 4,
        child: ClipOval(
          child: Image.asset(
            'assets/agent_gri.jpeg',
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: Platform.isIOS ? Duration.zero : const Duration(milliseconds: 500),
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
