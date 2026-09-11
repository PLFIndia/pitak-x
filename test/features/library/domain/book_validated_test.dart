import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

void main() {
  group('Book.validate (M15)', () {
    test('accepts a minimal valid book', () {
      final r = Book.validate(const Book(title: 'Godaan'));
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.title, 'Godaan');
    });

    test('rejects a blank title (whitespace-only)', () {
      final r = Book.validate(const Book(title: '   '));
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'title');
    });

    test('trims the title', () {
      final r = Book.validate(const Book(title: '  Godaan  '));
      expect(r.toNullable()!.title, 'Godaan');
    });

    test('rejects addedDate above the max date millis', () {
      final r = Book.validate(
        const Book(title: 'A', addedDate: CatalogueRules.maxDateMillis + 1),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'addedDate');
    });

    test('rejects a negative addedDate; 0 stays valid (unset)', () {
      expect(
        Book.validate(const Book(title: 'A', addedDate: -1)).isLeft(),
        isTrue,
      );
      expect(Book.validate(const Book(title: 'A')).isRight(), isTrue);
    });

    test('rejects copyCount 0 and negative', () {
      expect(
        Book.validate(const Book(title: 'A', copyCount: 0)).isLeft(),
        isTrue,
      );
      expect(
        Book.validate(const Book(title: 'A', copyCount: -2)).isLeft(),
        isTrue,
      );
      expect(Book.validate(const Book(title: 'A')).isRight(), isTrue);
    });

    test('rejects pageCount 0; null and positive pass', () {
      expect(
        Book.validate(const Book(title: 'A', pageCount: 0)).isLeft(),
        isTrue,
      );
      expect(
        Book.validate(const Book(title: 'A', pageCount: 384)).isRight(),
        isTrue,
      );
      expect(Book.validate(const Book(title: 'A')).isRight(), isTrue);
    });

    test('rejects publishedYear 0 and 10000; 1 and 9999 pass', () {
      expect(
        Book.validate(const Book(title: 'A', publishedYear: 0)).isLeft(),
        isTrue,
      );
      expect(
        Book.validate(const Book(title: 'A', publishedYear: 10000)).isLeft(),
        isTrue,
      );
      expect(
        Book.validate(const Book(title: 'A', publishedYear: 1)).isRight(),
        isTrue,
      );
      expect(
        Book.validate(const Book(title: 'A', publishedYear: 9999)).isRight(),
        isTrue,
      );
    });

    test('rejects a removedAt above the max date millis', () {
      final r = Book.validate(
        const Book(
          title: 'A',
          removed: true,
          removedAt: CatalogueRules.maxDateMillis + 1,
        ),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'removedAt');
    });

    test('rejects an over-cap text field (addedBy)', () {
      final r = Book.validate(
        Book(title: 'A', addedBy: 'x' * (CatalogueRules.maxFieldChars + 1)),
      );
      expect(r.isLeft(), isTrue);
      expect(r.getLeft().toNullable()!.single.field, 'addedBy');
    });

    test('normalises a non-allow-listed remote cover URL to null', () {
      // Not a rejection: a pre-M15 database row could already carry such a
      // URL, and rejecting would make that book uneditable forever (the form
      // copies base.coverUrl verbatim). The cover is inert anyway — display
      // and publish re-check the allow-list — so it is dropped, and the
      // importer reports the drop as a warning.
      final r = Book.validate(
        const Book(title: 'A', coverUrl: 'https://evil.example/c.jpg'),
      );
      expect(r.isRight(), isTrue);
      expect(r.toNullable()!.coverUrl, isNull);
    });

    test('accepts allow-listed remote covers and safe local refs', () {
      expect(
        Book.validate(
          const Book(
            title: 'A',
            coverUrl: 'https://covers.openlibrary.org/b/id/1.jpg',
          ),
        ).isRight(),
        isTrue,
      );
      expect(
        Book.validate(
          const Book(title: 'A', coverUrl: 'covers/uuid-1.jpg'),
        ).isRight(),
        isTrue,
      );
      // Legacy file:// local refs stay valid (old DB rows must still edit).
      expect(
        Book.validate(
          const Book(title: 'A', coverUrl: 'file:///data/app/covers/x.jpg'),
        ).isRight(),
        isTrue,
      );
      // Traversal / smuggling local refs are normalised away too.
      final traversal = Book.validate(
        const Book(title: 'A', coverUrl: 'covers/../x.jpg'),
      );
      expect(traversal.isRight(), isTrue);
      expect(traversal.toNullable()!.coverUrl, isNull);
      // Blank is normalised to null (no cover).
      expect(
        Book.validate(
          const Book(title: 'A', coverUrl: '   '),
        ).toNullable()!.coverUrl,
        isNull,
      );
    });

    test('collects multiple field errors at once', () {
      final r = Book.validate(
        const Book(title: '  ', copyCount: 0, publishedYear: 0),
      );
      final errors = r.getLeft().toNullable()!;
      expect(errors.length, greaterThanOrEqualTo(3));
      expect(
        errors.map((e) => e.field),
        containsAll(['title', 'copyCount', 'publishedYear']),
      );
    });
  });
}
