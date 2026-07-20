import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'ai_asistan_screen.dart';
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/native_ad_widget.dart';
import '../widgets/smart_title_text.dart';
import '../remote_config_service.dart';

class HomeScreen extends StatefulWidget {

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedMarketId;
  String? _selectedCategoryId;
  String _sortMode = 'popular'; // 'ending' | 'popular' | 'newest'

  final TextEditingController _searchController = TextEditingController();

  // Market & category data (loaded once)
  List<QueryDocumentSnapshot> _marketDocs = [];
  List<QueryDocumentSnapshot> _categoryDocs = [];
  final Map<String, String?> _marketLogos = {};
  final Map<String, String?> _marketLogosByName = {};
  final Map<String, String> _marketCanonicalNames = {};
  final Map<String, String?> _categoryIcons = {};
  final Map<String, String?> _categoryIconsByName = {};

  // Campaign stream
  List<DocumentSnapshot> _allCampaignDocs = [];
  StreamSubscription? _campaignSub;

  final _priceFmt = NumberFormat('#,##0.00', 'tr_TR');
  final _dateFmt  = DateFormat('dd MMM', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _setupNotifications();
    _loadMarkets();
    _loadCategories();
    _subscribeCampaigns();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _campaignSub?.cancel();
    super.dispose();
  }

  Future<void> _setupNotifications() async {
    if (!Platform.isIOS) {
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.subscribeToTopic('indirim_radari_all');
    }
  }

  Future<void> _loadMarkets() async {
    final snap = await FirebaseFirestore.instance.collection('markets').orderBy('name').get();
    final logos = <String, String?>{};
    final logosByName = <String, String?>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final logoUrl = data['logoUrl'] as String?;
      final name    = data['name'] as String? ?? '';
      logos[doc.id] = logoUrl;
      final key = name.toLowerCase();
      if (key.isNotEmpty) {
        logosByName[key] = logoUrl;
        _marketCanonicalNames[key] = name;
      }
    }
    if (mounted) setState(() {
      _marketDocs = snap.docs;
      _marketLogos.addAll(logos);
      _marketLogosByName.addAll(logosByName);
    });
  }

  Future<void> _loadCategories() async {
    final snap = await FirebaseFirestore.instance.collection('categories').orderBy('name').get();
    final icons = <String, String?>{};
    final iconsByName = <String, String?>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      icons[doc.id] = data['iconUrl'] as String?;
      final name = (data['name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) iconsByName[name] = data['iconUrl'] as String?;
    }
    if (mounted) setState(() {
      _categoryDocs = snap.docs;
      _categoryIcons.addAll(icons);
      _categoryIconsByName.addAll(iconsByName);
    });
  }

  void _subscribeCampaigns() {
    _campaignSub = FirebaseFirestore.instance
        .collection('campaigns')
        .orderBy('endDate')
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _allCampaignDocs = snap.docs);
    });
  }

  List<DocumentSnapshot> get _filteredCampaigns {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var docs = _allCampaignDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final endDate = (data['endDate'] as Timestamp?)?.toDate();
      if (endDate != null) {
        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
        if (endDay.isBefore(today)) return false;
      }
      if (_selectedMarketId != null && data['marketId'] != _selectedMarketId) return false;
      if (_selectedCategoryId != null && data['categoryId'] != _selectedCategoryId) return false;
      return true;
    }).toList();

    if (_sortMode == 'popular') {
      docs.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        final pa = _sortPriority(da);
        final pb = _sortPriority(db);
        if (pa != pb) return pa.compareTo(pb);
        return _discountPct(db).compareTo(_discountPct(da));
      });
    } else if (_sortMode == 'newest') {
      docs.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;
        final sa = (da['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final sb = (db['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return sb.compareTo(sa);
      });
    }
    // 'ending' is default order from Firestore

    return docs;
  }

  // Sıralama önceliği: 1=buyOneGetOne, 2=secondDiscount, 3=priceDiscount
  int _sortPriority(Map<String, dynamic> data) {
    final type = data['campaignType'] as String? ?? '';
    if (type == 'buyOneGetOne') return 1;
    if (type == 'secondDiscount') return 2;
    return 3;
  }

  int _discountPct(Map<String, dynamic> data) {
    final type = data['campaignType'] as String? ?? '';
    if (type == 'buyOneGetOne') return 100;
    if (type == 'secondDiscount') return (data['discountRate'] as num?)?.toInt() ?? 0;
    final old = (data['oldPrice'] as num?)?.toDouble() ?? 0;
    final neu = (data['newPrice'] as num?)?.toDouble() ?? 0;
    if (old > 0 && neu > 0) return ((old - neu) / old * 100).round();
    return 0;
  }

  // ── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Center(child: BannerAdWidget()),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildAiSection()),
                    SliverToBoxAdapter(child: _buildMarketsSection()),
                    SliverToBoxAdapter(child: _buildCategoriesSection()),
                    SliverToBoxAdapter(child: _buildCampaignHeader()),
                    _buildCampaignSliver(),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI SECTION ────────────────────────────────────────────────────

  Widget _buildAiSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.send,
              onSubmitted: _openAiWith,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Örn: En ucuz süt hangisinde?',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.auto_awesome, color: Color(0xFF16A34A), size: 18),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openAiWith(String query) {
    _searchController.clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiAsistanScreen(initialQuery: query.trim().isEmpty ? null : query.trim()),
      ),
    );
  }

  // ── MARKETS SECTION ───────────────────────────────────────────────

  Widget _buildMarketsSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('Marketler',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _buildMarketCard(
                  id: null,
                  name: 'Tümü',
                  logoUrl: null,
                  selected: _selectedMarketId == null,
                  isAll: true,
                ),
                ..._marketDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildMarketCard(
                    id: doc.id,
                    name: data['name'] as String? ?? '',
                    logoUrl: data['logoUrl'] as String?,
                    selected: _selectedMarketId == doc.id,
                    isAll: false,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketCard({
    required String? id,
    required String name,
    required String? logoUrl,
    required bool selected,
    required bool isAll,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _selectedMarketId = id == _selectedMarketId ? null : id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 64,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFECFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF16A34A) : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isAll)
              Icon(
                Icons.shopping_basket_rounded,
                size: 24,
                color: selected ? const Color(0xFF16A34A) : Colors.grey.shade400,
              )
            else if (logoUrl != null && logoUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  logoUrl,
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.store, size: 24, color: Colors.grey.shade400),
                ),
              )
            else
              Icon(Icons.store, size: 24, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? const Color(0xFF16A34A) : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CATEGORIES SECTION ────────────────────────────────────────────

  Widget _buildCategoriesSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('Kategoriler',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                // Tüm Kategoriler kartı
                GestureDetector(
                  onTap: () => setState(() => _selectedCategoryId = null),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 64,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _selectedCategoryId == null ? const Color(0xFFECFDF5) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedCategoryId == null ? const Color(0xFF16A34A) : Colors.grey.shade200,
                        width: _selectedCategoryId == null ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.grid_view_rounded, size: 24,
                            color: _selectedCategoryId == null ? const Color(0xFF16A34A) : Colors.grey.shade400),
                        const SizedBox(height: 3),
                        Text('Tümü',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: _selectedCategoryId == null ? FontWeight.w600 : FontWeight.normal,
                              color: _selectedCategoryId == null ? const Color(0xFF16A34A) : Colors.black54,
                            )),
                      ],
                    ),
                  ),
                ),
                ..._categoryDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name    = data['name'] as String? ?? '';
                final iconUrl = data['iconUrl'] as String?;
                final selected = _selectedCategoryId == doc.id;
                return GestureDetector(
                  onTap: () => setState(() =>
                    _selectedCategoryId = _selectedCategoryId == doc.id ? null : doc.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 64,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFECFDF5) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? const Color(0xFF16A34A) : Colors.grey.shade200,
                        width: selected ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (iconUrl != null && iconUrl.isNotEmpty)
                          Image.network(
                            iconUrl,
                            width: 28,
                            height: 28,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.category, size: 22, color: Colors.grey.shade400),
                          )
                        else
                          Icon(Icons.category, size: 22, color: Colors.grey.shade400),
                        const SizedBox(height: 3),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected ? const Color(0xFF16A34A) : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── CAMPAIGN HEADER ───────────────────────────────────────────────

  Widget _buildCampaignHeader() {
    final count = _filteredCampaigns.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('🔥', style: TextStyle(fontSize: 15)),
                    SizedBox(width: 4),
                    Text('Sana özel en iyi fırsatlar',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  ],
                ),
                const SizedBox(height: 2),
                Text('$count kampanya bulundu',
                    style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
          _buildSortButton(),
        ],
      ),
    );
  }

  Widget _buildSortButton() {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sıralama', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...['ending', 'popular', 'newest'].map((mode) {
                  final modeLabels = {'ending': 'Bitiş Tarihi', 'popular': 'En Avantajlı', 'newest': 'En Yeni'};
                  final selected = _sortMode == mode;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(modeLabels[mode]!),
                    trailing: selected ? const Icon(Icons.check, color: Color(0xFF16A34A)) : null,
                    onTap: () {
                      setState(() => _sortMode = mode);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              {'ending': 'Bitiş', 'popular': 'En Avantajlı', 'newest': 'En Yeni'}[_sortMode]!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  // ── CAMPAIGN SLIVER ───────────────────────────────────────────────

  Widget _buildCampaignSliver() {
    final docs = _filteredCampaigns;

    if (_allCampaignDocs.isEmpty) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (docs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 56, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              const Text('Kampanya bulunamadı', style: TextStyle(color: Colors.grey, fontSize: 15)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _selectedMarketId = null;
                  _selectedCategoryId = null;
                }),
                child: const Text('Filtreyi Temizle', style: TextStyle(color: Color(0xFF16A34A))),
              ),
            ],
          ),
        ),
      );
    }

    // Interleave ads every 6 items
    final totalItems = docs.length + (docs.length ~/ 6);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            // Remote Config'den gelen sıklıkta reklam kartı göster
            final freq = RemoteConfigService.instance.adFrequency;
            final slot = freq + 1;
            if ((i + 1) % slot == 0) return const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: NativeAdWidget(),
            );
            final adsBefore = i ~/ slot;
            final campaignIndex = i - adsBefore;
            if (campaignIndex >= docs.length) return null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCampaignCard(docs[campaignIndex]),
            );
          },
          childCount: totalItems,
        ),
      ),
    );
  }

  // ── CAMPAIGN CARD ─────────────────────────────────────────────────

  Widget _buildCampaignCard(DocumentSnapshot doc) {
    final data      = doc.data() as Map<String, dynamic>;
    final startDate = (data['startDate'] as Timestamp?)?.toDate();
    final endDate   = (data['endDate']   as Timestamp?)?.toDate();
    final now       = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);

    final isExpired  = endDate != null && endDate.isBefore(today);
    final isUpcoming = startDate != null && startDate.isAfter(now);

    final imageUrl   = data['productImageUrl'] as String?;
    final type       = data['campaignType']    as String? ?? '';
    final marketId   = data['marketId']        as String? ?? '';
    final marketName = data['marketName']      as String? ?? '';
    final catId      = data['categoryId']      as String? ?? '';
    final catName    = data['categoryName']    as String? ?? '';
    final logoUrl    = _marketLogos[marketId] ?? _marketLogosByName[marketName.toLowerCase()];
    final catIconUrl = _categoryIcons[catId]  ?? _categoryIconsByName[catName.toLowerCase()];

    // Dates
    final endDay = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : null;
    final diffDays = endDay != null ? endDay.difference(today).inDays : null;
    final isEndingToday = !isExpired && diffDays == 0;
    final isEndingTomorrow = !isExpired && diffDays == 1;

    return GestureDetector(
      onTap: () {
        if (imageUrl != null && imageUrl.isNotEmpty) {
          showImageLightbox(context, imageUrl, 'home_${doc.id}');
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: image ───────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Hero(
                        tag: 'home_${doc.id}',
                        child: Image.network(
                          imageUrl,
                          width: 88,
                          height: 100,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : Container(
                                  width: 88,
                                  height: 100,
                                  color: Colors.grey.shade100,
                                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                          errorBuilder: (_, __, ___) => Container(
                            width: 88,
                            height: 100,
                            color: Colors.grey.shade100,
                            child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 32),
                          ),
                        ),
                      )
                    : Container(
                        width: 88,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 32),
                      ),
              ),
              const SizedBox(width: 12),

              // ── Right: details ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    SmartTitleText(
                      data['product'] ?? data['title'] ?? '',
                      fontSize: 13,
                      color: isExpired ? Colors.grey : Colors.black87,
                    ),
                    const SizedBox(height: 6),

                    // Price info
                    _buildPriceSection(data, type, isExpired),

                    const SizedBox(height: 6),

                    // Market + category row
                    Row(
                      children: [
                        if (logoUrl != null && logoUrl.isNotEmpty) ...[
                          ClipOval(
                            child: Image.network(logoUrl, width: 14, height: 14, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.store, size: 12)),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          marketName,
                          style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                        ),
                        if (catName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          if (catIconUrl != null && catIconUrl.isNotEmpty) ...[
                            ClipOval(
                              child: Image.network(catIconUrl, width: 12, height: 12, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.category, size: 11)),
                            ),
                            const SizedBox(width: 3),
                          ],
                          Text(catName, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                        ],
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Date / "Bugün son" row
                    _buildDateBadge(isEndingToday, isEndingTomorrow, isExpired, startDate, endDate),
                  ],
                ),
              ),

              // ── Heart button (dış Row'da — ürün yüksekliğini etkilemez) ──
              ValueListenableBuilder<Set<String>>(
                valueListenable: FavoritesManager.notifier,
                builder: (_, favIds, __) {
                  final isFav = favIds.contains(doc.id);
                  return _FavoriteButton(
                    isFav: isFav,
                    onTap: () => FavoritesManager.toggle(doc.id, campaignData: data),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceSection(Map<String, dynamic> data, String type, bool isExpired) {
    if (type == 'priceDiscount') {
      final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
      final pct  = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_priceFmt.format(newP)} TL',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
          ),
          Row(
            children: [
              Text(
                '${_priceFmt.format(oldP)} TL',
                style: const TextStyle(fontSize: 12, color: Colors.black54, decoration: TextDecoration.lineThrough),
              ),
              if (pct > 0 && !isExpired) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('%$pct indirim',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ],
      );
    }
    if (type == 'buyOneGetOne') {
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('🔥 1 alana 1 bedava',
                style: TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
          ),
          if (price > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_priceFmt.format(price)} TL',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
            ),
        ],
      );
    }
    if (type == 'secondDiscount') {
      final rate  = (data['discountRate'] as num?)?.toInt() ?? 0;
      final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('🔥 2. üründe %$rate indirim',
                style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
          ),
          if (price > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_priceFmt.format(price)} TL',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildDateBadge(bool isEndingToday, bool isEndingTomorrow, bool isExpired,
      DateTime? startDate, DateTime? endDate) {
    if (isEndingToday) {
      return Row(children: const [
        Icon(Icons.hourglass_bottom, size: 13, color: Colors.orange),
        SizedBox(width: 3),
        Text('Bugün son', style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
      ]);
    }
    if (isEndingTomorrow) {
      return Row(children: [
        Icon(Icons.access_time, size: 13, color: Colors.orange.shade700),
        const SizedBox(width: 3),
        Text('Yarın bitiyor', style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
      ]);
    }
    if (startDate != null && endDate != null) {
      return Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.black54),
        const SizedBox(width: 3),
        Text(
          '${_dateFmt.format(startDate)} – ${_dateFmt.format(endDate)}',
          style: TextStyle(
            fontSize: 11,
            color: isExpired ? Colors.black38 : Colors.black87,
          ),
        ),
      ]);
    }
    return const SizedBox.shrink();
  }
}

// ── _FavoriteButton ───────────────────────────────────────────────────

class _FavoriteButton extends StatefulWidget {
  final bool isFav;
  final VoidCallback onTap;
  const _FavoriteButton({required this.isFav, required this.onTap});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.85), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.15), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFav && !oldWidget.isFav) _ctrl.forward(from: 0);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
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
      ),
    );
  }
}
