import 'package:flutter_test/flutter_test.dart';

// _isSimpleQuery mantığını kopyalayarak test ediyoruz
bool isSimpleQuery(String q) {
  final lower = q.toLowerCase().trim();
  final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length > 3) return false;
  const signals = [
    'en ucuz', 'en pahalı', 'en iyi', 'en çok', 'en az',
    'karşılaştır', 'hangisi', 'hangi market', 'hangi', 'nerede',
    'bütçe', ' tl', 'öner', 'tavsiye', 'bugün', 'yarın', 'bu hafta',
    'gelecek', 'kaç', 'ne kadar', 'nasıl', 'neden', 'niye',
    'var mı', 'yok mu', 'var mi', 'yok mi', '?', 'daha iyi',
    'fark', 'yerine', 'gibi', 'alternatif', 'öneri',
  ];
  for (final s in signals) {
    if (lower.contains(s)) return false;
  }
  return true;
}

void main() {
  group('isSimpleQuery - LOCAL olmalı (Gemini gitmemeli)', () {
    final localCases = [
      'peynir',
      'zeytin',
      'yumuşatıcı',
      'deterjan',
      'tavuk',
      'süt',
      'yoğurt',
      'Mehmet efendi kahve',
      'family ıslak mendil',
      'baldo pirinç',
      'torku bitter',
      'besler sucuk',
      'Molfix 6 numara',
      'torku bitterli cikolata',
    ];
    for (final q in localCases) {
      test('"$q" → local', () => expect(isSimpleQuery(q), true));
    }
  });

  group('isSimpleQuery - GEMİNİ gitmeli', () {
    final geminiCases = [
      'en ucuz sucuk',
      'en ucuz peynir altınkılıc',
      'sıvı deterjan nerede ucuz',
      '200 TL bütçem var ne alayım?',
      'Bu hafta deterjan kampanyası var mı?',
      'Hangi market bu hafta daha avantajlı?',
      'hangi ürünlerde kampanya var',
      'bulaşık makinesi tuzu hangisinde en uygun',
      'indirimdeki tuvalet kağıdı hangisinde var',
      'akşam yemeğinde salata yapacağım hangileri nerde uygun',
      'yarın ne var',
      '14 temmuz bim indirimleri',
      'sade kızilay soda 6li',
    ];
    for (final q in geminiCases) {
      test('"$q" → gemini', () => expect(isSimpleQuery(q), false));
    }
  });
}
