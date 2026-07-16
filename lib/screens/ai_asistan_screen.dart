import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../favorites_manager.dart';
import '../widgets/image_lightbox.dart';
import '../widgets/native_ad_widget.dart';
import '../app_logger.dart';
import '../remote_config_service.dart';
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
  double _questionScrollOffset = 0;

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
      'FORMAT KURALI (KESİNLİKLE UYULMASI GEREKİYOR): Kampanyaları asla liste veya tablo olarak gösterme. "## Aktif İndirimler:" gibi başlıklar veya markdown tabloları (| ile başlayan satırlar) KULLANMA. Sadece kısa bir özet cümle yaz (örn: "X markette 5 tavuk kampanyası buldum, aşağıda görebilirsin."). Fiyat, marka, indirim oranı gibi kampanya detaylarını tekrar yazma — bunlar zaten altta kartlarda gösterilecek.\n'
      '\n'
      'YASAK İFADELER (KESİNLİKLE KULLANMA): "markete gidip sorabilirsiniz", "marketi ziyaret edin", "birkaç gün sonra tekrar kontrol edin", "web sitesini ziyaret edin", "müşteri hizmetleri", "stok durumuna göre değişebilir". Kampanya verilerinde yoksa sadece "Şu an bu ürün için aktif kampanya bulamadım" de ve başka aktif kampanyalardan kısa bir öneri sun.\n'
      '\n'
      'Cevabında kampanya kartları gösterilecekse (KAMPANYALAR listesi boş değilse), cevabının sonuna mutlaka şunu ekle: "Kartlardaki ❤️ ikonuna dokunarak favorilerinize ekleyin, indirimleri kaçırmayın!"\n'
      '\n'
      'ÖNEMLİ: Cevabının EN SONUNA, ilgili kampanyaların ID\'lerini şu formatta ekle (geniş kategori sorgularında max 30, dar sorgularda max 15). TÜM marketlerdeki ilgili kampanyaları ekle, belirli bir marketi önceliklendirme:\n'
      'KAMPANYALAR:["id1","id2","id3"]\n'
      'İlgili kampanya yoksa: KAMPANYALAR:[]\n'
      'Kahvaltı/kahvaltılık sorgularında listede peynir, zeytin, zeytinyağı, yumurta, domates, salatalık, reçel, bal, marmelat, nutella, çikolatalı krema, tereyağı, kaymak, ekmek, tost, pide, poğaça, simit, tahini, pekmez geçen TÜM kampanyaları ID\'ye ekle.';

  Future<void> _loadApiKey() async {
    try {
      final geminiDoc = await FirebaseFirestore.instance.collection('config').doc('gemini').get();
      _apiKey = (geminiDoc.data()?['apiKey'] as String? ?? '').trim();
      if (_apiKey!.isEmpty) _apiKey = null;
      final prompt = geminiDoc.data()?['systemPrompt'] as String?;
      if (prompt != null && prompt.isNotEmpty) _systemPrompt = prompt;
    } catch (e, s) {
      logError('ai_loadApiKey', e, s);
    }
    try {
      final searchDoc = await FirebaseFirestore.instance.collection('config').doc('search').get();
      final data = searchDoc.data();
      if (data != null) {
        // synonymGroups map olarak saklanıyor: {"g0": [...], "g1": [...]}
        final groupsMap = data['synonymGroups'] as Map<String, dynamic>?;
        if (groupsMap != null) {
          _synonymGroupsDynamic = groupsMap.values
              .map((g) => List<String>.from(g as List))
              .toList();
        }
        final aliases = data['phraseAliases'] as Map<String, dynamic>?;
        if (aliases != null) {
          _phraseAliasesDynamic = aliases.map((k, v) => MapEntry(k, List<String>.from(v as List)));
        }
        final excludes = data['excludeFromGroups'] as Map<String, dynamic>?;
        if (excludes != null) {
          _excludeFromGroupsDynamic = excludes.map((k, v) => MapEntry(k, List<String>.from(v as List)));
        }
        final stops = data['stopWords'] as List<dynamic>?;
        if (stops != null) {
          _stopWordsDynamic = List<String>.from(stops);
        }
      }
    } catch (e, s) {
      logError('ai_loadSearchConfig', e, s);
    }
  }

  final _priceFmt = NumberFormat('#,##0.00', 'tr_TR');
  final _dateFmt = DateFormat('dd MMM', 'tr_TR');

  final List<String> _suggestions = [
    'Peynir',
    'Deterjan',
    'Tavuk',
    'Zeytinyağı',
    'Şampuan',
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

  // Tüm kampanyaları Firestore'dan çekip _activeCampaigns'e yükler (kart gösterimi için)
  Future<void> _loadAllCampaigns() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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
      final startDay = startDate != null
          ? DateTime(startDate.year, startDate.month, startDate.day)
          : null;
      if (startDay != null && startDay.isAfter(today)) {
        upcoming.add(d);
      } else {
        active.add(d);
      }
    }

    // Marketler arası dengeli sıralama
    final byMarket = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in active) {
      final market = (d.data()['marketName'] as String? ?? 'Diğer').toLowerCase();
      byMarket.putIfAbsent(market, () => []).add(d);
    }
    final interleavedActive = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final marketKeys = byMarket.keys.toList();
    int maxLen = byMarket.values.fold(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxLen; i++) {
      for (final key in marketKeys) {
        final list = byMarket[key]!;
        if (i < list.length) interleavedActive.add(list[i]);
      }
    }

    _activeCampaigns = [
      ...interleavedActive.map((d) {
        final data = d.data();
        final marketId = data['marketId'] as String? ?? '';
        return {'id': d.id, ...data, 'marketLogoUrl': marketLogos[marketId] ?? ''};
      }),
      ...upcoming.map((d) {
        final data = d.data();
        final marketId = data['marketId'] as String? ?? '';
        return {'id': d.id, ...data, 'marketLogoUrl': marketLogos[marketId] ?? '', '_upcoming': true};
      }),
    ];
  }

  // Kullanıcı sorgusuna göre filtrele, Gemini'ye gönderilecek max 25 kampanya döndür
  String _buildFilteredContext(String userQuery) {
    if (_activeCampaigns.isEmpty) return 'Şu an aktif kampanya bulunmuyor.';

    final combined = userQuery.toLowerCase();
    final searchTerms = <String>{};
    for (final word in combined.split(RegExp(r'\s+'))) {
      if (word.length < 2) continue;
      searchTerms.add(word);
      final wordAscii = _toAscii(word);
      for (final group in _synonymGroupsDynamic) {
        if (group.any((g) => _toAscii(g) == wordAscii)) {
          searchTerms.addAll(group);
          break;
        }
      }
    }

    // Skora göre sırala
    final scored = <Map<String, dynamic>>[];
    for (final c in _activeCampaigns) {
      final product = (c['product'] as String? ?? '').toLowerCase();
      final category = (c['categoryName'] as String? ?? '').toLowerCase();
      final market = (c['marketName'] as String? ?? '').toLowerCase();
      final searchable = '$product $category $market';
      int score = 0;
      for (final term in searchTerms) {
        if (term.length < 2) continue;
        if (searchable.contains(term)) score += 2;
        else {
          for (final w in searchable.split(RegExp(r'\s+'))) {
            if (w.length >= 2 && (term.startsWith(w) || w.startsWith(term))) {
              score++;
              break;
            }
          }
        }
      }
      if (score > 0) scored.add({...c, '_score': score});
    }
    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));

    final toSend = scored.isNotEmpty
        ? scored.take(25).toList()
        : _activeCampaigns.take(5).toList();

    String priceInfo(Map<String, dynamic> data) {
      final type = data['campaignType'] as String? ?? '';
      if (type == 'priceDiscount') {
        final newP = (data['newPrice'] as num?)?.toDouble() ?? 0;
        final oldP = (data['oldPrice'] as num?)?.toDouble() ?? 0;
        final pct = oldP > 0 ? ((oldP - newP) / oldP * 100).round() : 0;
        return '${_priceFmt.format(newP)} TL(%$pct)';
      } else if (type == 'buyOneGetOne') {
        return '1al1bedava';
      } else if (type == 'secondDiscount') {
        final rate = (data['discountRate'] as num?)?.toInt() ?? 0;
        return '2.ürün%$rate';
      }
      return '';
    }

    final sb = StringBuffer();
    final activeItems = toSend.where((c) => c['_upcoming'] != true).toList();
    final upcomingItems = toSend.where((c) => c['_upcoming'] == true).toList();

    if (activeItems.isNotEmpty) {
      sb.writeln('Kampanyalar(ID|Ürün|Market|Fiyat):');
      for (final c in activeItems) {
        sb.writeln('${c['id']}|${c['product'] ?? ''}|${c['marketName'] ?? ''}|${priceInfo(c)}');
      }
    }
    if (upcomingItems.isNotEmpty) {
      sb.writeln('Yakında(ID|Ürün|Market|Fiyat|Başlangıç):');
      for (final c in upcomingItems) {
        final startDate = (c['startDate'] as Timestamp?)?.toDate();
        sb.writeln('${c['id']}|${c['product'] ?? ''}|${c['marketName'] ?? ''}|${priceInfo(c)}|${startDate != null ? _dateFmt.format(startDate) : '-'}');
      }
    }
    return sb.toString();
  }

// Tümü Firestore config/search'ten yüklenir — koda kural gömme
  List<List<String>> _synonymGroupsDynamic = [];
  Map<String, List<String>> _phraseAliasesDynamic = {};
  Map<String, List<String>> _excludeFromGroupsDynamic = {};
  List<String> _stopWordsDynamic = [];

  // Türkçe → ASCII: her iki tarafı da ortak forma indirgeyerek karşılaştır
  // "cay" ve "çay" ikisi de "cay"a döner → eşleşir
  // "sut" ve "süt" ikisi de "sut"a döner → eşleşir
  static String _toAscii(String s) => s
      .replaceAll('ç', 'c')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i');

  // Geçerli Türkçe ekler — ASCII formunda
  static const _validSuffixesAscii = [
    '', 'lar', 'ler',
    'i', 'u', 'a', 'e',
    'da', 'de', 'ta', 'te',
    'dan', 'den', 'tan', 'ten',
    'in', 'un',
    'im', 'um',
    'si', 'su',
    'lari', 'leri',
    'lara', 'lere',
    'lardan', 'lerden',
    'larda', 'lerde',
  ];

  // Bir kelimenin geçerli Türkçe ek alarak term'e eşleşip eşleşmediği
  // Her ikisi de ASCII'ye çevrilerek karşılaştırılır
  bool _stemMatch(String word, String term) {
    final w = _toAscii(word);
    final t = _toAscii(term);
    if (!w.startsWith(t)) return false;
    final suffix = w.substring(t.length);
    return _validSuffixesAscii.contains(suffix);
  }

  // Ürün adındaki herhangi bir kelime, sorgu terimini stem olarak içeriyor mu?
  bool _productContainsTerm(String product, String term) {
    for (final w in product.split(RegExp(r'[\s\-\/,()+]+'))) {
      if (_stemMatch(w, term)) return true;
    }
    return false;
  }

  // Çok kelimeli bir ifadenin ürün adında tüm kelimelerinin eşleşip eşleşmediği
  bool _phraseMatchesProduct(String product, String phrase) {
    final words = phrase.split(RegExp(r'\s+')).where((w) => w.length >= 2).toList();
    return words.every((w) => _productContainsTerm(product, w));
  }

  List<Map<String, dynamic>> _matchCampaignsLocally(String userQuery) {
    final query = userQuery.toLowerCase().trim();
    final queryAscii = _toAscii(query);
    // Stop word filtresi: "getir", "çeşitleri" gibi komut/dolgu kelimelerini çıkar
    final stopAscii = _stopWordsDynamic.map(_toAscii).toSet();
    final queryWords = query
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2 && !stopAscii.contains(_toAscii(w)))
        .toList();

    // İfade eş anlamlısı var mı? (örn: "sıvı yağ")
    List<String>? phraseAlts;
    for (final entry in _phraseAliasesDynamic.entries) {
      if (_toAscii(entry.key) == queryAscii) {
        phraseAlts = entry.value;
        break;
      }
    }

    // Tek kelime synonym genişletmesi — ASCII normalize ederek karşılaştır
    final allTerms = <String>{...queryWords};
    for (final word in queryWords) {
      final wordAscii = _toAscii(word);
      for (final group in _synonymGroupsDynamic) {
        if (group.any((g) => _toAscii(g) == wordAscii)) {
          allTerms.addAll(group);
          break;
        }
      }
    }

    final scored = <Map<String, dynamic>>[];
    for (final c in _activeCampaigns) {
      final product = (c['product'] as String? ?? '').toLowerCase();
      final market = (c['marketName'] as String? ?? '').toLowerCase();

      // İfade eş anlamlısı varsa: alternatiflerden herhangi biri eşleşmeli
      if (phraseAlts != null) {
        final hit = phraseAlts.any((alt) => _phraseMatchesProduct(product, alt));
        if (!hit) continue;
        scored.add({...c, '_score': 1});
        continue;
      }

      // Grup bazlı hariç tutma (Firestore config/search excludeFromGroups)
      bool excluded = false;
      for (final entry in _excludeFromGroupsDynamic.entries) {
        if (allTerms.contains(entry.key)) {
          if (entry.value.any((w) => product.contains(w))) {
            excluded = true;
            break;
          }
        }
      }
      if (excluded) continue;

      // Skor hesapla — çok kelimeli synonym'ler için phraseMatch kullan
      int score = 0;
      for (final term in allTerms) {
        final isPhrase = term.contains(' ');
        final hit = isPhrase
            ? _phraseMatchesProduct(product, term) || _phraseMatchesProduct(market, term)
            : _productContainsTerm(product, term) || _productContainsTerm(market, term);
        if (hit) score++;
      }

      if (score > 0) scored.add({...c, '_score': score});
    }

    scored.sort((a, b) => (b['_score'] as int).compareTo(a['_score'] as int));
    return scored.take(20).toList();
  }

  // 1-2 kelime → direkt lokal
  // 3+ kelime → Gemini'ye niyet tespiti sor ("arama" mı "sohbet" mi)
  static const _marketNames = [
    'a101', 'bim', 'bimde', 'migros', 'şok', 'sok', 'carrefour',
    'metro', 'file', 'hakmar', 'diyos', 'onur', 'macro', 'kiler',
  ];

  // 1-2 kelime → lokal (true)
  // 3+ kelime + market adı → Gemini (false)
  // 3+ kelime, market yok → niyet tespiti
  Future<bool> _isSimpleQuery(String q) async {
    final lower = q.toLowerCase();
    final words = lower.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (words.length <= 2) return true; // kesin arama

    // Market adı varsa Gemini'ye git
    if (_marketNames.any((m) => lower.contains(m))) return false;

    if (_apiKey == null) return true;
    try {
      final resp = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=${_apiKey!}',
        ),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': 'Kullanıcı bir alışveriş asistanına şunu yazdı: "$q"\n\n'
                      'Bu mesaj:\n'
                      '- Bir ürün veya kategori araması ise "arama" yaz\n'
                      '- Fiyat sorusu, öneri, karşılaştırma, bütçe veya sohbet ise "sohbet" yaz\n\n'
                      'Sadece tek kelime yaz: arama veya sohbet',
                }
              ]
            }
          ],
          'generationConfig': {'temperature': 0, 'maxOutputTokens': 8},
        }),
      ).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        final text = ((body['candidates'] as List).first['content']['parts'] as List)
            .first['text'] as String;
        return text.trim().toLowerCase().contains('arama');
      }
    } catch (_) {}
    return true; // hata olursa lokal ara
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

      await _loadAllCampaigns();

      // Basit sorgularda Gemini'ye gitme — yerel filtrele
      if (await _isSimpleQuery(q)) {
        final localMatches = _matchCampaignsLocally(q);
        final qCap = q[0].toUpperCase() + q.substring(1);
        final localReply = localMatches.isNotEmpty
            ? '$qCap için ${localMatches.length} kampanya buldum, aşağıda görebilirsin. Kartlardaki ❤️ ikonuna dokunarak favorilerinize ekleyin, indirimleri kaçırmayın!'
            : 'Şu an "$q" için aktif kampanya bulamadım.';
        setState(() => _persistedMessages.add(_ChatMessage(
          text: localReply,
          isUser: false,
          matchedCampaigns: localMatches,
        )));
        unawaited(getOrCreateUserId().then((uid) {
          FirebaseFirestore.instance.collection('ai-logs').add({
            'uid': uid,
            'question': q,
            'answer': localReply,
            'provider': 'local',
            'platform': Platform.isIOS ? 'ios' : 'android',
            'askedAt': FieldValue.serverTimestamp(),
          });
        }));
        return;
      }

      final todayStr = DateFormat('d MMMM', 'tr_TR').format(DateTime.now());
      final context = _buildFilteredContext(q);

      final template = _systemPrompt ?? _kDefaultSystemPrompt;
      final systemPrompt = template.replaceAll('{TODAY}', todayStr)
          + '\n\nKampanya verisi (ID|Ürün|Market|Kategori|Fiyat|Bitiş):\n$context';

      final resp = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=${_apiKey!}',
        ),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'systemInstruction': {
            'parts': [{'text': systemPrompt}],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [{'text': q}],
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 512,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        final parts = ((body['candidates'] as List).first['content']['parts'] as List);
        // thought:true olan thinking parts'ları atla, sadece gerçek cevabı al
        final textParts = parts.where((p) => p['thought'] != true && p['text'] != null);
        String reply = textParts.isNotEmpty
            ? textParts.map((p) => p['text'] as String).join()
            : (parts.first['text'] as String? ?? '');

        // Markdown yapılarını temizle
        // 1. Markdown başlıkları (# ## ###)
        reply = reply.replaceAll(RegExp(r'^#{1,3}\s*.+$', multiLine: true), '');
        // 2. Tablo satırları (| ile başlayan)
        reply = reply.replaceAll(RegExp(r'^\s*\|.*$', multiLine: true), '');
        // 3. Numaralı liste satırları (1. 2. 3. ...)
        reply = reply.replaceAll(RegExp(r'^\s*\d+\.\s+.*$', multiLine: true), '');
        // 4. Tüm madde işareti satırları (- veya • ile başlayan)
        reply = reply.replaceAll(RegExp(r'^\s*[-•]\s+.*$', multiLine: true), '');
        // 5. Kalan **bold** markdown işaretlerini kaldır
        reply = reply.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
        // 6. Fazla boş satırları temizle
        reply = reply.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

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

            // Sebze/meyve karışmasını önle: sorguya göre filtrele
            final qLower = q.toLowerCase();
            // Sebze aranınca filtrelenecek belirgin meyveler (limon/narenciye hariç)
            const sadeceMeyve = ['karpuz','kavun','muz','kiraz','şeftali','erik','çilek','ananas','mango','üzüm'];
            // Meyve aranınca filtrelenecek belirgin sebzeler
            const sadeceSebze = ['domates','salatalık','biber','patlıcan','kabak','ıspanak','marul','soğan','patates','havuç','brokoli','bezelye','pırasa','enginar'];
            final sorguSebze = qLower.contains('sebze') || sadeceSebze.any((s) => qLower.contains(s));
            final sorguMeyve = qLower.contains('meyve') || sadeceMeyve.any((s) => qLower.contains(s));
            if (sorguSebze && !sorguMeyve) {
              matched = matched.where((c) {
                final p = (c['product'] as String? ?? '').toLowerCase();
                return !sadeceMeyve.any((m) => p.contains(m));
              }).toList();
              // Metinden de meyve isimlerini içeren cümleleri çıkar
              for (final meyve in sadeceMeyve) {
                reply = reply.replaceAll(
                  RegExp('[^.!?]*$meyve[^.!?]*[.!?]', caseSensitive: false), '');
              }
            } else if (sorguMeyve && !sorguSebze) {
              matched = matched.where((c) {
                final p = (c['product'] as String? ?? '').toLowerCase();
                return !sadeceSebze.any((s) => p.contains(s));
              }).toList();
              // Metinden de sebze isimlerini içeren cümleleri çıkar
              for (final sebze in sadeceSebze) {
                reply = reply.replaceAll(
                  RegExp('[^.!?]*$sebze[^.!?]*[.!?]', caseSensitive: false), '');
              }
            }
            reply = reply.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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
            'provider': 'gemini',
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
          'provider': 'gemini',
          'statusCode': resp.statusCode,
          'errorMessage': errorDetail,
          'userQuery': q,
          'timestamp': FieldValue.serverTimestamp(),
        });
        setState(() => _persistedMessages.add(_ChatMessage(
          text: 'Şu an cevap veremiyorum, lütfen sorunuzu tekrar sorar mısınız?',
          isUser: false,
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
        text: 'Şu an cevap veremiyorum, lütfen sorunuzu tekrar sorar mısınız?',
        isUser: false,
      )));
    } finally {
      setState(() => _loading = false);
    }
  }

  // Soru gönderilince: en alta in (kullanıcı mesajı görünsün)
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  // Cevap gelince: kullanıcı sorusunun başına scroll et
  // (son kullanıcı mesajı = son 2 mesajdan önceki)
  void _scrollToLastQuestion() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        // Viewport yüksekliği kadar yukarı çık — cevabın tepesini göster
        final target = (pos.maxScrollExtent - pos.viewportDimension * 0.85)
            .clamp(0.0, pos.maxScrollExtent);
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      });
    });
  }

  static const _green = Color(0xFF16A34A);

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _green),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(5),
            child: ClipOval(
              child: Image.asset('assets/agent.jpeg', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'İndirim ve Fırsat Asistanı',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ),
          if (_persistedMessages.length > 1)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.grey.shade500),
              tooltip: 'Sohbeti Temizle',
              onPressed: () {
                setState(() {
                  _persistedMessages.clear();
                  _persistedMessages.add(_ChatMessage(
                    text: 'Merhaba! 👋 Ben İndirim ve Fırsat Asistanıyım.\n\nMevcut kampanyalar hakkında her şeyi sorabilirsin. Bütçene göre öneri, market karşılaştırması, kategori bazlı arama yapabilirim!',
                    isUser: false,
                  ));
                });
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: Colors.grey.shade200),
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
                Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ClipOval(
                    child: Image.asset('assets/agent.jpeg', fit: BoxFit.cover),
                  ),
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
                  ..._buildCampaignListWithAds(msg.matchedCampaigns),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Kampanya kartları arasına reklam kartı ekler.
  /// Her [freq] kampanya kartından sonra 1 reklam; [freq]'den az ürün varsa en alta 1 reklam.
  List<Widget> _buildCampaignListWithAds(List<Map<String, dynamic>> campaigns) {
    final freq   = RemoteConfigService.instance.adFrequency;
    final result = <Widget>[];
    for (int i = 0; i < campaigns.length; i++) {
      result.add(_buildCampaignCard(campaigns[i]));
      final isLast    = i == campaigns.length - 1;
      final hitFreq   = (i + 1) % freq == 0;
      if (hitFreq && !isLast) {
        result.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: NativeAdWidget(),
        ));
      }
    }
    // 5'ten az ürün varsa veya son gruptan sonra: en alta 1 reklam
    if (campaigns.isNotEmpty && campaigns.length % freq != 0) {
      result.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: NativeAdWidget(),
      ));
    }
    return result;
  }

  Widget _buildCampaignCard(Map<String, dynamic> c) {
    final id = c['id'] as String;
    final product = c['product'] as String? ?? '';
    final market = c['marketName'] as String? ?? '';
    final type = c['campaignType'] as String? ?? '';
    final imageUrl = c['productImageUrl'] as String?;
    final endDate = (c['endDate'] as Timestamp?)?.toDate();
    final startDate = (c['startDate'] as Timestamp?)?.toDate();
    final isUpcoming = c['_upcoming'] == true;

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
                    if (priceWidget != null) priceWidget,
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if ((c['marketLogoUrl'] as String?) != null && (c['marketLogoUrl'] as String).isNotEmpty)
                          ClipOval(child: Image.network(c['marketLogoUrl'] as String, width: 13, height: 13, fit: BoxFit.cover))
                        else
                          Icon(Icons.store, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(market, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        if (isUpcoming && startDate != null) ...[
                          Text('  ·  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          Text('${_dateFmt.format(startDate)}',
                              style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500)),
                          if (endDate != null) ...[
                            Text(' – ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                            Text('${_dateFmt.format(endDate)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ] else if (endDate != null) ...[
                          if (startDate != null) ...[
                            Text('  ·  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                            Text('${_dateFmt.format(startDate)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text(' – ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          ] else ...[
                            Text('  ·  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                          ],
                          Text('${_dateFmt.format(endDate)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ],
                    ),
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
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(4),
            child: ClipOval(
              child: Image.asset('assets/agent.jpeg', fit: BoxFit.cover),
            ),
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
