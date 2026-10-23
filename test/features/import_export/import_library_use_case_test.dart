import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../periodicals/application/periodical_fakes.dart';

/// In-memory fakes so the use case is tested without Drift.
class _FakeBookRepo implements CatalogueItemRepository {
  final List<CatalogueItem> stored = [];

  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(stored.where((b) => b.itemUid == itemUid).firstOrNull);

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async {
    final match = stored.where((b) => b.isbn == isbn).firstOrNull;
    return right(match);
  }

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    final withId = book.copyWith(id: stored.length + 1);
    stored.add(withId);
    return right(withId);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    final i = stored.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    stored[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async {
    stored.addAll(books);
    return right(books.length);
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async {
    stored
      ..clear()
      ..addAll(books);
    return right(books.length);
  }
}

class _FakeWishlistRepo implements WishlistRepository {
  final List<WishlistBook> stored = [];

  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async {
    final match = stored.where((b) => b.isbn == isbn).firstOrNull;
    return right(match);
  }

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    final withId = book.copyWith(id: stored.length + 1);
    stored.add(withId);
    return right(withId);
  }

  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async {
    final i = stored.indexWhere((b) => b.id == book.id);
    if (i >= 0) {
      stored[i] = book;
      return right(book);
    }
    return insert(book);
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async =>
      right(stored.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async {
    final i = stored.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    stored[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    stored.removeWhere((b) => b.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books) async {
    stored.addAll(books);
    return right(books.length);
  }
}

void main() {
  late _FakeBookRepo bookRepo;
  late _FakeWishlistRepo wishlistRepo;
  late ImportLibraryUseCase useCase;

  setUp(() {
    bookRepo = _FakeBookRepo();
    wishlistRepo = _FakeWishlistRepo();
    useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: bookRepo,
      wishlistRepo: wishlistRepo,
      periodicalRepo: FakePeriodicals(),
    );
  });

  ImportSummary ok(Either<Failure, ImportSummary> e) =>
      e.getOrElse((f) => fail('unexpected failure: $f'));

  String jsonWith({List<Map<String, dynamic>> books = const []}) => jsonEncode({
    'schemaVersion': 3,
    'exportedAt': 0,
    'books': books,
    'wishlist': <dynamic>[],
  });

  group('ImportLibraryUseCase', () {
    test('unrecognized format is a failure summary', () async {
      final s = ok(await useCase.importText('random text'));
      expect(s.format, isNull);
      expect(s.parseErrors, isNotEmpty);
    });

    test('detects JSON and adds books', () async {
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {'title': 'A', 'isbn': '111'},
            ],
          ),
        ),
      );
      expect(s.format, ImportFormat.pitakaJson);
      expect(s.booksAdded, 1);
      expect(bookRepo.stored.single.title, 'A');
    });

    test('skips a library book whose ISBN already exists', () async {
      bookRepo.stored.add(
        const CatalogueItem(title: 'Existing', isbn: '111', id: 1),
      );
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {'title': 'Dup', 'isbn': '111'},
              {'title': 'New', 'isbn': '222'},
            ],
          ),
        ),
      );
      expect(s.booksAdded, 1);
      expect(s.booksSkipped, 1);
    });

    // Decision Q9 (review 2026-09-03): a re-imported book with the SAME
    // itemUid is updated in place — same id (vault loans keep resolving),
    // same uid — instead of colliding on the UNIQUE book_uid index.
    test('updates a book in place when the file carries its bookUid', () async {
      bookRepo.stored.add(
        const CatalogueItem(
          id: 7,
          itemUid: 'uid-7',
          title: 'Old title',
          coverUrl: 'covers/local.jpg',
          addedBy: 'me',
        ),
      );
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {'bookUid': 'uid-7', 'title': 'New title', 'author': 'A'},
            ],
          ),
        ),
      );
      expect(s.booksUpdated, 1);
      expect(s.booksAdded, 0);
      final row = bookRepo.stored.single;
      expect(row.id, 7, reason: 'device id preserved');
      expect(row.itemUid, 'uid-7');
      expect(row.title, 'New title');
      expect(row.author, 'A');
      expect(row.coverUrl, 'covers/local.jpg', reason: 'local cover kept');
      expect(row.addedBy, 'me', reason: 'attribution kept when file has none');
    });

    // M09 (user decision 2026-09-09): a photo the user took of the physical
    // book is never replaced by a remote URL arriving in an import file.
    test('M09: same-uid import keeps the local PHOTO over an incoming '
        'https cover', () async {
      bookRepo.stored.add(
        const CatalogueItem(
          id: 7,
          itemUid: 'uid-7',
          title: 'Old title',
          coverUrl: 'covers/photo.jpg',
        ),
      );
      final s = ok(
        await useCase.importText(
          jsonWith(
            books: [
              {
                'bookUid': 'uid-7',
                'title': 'New title',
                'coverUrl': 'https://covers.openlibrary.org/b/id/1-L.jpg',
              },
            ],
          ),
        ),
      );
      expect(s.booksUpdated, 1);
      final row = bookRepo.stored.single;
      expect(row.title, 'New title', reason: 'other fields still taken');
      expect(row.coverUrl, 'covers/photo.jpg', reason: 'photo wins');
    });

    test('M09: same-uid import takes the incoming https cover when the '
        'local row has NO cover', () async {
      bookRepo.stored.add(
        const CatalogueItem(id: 7, itemUid: 'uid-7', title: 'Old title'),
      );
      ok(
        await useCase.importText(
          jsonWith(
            books: [
              {
                'bookUid': 'uid-7',
                'title': 'New title',
                'coverUrl': 'https://covers.openlibrary.org/b/id/1-L.jpg',
              },
            ],
          ),
        ),
      );
      expect(
        bookRepo.stored.single.coverUrl,
        'https://covers.openlibrary.org/b/id/1-L.jpg',
      );
    });

    test('re-importing your own export is idempotent (no growth)', () async {
      final first = jsonWith(
        books: [
          {'bookUid': 'u1', 'title': 'A'},
          {'bookUid': 'u2', 'title': 'B', 'isbn': '999'},
        ],
      );
      ok(await useCase.importText(first));
      final s = ok(await useCase.importText(first));
      expect(s.booksAdded, 0);
      expect(s.booksUpdated, 2);
      expect(bookRepo.stored, hasLength(2));
    });

    test('replaces a wishlist entry on existing ISBN (latest-wins)', () async {
      wishlistRepo.stored.add(
        const WishlistBook(title: 'Old', isbn: '999', id: 5, addedDate: 100),
      );
      const goodreads =
          'Title,ISBN13,Exclusive Shelf\nNewWanted,="999",to-read';
      final s = ok(await useCase.importText(goodreads));
      expect(s.format, ImportFormat.goodreadsCsv);
      expect(s.wishlistReplaced, 1);
      expect(s.wishlistAdded, 0);
      // Same id reused; addedDate preserved; title updated.
      final row = wishlistRepo.stored.single;
      expect(row.id, 5);
      expect(row.addedDate, 100);
      expect(row.title, 'NewWanted');
    });

    test('propagates a repository failure as Left', () async {
      final failing = ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: _FailingBookRepo(),
        wishlistRepo: wishlistRepo,
        periodicalRepo: FakePeriodicals(),
      );
      final result = await failing.importText(
        jsonWith(
          books: [
            {'title': 'A', 'isbn': '111'},
          ],
        ),
      );
      expect(result.isLeft(), isTrue);
    });
  });

  group('schema v4 periodicals (ADR 0014 W1)', () {
    late FakeItems items;
    late FakePeriodicals periodicals;

    setUp(() {
      items = FakeItems();
      periodicals = FakePeriodicals();
    });

    ImportLibraryUseCase useCaseOver({
      FakeItems? itemRepo,
      FakePeriodicals? periodicalRepo,
    }) => ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: itemRepo ?? items,
      wishlistRepo: wishlistRepo,
      periodicalRepo: periodicalRepo ?? periodicals,
    );

    String v4({
      List<Map<String, dynamic>> periodicals = const [],
      List<Map<String, dynamic>> books = const [],
    }) => jsonEncode({
      'schemaVersion': 4,
      'exportedAt': 0,
      'periodicals': periodicals,
      'books': books,
      'wishlist': <dynamic>[],
    });

    test('periodicals are applied before the item rows, and an issue keeps '
        'its details', () async {
      final order = <String>[];
      final probeItems = _OrderedItems(items, order);
      final probePeriodicals = _OrderedPeriodicals(periodicals, order);
      final uc = ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: probeItems,
        wishlistRepo: wishlistRepo,
        periodicalRepo: probePeriodicals,
      );

      final s = ok(
        await uc.importText(
          v4(
            periodicals: [
              {'periodicalUid': 'per-1', 'title': 'Frontline'},
            ],
            books: [
              {
                'bookUid': 'i1',
                'kind': 'magazine-issue',
                'title': 'Frontline — No 5',
                'issue': {'periodicalUid': 'per-1', 'issueNumber': 5},
              },
            ],
          ),
        ),
      );

      expect(s.periodicalsAdded, 1);
      expect(s.booksAdded, 1);
      expect(order, ['periodicals', 'items'], reason: 'series before issues');
      final storedSeries = periodicals.rows.values.single;
      expect(storedSeries.title, 'Frontline');
      expect(storedSeries.periodicalUid, 'per-1', reason: 'the file uid wins');
      final storedIssue = items.rows.values.single;
      expect(storedIssue.kind, ItemKind.magazineIssue);
      expect(
        storedIssue.details,
        isA<IssueOf>().having((d) => d.periodicalUid, 'periodicalUid', 'per-1'),
      );
    });

    test(
      'a same-uid periodical is updated in place (id and uid kept)',
      () async {
        final existing = periodicals.seed(
          const Periodical(
            title: 'Old name',
            periodicalUid: 'per-1',
            issn: '1234-5679',
          ),
        );
        final s = ok(
          await useCaseOver().importText(
            v4(
              periodicals: [
                {
                  'periodicalUid': 'per-1',
                  'title': 'Frontline',
                  'issn': '1234-5679',
                },
              ],
            ),
          ),
        );
        expect(s.periodicalsUpdated, 1);
        expect(s.periodicalsAdded, 0);
        final stored = periodicals.rows[existing.id]!;
        expect(stored.title, 'Frontline');
        expect(stored.periodicalUid, 'per-1', reason: 'the stored uid wins');
      },
    );

    test('a same-ISSN periodical under another uid is skipped', () async {
      periodicals.seed(const Periodical(title: 'Frontline', issn: '1234-5679'));
      final s = ok(
        await useCaseOver().importText(
          v4(
            periodicals: [
              {
                'periodicalUid': 'other-uid',
                'title': 'Frontline duplicate',
                'issn': '1234567-9', // the same ISSN, un-normalised
              },
            ],
          ),
        ),
      );
      expect(s.periodicalsSkipped, 1);
      expect(s.periodicalsAdded, 0);
      expect(
        periodicals.rows.values.single.title,
        'Frontline',
        reason: 'you already track this title',
      );
    });

    test(
      'a write failure fails the whole import inside one transaction',
      () async {
        items.insertFailure = const StorageFailure('synthetic');
        final result = await useCaseOver().importText(
          v4(
            periodicals: [
              {'periodicalUid': 'per-1', 'title': 'Frontline'},
            ],
            books: [
              {'title': 'A'},
            ],
          ),
        );
        expect(result.isLeft(), isTrue);
        expect(items.transactions, 1, reason: 'one all-or-nothing transaction');
        expect(items.rows, isEmpty);
        expect(items.rolledBack, isTrue);
        // FakePeriodicals does not roll back its own rows; the real rollback of
        // BOTH stores is a Drift-level guarantee pinned by the S12 repository
        // tests (one database, one transaction).
      },
    );

    test(
      'a re-imported item keeps its kind (the incoming details win)',
      () async {
        items.seed(
          const CatalogueItem(
            title: 'Carrom board',
            itemUid: 'o1',
            details: OtherItemOf(),
          ),
        );
        final s = ok(
          await useCaseOver().importText(
            v4(
              books: [
                {'bookUid': 'o1', 'kind': 'other', 'title': 'Carrom board'},
              ],
            ),
          ),
        );
        expect(s.booksUpdated, 1);
        expect(items.rows.values.single.kind, ItemKind.other);
        expect(items.rows.values.single.details, isA<OtherItemOf>());
      },
    );
  });
}

/// Ordering probes for the "periodicals first" pin: record each store's
/// first insert into one shared log.
class _OrderedItems extends FakeItems {
  _OrderedItems(this._inner, this.order);

  final FakeItems _inner;
  final List<String> order;

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) {
    order.add('items');
    return _inner.insert(book);
  }
}

class _OrderedPeriodicals extends FakePeriodicals {
  _OrderedPeriodicals(this._inner, this.order);

  final FakePeriodicals _inner;
  final List<String> order;

  @override
  Future<Either<Failure, Periodical>> insert(Periodical periodical) {
    order.add('periodicals');
    return _inner.insert(periodical);
  }
}

class _FailingBookRepo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      left(const StorageFailure('boom'));
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      left(const StorageFailure('boom'));
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      right(const []);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(0);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
      right(0);
}
