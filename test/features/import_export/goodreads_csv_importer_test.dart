import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/goodreads_csv_importer.dart';

void main() {
  const importer = GoodreadsCsvImporter();

  String csv(List<List<String>> rows) =>
      rows.map((r) => r.join(',')).join('\n');

  group('GoodreadsCsvImporter', () {
    test('routes to-read to wishlist, others to library', () {
      final text = csv([
        ['Title', 'Author', 'ISBN13', 'Exclusive Shelf'],
        ['Owned Book', 'Author A', '="9780000000001"', 'read'],
        ['Wanted Book', 'Author B', '="9780000000002"', 'to-read'],
      ]);
      final payload = importer.parse(text);
      expect(payload.parseErrors, isEmpty);
      expect(payload.books.single.title, 'Owned Book');
      expect(payload.wishlist.single.title, 'Wanted Book');
    });

    test('unwraps Goodreads ="..." ISBN and strips hyphens', () {
      final text = csv([
        ['Title', 'ISBN13', 'Exclusive Shelf'],
        ['B', '="978-0-00-000000-1"', 'read'],
      ]);
      expect(importer.parse(text).books.single.isbn, '9780000000001');
    });

    test('prefers ISBN13 over ISBN10', () {
      final text = csv([
        ['Title', 'ISBN', 'ISBN13', 'Exclusive Shelf'],
        ['B', '="0000000001"', '="9780000000001"', 'read'],
      ]);
      expect(importer.parse(text).books.single.isbn, '9780000000001');
    });

    test('falls back to ISBN10 when ISBN13 empty', () {
      final text = csv([
        ['Title', 'ISBN', 'ISBN13', 'Exclusive Shelf'],
        ['B', '="0000000001"', '=""', 'read'],
      ]);
      expect(importer.parse(text).books.single.isbn, '0000000001');
    });

    test('collects per-row error for a missing title, keeps going', () {
      final text = csv([
        ['Title', 'Exclusive Shelf'],
        ['', 'read'],
        ['Good', 'read'],
      ]);
      final payload = importer.parse(text);
      expect(payload.books.single.title, 'Good');
      expect(payload.parseErrors.single, contains('Row 2'));
    });

    test('rejects a non-Goodreads CSV (missing required headers)', () {
      final text = csv([
        ['Foo', 'Bar'],
        ['1', '2'],
      ]);
      final payload = importer.parse(text);
      expect(payload.isEmpty, isTrue);
      expect(payload.parseErrors.single, contains('missing columns'));
    });

    test('empty file reports empty', () {
      final payload = importer.parse('');
      expect(payload.parseErrors.single, contains('empty'));
    });

    test('Year Published falls back to Original Publication Year', () {
      final text = csv([
        [
          'Title',
          'Year Published',
          'Original Publication Year',
          'Exclusive Shelf',
        ],
        ['B', '', '1925', 'read'],
      ]);
      expect(importer.parse(text).books.single.publishedYear, 1925);
    });
  });
}
