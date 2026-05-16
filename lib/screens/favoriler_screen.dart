import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/native_ad_widget.dart';

enum FavFilter { tumu, aktif, yakinda }

class FavorilerScreen extends StatefulWidget {
  const FavorilerScreen({super.key});

  @override
  State<FavorilerScreen> createState() => _FavorilerScreenState();
}

class _FavorilerScreenState extends State<FavorilerScreen> {
  FavFilter _filter = FavFilter.tumu;
  final Map<String, String?> _marketLogos = {};
  final Map<String, String?> _marketLogosByName = {};
  final Map<String, String?> _categoryIcons = {};
  final Map<String, String?> _categoryIconsByName = {};

  @override
  void initState() {
    super.initState();
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    final markets = await FirebaseFirestore.instance.collection('markets').get();
    final categories = await FirebaseFirestore.instance.collection('categories').get();
    final mLogos = <String, String?>{};
    final mLogosByName = <String, String?>{};
    for (final doc in markets.docs) {
      final d = doc.data();
      mLogos[doc.id] = d['logoUrl'] as String?;
      final name = (d['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) mLogosByName[name] = d['logoUrl'] as String?;
    }
    final cIcons = <String, String?>{};
    final cIconsByName = <String, String?>{};
    for (final doc in categories.docs) {
      final d = doc.data();
      cIcons[doc.id] = d['iconUrl'] as String?;
      final name = (d['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) cIconsByName[name] = d['iconUrl'] as String?;
    }
    if (mounted) {
      setState(() {
        _marketLogos.addAll(mLogos);
        _marketLogosByName.addAll(mLogosByName);
        _categoryIcons.addAll(cIcons);
        _categoryIconsByName.addAll(cIconsByName);
      });
    }
  }

  double _calcSavings(Map<String, dynamic> data) {
    if (data['campaignType'] == 'priceDiscount') {
      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
      return oldP - newP;
    } else if (data['campaignType'] == 'buyOneGetOne') {
      return (data['productPrice'] as num?)?.toDouble() ?? 0;
    } else if (data['campaignType'] == 'secondDiscount') {
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      final rate = (data['discountRate'] as num?)?.toDouble() ?? 0;
      return price * rate / 100;
    }
    return 0;
  }

  Widget _buildPriceSection(Map<String, dynamic> data, NumberFormat fmt) {
    final type = data['campaignType'] as String?;

    if (type == 'priceDiscount') {
      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
      final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${fmt.format(oldP)} TL',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 6),
              Text('${fmt.format(newP)} TL',
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          if (pct > 0) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('🔥 %$pct indirim',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );
    }

    if (type == 'buyOneGetOne') {
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      final fullTotal = price * 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('🔥 1 alana 1 bedava',
                style: TextStyle(
                    fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Text('2 Ürün: ',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
                Text('${fmt.format(fullTotal)} TL',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 5),
                Text('${fmt.format(price)} TL',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      );
    }

    if (type == 'secondDiscount') {
      final rate = (data['discountRate'] as num?)?.toDouble() ?? 0;
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      final fullTotal = price * 2;
      final discountedTotal = price + price * (1 - rate / 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('🔥 1 alana 2. %${rate.toInt()} indirimli',
                style: const TextStyle(
                    fontSize: 11, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Text('2 Ürün: ',
                    style: TextStyle(fontSize: 12, color: Colors.black87)),
                Text('${fmt.format(fullTotal)} TL',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 5),
                Text('${fmt.format(discountedTotal)} TL',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesManager.notifier,
      builder: (context, favIds, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Row(children: [
              Icon(Icons.favorite, color: Colors.white),
              SizedBox(width: 8),
              Text('Favoriler',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            backgroundColor: const Color(0xFF16A34A),
          ),
          body: favIds.isEmpty
              ? _buildEmpty()
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('campaigns')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final priceFormat = NumberFormat('#,##0.00', 'tr_TR');

                    // Sadece favorileri al, bitenler hariç
                    final allFavDocs = snapshot.data!.docs.where((d) {
                      if (!favIds.contains(d.id)) return false;
                      final data = d.data() as Map<String, dynamic>;
                      final endDate = (data['endDate'] as Timestamp?)?.toDate();
                      if (endDate != null) {
                        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
                        if (endDay.isBefore(today)) return false;
                      }
                      return true;
                    }).toList()
                      ..sort((a, b) {
                        final aEnd = ((a.data() as Map)['endDate'] as Timestamp?)?.toDate();
                        final bEnd = ((b.data() as Map)['endDate'] as Timestamp?)?.toDate();
                        if (aEnd == null && bEnd == null) return 0;
                        if (aEnd == null) return 1;
                        if (bEnd == null) return -1;
                        return aEnd.compareTo(bEnd);
                      });

                    // Aktif / Yakında sayıları
                    final activeCount = allFavDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final start = (data['startDate'] as Timestamp?)?.toDate();
                      return start == null || !start.isAfter(now);
                    }).length;
                    final upcomingCount = allFavDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final start = (data['startDate'] as Timestamp?)?.toDate();
                      return start != null && start.isAfter(now);
                    }).length;

                    // Filtre uygula
                    final filtered = allFavDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final start = (data['startDate'] as Timestamp?)?.toDate();
                      if (_filter == FavFilter.aktif) {
                        return start == null || !start.isAfter(now);
                      } else if (_filter == FavFilter.yakinda) {
                        return start != null && start.isAfter(now);
                      }
                      return true; // tumu
                    }).toList();

                    // Toplam tasarruf
                    final totalSavings = allFavDocs.fold<double>(
                        0, (s, d) => s + _calcSavings(d.data() as Map<String, dynamic>));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tasarruf banner
                        if (totalSavings > 0)
                          _buildSavingsBanner(totalSavings, priceFormat),
                        // Filtre sekmeleri
                        _buildFilterTabs(allFavDocs.length, activeCount, upcomingCount),
                        // Liste
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Text('Bu filtrede kampanya yok',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                                  itemCount: () {
                                    final base = filtered.length + (filtered.length ~/ 5);
                                    return base % 6 == 0 ? base : base + 1;
                                  }(),
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) {
                                    final base = filtered.length + (filtered.length ~/ 5);
                                    final totalCount = base % 6 == 0 ? base : base + 1;
                                    if (i == totalCount - 1 && base % 6 != 0) return const NativeAdWidget();
                                    if ((i + 1) % 6 == 0) return const NativeAdWidget();
                                    final adCount = i ~/ 6;
                                    final idx = i - adCount;
                                    return _buildFavCard(filtered[idx], now, priceFormat);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_outline, size: 72, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          const Text('Henüz favorin yok',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black54)),
          const SizedBox(height: 8),
          Text('Kampanyalar ekranından kampanyalara ❤️ basarak\nburaya ekleyebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildSavingsBanner(double total, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('💰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Toplam tasarruf potansiyeli',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Text('${fmt.format(total)} TL',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int total, int active, int upcoming) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          _filterTab('Tümü ($total)', FavFilter.tumu),
          const SizedBox(width: 8),
          _filterTab('Aktif ($active)', FavFilter.aktif),
          const SizedBox(width: 8),
          _filterTab('Yakında ($upcoming)', FavFilter.yakinda),
        ],
      ),
    );
  }

  Widget _filterTab(String label, FavFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF16A34A) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF16A34A) : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }


  Widget _buildFavCard(DocumentSnapshot doc, DateTime now, NumberFormat fmt) {
    final data = doc.data() as Map<String, dynamic>;
    final imageUrl = data['productImageUrl'] as String?;
    final endDate = (data['endDate'] as Timestamp?)?.toDate();
    final startDate = (data['startDate'] as Timestamp?)?.toDate();
    final isUpcoming = startDate != null && startDate.isAfter(now);
    final endDay = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : null;
    final today = DateTime(now.year, now.month, now.day);
    final daysLeft = endDay?.difference(today).inDays;

    String timeLabel;
    Color timeColor;
    if (isUpcoming) {
      timeLabel = 'Yakında';
      timeColor = Colors.orange;
    } else if (daysLeft != null && daysLeft == 0) {
      timeLabel = 'Bugün son';
      timeColor = Colors.red;
    } else if (daysLeft != null && daysLeft <= 3) {
      timeLabel = '$daysLeft gün kaldı';
      timeColor = Colors.red;
    } else if (daysLeft != null) {
      timeLabel = '$daysLeft gün kaldı';
      timeColor = const Color(0xFF16A34A);
    } else {
      timeLabel = '';
      timeColor = Colors.grey;
    }

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail
            GestureDetector(
              onTap: (imageUrl != null && imageUrl.isNotEmpty)
                  ? () => showImageLightbox(context, imageUrl, 'fav_${doc.id}')
                  : null,
              child: Hero(
                tag: 'fav_${doc.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl,
                          width: 56, height: 56, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumbPlaceholder())
                      : _thumbPlaceholder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // İçerik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _iconChip(
                        _marketLogos[data['marketId'] as String? ?? ''] ??
                            _marketLogosByName[(data['marketName'] as String? ?? '').toLowerCase()],
                        Icons.store,
                        data['marketName'] as String? ?? '',
                      ),
                      const SizedBox(width: 6),
                      _iconChip(
                        _categoryIcons[data['categoryId'] as String? ?? ''] ??
                            _categoryIconsByName[(data['categoryName'] as String? ?? '').toLowerCase()],
                        Icons.category,
                        data['categoryName'] as String? ?? '',
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data['product'] ?? data['title'] ?? '',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  _buildPriceSection(data, fmt),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Sağ: gün + X
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (timeLabel.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 10, color: timeColor),
                      const SizedBox(width: 3),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 11, color: timeColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => FavoritesManager.toggle(doc.id),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, color: Colors.grey.shade400, size: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconChip(String? iconUrl, IconData fallback, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconUrl != null && iconUrl.isNotEmpty)
          ClipOval(
            child: Image.network(
              iconUrl,
              width: 13,
              height: 13,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(fallback, size: 12, color: Colors.grey.shade400),
            ),
          )
        else
          Icon(fallback, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 28),
    );
  }
}
