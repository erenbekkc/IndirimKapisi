import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/native_ad_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum StatusFilter { all, active, upcoming }

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedMarketId;
  String? _selectedCategoryId;
  StatusFilter _statusFilter = StatusFilter.active;
  final Map<String, String?> _marketLogos = {};
  final Map<String, String?> _marketLogosByName = {};
  final Map<String, String> _marketCanonicalNames = {};
  final Map<String, String?> _categoryIcons = {};
  final Map<String, String?> _categoryIconsByName = {};

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _loadMarketLogos();
    _loadCategoryIcons();
  }

  Future<void> _setupNotifications() async {
    await FirebaseMessaging.instance.requestPermission();
    await FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all');
  }

  Future<void> _loadCategoryIcons() async {
    final snap = await FirebaseFirestore.instance.collection('categories').get();
    final icons = <String, String?>{};
    final iconsByName = <String, String?>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      icons[doc.id] = data['iconUrl'] as String?;
      final name = (data['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) iconsByName[name] = data['iconUrl'] as String?;
    }
    if (mounted) setState(() {
      _categoryIcons.addAll(icons);
      _categoryIconsByName.addAll(iconsByName);
    });
  }

  Future<void> _loadMarketLogos() async {
    final snap = await FirebaseFirestore.instance.collection('markets').get();
    final logos = <String, String?>{};
    final logosByName = <String, String?>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final logoUrl = data['logoUrl'] as String?;
      final canonicalName = data['name'] as String? ?? '';
      logos[doc.id] = logoUrl;
      final nameLower = canonicalName.toLowerCase();
      if (nameLower.isNotEmpty) {
        logosByName[nameLower] = logoUrl;
        _marketCanonicalNames[nameLower] = canonicalName;
      }
    }
    if (mounted) setState(() {
      _marketLogos.addAll(logos);
      _marketLogosByName.addAll(logosByName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildBanner(context),
              _buildMarketChips(),
              _buildCategoryChips(),
              Expanded(child: _buildCampaignList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
    return ClipRect(
      child: Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.width * 0.30,
          child: Image.asset(
            'assets/guncelustbanner.jpeg',
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 10,
          child: Row(
            children: [
              _buildStatusFilterPill(
                label: 'Aktif',
                dotColor: const Color(0xFF4ADE80),
                selected: _statusFilter == StatusFilter.active,
                onTap: () => setState(() => _statusFilter =
                    _statusFilter == StatusFilter.active
                        ? StatusFilter.all
                        : StatusFilter.active),
              ),
              const SizedBox(width: 6),
              _buildStatusFilterPill(
                label: 'Yakında',
                dotColor: const Color(0xFFFBBF24),
                selected: _statusFilter == StatusFilter.upcoming,
                onTap: () => setState(() => _statusFilter =
                    _statusFilter == StatusFilter.upcoming
                        ? StatusFilter.all
                        : StatusFilter.upcoming),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildMarketChips() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('markets').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 48);
        final docs = snapshot.data!.docs;
        return Container(
          color: const Color(0xFFF0FDF4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: 'Tüm Marketler',
                  selected: _selectedMarketId == null,
                  onTap: () => setState(() => _selectedMarketId = null),
                  color: const Color(0xFF2563EB),
                ),
                ...docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final logoUrl = data['logoUrl'] as String?;
                  return _marketChip(
                    label: doc.get('name') as String,
                    logoUrl: logoUrl,
                    selected: _selectedMarketId == doc.id,
                    onTap: () => setState(() =>
                      _selectedMarketId = _selectedMarketId == doc.id ? null : doc.id,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('categories').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 44);
        final docs = snapshot.data!.docs;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                offset: const Offset(0, 3),
                blurRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip(
                  label: 'Tüm Kategoriler',
                  selected: _selectedCategoryId == null,
                  onTap: () => setState(() => _selectedCategoryId = null),
                  color: const Color(0xFF7C3AED),
                ),
                ...docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final iconUrl = data['iconUrl'] as String?;
                  final name = data['name'] as String? ?? '';
                  return _categoryChip(
                    name: name,
                    iconUrl: iconUrl,
                    selected: _selectedCategoryId == doc.id,
                    onTap: () => setState(() =>
                      _selectedCategoryId = _selectedCategoryId == doc.id ? null : doc.id,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _categoryChip({
    required String name,
    String? iconUrl,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const color = Color(0xFF7C3AED);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconUrl != null && iconUrl.isNotEmpty) ...[
                ClipOval(
                  child: Image.network(
                    iconUrl,
                    width: 16,
                    height: 16,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.category,
                      size: 14,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marketChip({
    required String label,
    String? logoUrl,
    required bool selected,
    required VoidCallback onTap,
  }) {
    const color = Color(0xFF2563EB);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logoUrl != null && logoUrl.isNotEmpty) ...[
                ClipOval(
                  child: Image.network(
                    logoUrl,
                    width: 16,
                    height: 16,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.store,
                      size: 14,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilterPill({
    required String label,
    required Color dotColor,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.4),
            width: 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4, offset: const Offset(0, 2))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF16A34A) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCampaignList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('campaigns')
          .orderBy('endDate', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Hata oluştu'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final now = DateTime.now();
        var docs = snapshot.data!.docs;

        // Client-side filtreleme
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (_selectedMarketId != null && data['marketId'] != _selectedMarketId) return false;
          if (_selectedCategoryId != null && data['categoryId'] != _selectedCategoryId) return false;
          final startDate = (data['startDate'] as Timestamp?)?.toDate();
          final endDate = (data['endDate'] as Timestamp?)?.toDate();
          final today = DateTime(now.year, now.month, now.day);
          if (_statusFilter == StatusFilter.active) {
            if (endDate != null && endDate.isBefore(today)) return false;
            if (startDate != null && startDate.isAfter(now)) return false;
          } else if (_statusFilter == StatusFilter.upcoming) {
            if (startDate == null || !startDate.isAfter(now)) return false;
          } else {
            if (endDate != null && endDate.isBefore(today)) return false;
          }
          return true;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('Kampanya bulunamadı',
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                if (_selectedMarketId != null || _selectedCategoryId != null || _statusFilter != StatusFilter.all) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedMarketId = null;
                      _selectedCategoryId = null;
                      _statusFilter = StatusFilter.all;
                    }),
                    child: const Text('Filtreyi Temizle'),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
              child: Center(
                child: Text('${docs.length} Kampanya',
                    style: const TextStyle(fontSize: 15, color: Color(0xFF16A34A), fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                // Her 5 kampanyada 1 reklam eklenir
                itemCount: docs.length + (docs.length ~/ 5),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  // Her 6. eleman (index 5, 11, 17...) native reklam
                  if ((i + 1) % 6 == 0) {
                    return const NativeAdWidget();
                  }
                  // Reklam slotlarını sayarak gerçek kampanya indexini bul
                  final adCount = i ~/ 6;
                  final campaignIndex = i - adCount;
                  return _buildCampaignCard(docs[campaignIndex]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCampaignCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final dateFormat = DateFormat('dd MMM', 'tr_TR');
    final priceFormat = NumberFormat('#,##0.00', 'tr_TR');
    final startDate = (data['startDate'] as Timestamp?)?.toDate();
    final endDate = (data['endDate'] as Timestamp?)?.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isExpired = endDate != null && endDate.isBefore(today);
    final isUpcoming = startDate != null && startDate.isAfter(now);

    Color badgeColor;
    String badgeText;
    if (isExpired) {
      badgeColor = Colors.grey;
      badgeText = 'Bitti';
    } else if (isUpcoming) {
      badgeColor = Colors.orange;
      badgeText = 'Yakında';
    } else {
      badgeColor = const Color(0xFF16A34A);
      badgeText = 'Aktif';
    }

    final imageUrl = data['productImageUrl'] as String?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Text(
              data['product'] ?? data['title'] ?? '',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isExpired ? Colors.grey : null,
              ),
            ),
            if (data['campaignType'] == 'priceDiscount') ...[
              const SizedBox(height: 6),
              Builder(builder: (_) {
                final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
                final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
                final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${priceFormat.format(oldP)} TL',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${priceFormat.format(newP)} TL',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (!isExpired) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🔥 %$pct indirim',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              }),
            ],
            if (data['campaignType'] == 'buyOneGetOne' &&
                (data['productPrice'] as num?) != null &&
                (data['productPrice'] as num) > 0) ...[
              const SizedBox(height: 6),
              Builder(builder: (_) {
                final price = (data['productPrice'] as num).toDouble();
                final fullTotal = price * 2;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pill: 🔥 1 alana 1 bedava
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '🔥 1 alana 1 bedava',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('2 Ürün: ',
                            style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                        Text(
                          '${priceFormat.format(fullTotal)} TL',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${priceFormat.format(price)} TL',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ],
            if (data['campaignType'] == 'secondDiscount') ...[
              const SizedBox(height: 6),
              Builder(builder: (_) {
                final rate = (data['discountRate'] as num?)?.toDouble() ?? 0;
                final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
                if (price > 0 && rate > 0) {
                  final fullTotal = price * 2;
                  final discountedTotal = price + price * (1 - rate / 100);
                  final savings = fullTotal - discountedTotal;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pill: 🔥 1 alana 2. %X indirimli
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🔥 1 alana 2. %${rate.toInt()} indirimli',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('2 Ürün: ',
                              style: TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                          Text(
                            '${priceFormat.format(fullTotal)} TL',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${priceFormat.format(discountedTotal)} TL',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
                return Text(
                  '2. üründe %${rate.toInt()} indirim',
                  style: const TextStyle(fontSize: 13, color: Colors.deepOrange, fontWeight: FontWeight.w600),
                );
              }),
            ],
            if ((data['description'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                data['description'],
                style: TextStyle(
                    color: isExpired ? Colors.grey : Colors.grey.shade700, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMarketChipCard(
                  data['marketId'] as String? ?? '',
                  data['marketName'] as String? ?? '',
                ),
                const SizedBox(width: 8),
                _buildCategoryChipCard(
                  data['categoryId'] as String? ?? '',
                  data['categoryName'] as String? ?? '',
                ),
              ],
            ),
            if (startDate != null && endDate != null) ...[
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final today = DateTime(now.year, now.month, now.day);
                final endDay = DateTime(endDate.year, endDate.month, endDate.day);
                final diff = endDay.difference(today).inDays;
                if (!isExpired && diff == 0) {
                  return const Row(
                    children: [
                      Icon(Icons.hourglass_bottom, size: 14, color: Colors.red),
                      SizedBox(width: 4),
                      Text('Bugün son', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w600)),
                    ],
                  );
                } else if (!isExpired && diff == 1) {
                  return Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.orange.shade700),
                      const SizedBox(width: 4),
                      Text('Yarın bitiyor', style: TextStyle(fontSize: 13, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                    ],
                  );
                } else {
                  return Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isExpired ? Colors.grey : const Color(0xFF16A34A),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  );
                }
              }),
            ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Badge + Kalp yan yana
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                            color: badgeColor.withOpacity(0.75), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: FavoritesManager.notifier,
                      builder: (_, favIds, __) {
                        final isFav = favIds.contains(doc.id);
                        return _FavoriteButton(
                          isFav: isFav,
                          onTap: () => FavoritesManager.toggle(doc.id),
                        );
                      },
                    ),
                  ],
                ),
                if (imageUrl != null && imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => showImageLightbox(context, imageUrl, 'home_${doc.id}'),
                    child: Hero(
                      tag: 'home_${doc.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          width: 98,
                          height: 98,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : const SizedBox(
                                  width: 98,
                                  height: 98,
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketChipCard(String marketId, String marketName) {
    const color = Colors.grey;
    final logoUrl = _marketLogos[marketId] ?? _marketLogosByName[marketName.toLowerCase()];
    final displayName = _marketCanonicalNames[marketName.toLowerCase()] ?? marketName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl != null && logoUrl.isNotEmpty)
            ClipOval(
              child: Image.network(
                logoUrl,
                width: 14,
                height: 14,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.store, size: 12, color: Colors.grey),
              ),
            )
          else
            const Icon(Icons.store, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Text(displayName,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCategoryChipCard(String categoryId, String categoryName) {
    const color = Colors.grey;
    final iconUrl = _categoryIcons[categoryId] ??
        _categoryIconsByName[categoryName.toLowerCase()];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconUrl != null && iconUrl.isNotEmpty)
            ClipOval(
              child: Image.network(
                iconUrl,
                width: 12,
                height: 12,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.category, size: 12, color: Colors.grey),
              ),
            )
          else
            const Icon(Icons.category, size: 12, color: Colors.grey),
          const SizedBox(width: 4),
          Text(categoryName,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatefulWidget {
  final bool isFav;
  final VoidCallback onTap;

  const _FavoriteButton({required this.isFav, required this.onTap});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.6), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.6, end: 0.8), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.2), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFav && !oldWidget.isFav) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              widget.isFav ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(widget.isFav),
              size: 22,
              color: widget.isFav ? Colors.red.shade400 : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }
}
