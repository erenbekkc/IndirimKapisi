import 'package:flutter_test/flutter_test.dart';

// Chatbot markdown temizleme pipeline'ını test eder.
// AI yanıtındaki istenmeyen formatlar temizlenmeli.

String cleanMarkdown(String reply) {
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
  return reply;
}

void main() {
  group('Markdown Temizleme', () {
    test('# başlıklar kaldırılır', () {
      final result = cleanMarkdown('# BİM Taze Kaşar Peyniri\nAktif kampanya yok.');
      expect(result, isNot(contains('#')));
      expect(result, contains('Aktif kampanya yok.'));
    });

    test('## ve ### başlıklar da kaldırılır', () {
      final result = cleanMarkdown('## Önerilerim:\n### Alt başlık\nMetin');
      expect(result, isNot(contains('##')));
      expect(result, isNot(contains('###')));
    });

    test('Tablo satırları kaldırılır', () {
      final result = cleanMarkdown('Merhaba\n| Ürün | Fiyat |\n| --- | --- |\nDevam');
      expect(result, isNot(contains('|')));
    });

    test('Numaralı liste satırları kaldırılır', () {
      final result = cleanMarkdown('1. A101\'de bakabilirsiniz\n2. BİM\'e gidin');
      expect(result.trim(), isEmpty);
    });

    test('Madde işareti satırları (- ile) kaldırılır', () {
      final result = cleanMarkdown('- A101\'de peynir seçenekleri\n- BİM\'de başka ürünler');
      expect(result.trim(), isEmpty);
    });

    test('Madde işareti satırları (• ile) kaldırılır', () {
      final result = cleanMarkdown('• Migros\'ta kampanya var\n• BİM\'de fırsat');
      expect(result.trim(), isEmpty);
    });

    test('**bold** işaretleri metni koruyarak kaldırılır', () {
      final result = cleanMarkdown('**BİM**\'de kampanya yok.');
      expect(result, contains('BİM'));
      expect(result, isNot(contains('**')));
    });

    test('Gerçek AI yanıtı örneği temizlenir', () {
      const input = '# BİM Taze Kaşar Peyniri 🧀\n'
          'Maalesef şu anda aktif kampanyalarda **BİM\'de taze kaşar peyniri** bulunmamaktadır.\n'
          '## Önerilerim:\n'
          '- **A101**\'de peynir seçeneklerini kontrol edebilirsiniz\n'
          '- **BİM**\'de başka peynir çeşitleri olabilir\n'
          '- Kampanyalar sık güncellendiği için birkaç gün sonra kontrol edin';
      final result = cleanMarkdown(input);
      expect(result, isNot(contains('#')));
      expect(result, isNot(contains('**')));
      expect(result, isNot(contains('- ')));
      expect(result, contains('BİM'));
      expect(result, contains('bulunmamaktadır'));
    });

    test('Normal metin bozulmaz', () {
      const input = 'Migros\'ta 3 tavuk kampanyası buldum, aşağıda görebilirsin.';
      final result = cleanMarkdown(input);
      expect(result, equals(input));
    });

    test('3+ boş satır 2\'ye indirilir', () {
      final result = cleanMarkdown('Metin A\n\n\n\nMetin B');
      expect(result, equals('Metin A\n\nMetin B'));
    });
  });
}
