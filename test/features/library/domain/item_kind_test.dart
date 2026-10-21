import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

// ADR 0013 F3: the kind token is persisted and carried in every wire format,
// so its parse must be tolerant, stable and never default an UNKNOWN value to
// a book (F6 — unknown kinds are refused by the caller, not disguised).
void main() {
  group('ItemKind', () {
    test('tokens round-trip and stay in the SQL-literal-safe charset', () {
      final safe = RegExp(r'^[a-z-]+$');
      for (final kind in ItemKind.values) {
        expect(ItemKind.fromToken(kind.token), kind);
        expect(safe.hasMatch(kind.token), isTrue, reason: kind.token);
      }
      expect(ItemKind.book.token, 'book');
      expect(ItemKind.magazineIssue.token, 'magazine-issue');
      expect(ItemKind.other.token, 'other');
    });

    test('tokens are distinct', () {
      final tokens = ItemKind.values.map((k) => k.token).toSet();
      expect(tokens, hasLength(ItemKind.values.length));
    });

    test('fromToken is tolerant of case, whitespace and the enum name', () {
      expect(ItemKind.fromToken(' Magazine-Issue '), ItemKind.magazineIssue);
      expect(ItemKind.fromToken('magazineIssue'), ItemKind.magazineIssue);
      expect(ItemKind.fromToken('BOOK'), ItemKind.book);
      expect(ItemKind.fromToken('Other'), ItemKind.other);
    });

    test(
      'fromToken returns null for blank, null and unknown — never a book',
      () {
        expect(ItemKind.fromToken(null), isNull);
        expect(ItemKind.fromToken(''), isNull);
        expect(ItemKind.fromToken('   '), isNull);
        expect(ItemKind.fromToken('dvd'), isNull);
        expect(ItemKind.fromToken('magazine'), isNull);
        expect(ItemKind.fromToken("book'; DROP TABLE books"), isNull);
      },
    );

    test('labels are the plural chip names (U1)', () {
      expect(ItemKind.book.label, 'Books');
      expect(ItemKind.magazineIssue.label, 'Magazines');
      expect(ItemKind.other.label, 'Others');
    });

    test('the chip row order is books, magazines, others', () {
      expect(ItemKind.values, [
        ItemKind.book,
        ItemKind.magazineIssue,
        ItemKind.other,
      ]);
    });
  });
}
