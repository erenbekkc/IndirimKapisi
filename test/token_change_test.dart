import 'package:flutter_test/flutter_test.dart';

// FCM token değişim mantığını test eder.
// Firestore/FCM bağımlılığı olmadan saf mantık testleri.

bool shouldSaveToFirestore({
  required String? newToken,
  required String? savedToken,
}) {
  return newToken != null && newToken != savedToken;
}

void main() {
  group('FCM Token Değişim Mantığı', () {
    test('Yeni token null ise Firestore\'a yazılmaz', () {
      expect(shouldSaveToFirestore(newToken: null, savedToken: 'eski-token'), isFalse);
    });

    test('Token değişmemişse Firestore\'a yazılmaz', () {
      expect(shouldSaveToFirestore(newToken: 'abc123', savedToken: 'abc123'), isFalse);
    });

    test('Token değişmişse Firestore\'a yazılır', () {
      expect(shouldSaveToFirestore(newToken: 'yeni-token', savedToken: 'eski-token'), isTrue);
    });

    test('Daha önce hiç kaydedilmemişse (savedToken null) yazılır', () {
      expect(shouldSaveToFirestore(newToken: 'ilk-token', savedToken: null), isTrue);
    });

    test('İkisi de null ise yazılmaz', () {
      expect(shouldSaveToFirestore(newToken: null, savedToken: null), isFalse);
    });

    test('Boş string ile null farklı token sayılır', () {
      expect(shouldSaveToFirestore(newToken: 'abc', savedToken: ''), isTrue);
    });
  });
}
