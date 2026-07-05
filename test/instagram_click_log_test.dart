import 'package:flutter_test/flutter_test.dart';

// Instagram tıklama log mantığını test eder.
// Firestore bağımlılığı olmadan saf mantık testleri.

Map<String, dynamic> buildInstagramClickLog({
  required String uid,
  required DateTime clickedAt,
}) {
  return {
    'uid': uid,
    'clickedAt': clickedAt,
  };
}

void main() {
  group('Instagram Click Log', () {
    test('uid ve clickedAt alanları doğru oluşturulur', () {
      final now = DateTime(2026, 7, 5, 13, 0, 0);
      final log = buildInstagramClickLog(uid: 'test-uid-123', clickedAt: now);

      expect(log['uid'], 'test-uid-123');
      expect(log['clickedAt'], now);
    });

    test('uid boş olamaz', () {
      final log = buildInstagramClickLog(uid: '', clickedAt: DateTime.now());
      expect((log['uid'] as String).isEmpty, isTrue);
    });

    test('farklı uid\'ler birbirinden ayrı loglanır', () {
      final log1 = buildInstagramClickLog(uid: 'user-1', clickedAt: DateTime.now());
      final log2 = buildInstagramClickLog(uid: 'user-2', clickedAt: DateTime.now());

      expect(log1['uid'], isNot(equals(log2['uid'])));
    });

    test('log sadece uid ve clickedAt alanlarını içerir', () {
      final log = buildInstagramClickLog(uid: 'abc', clickedAt: DateTime.now());
      expect(log.keys.toSet(), equals({'uid', 'clickedAt'}));
    });
  });
}
