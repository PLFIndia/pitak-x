import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

void main() {
  const importer = PitakaJsonImporter();

  group('PitakaJsonImporter', () {
    test('reads a v3 export with all book fields (camelCase keys)', () {
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 1700000000000,
        'libraryId': 'lib-1',
        'libraryName': 'Home',
        'books': [
          {
            'id': 42,
            'bookUid': 'uid-abc',
            'title': 'गोदान',
            'titleTransliteration': 'Godaan',
            'author': 'Premchand',
            'isbn': '9788126415236',
            'publisher': 'Diamond',
            'publishedYear': 1936,
            'genre': 'Fiction',
            'coverUrl': 'https://example.com/c.jpg',
            'pageCount': 384,
            'language': 'hi',
            'notes': 'classic',
            'location': 'Shelf 3',
            'sourceType': 'GIFT',
            'sourceDetail': 'from Ravi',
            'ageGroup': 'advanced',
            'addedDate': 1699999999000,
            'copyCount': 2,
            'needsMetadata': false,
            'removed': false,
            'removedAt': null,
            'addedBy': 'Asha',
          },
        ],
        'wishlist': <dynamic>[],
      });

      final payload = importer.parse(json);
      expect(payload.parseErrors, isEmpty);
      final b = payload.books.single;
      // Fresh id on import — the file's id is ignored.
      expect(b.id, Book.emptyId);
      expect(b.bookUid, 'uid-abc');
      expect(b.title, 'गोदान');
      expect(b.titleTransliteration, 'Godaan');
      expect(b.publishedYear, 1936);
      expect(b.pageCount, 384);
      expect(b.sourceType, BookSourceType.gift);
      expect(b.ageGroup, AgeGroup.advanced);
      expect(b.copyCount, 2);
      expect(b.addedBy, 'Asha');
      // Remote https cover passes through untouched.
      expect(b.coverUrl, 'https://example.com/c.jpg');
    });

    test('drops LOCAL cover refs in plain JSON import', () {
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'A', 'coverUrl': 'covers/uuid-1.jpg'},
          {'title': 'B', 'coverUrl': 'file:///data/app/covers/x.jpg'},
          {'title': 'C', 'coverUrl': 'https://remote/x.jpg'},
        ],
        'wishlist': <dynamic>[],
      });

      final books = importer.parse(json).books;
      expect(books[0].coverUrl, isNull); // relative local dropped
      expect(books[1].coverUrl, isNull); // legacy file:// dropped
      expect(books[2].coverUrl, 'https://remote/x.jpg'); // remote kept
    });

    test('keepLocalCovers preserves local refs (bundle path)', () {
      const bundleImporter = PitakaJsonImporter(keepLocalCovers: true);
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'A', 'coverUrl': 'covers/uuid-1.jpg'},
        ],
        'wishlist': <dynamic>[],
      });
      expect(
        bundleImporter.parse(json).books.single.coverUrl,
        'covers/uuid-1.jpg',
      );
    });

    test('refuses a schemaVersion newer than this build', () {
      final json = jsonEncode({
        'schemaVersion': 99,
        'exportedAt': 0,
        'books': <dynamic>[],
        'wishlist': <dynamic>[],
      });
      final payload = importer.parse(json);
      expect(payload.isEmpty, isTrue);
      expect(payload.parseErrors.single, contains('newer version'));
    });

    test('tolerant legacy age token (age_11_16 → above-10)', () {
      final json = jsonEncode({
        'schemaVersion': 1,
        'exportedAt': 0,
        'books': [
          {'title': 'Old', 'ageGroup': 'age_11_16'},
        ],
        'wishlist': <dynamic>[],
      });
      expect(importer.parse(json).books.single.ageGroup, AgeGroup.above10);
    });

    test('reads wishlist fields incl. priceEstimate and priority', () {
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': <dynamic>[],
        'wishlist': [
          {
            'title': 'Wanted',
            'priceEstimate': 12.5,
            'priority': 2,
            'source': 'SCANNED',
            'purchased': true,
            'purchasedDate': 123,
          },
        ],
      });
      final w = importer.parse(json).wishlist.single;
      expect(w.id, WishlistBook.emptyId);
      expect(w.priceEstimate, 12.5);
      expect(w.priority, WishlistBook.priorityHigh);
      expect(w.source, WishlistSource.scanned);
      expect(w.purchased, isTrue);
      expect(w.purchasedDate, 123);
    });

    test('malformed JSON does not throw — returns an error', () {
      final payload = importer.parse('{not json');
      expect(payload.isEmpty, isTrue);
      expect(payload.parseErrors, isNotEmpty);
    });

    test('non-object JSON returns an error', () {
      final payload = importer.parse('[]');
      expect(payload.isEmpty, isTrue);
      expect(payload.parseErrors, isNotEmpty);
    });

    test('parseEnvelope reads libraryId/libraryName off the envelope', () {
      final json = jsonEncode({
        'schemaVersion': 3,
        'libraryId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'libraryName': '  Riverside  ',
        'books': <dynamic>[],
        'wishlist': <dynamic>[],
      });
      final env = importer.parseEnvelope(json);
      expect(env.libraryId, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(env.libraryName, 'Riverside'); // trimmed
    });

    test('parseEnvelope returns blanks for a missing envelope / junk', () {
      expect(importer.parseEnvelope('{"schemaVersion":3}').libraryId, '');
      expect(importer.parseEnvelope('{not json').libraryId, '');
      expect(importer.parseEnvelope('[]').libraryName, '');
    });
  });
}
