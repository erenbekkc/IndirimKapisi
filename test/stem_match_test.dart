import 'package:flutter_test/flutter_test.dart';

String toAscii(String s) => s
    .replaceAll('ç', 'c')
    .replaceAll('ş', 's')
    .replaceAll('g', 'g')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ı', 'i')
    .replaceAll('İ', 'i');

const validSuffixes = [
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
  'lerinde', 'larinda', 'lerinden', 'larindan',
  'lerini', 'larini',
];

bool stemMatch(String word, String term) {
  final w = toAscii(word);
  final t = toAscii(term);
  if (!w.startsWith(t)) return false;
  return validSuffixes.contains(w.substring(t.length));
}

bool productContainsTerm(String product, String term) {
  for (final w in product.split(RegExp(r'[\s\-\/,()+]+'))) {
    if (stemMatch(w, term)) return true;
  }
  return false;
}

bool multiWordMatch(String product, List<String> terms) {
  return terms.where((t) => t.length >= 2).every((t) => productContainsTerm(product, t));
}

void main() {
  group('Doğru eşleşmeler (✓)', () {
    final cases = [
      ['peynir', 'Beyaz Peynir 400g'],
      ['yumurta', 'Yumurta 10lu'],
      ['deterjan', 'Ariel Deterjan 4kg'],
      ['süt', 'Süt 1lt'],
      ['tavuk', 'Bütün Tavuk'],
      ['çay', 'Çaykur Çay 1kg'],
      ['kahve', 'Türk Kahvesi'],
    ];
    for (final c in cases) {
      test('"${c[0]}" → "${c[1]}"', () =>
          expect(productContainsTerm(c[1].toLowerCase(), c[0]), true));
    }
  });

  group('Türkçe karakter yazım hatası (✓)', () {
    final cases = [
      ['cay', 'Çaykur Çay 1kg'],
      ['sampuan', 'Şampuan 400ml'],
      ['yogurt', 'Yoğurt 500g'],
      ['sut', 'Süt 1lt'],
      ['kuruyemis', 'Kuruyemiş Çeşitleri'],
    ];
    for (final c in cases) {
      test('"${c[0]}" (typo) → "${c[1]}"', () =>
          expect(productContainsTerm(c[1].toLowerCase(), c[0]), true));
    }
  });

  group('Yanlış eşleşmeler (✗)', () {
    final cases = [
      ['yumurta', 'Yumurtalı Kek'],
      ['süt', 'Sütlü Çikolata'],
      ['süt', 'Laktozsüt'],
      ['kahve', 'Kahveli Çay'],
      ['hindi', 'Hindistan Cevizi'],
      ['ceviz', 'Hindistan Cevizli Yağlı Sprey'],
      ['çay', 'Çaylak'],
    ];
    for (final c in cases) {
      test('"${c[0]}" → "${c[1]}" eşleşmemeli', () =>
          expect(productContainsTerm(c[1].toLowerCase(), c[0]), false));
    }
  });

  group('Çok kelimeli: TÜM kelimeler eşleşmeli', () {
    test('"sıvı yağ" → "Sıvı Ayçiçek Yağı" ✓', () =>
        expect(multiWordMatch('sıvı ayçiçek yağı', ['sıvı', 'yağ']), true));
    test('"sıvı yağ" → "Sıvı Sabun" ✗', () =>
        expect(multiWordMatch('sıvı sabun 500ml', ['sıvı', 'yağ']), false));
    test('"sıvı yağ" → "Sıvı Deterjan" ✗', () =>
        expect(multiWordMatch('sıvı deterjan 3kg', ['sıvı', 'yağ']), false));
    test('"sıvı yağ" → "Yağlı Hijyenik Ped" ✗', () =>
        expect(multiWordMatch('yağlı hijyenik ped', ['sıvı', 'yağ']), false));
    test('"filtre kahve" → "Türk Kahvesi" ✗', () =>
        expect(multiWordMatch('türk kahvesi 100g', ['filtre', 'kahve']), false));
    test('"filtre kahve" → "Filtre Kahve 250g" ✓', () =>
        expect(multiWordMatch('filtre kahve 250g', ['filtre', 'kahve']), true));
    test('"bebek bez" → "Bebek Bezlerinde 1 Alana 1 Bedava" ✓', () =>
        expect(multiWordMatch('bebek bezlerinde 1 alana 1 bedava', ['bebek', 'bez']), true));
  });
}
