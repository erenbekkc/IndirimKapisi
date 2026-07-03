import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../favourite_logger.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/smart_title_text.dart';

enum FavFilter { tumu, aktif, yakinda }

class FavorilerScreen extends StatefulWidget {
  const FavorilerScreen({super.key});

  @override
  State<FavorilerScreen> createState() => _FavorilerScreenState();
}

class _FavorilerScreenState extends State<FavorilerScreen> {
  FavFilter _filter = FavFilter.tumu;
  final Map<String, String?> _marketLogos    = {};
  final Map<String, String?> _marketLogosByName = {};
  final Map<String, String?> _categoryIcons  = {};
  final Map<String, String?> _categoryIconsByName = {};

  static const _green = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    _loadIcons();
    FavouriteLogger.updateExpired();
  }

  Future<void> _loadIcons() async {
    final markets    = await FirebaseFirestore.instance.collection('markets').get();
    final categories = await FirebaseFirestore.instance.collection('categories').get();
    final mLogos     = <String, String?>{};
    final mByName    = <String, String?>{};
    for (final doc in markets.docs) {
      final d = doc.data();
      mLogos[doc.id] = d['logoUrl'] as String?;
      final name = (d['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) mByName[name] = d['logoUrl'] as String?;
    }
    final cIcons  = <String, String?>{};
    final cByName = <String, String?>{};
    for (final doc in categories.docs) {
      final d = doc.data();
      cIcons[doc.id] = d['iconUrl'] as String?;
      final name = (d['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) cByName[name] = d['iconUrl'] as String?;
    }
    if (mounted) setState(() {
      _marketLogos.addAll(mLogos);
      _marketLogosByName.addAll(mByName);
      _categoryIcons.addAll(cIcons);
      _categoryIconsByName.addAll(cByName);
    });
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
      final rate  = (data['discountRate']  as num?)?.toDouble() ?? 0;
      return price * rate / 100;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesManager.notifier,
      builder: (context, favIds, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Başlık ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.favorite, color: _green, size: 26),
                      const SizedBox(width: 8),
                      const Text('Favoriler',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                    ],
                  ),
                ),

                // ── İçerik ───────────────────────────────────────────
                Expanded(
                  child: favIds.isEmpty
                      ? _buildEmpty()
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('campaigns')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final now   = DateTime.now();
                            final today = DateTime(now.year, now.month, now.day);
                            final fmt   = NumberFormat('#,##0.00', 'tr_TR');

                            final allFavDocs = snapshot.data!.docs.where((d) {
                              if (!favIds.contains(d.id)) return false;
                              final data = d.data() as Map<String, dynamic>;
                              final endDate =
                                  (data['endDate'] as Timestamp?)?.toDate();
                              if (endDate != null) {
                                final endDay = DateTime(
                                    endDate.year, endDate.month, endDate.day);
                                if (endDay.isBefore(today)) return false;
                              }
                              return true;
                            }).toList()
                              ..sort((a, b) {
                                final aEnd =
                                    ((a.data() as Map)['endDate'] as Timestamp?)
                                        ?.toDate();
                                final bEnd =
                                    ((b.data() as Map)['endDate'] as Timestamp?)
                                        ?.toDate();
                                if (aEnd == null && bEnd == null) return 0;
                                if (aEnd == null) return 1;
                                if (bEnd == null) return -1;
                                return aEnd.compareTo(bEnd);
                              });

                            final activeCount = allFavDocs.where((d) {
                              final start = ((d.data() as Map)['startDate']
                                      as Timestamp?)
                                  ?.toDate();
                              return start == null || !start.isAfter(now);
                            }).length;
                            final upcomingCount = allFavDocs.where((d) {
                              final start = ((d.data() as Map)['startDate']
                                      as Timestamp?)
                                  ?.toDate();
                              return start != null && start.isAfter(now);
                            }).length;

                            final filtered = allFavDocs.where((d) {
                              final start = ((d.data() as Map)['startDate']
                                      as Timestamp?)
                                  ?.toDate();
                              if (_filter == FavFilter.aktif) {
                                return start == null || !start.isAfter(now);
                              } else if (_filter == FavFilter.yakinda) {
                                return start != null && start.isAfter(now);
                              }
                              return true;
                            }).toList();

                            final totalSavings = allFavDocs.fold<double>(
                                0,
                                (s, d) => s +
                                    _calcSavings(
                                        d.data() as Map<String, dynamic>));

                            if (filtered.isEmpty) {
                              return Column(
                                children: [
                                  if (totalSavings > 0)
                                    _buildSavingsBanner(totalSavings, fmt),
                                  _buildFilterTabs(allFavDocs.length,
                                      activeCount, upcomingCount),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        'Bu filtrede kampanya yok',
                                        style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            final headerCount = totalSavings > 0 ? 2 : 1;
                            final base = filtered.length + (filtered.length ~/ 5);
                            final campaignTotal = base % 6 == 0 ? base : base + 1;
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: headerCount + campaignTotal,
                              separatorBuilder: (_, i) =>
                                  i < headerCount - 1
                                      ? const SizedBox(height: 0)
                                      : const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                if (i == 0) {
                                  return totalSavings > 0
                                      ? _buildSavingsBanner(totalSavings, fmt)
                                      : _buildFilterTabs(allFavDocs.length,
                                          activeCount, upcomingCount);
                                }
                                if (totalSavings > 0 && i == 1) {
                                  return _buildFilterTabs(allFavDocs.length,
                                      activeCount, upcomingCount);
                                }
                                final ci = i - headerCount;
                                if (ci == campaignTotal - 1 && base % 6 != 0)
                                  return const NativeAdWidget();
                                if ((ci + 1) % 6 == 0) return const NativeAdWidget();
                                final adCount = ci ~/ 6;
                                return _buildFavCard(
                                    filtered[ci - adCount], now, fmt);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
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
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          Text(
            'Kampanyalar ekranından kampanyalara ❤️ basarak\nburaya ekleyebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsBanner(double total, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D7A3B), Color(0xFF22C55E)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('💰', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Toplam tasarruf potansiyeli',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Text('${fmt.format(total)} TL',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Colors.white, size: 20),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int total, int active, int upcoming) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _green : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _green : Colors.grey.shade300, width: 1.2),
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
    final data     = doc.data() as Map<String, dynamic>;
    final imageUrl = data['productImageUrl'] as String?;
    final marketId = data['marketId']   as String? ?? '';
    final marketName = data['marketName'] as String? ?? '';
    final catId    = data['categoryId']  as String? ?? '';
    final catName  = data['categoryName'] as String? ?? '';

    final logoUrl   = _marketLogos[marketId] ?? _marketLogosByName[marketName.toLowerCase()];
    final catIconUrl = _categoryIcons[catId] ?? _categoryIconsByName[catName.toLowerCase()];

    final endDate   = (data['endDate']   as Timestamp?)?.toDate();
    final startDate = (data['startDate'] as Timestamp?)?.toDate();
    final isUpcoming = startDate != null && startDate.isAfter(now);
    final endDay = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : null;
    final today    = DateTime(now.year, now.month, now.day);
    final daysLeft = endDay?.difference(today).inDays;

    String timeLabel;
    Color  timeColor;
    if (isUpcoming) {
      timeLabel = 'Yakında';
      timeColor = Colors.orange;
    } else if (daysLeft != null && daysLeft == 0) {
      timeLabel = 'Bugün son';
      timeColor = _green;
    } else if (daysLeft != null && daysLeft <= 3) {
      timeLabel = '$daysLeft gün kaldı';
      timeColor = Colors.orange;
    } else if (daysLeft != null) {
      timeLabel = '$daysLeft gün kaldı';
      timeColor = _green;
    } else {
      timeLabel = '';
      timeColor = Colors.grey;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            GestureDetector(
              onTap: (imageUrl != null && imageUrl.isNotEmpty)
                  ? () => showImageLightbox(context, imageUrl, 'fav_${doc.id}')
                  : null,
              child: Hero(
                tag: 'fav_${doc.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
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
                  // Market + Kategori satırı
                  Row(
                    children: [
                      if (logoUrl != null && logoUrl.isNotEmpty) ...[
                        ClipOval(
                          child: Image.network(logoUrl,
                              width: 14, height: 14, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.store, size: 12)),
                        ),
                        const SizedBox(width: 4),
                      ] else ...[
                        const Icon(Icons.store, size: 12, color: Colors.black54),
                        const SizedBox(width: 4),
                      ],
                      Text(marketName,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                              fontWeight: FontWeight.w600)),
                      if (catName.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(Icons.circle,
                              size: 3, color: Colors.grey.shade400),
                        ),
                        if (catIconUrl != null && catIconUrl.isNotEmpty) ...[
                          ClipOval(
                            child: Image.network(catIconUrl,
                                width: 13, height: 13, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.category, size: 11)),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(catName,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Ürün adı
                  SmartTitleText(
                    data['product'] ?? data['title'] ?? '',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  const SizedBox(height: 6),

                  // Fiyat
                  _buildPriceSection(data, fmt),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Sağ sütun: tarih + X
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (timeLabel.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 11, color: timeColor),
                      const SizedBox(width: 3),
                      Text(timeLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: timeColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: () =>
                      FavoritesManager.toggle(doc.id, campaignData: data),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close,
                        color: Colors.grey.shade500, size: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection(Map<String, dynamic> data, NumberFormat fmt) {
    final type = data['campaignType'] as String?;

    if (type == 'priceDiscount') {
      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
      final pct  = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${fmt.format(oldP)} TL',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 8),
              Text('${fmt.format(newP)} TL',
                  style: const TextStyle(
                      fontSize: 15,
                      color: _green,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          if (pct > 0) ...[
            const SizedBox(height: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('🔥 %$pct indirim',
                  style: const TextStyle(
                      fontSize: 11,
                      color: _green,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );
    }

    if (type == 'buyOneGetOne') {
      final price    = (data['productPrice'] as num?)?.toDouble() ?? 0;
      final fullTotal = price * 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('🔥 1 alana 1 bedava',
                style: TextStyle(
                    fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${fmt.format(fullTotal)} TL',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
                Text('${fmt.format(price)} TL',
                    style: const TextStyle(
                        fontSize: 15,
                        color: _green,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      );
    }

    if (type == 'secondDiscount') {
      final rate          = (data['discountRate']  as num?)?.toDouble() ?? 0;
      final price         = (data['productPrice']  as num?)?.toDouble() ?? 0;
      final fullTotal     = price * 2;
      final discountedTotal = price + price * (1 - rate / 100);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('🔥 1 alana 2. %${rate.toInt()} indirimli',
                style: const TextStyle(
                    fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('${fmt.format(fullTotal)} TL',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 6),
                Text('${fmt.format(discountedTotal)} TL',
                    style: const TextStyle(
                        fontSize: 15,
                        color: _green,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 32),
    );
  }
}
