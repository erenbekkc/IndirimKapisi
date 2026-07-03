import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/smart_title_text.dart';
import '../widgets/image_lightbox.dart';

enum SonFirsatFilter { tumu, bugun, yarin, yuzotuzArti }

class AlarmlarScreen extends StatefulWidget {
  const AlarmlarScreen({super.key});

  @override
  State<AlarmlarScreen> createState() => _AlarmlarScreenState();
}

class _AlarmlarScreenState extends State<AlarmlarScreen> {
  SonFirsatFilter _filter = SonFirsatFilter.tumu;
  final Map<String, String?> _marketLogos      = {};
  final Map<String, String?> _marketLogosByName = {};
  final Map<String, String?> _categoryIcons    = {};
  final Map<String, String?> _categoryIconsByName = {};

  static const _green = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    final markets    = await FirebaseFirestore.instance.collection('markets').get();
    final categories = await FirebaseFirestore.instance.collection('categories').get();
    final mLogos     = <String, String?>{};
    final mByName    = <String, String?>{};
    for (final doc in markets.docs) {
      final d = doc.data();
      mLogos[doc.id] = d['logoUrl'] as String?;
      final n = (d['name'] as String? ?? '').toLowerCase();
      if (n.isNotEmpty) mByName[n] = d['logoUrl'] as String?;
    }
    final cIcons  = <String, String?>{};
    final cByName = <String, String?>{};
    for (final doc in categories.docs) {
      final d = doc.data();
      cIcons[doc.id] = d['iconUrl'] as String?;
      final n = (d['name'] as String? ?? '').toLowerCase();
      if (n.isNotEmpty) cByName[n] = d['iconUrl'] as String?;
    }
    if (mounted) setState(() {
      _marketLogos.addAll(mLogos);
      _marketLogosByName.addAll(mByName);
      _categoryIcons.addAll(cIcons);
      _categoryIconsByName.addAll(cByName);
    });
  }

  bool _isHighDiscount(Map<String, dynamic> data) {
    final type = data['campaignType'] as String?;
    if (type == 'priceDiscount') {
      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
      return oldP > 0 && (oldP - newP) / oldP >= 0.30;
    }
    if (type == 'buyOneGetOne') return true;
    if (type == 'secondDiscount') {
      return ((data['discountRate'] as num?)?.toDouble() ?? 0) >= 30;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Başlık ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  const Text('Alarmlar',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                ],
              ),
            ),

            // ── İçerik ───────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('campaigns')
                    .orderBy('endDate')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final now   = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final fmt   = NumberFormat('#,##0', 'tr_TR');
                  final dateFmt = DateFormat('dd MMM', 'tr_TR');

                  final allDocs = snapshot.data!.docs.where((d) {
                    final data      = d.data() as Map<String, dynamic>;
                    final endDate   = (data['endDate']   as Timestamp?)?.toDate();
                    final startDate = (data['startDate'] as Timestamp?)?.toDate();
                    if (endDate == null) return false;
                    final endDay  = DateTime(endDate.year, endDate.month, endDate.day);
                    if (endDay.isBefore(today)) return false;
                    final isActive = startDate == null || !startDate.isAfter(now);
                    final daysLeft = endDay.difference(today).inDays;
                    return isActive && daysLeft <= 1;
                  }).toList();

                  if (allDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 72, color: Colors.grey.shade200),
                          const SizedBox(height: 16),
                          const Text('Son fırsat yok',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54)),
                          const SizedBox(height: 8),
                          Text('Bugün veya yarın bitecek\nkampanya bulunmuyor.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade400)),
                        ],
                      ),
                    );
                  }

                  final todayCount = allDocs.where((d) {
                    final e = ((d.data() as Map)['endDate'] as Timestamp?)?.toDate();
                    if (e == null) return false;
                    return DateTime(e.year, e.month, e.day).difference(today).inDays == 0;
                  }).length;
                  final yarinCount = allDocs.where((d) {
                    final e = ((d.data() as Map)['endDate'] as Timestamp?)?.toDate();
                    if (e == null) return false;
                    return DateTime(e.year, e.month, e.day).difference(today).inDays == 1;
                  }).length;
                  final yuzotuzCount = allDocs
                      .where((d) => _isHighDiscount(d.data() as Map<String, dynamic>))
                      .length;

                  final totalSavings = allDocs.fold<double>(0.0, (sum, d) {
                    final data = d.data() as Map<String, dynamic>;
                    final type = data['campaignType'] as String?;
                    if (type == 'priceDiscount') {
                      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
                      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
                      return sum + (oldP - newP).clamp(0, double.infinity);
                    } else if (type == 'buyOneGetOne') {
                      return sum + ((data['productPrice'] as num?)?.toDouble() ?? 0);
                    } else if (type == 'secondDiscount') {
                      final rate  = (data['discountRate'] as num?)?.toDouble() ?? 0;
                      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
                      return sum + price * rate / 100;
                    }
                    return sum;
                  });

                  final filtered = allDocs.where((d) {
                    final data    = d.data() as Map<String, dynamic>;
                    final endDate = (data['endDate'] as Timestamp?)?.toDate()!;
                    final daysLeft = DateTime(endDate!.year, endDate.month, endDate.day)
                        .difference(today)
                        .inDays;
                    switch (_filter) {
                      case SonFirsatFilter.bugun:       return daysLeft == 0;
                      case SonFirsatFilter.yarin:       return daysLeft == 1;
                      case SonFirsatFilter.yuzotuzArti: return _isHighDiscount(data);
                      case SonFirsatFilter.tumu:        return true;
                    }
                  }).toList();

                  // 2 header items (banner + filter) + campaigns with ads
                  const headerCount = 2;
                  final baseCount = filtered.length + (filtered.length ~/ 5);
                  final campaignTotal = baseCount % 6 == 0 ? baseCount : baseCount + 1;
                  final totalCount = headerCount + campaignTotal;

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: totalCount,
                    separatorBuilder: (_, i) =>
                        i < headerCount - 1 ? const SizedBox(height: 0) : const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return _buildUrgencyBanner(allDocs.length, todayCount, totalSavings, fmt);
                      }
                      if (i == 1) {
                        return _buildFilterTabs(allDocs.length, todayCount, yarinCount, yuzotuzCount);
                      }
                      final ci = i - headerCount;
                      if (ci == campaignTotal - 1 && baseCount % 6 != 0) return const NativeAdWidget();
                      if ((ci + 1) % 6 == 0) return const NativeAdWidget();
                      final adCount = ci ~/ 6;
                      return _buildCard(filtered[ci - adCount], today, now, fmt, dateFmt);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Urgency Banner ────────────────────────────────────────────────────
  Widget _buildUrgencyBanner(int total, int todayCount, double totalSavings, NumberFormat fmt) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.30),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    children: const [
                      Positioned(top: 2,    left: 2,  child: Text('⚡', style: TextStyle(fontSize: 14))),
                      Positioned(top: 0,    right: 4, child: Text('⚡', style: TextStyle(fontSize: 11))),
                      Positioned(bottom: 4, left: 0,  child: Text('⚡', style: TextStyle(fontSize: 12))),
                      Positioned(bottom: 2, right: 2, child: Text('⚡', style: TextStyle(fontSize: 10))),
                      Center(child: Text('⏰', style: TextStyle(fontSize: 50, height: 1.0))),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$total fırsat',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('KAÇIRMAK ÜZERESİN!',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3)),
                      if (totalSavings > 0) ...[
                        const SizedBox(height: 5),
                        Text(
                          '💰 En az ${fmt.format(totalSavings)} TL indirim fırsatını kaçırmak üzeresin!',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 1.4),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (todayCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF991B1B),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(
                '🔥 $todayCount üründe indirim fırsatı bugün bitiyor',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // ── Filter Tabs ───────────────────────────────────────────────────────
  Widget _buildFilterTabs(int total, int bugun, int yarin, int yuzotuz) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterTab('Tümü ($total)', SonFirsatFilter.tumu),
            const SizedBox(width: 8),
            _filterTab('Bugün ($bugun)', SonFirsatFilter.bugun),
            const SizedBox(width: 8),
            _filterTab('Yarın ($yarin)', SonFirsatFilter.yarin),
            const SizedBox(width: 8),
            _filterTab('%30+ ($yuzotuz)', SonFirsatFilter.yuzotuzArti),
          ],
        ),
      ),
    );
  }

  Widget _filterTab(String label, SonFirsatFilter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _green : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _green : Colors.grey.shade200,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black54)),
      ),
    );
  }

  // ── Campaign Card ─────────────────────────────────────────────────────
  Widget _buildCard(
    QueryDocumentSnapshot doc,
    DateTime today,
    DateTime now,
    NumberFormat fmt,
    DateFormat dateFmt,
  ) {
    final data       = doc.data() as Map<String, dynamic>;
    final endDate    = (data['endDate'] as Timestamp?)?.toDate()!;
    final endDay     = DateTime(endDate!.year, endDate.month, endDate.day);
    final daysLeft   = endDay.difference(today).inDays;
    final imageUrl   = data['productImageUrl'] as String?;
    final marketId   = data['marketId']    as String? ?? '';
    final marketName = data['marketName']  as String? ?? '';
    final catId      = data['categoryId']  as String? ?? '';
    final catName    = data['categoryName'] as String? ?? '';

    final logoUrl   = _marketLogos[marketId] ?? _marketLogosByName[marketName.toLowerCase()];
    final catIconUrl = _categoryIcons[catId] ?? _categoryIconsByName[catName.toLowerCase()];

    final isToday = daysLeft == 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fotoğraf
            GestureDetector(
              onTap: (imageUrl != null && imageUrl.isNotEmpty)
                  ? () => showImageLightbox(context, imageUrl, 'alarm_${doc.id}')
                  : null,
              child: Hero(
                tag: 'alarm_${doc.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl,
                          width: 72, height: 72, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // İçerik
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Market + kategori
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
                        const Icon(Icons.store, size: 12, color: Colors.black45),
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
                                fontSize: 11, color: Colors.black45)),
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
                  const SizedBox(height: 6),

                  // Bitiş tarihi
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 11, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('Bitiş: ${dateFmt.format(endDate)}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Sağ sütun: kalp üstte, badge altta
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isToday ? const Color(0xFFDC2626) : Colors.orange.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alarm, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        isToday ? 'Bugün son!' : 'Yarın bitiyor!',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Price Section ─────────────────────────────────────────────────────
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
                      color: Colors.black38,
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
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('🔥 %$pct indirim',
                  style: const TextStyle(
                      fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );
    }

    if (type == 'buyOneGetOne') {
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('🔥 1 alana 1 bedava',
                style: TextStyle(
                    fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Text('${fmt.format(price * 2)} TL',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black38,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 6),
              Text('${fmt.format(price)} TL',
                  style: const TextStyle(
                      fontSize: 15, color: _green, fontWeight: FontWeight.bold)),
            ]),
          ],
        ],
      );
    }

    if (type == 'secondDiscount') {
      final rate  = (data['discountRate'] as num?)?.toDouble() ?? 0;
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20)),
            child: Text('🔥 1 alana 2. %${rate.toInt()} indirimli',
                style: const TextStyle(
                    fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Text('${fmt.format(price * 2)} TL',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black38,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 6),
              Text('${fmt.format(price + price * (1 - rate / 100))} TL',
                  style: const TextStyle(
                      fontSize: 15, color: _green, fontWeight: FontWeight.bold)),
            ]),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _placeholder() {
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 28),
    );
  }
}

// ── _FavoriteButton ───────────────────────────────────────────────────────
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
        vsync: this, duration: const Duration(milliseconds: 550));
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
    if (widget.isFav && !oldWidget.isFav) _controller.forward(from: 0);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

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
              size: 31,
              color: widget.isFav ? Colors.red.shade400 : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }
}
