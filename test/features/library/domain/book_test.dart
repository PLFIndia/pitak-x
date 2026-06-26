import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

void main() {
  group('AgeGroup.fromToken (tolerant, mirrors Kotlin)', () {
    test('current tokens round-trip', () {
      for (final v in AgeGroup.values) {
        expect(AgeGroup.fromToken(v.token), v);
      }
    });

    test('current enum names (above_3 …) parse', () {
      expect(AgeGroup.fromToken('above_3'), AgeGroup.above3);
      expect(AgeGroup.fromToken('above_6'), AgeGroup.above6);
      expect(AgeGroup.fromToken('above_10'), AgeGroup.above10);
      expect(AgeGroup.fromToken('above_15'), AgeGroup.above15);
      expect(AgeGroup.fromToken('advanced'), AgeGroup.advanced);
    });

    test('LEGACY pre-"above N" names map per MIGRATION_9_10', () {
      expect(AgeGroup.fromToken('age_0_5'), AgeGroup.above3);
      expect(AgeGroup.fromToken('age_6_10'), AgeGroup.above6);
      expect(AgeGroup.fromToken('age_11_16'), AgeGroup.above10);
      expect(AgeGroup.fromToken('advance'), AgeGroup.advanced);
    });

    test('case-insensitive and whitespace-tolerant', () {
      expect(AgeGroup.fromToken('  ABOVE-3 '), AgeGroup.above3);
      expect(AgeGroup.fromToken('Age_11_16'), AgeGroup.above10);
    });

    test('unknown / blank / null → null (never throws)', () {
      expect(AgeGroup.fromToken(null), isNull);
      expect(AgeGroup.fromToken(''), isNull);
      expect(AgeGroup.fromToken('   '), isNull);
      expect(AgeGroup.fromToken('nonsense'), isNull);
      // above-15 has no legacy source — only its own token/name resolve.
      expect(AgeGroup.fromToken('age_17_plus'), isNull);
    });

    test('sortRank defines band order (not alphabetical)', () {
      final sorted = AgeGroup.values.toList()
        ..sort((a, b) => a.sortRank.compareTo(b.sortRank));
      expect(sorted, [
        AgeGroup.above3,
        AgeGroup.above6,
        AgeGroup.above10,
        AgeGroup.above15,
        AgeGroup.advanced,
      ]);
    });
  });

  group('BookSourceType.fromToken', () {
    test('round-trips and is tolerant', () {
      for (final v in BookSourceType.values) {
        expect(BookSourceTypeX.fromToken(v.token), v);
        expect(BookSourceTypeX.fromToken(v.name), v);
      }
      expect(
        BookSourceTypeX.fromToken('  purchased '),
        BookSourceType.purchased,
      );
      expect(BookSourceTypeX.fromToken(null), isNull);
      expect(BookSourceTypeX.fromToken('bogus'), isNull);
    });
  });

  group('Book', () {
    test('copyWith replaces only given fields', () {
      const book = Book(title: 'A', author: 'X');
      final updated = book.copyWith(author: 'Y', copyCount: 2);
      expect(updated.title, 'A');
      expect(updated.author, 'Y');
      expect(updated.copyCount, 2);
    });

    test('defaults match Kotlin', () {
      const book = Book(title: 'T');
      expect(book.id, Book.emptyId);
      expect(book.copyCount, 1);
      expect(book.needsMetadata, isFalse);
      expect(book.removed, isFalse);
      expect(book.bookUid, isNull);
    });
  });
}
