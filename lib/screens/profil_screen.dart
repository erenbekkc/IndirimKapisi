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

  Future<void> _toggleMarket(String topicKey, bool subscribe) async {
    final prefs = await SharedPreferences.getInstance();
    final safeTopic = 'market_${_normalizeTopicKey(topicKey)}';
    try {
      if (subscribe) {
        await FirebaseMessaging.instance.subscribeToTopic(safeTopic);
        _subscribedMarkets.add(topicKey);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(safeTopic);
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
      if (subscribe) {
        await FirebaseMessaging.instance.subscribeToTopic(safeTopic);
        _subscribedCategories.add(topicKey);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(safeTopic);
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Marketler',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
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
