import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _normalizeTopicKey(String key) {
  const tr = 'şŞıİğĞüÜöÖçÇ';
  const en = 'sSiIgGuUoOcC';
  var s = key;
  for (var i = 0; i < tr.length; i++) {
    s = s.replaceAll(tr[i], en[i]);
  }
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  final Set<String> _subscribedMarkets = {};
  final Set<String> _subscribedCategories = {};
  bool _loading = true;
  bool _subscribingAll = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _subscribedMarkets.addAll(prefs.getStringList('subscribed_markets') ?? []);
      _subscribedCategories.addAll(prefs.getStringList('subscribed_categories') ?? []);
      _loading = false;
    });
  }

  Future<void> _ensureApnsToken() async {
    if (!Platform.isIOS) return;
    await FirebaseMessaging.instance.requestPermission();
    for (int i = 0; i < 15; i++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    throw Exception('APNS token alınamadı. Lütfen tekrar deneyin.');
  }

  Future<void> _safeSubscribe(String topic) async {
    for (int i = 0; i < 5; i++) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        return;
      } catch (_) {
        if (i == 4) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _safeUnsubscribe(String topic) async {
    for (int i = 0; i < 5; i++) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        return;
      } catch (_) {
        if (i == 4) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _subscribeAll() async {
    setState(() => _subscribingAll = true);
    try {
      await _ensureApnsToken();
      final prefs = await SharedPreferences.getInstance();
      final marketsSnap = await FirebaseFirestore.instance.collection('markets').get();
      final categoriesSnap = await FirebaseFirestore.instance.collection('categories').get();
      for (final doc in marketsSnap.docs) {
        final topicKey = doc.get('topicKey') as String? ?? doc.id;
        await _safeSubscribe('market_${_normalizeTopicKey(topicKey)}');
        _subscribedMarkets.add(topicKey);
      }
      await prefs.setStringList('subscribed_markets', _subscribedMarkets.toList());
      for (final doc in categoriesSnap.docs) {
        final topicKey = doc.get('topicKey') as String? ?? doc.id;
        await _safeSubscribe('category_${_normalizeTopicKey(topicKey)}');
        _subscribedCategories.add(topicKey);
      }
      await prefs.setStringList('subscribed_categories', _subscribedCategories.toList());
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm bildirimler açıldı!'), backgroundColor: Color(0xFF16A34A)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _subscribingAll = false);
    }
  }

  Future<void> _toggleMarket(String topicKey, bool subscribe) async {
    final prefs = await SharedPreferences.getInstance();
    final safeTopic = 'market_${_normalizeTopicKey(topicKey)}';
    try {
      await _ensureApnsToken();
      if (subscribe) {
        await _safeSubscribe(safeTopic);
        _subscribedMarkets.add(topicKey);
      } else {
        await _safeUnsubscribe(safeTopic);
        _subscribedMarkets.remove(topicKey);
      }
      await prefs.setStringList('subscribed_markets', _subscribedMarkets.toList());
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim ayarı değiştirilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleCategory(String topicKey, bool subscribe) async {
    final prefs = await SharedPreferences.getInstance();
    final safeTopic = 'category_${_normalizeTopicKey(topicKey)}';
    try {
      await _ensureApnsToken();
      if (subscribe) {
        await _safeSubscribe(safeTopic);
        _subscribedCategories.add(topicKey);
      } else {
        await _safeUnsubscribe(safeTopic);
        _subscribedCategories.remove(topicKey);
      }
      await prefs.setStringList('subscribed_categories', _subscribedCategories.toList());
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim ayarı değiştirilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.notifications_outlined, color: Colors.white),
          SizedBox(width: 8),
          Text('Bildirimler',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        backgroundColor: const Color(0xFF16A34A),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Marketler',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const Spacer(),
                      _subscribingAll
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16A34A)))
                          : TextButton(
                              onPressed: _subscribeAll,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                backgroundColor: const Color(0xFFDCFCE7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Tüm Bildirimleri Aç',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                            ),
                    ],
                  ),
                ),
                _buildMarketList(),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Kategoriler',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                _buildCategoryList(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Seçtiğiniz market veya kategorilerde kampanya başladığında bildirim alırsınız.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMarketList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('markets').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return Column(
          children: docs.map((doc) {
            final topicKey = doc.get('topicKey') as String? ?? doc.id;
            final data = doc.data() as Map<String, dynamic>;
            final logoUrl = data['logoUrl'] as String?;
            final isSubscribed = _subscribedMarkets.contains(topicKey);
            return SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor: const Color(0xFFDCEDFF),
                child: (logoUrl != null && logoUrl.isNotEmpty)
                    ? ClipOval(
                        child: Image.network(logoUrl,
                            width: 40, height: 40, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.store, color: Color(0xFF2563EB))),
                      )
                    : const Icon(Icons.store, color: Color(0xFF2563EB)),
              ),
              title: Text(doc.get('name')),
              subtitle: Text(
                isSubscribed ? 'Bildirim açık' : 'Bildirim kapalı',
                style: TextStyle(
                  color: isSubscribed ? const Color(0xFF16A34A) : Colors.grey,
                  fontSize: 12,
                ),
              ),
              value: isSubscribed,
              activeColor: const Color(0xFF16A34A),
              onChanged: (v) => _toggleMarket(topicKey, v),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildCategoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('categories').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return Column(
          children: docs.map((doc) {
            final topicKey = doc.get('topicKey') as String? ?? doc.id;
            final data = doc.data() as Map<String, dynamic>;
            final iconUrl = data['iconUrl'] as String?;
            final icon = data['icon'] as String? ?? '';
            final isSubscribed = _subscribedCategories.contains(topicKey);
            return SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor: const Color(0xFFF0FDF4),
                child: (iconUrl != null && iconUrl.isNotEmpty)
                    ? ClipOval(
                        child: Image.network(
                          iconUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => icon.isNotEmpty
                              ? Text(icon, style: const TextStyle(fontSize: 18))
                              : const Icon(Icons.category, color: Color(0xFF16A34A)),
                        ),
                      )
                    : icon.isNotEmpty
                        ? Text(icon, style: const TextStyle(fontSize: 18))
                        : const Icon(Icons.category, color: Color(0xFF16A34A)),
              ),
              title: Text(doc.get('name')),
              subtitle: Text(
                isSubscribed ? 'Bildirim açık' : 'Bildirim kapalı',
                style: TextStyle(
                  color: isSubscribed ? const Color(0xFF16A34A) : Colors.grey,
                  fontSize: 12,
                ),
              ),
              value: isSubscribed,
              activeColor: const Color(0xFF16A34A),
              onChanged: (v) => _toggleCategory(topicKey, v),
            );
          }).toList(),
        );
      },
    );
  }
}
