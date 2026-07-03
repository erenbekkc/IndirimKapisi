import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/image_lightbox.dart';
import '../app_logger.dart';
import 'settings_screen.dart' show getOrCreateUserId;

// Mesajlar uygulama açık olduğu sürece korunur
final List<_ChatMessage> _persistedMessages = [];

class AiAsistanScreen extends StatefulWidget {
  final String? initialQuery;
  const AiAsistanScreen({super.key, this.initialQuery});

  @override
  State<AiAsistanScreen> createState() => _AiAsistanScreenState();
}

class _AiAsistanScreenState extends State<AiAsistanScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = false;

  List<Map<String, dynamic>> _activeCampaigns = [];

  String? _apiKey;
  String? _systemPrompt;

  static const _kDefaultSystemPrompt =
      'Sen İndirim Kapısı uygulamasının alışveriş asistanısın.\n'
      'Bugünün tarihi: {TODAY}. Tarih sorarlarsa veya "bugün biten" gibi sorgularda bu tarihi kullan.\n'
      'Türkiye\'deki market kampanyaları hakkında yardım ediyorsun.\n'
      'Kısa, net ve samimi cevaplar ver. Türkçe eş anlamlı kelimeleri anla (tavuk=piliç=kanat=but=göğüs=baget, deterjan=çamaşır=temizlik, vb.).\n'
      'TL cinsinden tasarruf hesapları yap, bütçeye göre öneriler sun.\n'
      'Kahvaltı veya kahvaltılık denildiğinde şu ürünleri ara: peynir, zeytin, zeytinyağı, yumurta, domates, salatalık, reçel, bal, marmelat, nutella, çikolatalı krema, tereyağı, kaymak, ekmek, tost ekmeği, pide, açma, poğaça, simit, tahini, pekmez. Bu ürünlerin geçtiği TÜM kampanyaları ID listesine ekle.\n'
      'Kampanya verisinde "Yakında başlayacak kampanyalar" bölümü varsa: kullanıcı o ürünü sorarken şu an geçerli indirim yoksa ama yakında başlayacaksa bunu mutlaka belirt — örneğin "Şu an aktif değil ama X tarihinde başlıyor" veya "2 gün sonra bu indirim başlıyor" gibi. Kaç gün kaldığını hesapla ve söyle.\n'
      '\n'
      'Cevabında kampanya kartları gösterilecekse (KAMPANYALAR listesi boş değilse), cevabının sonuna şunu ekle: "Ürünleri favorilerinize alın, indirimleri kaçırmayın! ❤️"\n'
      '\n'
      'ÖNEMLİ: Cevabının EN SONUNA, ilgili kampanyaların ID\'lerini şu formatta ekle (geniş kategori sorgularında max 15, dar sorgularda max 5):\n'
      'KAMPANYALAR:["id1","id2","id3"]\n'
      'İlgili kampanya yoksa: KAMPANYALAR:[]\n'
      'Kahvaltı/kahvaltılık sorgularında listede peynir, zeytin, zeytinyağı, yumurta, domates, salatalık, reçel, bal, marmelat, nutella, çikolatalı krema, tereyağı, kaymak, ekmek, tost, pide, poğaça, simit, tahini, pekmez geçen TÜM kampanyaları ID\'ye ekle.';

  Future<void> _loadApiKey() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('ai').get();
      _apiKey = doc.data()?['apiKey'] as String?;
      final prompt = doc.data()?['systemPrompt'] as String?;
      if (prompt != null && prompt.isNotEmpty) _systemPrompt = prompt;
    } catch (e, s) {
      logError('ai_loadApiKey', e, s);
    }
  }

  final _priceFmt = NumberFormat('#,##0.00', 'tr_TR');
  final _dateFmt = DateFormat('dd MMM', 'tr_TR');

  final List<String> _suggestions = [
    '200 TL bütçem var ne alayım?',
    'Bu hafta deterjan kampanyası var mı?',
    'Hangi market bu hafta daha avantajlı?',
    'Bugün biten kampanyalar neler?',
    'En yüksek indirimli ürünler hangileri?',
  ];

  @override
  void initState() {
    super.initState();
    if (_persistedMessages.isEmpty) {
      _persistedMessages.add(_ChatMessage(
        text: 'Merhaba! 👋 Ben İndirim ve Fırsat Asistanıyım.\n\nMevcut kampanyalar hakkında her şeyi sorabilirsin. Bütçene göre öneri, market karşılaştırması, kategori bazlı arama yapabilirim!',
        isUser: false,
      ));
    }
    _loadApiKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
        _send(widget.initialQuery!);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> _fetchCampaignContext() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Market logolarını çek
    final marketsSnap = await FirebaseFirestore.instance.collection('markets').get();
    final marketLogos = <String, String>{};
    for (final m in marketsSnap.docs) {
      final logo = (m.data())['logoUrl'] as String?;
      if (logo != null && logo.isNotEmpty) marketLogos[m.id] = logo;
    }

    final snap = await FirebaseFirestore.instance
        .collection('campaigns')
        .orderBy('endDate')
        .get();

    final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final upcoming = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (final d in snap.docs) {
      final data = d.data();
      final endDate = (data['endDate'] as Timestamp?)?.toDate();
      final startDate = (data['startDate'] as Timestamp?)?.toDate();
      if (endDate == null) continue;
      final endDay = DateTime(endDate.year, endDate.month, endDate.day);
      if (endDay.isBefore(today)) continue;
      if (startDate != null && startDate.isAfter(now)) {
        upcoming.add(d);
      } else {
        active.add(d);
      }
    }

    _activeCampaigns = [
      ...active.take(1000).map((d) {
        final data = d.data();
        final marketId = data['marketId'] as String? ?? '';
        return {'id': d.id, ...data, 'marketLogoUrl': marketLogos[marketId] ?? ''};
      }),
      ...upcoming.take(50).map((d) {
        final data = d.data();
        final marketId = data['marketId'] as String? ?? '';
        return {'id': d.id, ...data, 'marketLogoUrl': marketLogos[marketId] ?? ''};
      }),
    ];

    if (active.isEmpty && upcoming.isEmpty) return 'Şu an aktif kampanya bulunmuyor.';

    String priceInfo(Map<String, dynamic> data) {
      final type = data['campaignType'] as String? ?? '';
      if (type == 'priceDiscount') {
        final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
        final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
        final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
        return '${_priceFmt.format(oldP)} TL → ${_priceFmt.format(newP)} TL (%$pct indirim)';
      } else if (type == 'buyOneGetOne') {
        final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
        return '1 alana 1 bedava (${_priceFmt.format(price)} TL)';
      } else if (type == 'secondDiscount') {
        final rate = (data['discountRate'] as num?)?.toInt() ?? 0;
        final price = (data['productPrice'] as num?)?.toDouble() ?? 0;
        return '2. üründe %$rate indirim (${_priceFmt.format(price)} TL)';
      }
      return '';
    }

    final sb = StringBuffer();

    if (active.isNotEmpty) {
      sb.writeln('Aktif kampanyalar (ID|Ürün|Market|Kategori|Fiyat Bilgisi|Bitiş):\n');
      for (final doc in active.take(1000)) {
        final data = doc.data();
        final product = data['product'] as String? ?? '';
        final market = data['marketName'] as String? ?? '';
        final category = data['categoryName'] as String? ?? '';
        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        sb.writeln('${doc.id}|$product|$market|$category|${priceInfo(data)}|${endDate != null ? _dateFmt.format(endDate) : "-"}');
      }
    }

    if (upcoming.isNotEmpty) {
      sb.writeln('\nYakında başlayacak kampanyalar (ID|Ürün|Market|Kategori|Fiyat Bilgisi|Başlangıç|Bitiş):\n');
      for (final doc in upcoming.take(50)) {
        final data = doc.data();
        final product = data['product'] as String? ?? '';
        final market = data['marketName'] as String? ?? '';
        final category = data['categoryName'] as String? ?? '';
        final startDate = (data['startDate'] as Timestamp?)?.toDate();
        final endDate = (data['endDate'] as Timestamp?)?.toDate();
        sb.writeln('${doc.id}|$product|$market|$category|${priceInfo(data)}|${startDate != null ? _dateFmt.format(startDate) : "-"}|${endDate != null ? _dateFmt.format(endDate) : "-"}');
      }
    }

    return sb.toString();
  }

  // Eş anlamlı kelime grupları
  static const _synonymGroups = [
    ['tavuk', 'piliç', 'kanat', 'bonfile', 'but', 'göğüs', 'baget', 'hindi'],
    ['deterjan', 'çamaşır', 'temizlik', 'sabun', 'yumuşatıcı', 'çamaşır suyu', 'toz'],
    ['meyve', 'sebze', 'elma', 'portakal', 'muz', 'salata'],
    ['süt', 'yoğurt', 'peynir', 'tereyağı', 'kaymak', 'ayran', 'kefir', 'süt ürün'],
    ['ekmek', 'pasta', 'kek', 'bisküvi', 'kraker', 'börek', 'poğaça', 'simit', 'tost'],
    ['şampuan', 'saç', 'krem', 'losyon', 'deodorant', 'parfüm', 'kozmetik'],
    ['kahve', 'çay', 'nescafe', 'türk kahvesi', 'bitki çayı'],
    ['makarna', 'pirinç', 'bulgur', 'un', 'şeker', 'tuz', 'yağ', 'zeytinyağı'],
    ['bebek', 'bez', 'mama', 'ıslak mendil', 'biberon'],
    ['et', 'kıyma', 'köfte', 'sucuk', 'sosis', 'salam', 'jambon'],
    ['balık', 'deniz ürün', 'ton balığı', 'somon', 'sardalye'],
    ['su', 'maden suyu', 'içecek', 'meşrubat', 'kola', 'ayran', 'meyve suyu'],
    ['atıştırmalık', 'çikolata', 'gofret', 'cips', 'fındık', 'fıstık', 'kuruyemiş'],
    ['kahvaltı', 'kahvaltılık', 'peynir', 'zeytin', 'yumurta', 'domates', 'salatalık',
     'reçel', 'bal', 'marmelat', 'nutella', 'çikolatalı krema', 'tereyağı', 'kaymak',
     'ekmek', 'tost', 'pide', 'açma', 'poğaça', 'simit', 'tahini', 'pekmez'],
  ];

  List<Map<String, dynamic>> _matchCampaignsLocally(String userQuery) {
    final combined = userQuery.toLowerCase();

    // Sorgudaki kelimelerle eş anlamlı genişletme
    final searchTerms = <String>{};
    for (final word in combined.split(RegExp(r'\s+'))) {
      if (word.length < 3) continue;
      searchTerms.add(word);
      for (final group in _synonymGroups) {
        if (group.any((s) => word.contains(s) || s.contains(word))) {
          searchTerms.addAll(group);
          break;
        }
      }
    }

    final scored = <Map<String, dynamic>>[];
    for (final c in _activeCampaigns) {
      final product = (c['product'] as String? ?? '').toLowerCase();
      final category = (c['categoryName'] as String? ?? '').toLowerCase();
      final market = (c['marketName'] as String? ?? '').toLowerCase();
      final searchable = '$product $category $market';

      int score = 0;
      for (final term in searchTerms) {
        if (term.length < 3) continue;
        if (searchable.contains(term)) {
          score++;
        } else {
          // Türkçe ek kontrolü: "migrostaki" → "migros" gibi
          for (final w in searchable.split(RegExp(r'\s+'))) {
            if (w.length >= 3 && term.startsWith(w)) {
              score++;
              break;
            }
          }
        }
      }
      if (score > 0) scored.add({...c, '_score': score});
    }

    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
    return scored.take(5).toList();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _loading) return;

    _controller.clear();
    setState(() {
      _persistedMessages.add(_ChatMessage(text: q, isUser: true));
      _loading = true;
    });
    _scrollToBottom();

    try {
      if (_apiKey == null) {
        await _loadApiKey();
      }
      if (_apiKey == null) {
        setState(() => _persistedMessages.add(_ChatMessage(
          text: 'Asistan şu an kullanılamıyor, lütfen daha sonra tekrar deneyin.',
          isUser: false,
          isError: true,
        )));
        setState(() => _loading = false);
        return;
      }

      final context = await _fetchCampaignContext();
      final todayStr = DateFormat('d MMMM', 'tr_TR').format(DateTime.now());

      final template = _systemPrompt ?? _kDefaultSystemPrompt;
      final systemPrompt = template.replaceAll('{TODAY}', todayStr)
          + '\n\nKampanya verisi (ID|Ürün|Market|Kategori|Fiyat|Bitiş):\n$context';

      final resp = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey!,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5-20251001',
          'max_tokens': 2048,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': q}
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        String reply = (body['content'] as List).first['text'] as String;

        // AI cevabından KAMPANYALAR:[...] kısmını parse et
        final kampanyalarRegex = RegExp(r'KAMPANYALAR:\[([^\]]*)\]');
        final kampanyalarMatch = kampanyalarRegex.firstMatch(reply);
        List<Map<String, dynamic>> matched = [];

        if (kampanyalarMatch != null) {
          reply = reply.replaceAll(kampanyalarRegex, '').trim();
          try {
            final rawIds = kampanyalarMatch.group(1) ?? '';
            final ids = rawIds
                .split(',')
                .map((s) => s.trim().replaceAll('"', '').replaceAll("'", ''))
                .where((s) => s.isNotEmpty)
                .toList();
            matched = _activeCampaigns
                .where((c) => ids.contains(c['id'] as String? ?? ''))
                .toList();
          } catch (_) {}
        }

        setState(() => _persistedMessages.add(_ChatMessage(
          text: reply,
          isUser: false,
          matchedCampaigns: matched,
        )));

        // Diyaloğu ai-logs'a kaydet
        unawaited(getOrCreateUserId().then((uid) {
          FirebaseFirestore.instance.collection('ai-logs').add({
            'uid': uid,
            'question': q,
            'answer': reply,
            'platform': Platform.isIOS ? 'ios' : 'android',
            'askedAt': FieldValue.serverTimestamp(),
          });
        }));
      } else {
        String errorDetail = '';
        try {
          final errBody = jsonDecode(utf8.decode(resp.bodyBytes));
          errorDetail = errBody['error']?['message'] ?? resp.body;
        } catch (_) {
          errorDetail = resp.body;
        }
        FirebaseFirestore.instance.collection('chatbot_logs').add({
          'type': 'api_error',
          'statusCode': resp.statusCode,
          'errorMessage': errorDetail,
          'userQuery': q,
          'timestamp': FieldValue.serverTimestamp(),
        });
        setState(() => _persistedMessages.add(_ChatMessage(
          text: 'Bir hata oluştu, tekrar deneyin.',
          isUser: false,
          isError: true,
        )));
      }
    } catch (e) {
      FirebaseFirestore.instance.collection('chatbot_logs').add({
        'type': 'connection_error',
        'errorMessage': e.toString(),
        'userQuery': q,
        'timestamp': FieldValue.serverTimestamp(),
      });
      setState(() => _persistedMessages.add(_ChatMessage(
        text: 'Bağlantı hatası oluştu, tekrar deneyin.',
        isUser: false,
        isError: true,
      )));
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: AssetImage('assets/agent_gri.jpeg'),
            backgroundColor: Colors.transparent,
          ),
          SizedBox(width: 8),
          Text('İndirim ve Fırsat Asistanı',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        backgroundColor: const Color(0xFF16A34A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_persistedMessages.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Sohbeti Temizle',
              onPressed: () {
                setState(() {
                  _persistedMessages.clear();
                  _persistedMessages.add(_ChatMessage(
                    text: 'Merhaba! 👋 Ben İndirim ve Fırsat Asistanıyım.\n\nMevcut kampanyalar hakkında her şeyi sorabilirsin!',
                    isUser: false,
                  ));
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _persistedMessages.length + (_loading ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _persistedMessages.length) return _buildTypingIndicator();
                return _buildMessage(_persistedMessages[i]);
              },
            ),
          ),

          if (_persistedMessages.length == 1 && !_loading)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_suggestions[i], style: const TextStyle(fontSize: 12)),
                  onPressed: () => _send(_suggestions[i]),
                  backgroundColor: const Color(0xFFF0FDF4),
                  side: const BorderSide(color: Color(0xFF16A34A), width: 0.8),
                  labelStyle: const TextStyle(color: Color(0xFF16A34A)),
                ),
              ),
            ),

          const SizedBox(height: 8),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: 'Kampanyalar hakkında sor...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(color: Color(0xFF16A34A)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _send(_controller.text),
                    child: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isUser) ...[
                ClipOval(
                  child: Image.asset('assets/agent_gri.jpeg', width: 32, height: 32, fit: BoxFit.cover),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? const Color(0xFF16A34A)
                        : msg.isError
                            ? Colors.red.shade50
                            : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                      bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: msg.isUser ? Colors.white : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (msg.isUser) const SizedBox(width: 8),
            ],
          ),

          if (msg.matchedCampaigns.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('İlgili kampanyalar:',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  ),
                  ...msg.matchedCampaigns.map((c) => _buildCampaignCard(c)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCampaignCard(Map<String, dynamic> c) {
    final id = c['id'] as String;
    final product = c['product'] as String? ?? '';
    final market = c['marketName'] as String? ?? '';
    final type = c['campaignType'] as String? ?? '';
    final imageUrl = c['productImageUrl'] as String?;
    final endDate = (c['endDate'] as Timestamp?)?.toDate();

    Widget? priceWidget;
    if (type == 'priceDiscount') {
      final oldP = (c['oldPrice'] as num?)?.toDouble() ?? 0;
      final newP = (c['newPrice'] as num?)?.toDouble() ?? 0;
      final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
      priceWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('${_priceFmt.format(oldP)} TL',
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey,
                    decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 6),
            Text('${_priceFmt.format(newP)} TL',
                style: const TextStyle(
                    fontSize: 13, color: Colors.deepOrange,
                    fontWeight: FontWeight.bold)),
          ]),
          if (pct > 0) ...[
            const SizedBox(height: 2),
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
    } else if (type == 'buyOneGetOne') {
      priceWidget = const Text('🔥 1 alana 1 bedava',
          style: TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600));
    } else if (type == 'secondDiscount') {
      final rate = (c['discountRate'] as num?)?.toInt() ?? 0;
      priceWidget = Text('🔥 2. üründe %$rate indirim',
          style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600));
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: FavoritesManager.notifier,
      builder: (_, favIds, __) {
        final isFav = favIds.contains(id);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                GestureDetector(
                  onTap: () => showImageLightbox(context, imageUrl, 'ai_campaign_$id'),
                  child: Hero(
                    tag: 'ai_campaign_$id',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(imageUrl, width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 48)),
                    ),
                  ),
                )
              else
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.image_outlined, color: Colors.grey.shade300, size: 24),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if ((c['marketLogoUrl'] as String?) != null && (c['marketLogoUrl'] as String).isNotEmpty)
                          ClipOval(child: Image.network(c['marketLogoUrl'] as String, width: 14, height: 14, fit: BoxFit.cover))
                        else
                          Icon(Icons.store, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(market, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                      ],
                    ),
                    if (priceWidget != null) priceWidget,
                    if (endDate != null)
                      Text('Bitiş: ${_dateFmt.format(endDate)}',
                          style: const TextStyle(fontSize: 11, color: Colors.black87)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => FavoritesManager.toggle(id),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(isFav),
                    color: isFav ? Colors.red.shade400 : Colors.grey.shade300,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset('assets/agent_gri.jpeg', width: 32, height: 32, fit: BoxFit.cover),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final List<Map<String, dynamic>> matchedCampaigns;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.matchedCampaigns = const [],
  });
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final val = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = val < 0.5 ? val * 2 : (1.0 - val) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: 0.3 + opacity * 0.7,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
