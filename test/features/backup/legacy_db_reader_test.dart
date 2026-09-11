/// M15 part 2 (astra-review.md): the backup-restore reader is the last
/// ingress that built catalogue entities with the plain constructors. Every
/// row must pass `Book.validate` / `WishlistBook.validate` before it can be
/// persisted, and the archive must be REFUSED (typed `ValidationFailure`,
/// never a throw) on the first invalid row — restore is an authoritative
/// overwrite, so silently skipping or truncating a row would break the
/// zero-data-loss promise.
///
/// These tests open an in-memory `sqlite3` database directly (no archive,
/// no Drift) so each hostile column value is exercised in isolation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late CommonDatabase db;

  setUp(() {
    db = sqlite3.openInMemory();
  });

  tearDown(() {
    db.dispose();
  });

  void createBooks() {
    db.execute('''
      CREATE TABLE books(
        id INTEGER PRIMARY KEY NOT NULL, book_uid TEXT, title TEXT NOT NULL,
        title_transliteration TEXT, author TEXT,
        title_sort TEXT NOT NULL DEFAULT '',
        author_sort TEXT NOT NULL DEFAULT '', isbn TEXT, publisher TEXT,
        published_year INTEGER, genre TEXT, cover_url TEXT, page_count INTEGER,
        language TEXT, notes TEXT, location TEXT, source_type TEXT,
        source_detail TEXT, age_group TEXT, added_date INTEGER NOT NULL,
        copy_count INTEGER NOT NULL DEFAULT 1,
        needs_metadata INTEGER NOT NULL DEFAULT 0,
        removed INTEGER NOT NULL DEFAULT 0, removed_at INTEGER, added_by TEXT);
    ''');
  }

  void createWishlist() {
    db.execute('''
      CREATE TABLE wishlist_books(
        id INTEGER PRIMARY KEY NOT NULL, title TEXT NOT NULL,
        title_transliteration TEXT, author TEXT, isbn TEXT, publisher TEXT,
        published_year INTEGER, cover_url TEXT, price_estimate REAL,
        priority INTEGER NOT NULL DEFAULT 1, notes TEXT, source TEXT NOT NULL,
        added_date INTEGER NOT NULL, purchased INTEGER NOT NULL DEFAULT 0,
        purchased_date INTEGER, needs_metadata INTEGER NOT NULL DEFAULT 0);
    ''');
  }

  /// Inserts one books row; [values] overrides individual columns of a
  /// known-good baseline. Values are SQL literals (e.g. `'1e400'`, `'0'`).
  void insertBook(Map<String, String> values) {
    final cols = <String, String>{
      'id': '42',
      'book_uid': "'uid-42'",
      'title': "'Godan'",
      'added_date': '1699999999000',
      'copy_count': '1',
      ...values,
    };
    db.execute(
      'INSERT INTO books(${cols.keys.join(',')}) '
      'VALUES(${cols.values.join(',')})',
    );
  }

  void insertWishlist(Map<String, String> values) {
    final cols = <String, String>{
      'id': '9',
      'title': "'Wanted'",
      'source': "'SCANNED'",
      'added_date': '1698000000000',
      'priority': '1',
      ...values,
    };
    db.execute(
      'INSERT INTO wishlist_books(${cols.keys.join(',')}) '
      'VALUES(${cols.values.join(',')})',
    );
  }

  Failure readBooksFailure() {
    final result = LegacyDbReader(db).readBooks();
    return result.fold((f) => f, (_) => fail('expected a refusal'));
  }

  List<Book> readBooksOk() {
    final result = LegacyDbReader(db).readBooks();
    return result.fold(
      (f) => fail('unexpected refusal: $f'),
      (rows) => rows.books,
    );
  }

  Failure readWishlistFailure() {
    final result = LegacyDbReader(db).readWishlist();
    return result.fold((f) => f, (_) => fail('expected a refusal'));
  }

  List<WishlistBook> readWishlistOk() {
    final result = LegacyDbReader(db).readWishlist();
    return result.fold(
      (f) => fail('unexpected refusal: $f'),
      (rows) => rows.books,
    );
  }

  group('happy path (byte-for-byte contract preserved)', () {
    test('a fully populated valid row reads exactly as before', () {
      createBooks();
      insertBook({
        'author': "'Premchand'",
        'isbn': "'9788126415236'",
        'published_year': '1936',
        'cover_url': "'covers/abc.jpg'",
        'page_count': '384',
        'copy_count': '3',
        'removed': '1',
        'removed_at': '1700000000000',
        'added_by': "'Asha'",
      });

      final rows = readBooksOk();
      expect(rows.single.id, 42);
      expect(rows.single.bookUid, 'uid-42');
      expect(rows.single.title, 'Godan');
      expect(rows.single.coverUrl, 'covers/abc.jpg');
      expect(rows.single.copyCount, 3);
      expect(rows.single.removedAt, 1700000000000);
    });

    test('a valid wishlist row reads exactly as before', () {
      createWishlist();
      insertWishlist({
        'price_estimate': '19.99',
        'priority': '2',
        'purchased': '1',
        'purchased_date': '1699000000000',
      });

      final rows = readWishlistOk();
      expect(rows.single.id, 9);
      expect(rows.single.priceEstimate, 19.99);
      expect(rows.single.priority, 2);
      expect(rows.single.purchasedDate, 1699000000000);
    });
  });

  group('M15 — hostile books rows are refused, not coerced', () {
    test('added_date above maxDateMillis is refused', () {
      createBooks();
      insertBook({'added_date': '${CatalogueRules.maxDateMillis + 1}'});
      final f = readBooksFailure();
      expect(f, isA<ValidationFailure>());
      expect((f as ValidationFailure).message, contains('books row 42'));
      expect(f.message, contains('date added'));
    });

    test('a negative added_date is refused', () {
      createBooks();
      insertBook({'added_date': '-5'});
      expect(readBooksFailure(), isA<ValidationFailure>());
    });

    test('removed_at above maxDateMillis is refused', () {
      createBooks();
      insertBook({
        'removed': '1',
        'removed_at': '${CatalogueRules.maxDateMillis + 1}',
      });
      final f = readBooksFailure();
      expect((f as ValidationFailure).message, contains('removal date'));
    });

    test('copy_count 0 is refused (availability math breaks)', () {
      createBooks();
      insertBook({'copy_count': '0'});
      final f = readBooksFailure();
      expect((f as ValidationFailure).message, contains('Copies'));
    });

    test('page_count 0 is refused', () {
      createBooks();
      insertBook({'page_count': '0'});
      expect(readBooksFailure(), isA<ValidationFailure>());
    });

    test('published_year 0 and 10000 are refused', () {
      createBooks();
      insertBook({'published_year': '0'});
      expect(readBooksFailure(), isA<ValidationFailure>());

      db.execute('DELETE FROM books');
      insertBook({'published_year': '10000'});
      expect(readBooksFailure(), isA<ValidationFailure>());
    });

    test('a blank title is refused', () {
      createBooks();
      insertBook({'title': "'   '"});
      final f = readBooksFailure();
      expect((f as ValidationFailure).message, contains('title'));
    });

    test('a NULL title is refused (crafted file has no NOT NULL)', () {
      createBooks();
      // Bypass the schema's NOT NULL by building the table without it.
      db
        ..execute('DROP TABLE books')
        ..execute('''
        CREATE TABLE books(
          id INTEGER PRIMARY KEY NOT NULL, book_uid TEXT, title TEXT,
          title_transliteration TEXT, author TEXT,
          title_sort TEXT NOT NULL DEFAULT '',
          author_sort TEXT NOT NULL DEFAULT '', isbn TEXT, publisher TEXT,
          published_year INTEGER, genre TEXT, cover_url TEXT,
          page_count INTEGER, language TEXT, notes TEXT, location TEXT,
          source_type TEXT, source_detail TEXT, age_group TEXT,
          added_date INTEGER NOT NULL, copy_count INTEGER NOT NULL DEFAULT 1,
          needs_metadata INTEGER NOT NULL DEFAULT 0,
          removed INTEGER NOT NULL DEFAULT 0, removed_at INTEGER,
          added_by TEXT);
      ''');
      insertBook({'title': 'NULL'});
      expect(readBooksFailure(), isA<ValidationFailure>());
    });

    test('over-cap notes are refused (D1 = a: no truncation on restore)', () {
      createBooks();
      final long = 'x' * (CatalogueRules.maxFieldChars + 1);
      insertBook({'notes': "'$long'"});
      final f = readBooksFailure();
      expect(f, isA<ValidationFailure>());
      expect((f as ValidationFailure).message, contains('notes'));
    });

    test('over-cap added_by is refused', () {
      createBooks();
      final long = 'y' * (CatalogueRules.maxFieldChars + 1);
      insertBook({'added_by': "'$long'"});
      expect(readBooksFailure(), isA<ValidationFailure>());
    });

    test('the refusal message names table, row id and field — never the '
        'value', () {
      createBooks();
      insertBook({'copy_count': '0', 'notes': "'SECRET-VALUE'"});
      final f = readBooksFailure() as ValidationFailure;
      expect(f.message, contains('books'));
      expect(f.message, contains('42'));
      expect(f.message, isNot(contains('SECRET-VALUE')));
    });
  });

  group('M15 — covers are normalised (dropped), never a rejection', () {
    test('an http:// cover is dropped and counted', () {
      createBooks();
      insertBook({'cover_url': "'http://evil.example/x.jpg'"});
      final result = LegacyDbReader(db).readBooks();
      final rows = result.fold((f) => fail('must not refuse: $f'), (r) => r);
      expect(rows.books.single.coverUrl, isNull);
      expect(rows.coversDropped, 1);
    });

    test('a traversal cover is dropped and counted', () {
      createBooks();
      insertBook({'cover_url': "'covers/../../etc/passwd'"});
      final result = LegacyDbReader(db).readBooks();
      final rows = result.fold((f) => fail('must not refuse: $f'), (r) => r);
      expect(rows.books.single.coverUrl, isNull);
      expect(rows.coversDropped, 1);
    });

    test('a non-allow-listed https cover is dropped and counted', () {
      createBooks();
      insertBook({'cover_url': "'https://tracker.example/c.jpg'"});
      final result = LegacyDbReader(db).readBooks();
      final rows = result.fold((f) => fail('must not refuse: $f'), (r) => r);
      expect(rows.books.single.coverUrl, isNull);
      expect(rows.coversDropped, 1);
    });

    test('an allow-listed https cover is kept and not counted', () {
      createBooks();
      insertBook({
        'cover_url': "'https://covers.openlibrary.org/b/id/1-L.jpg'",
      });
      final result = LegacyDbReader(db).readBooks();
      final rows = result.fold((f) => fail('must not refuse: $f'), (r) => r);
      expect(rows.books.single.coverUrl, isNotNull);
      expect(rows.coversDropped, 0);
    });
  });

  group('M15 — _int must not throw on non-finite REAL columns', () {
    test(
      'added_date holding REAL Infinity is a typed refusal, not a throw',
      () {
        createBooks();
        // SQLite is dynamically typed: an INTEGER column can hold a REAL.
        // 1e400 is stored as +Inf; Dart double.toInt() on it THROWS. The reader
        // must refuse the row, not crash and not silently coerce to "unset".
        insertBook({'added_date': '1e400'});
        final f = readBooksFailure();
        expect(f, isA<ValidationFailure>());
        expect((f as ValidationFailure).message, contains('date added'));
      },
    );

    // Note: a NaN added_date cannot be tested here — SQLite stores NaN as
    // NULL (verified against the pinned SDK), and the books schema declares
    // added_date NOT NULL, so the INSERT itself is rejected. The non-finite
    // path is fully covered by the Infinity test above.
  });

  group('M15 — hostile wishlist rows are refused', () {
    test('priority 7 is refused (no matching dropdown item)', () {
      createWishlist();
      insertWishlist({'priority': '7'});
      final f = readWishlistFailure();
      expect((f as ValidationFailure).message, contains('priority'));
    });

    test('priority -1 is refused', () {
      createWishlist();
      insertWishlist({'priority': '-1'});
      expect(readWishlistFailure(), isA<ValidationFailure>());
    });

    test(
      'a NaN price_estimate is stored as NULL by SQLite → kept as absent',
      () {
        createWishlist();
        // SQLite stores NaN as NULL, so the hostile NaN never reaches the
        // reader as a double; NULL price is the legitimate "unknown" state.
        insertWishlist({'price_estimate': '0.0/0.0'});
        expect(readWishlistOk().single.priceEstimate, isNull);
      },
    );

    test('an Infinity price_estimate is refused', () {
      createWishlist();
      insertWishlist({'price_estimate': '1e400'});
      expect(readWishlistFailure(), isA<ValidationFailure>());
    });

    test('purchased_date above maxDateMillis is refused', () {
      createWishlist();
      insertWishlist({
        'purchased': '1',
        'purchased_date': '${CatalogueRules.maxDateMillis + 1}',
      });
      expect(readWishlistFailure(), isA<ValidationFailure>());
    });

    test('a wishlist cover on a non-allow-listed host is dropped', () {
      createWishlist();
      insertWishlist({'cover_url': "'https://tracker.example/c.jpg'"});
      final result = LegacyDbReader(db).readWishlist();
      final rows = result.fold((f) => fail('must not refuse: $f'), (r) => r);
      expect(rows.books.single.coverUrl, isNull);
      expect(rows.coversDropped, 1);
    });
  });
}
