import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

void main() {
  group('WishlistBook.validate (M15)', () {
    test('accepts a minimal valid entry', () {
      final r = WishlistBook.validate(const WishlistBook(title: 'Wanted'));
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.title, 'Wanted');
    });

    test('rejects a blank title', () {
      final r = WishlistBook.validate(const WishlistBook(title: ''));
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'title');
    });

    test('rejects a priority outside 0..2 (dropdown has no such item)', () {
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priority: 3),
        ).isLeft(),
        isTrue,
      );
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priority: -1),
        ).isLeft(),
        isTrue,
      );
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priority: WishlistBook.priorityLow),
        ).isRight(),
        isTrue,
      );
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priority: WishlistBook.priorityHigh),
        ).isRight(),
        isTrue,
      );
    });

    test('rejects non-finite and negative priceEstimate', () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -0.01,
      ]) {
        final r = WishlistBook.validate(
          WishlistBook(title: 'A', priceEstimate: bad),
        );
        expect(r.isLeft(), isTrue, reason: 'price $bad must be rejected');
        expect(r.getLeft().toNullable()!.single.field, 'priceEstimate');
      }
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priceEstimate: 0),
        ).isRight(),
        isTrue,
      );
      expect(
        WishlistBook.validate(
          const WishlistBook(title: 'A', priceEstimate: 12.5),
        ).isRight(),
        isTrue,
      );
    });

    test('rejects addedDate / purchasedDate above the max date millis', () {
      expect(
        WishlistBook.validate(
          const WishlistBook(
            title: 'A',
            addedDate: CatalogueRules.maxDateMillis + 1,
          ),
        ).isLeft(),
        isTrue,
      );
      expect(
        WishlistBook.validate(
          const WishlistBook(
            title: 'A',
            purchasedDate: CatalogueRules.maxDateMillis + 1,
          ),
        ).isLeft(),
        isTrue,
      );
      expect(
        WishlistBook.validate(const WishlistBook(title: 'A')).isRight(),
        isTrue,
      );
    });

    test('normalises a non-allow-listed remote cover URL to null', () {
      // Same rationale as Book.validate: never trap a pre-existing row.
      final r = WishlistBook.validate(
        const WishlistBook(title: 'A', coverUrl: 'https://evil.example/c.jpg'),
      );
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.coverUrl, isNull);
    });

    test('rejects an over-cap notes field', () {
      final r = WishlistBook.validate(
        WishlistBook(
          title: 'A',
          notes: 'x' * (CatalogueRules.maxFieldChars + 1),
        ),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'notes');
    });
  });
}
