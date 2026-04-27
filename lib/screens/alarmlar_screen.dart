import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/image_lightbox.dart';

enum SonFirsatFilter { tumu, bugun, yarin, yuzotuzArti }

class AlarmlarScreen extends StatefulWidget {
  const AlarmlarScreen({super.key});

  @override
  State<AlarmlarScreen> createState() => _AlarmlarScreenState();
}

class _AlarmlarScreenState extends State<AlarmlarScreen> {
  SonFirsatFilter _filter = SonFirsatFilter.tumu;
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
      final data = doc.data();
      mLogos[doc.id] = data['logoUrl'] as String?;
      final name = (data['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) mLogosByName[name] = data['logoUrl'] as String?;
    }
    final cIcons = <String, String?>{};
    final cIconsByName = <String, String?>{};
    for (final doc in categories.docs) {
      final data = doc.data();
      cIcons[doc.id] = data['iconUrl'] as String?;
      final name = (data['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) cIconsByName[name] = data['iconUrl'] as String?;
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
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.local_fire_department, color: Colors.white),
          SizedBox(width: 8),
          Text('Alarmlar',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        backgroundColor: const Color(0xFF16A34A),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('campaigns')
            .orderBy('endDate')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final fmt = NumberFormat('#,##0.00', 'tr_TR');
          final dateFormat = DateFormat('dd MMM', 'tr_TR');

          // Sadece bugün ve yarın biten aktif kampanyalar
          final allDocs = snapshot.data!.docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final endDate = (data['endDate'] as Timestamp?)?.toDate();
            final startDate = (data['startDate'] as Timestamp?)?.toDate();
            if (endDate == null) return false;
            final endDay = DateTime(endDate.year, endDate.month, endDate.day);
            if (endDay.isBefore(today)) return false; // gün bazında karşılaştır
            final isActive = startDate == null || !startDate.isAfter(now);
            final daysLeft = endDay.difference(today).inDays;
            return isActive && daysLeft <= 1;
          }).toList();

          if (allDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department_outlined,
                      size: 72, color: Colors.grey.shade200),
                  const SizedBox(height: 16),
                  const Text('Son fırsat yok',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Text('Bugün veya yarın bitecek\nkampanya bulunmuyor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                ],
              ),
            );
          }

          final todayCount = allDocs.where((d) {
            final endDate = ((d.data() as Map)['endDate'] as Timestamp?)?.toDate();
            if (endDate == null) return false;
            return DateTime(endDate.year, endDate.month, endDate.day)
                    .difference(today)
                    .inDays ==
                0;
          }).length;
          final yarinCount = allDocs.where((d) {
            final endDate = ((d.data() as Map)['endDate'] as Timestamp?)?.toDate();
            if (endDate == null) return false;
            return DateTime(endDate.year, endDate.month, endDate.day)
                    .difference(today)
                    .inDays ==
                1;
          }).length;
          final yuzotuzCount = allDocs
              .where((d) => _isHighDiscount(d.data() as Map<String, dynamic>))
              .length;

          // Toplam potansiyel tasarruf hesabı
          final totalSavings = allDocs.fold<double>(0.0, (sum, d) {
            final data = d.data() as Map<String, dynamic>;
            final type = data['campaignType'] as String?;
            if (type == 'priceDiscount') {
              final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
              final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
              return sum + (oldP - newP).clamp(0, double.infinity);
            } else if (type == 'buyOneGetOne') {
              final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
              return sum + price;
            } else if (type == 'secondDiscount') {
              final rate = (data['discountRate'] as num?)?.toDouble() ?? 0;
              final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
              return sum + price * rate / 100;
            }
            return sum;
          });

          // Filtre uygula
          final filtered = allDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final endDate = (data['endDate'] as Timestamp?)?.toDate()!;
            final daysLeft = DateTime(endDate!.year, endDate.month, endDate.day)
                .difference(today)
                .inDays;
            switch (_filter) {
              case SonFirsatFilter.bugun:
                return daysLeft == 0;
              case SonFirsatFilter.yarin:
                return daysLeft == 1;
              case SonFirsatFilter.yuzotuzArti:
                return _isHighDiscount(data);
              case SonFirsatFilter.tumu:
                return true;
            }
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kırmızı banner
              _buildUrgencyBanner(allDocs.length, todayCount, totalSavings, fmt),
              // Filtre sekmeleri
              _buildFilterTabs(allDocs.length, todayCount, yarinCount, yuzotuzCount),
              // Liste
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('Bu filtrede kampanya yok',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: filtered.length + (filtered.length ~/ 5),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          if ((i + 1) % 6 == 0) return const NativeAdWidget();
                          final adCount = i ~/ 6;
                          return _buildCard(filtered[i - adCount], today, now, fmt, dateFormat);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(
    QueryDocumentSnapshot doc,
    DateTime today,
    DateTime now,
    NumberFormat fmt,
    DateFormat dateFormat,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final endDate = (data['endDate'] as Timestamp?)?.toDate()!;
    final endDay = DateTime(endDate!.year, endDate.month, endDate.day);
    final daysLeft = endDay.difference(today).inDays;
    final imageUrl = data['productImageUrl'] as String?;
    final marketId = data['marketId'] as String? ?? '';
    final marketName = data['marketName'] as String? ?? '';
    final categoryId = data['categoryId'] as String? ?? '';
    final categoryName = data['categoryName'] as String? ?? '';
    final marketLogo =
        _marketLogos[marketId] ?? _marketLogosByName[marketName.toLowerCase()];
    final categoryIcon =
        _categoryIcons[categoryId] ?? _categoryIconsByName[categoryName.toLowerCase()];

    final urgencyColor = daysLeft == 0 ? Colors.red : Colors.orange;
    final urgencyLabel = daysLeft == 0 ? 'Bugün son!' : 'Yarın bitiyor!';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                  borderRadius: BorderRadius.circular(8),
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? Image.network(imageUrl,
                          width: 56, height: 56, fit: BoxFit.cover,
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
                  Row(
                    children: [
                      _iconChip(marketLogo, Icons.store, marketName),
                      const SizedBox(width: 6),
                      _iconChip(categoryIcon, Icons.category, categoryName),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(data['product'] ?? data['title'] ?? '',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  _buildPriceSection(data, fmt),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('Bitiş: ${dateFormat.format(endDate)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Sağ: favori üstte, aciliyet badge altında
            Column(
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: urgencyColor.withOpacity(0.3)),
                  ),
                  child: Text(urgencyLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: urgencyColor,
                          fontWeight: FontWeight.w700)),
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
      final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${fmt.format(oldP)} TL',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 6),
              Text('${fmt.format(newP)} TL',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.deepOrange,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          if (pct > 0) ...[
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('🔥 %$pct indirim',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.deepOrange,
                      fontWeight: FontWeight.w600)),
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
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('🔥 1 alana 1 bedava',
                style: TextStyle(
                    fontSize: 11, color: Colors.deepOrange,
                    fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Text('2 Ürün: ',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
              Text('${fmt.format(price * 2)} TL',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 5),
              Text('${fmt.format(price)} TL',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.deepOrange,
                      fontWeight: FontWeight.bold)),
            ]),
          ],
        ],
      );
    }

    if (type == 'secondDiscount') {
      final rate = (data['discountRate'] as num?)?.toDouble() ?? 0;
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20)),
            child: Text('🔥 1 alana 2. %${rate.toInt()} indirimli',
                style: const TextStyle(
                    fontSize: 11, color: Colors.deepOrange,
                    fontWeight: FontWeight.w600)),
          ),
          if (price > 0) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Text('2 Ürün: ',
                  style: TextStyle(fontSize: 12, color: Colors.black87)),
              Text('${fmt.format(price * 2)} TL',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey,
                      decoration: TextDecoration.lineThrough)),
              const SizedBox(width: 5),
              Text('${fmt.format(price + price * (1 - rate / 100))} TL',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.deepOrange,
                      fontWeight: FontWeight.bold)),
            ]),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildUrgencyBanner(int total, int todayCount, double totalSavings, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⏰', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Kaçırmak Üzeresin!',
                    style: TextStyle(
                        color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$total fırsat',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (totalSavings > 0) ...[
            const SizedBox(height: 6),
            Text('💰 En az ${fmt.format(totalSavings)} TL indirim fırsatını kaçırmak üzeresin!',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
          if (todayCount > 0) ...[
            const SizedBox(height: 4),
            Text('🔥 $todayCount üründe indirim fırsatı bugün bitiyor',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterTabs(int total, int bugun, int yarin, int yuzotuz) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
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
            _filterTab('%30+ İndirim ($yuzotuz)', SonFirsatFilter.yuzotuzArti),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.red : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.red : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }

  Widget _iconChip(String? iconUrl, IconData fallback, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconUrl != null && iconUrl.isNotEmpty)
          ClipOval(
            child: Image.network(iconUrl,
                width: 14, height: 14, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(fallback, size: 12, color: Colors.grey.shade400)),
          )
        else
          Icon(fallback, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      width: 56, height: 56,
      color: Colors.grey.shade100,
      child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 24),
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
