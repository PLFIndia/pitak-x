import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
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
            'coverUrl': 'https://covers.openlibrary.org/b/id/1.jpg',
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
      // Allow-listed remote https cover passes through untouched (M15).
      expect(b.coverUrl, 'https://covers.openlibrary.org/b/id/1.jpg');
    });

    test('drops LOCAL cover refs in plain JSON import', () {
      final json = jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'A', 'coverUrl': 'covers/uuid-1.jpg'},
          {'title': 'B', 'coverUrl': 'file:///data/app/covers/x.jpg'},
          {'title': 'C', 'coverUrl': 'https://covers.openlibrary.org/c.jpg'},
        ],
        'wishlist': <dynamic>[],
      });

      final books = importer.parse(json).books;
      expect(books[0].coverUrl, isNull); // relative local dropped
      expect(books[1].coverUrl, isNull); // legacy file:// dropped
      // Allow-listed remote kept (M15: non-allow-listed https is rejected).
      expect(books[2].coverUrl, 'https://covers.openlibrary.org/c.jpg');
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

    test('out-of-range numbers (1e400) never throw', () {
      const importer = PitakaJsonImporter();
      final payload = importer.parse(
        '{"schemaVersion": 1, "books": [{"title": "A", "publishedYear": 1e400,'
        ' "pageCount": 1e999, "copyCount": -1e400}]}',
      );
      expect(payload.books, hasLength(1));
      expect(payload.books.single.publishedYear, isNull);
      expect(payload.books.single.pageCount, isNull);
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

    group('M15 — invalid rows are rejected and reported, never coerced', () {
      String jsonWith({
        List<Map<String, dynamic>> books = const [],
        List<Map<String, dynamic>> wishlist = const [],
      }) => jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': books,
        'wishlist': wishlist,
      });

      test('out-of-range addedDate (max+1) drops the row with an error', () {
        final payload = importer.parse(
          jsonWith(
            books: [
              {'title': 'Bad date', 'addedDate': 8640000000000001},
              {'title': 'Good'},
            ],
          ),
        );
        expect(payload.books.single.title, 'Good');
        expect(payload.parseErrors.single, contains('addedDate'));
        expect(payload.parseErrors.single, contains('Bad date'));
      });

      test('copyCount 0 or negative drops the row', () {
        final payload = importer.parse(
          jsonWith(
            books: [
              {'title': 'Zero copies', 'copyCount': 0},
              {'title': 'Negative', 'copyCount': -3},
              {'title': 'Fine', 'copyCount': 2},
            ],
          ),
        );
        expect(payload.books.single.title, 'Fine');
        expect(payload.parseErrors, hasLength(2));
        expect(payload.parseErrors.first, contains('copyCount'));
      });

      test('blank title drops the row', () {
        final payload = importer.parse(
          jsonWith(
            books: [
              {'title': '   '},
              {'title': 'Real'},
            ],
          ),
        );
        expect(payload.books.single.title, 'Real');
        expect(payload.parseErrors.single, contains('title'));
      });

      test('wishlist priority outside 0..2 drops the row', () {
        final payload = importer.parse(
          jsonWith(
            wishlist: [
              {'title': 'Bad prio', 'priority': 7},
              {'title': 'Good prio', 'priority': 2},
            ],
          ),
        );
        expect(payload.wishlist.single.title, 'Good prio');
        expect(payload.parseErrors.single, contains('priority'));
      });

      test('non-finite priceEstimate (1e400 → Infinity) drops the row', () {
        // Hand-written JSON: jsonEncode itself refuses Infinity (which is
        // exactly the export crash M15 prevents from round-tripping).
        const text =
            '{"schemaVersion": 3, "exportedAt": 0, "books": [],'
            ' "wishlist": ['
            ' {"title": "Inf price", "priceEstimate": 1e400},'
            ' {"title": "NaN price", "priceEstimate": "NaN"},'
            ' {"title": "Ok price", "priceEstimate": 12.5}]}';
        final payload = importer.parse(text);
        expect(payload.wishlist.single.title, 'Ok price');
        expect(payload.parseErrors, hasLength(2));
        expect(payload.parseErrors.first, contains('priceEstimate'));
      });

      test('negative priceEstimate drops the row', () {
        final payload = importer.parse(
          jsonWith(
            wishlist: [
              {'title': 'Neg price', 'priceEstimate': -5},
            ],
          ),
        );
        expect(payload.wishlist, isEmpty);
        expect(payload.parseErrors.single, contains('priceEstimate'));
      });

      test('over-cap addedBy is truncated and reported, row kept', () {
        final payload = importer.parse(
          jsonWith(
            books: [
              {'title': 'Long name', 'addedBy': 'x' * 9000},
            ],
          ),
        );
        expect(payload.books.single.addedBy, hasLength(8000));
        expect(payload.warnings.single, contains('addedBy'));
        expect(payload.warnings.single, contains('shortened'));
        expect(payload.parseErrors, isEmpty);
      });

      test(
        'non-allow-listed https cover is dropped with a warning, row kept',
        () {
          final payload = importer.parse(
            jsonWith(
              books: [
                {
                  'title': 'Bad cover',
                  'coverUrl': 'https://evil.example/c.jpg',
                },
                {
                  'title': 'Good cover',
                  'coverUrl': 'https://covers.openlibrary.org/b/id/1.jpg',
                },
              ],
            ),
          );
          expect(payload.books, hasLength(2));
          expect(payload.books[0].coverUrl, isNull);
          expect(
            payload.books[1].coverUrl,
            'https://covers.openlibrary.org/b/id/1.jpg',
          );
          expect(payload.warnings.single, contains('cover'));
          expect(payload.warnings.single, contains('Bad cover'));
          expect(payload.parseErrors, isEmpty);
        },
      );

      test(
        'wishlist local cover refs are dropped in plain JSON (like books)',
        () {
          final payload = importer.parse(
            jsonWith(
              wishlist: [
                {'title': 'Local ref', 'coverUrl': 'covers/uuid-9.jpg'},
              ],
            ),
          );
          expect(payload.wishlist.single.coverUrl, isNull);
        },
      );

      test(
        'keepLocalCovers still preserves wishlist local refs (bundle path)',
        () {
          const bundleImporter = PitakaJsonImporter(keepLocalCovers: true);
          final payload = bundleImporter.parse(
            jsonWith(
              wishlist: [
                {'title': 'Local ref', 'coverUrl': 'covers/uuid-9.jpg'},
              ],
            ),
          );
          expect(payload.wishlist.single.coverUrl, 'covers/uuid-9.jpg');
        },
      );

      test('a fully valid file still imports with no errors', () {
        final payload = importer.parse(
          jsonWith(
            books: [
              {'title': 'A', 'copyCount': 3, 'addedDate': 1699999999000},
            ],
            wishlist: [
              {'title': 'W', 'priority': 0, 'priceEstimate': 0},
            ],
          ),
        );
        expect(payload.parseErrors, isEmpty);
        expect(payload.books.single.copyCount, 3);
        expect(payload.wishlist.single.priority, 0);
      });
    });
  });
}
