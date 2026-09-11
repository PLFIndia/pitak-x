import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

T ok<T>(Either<Failure, T> e) =>
    e.getOrElse((f) => fail('unexpected failure: $f'));

Failure err<T>(Either<Failure, T> e) =>
    e.fold((f) => f, (_) => fail('expected a failure'));

void main() {
  late AppDatabase db;
  late DriftWishlistRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftWishlistRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('repository getById / update / delete', () {
    test('getById returns inserted, null for missing', () async {
      final ins = ok(await repo.insert(const WishlistBook(title: 'A')));
      expect(ok(await repo.getById(ins.id))?.title, 'A');
      expect(ok(await repo.getById(99999)), isNull);
    });

    test('update edits in place, preserving id', () async {
      final ins = ok(await repo.insert(const WishlistBook(title: 'Old')));
      final upd = ok(await repo.update(ins.copyWith(title: 'New')));
      expect(upd.id, ins.id);
      expect(ok(await repo.getById(ins.id))?.title, 'New');
    });

    test('update of a missing row is NotFound', () async {
      final r = await repo.update(const WishlistBook(id: 555, title: 'ghost'));
      expect(err(r), isA<NotFoundFailure>());
    });

    test('delete removes the row; deleting twice is idempotent', () async {
      final ins = ok(await repo.insert(const WishlistBook(title: 'X')));
      ok(await repo.delete(ins.id));
      expect(ok(await repo.getById(ins.id)), isNull);
      ok(await repo.delete(ins.id)); // no throw, still right(unit)
    });
  });

  group('AddWishlistBookUseCase', () {
    test('rejects blank title', () async {
      final r = await AddWishlistBookUseCase(repo)(
        const WishlistBook(title: '  '),
      );
      expect(err(r), isA<ValidationFailure>());
    });

    test('inserts a valid entry', () async {
      final saved = ok(
        await AddWishlistBookUseCase(repo)(const WishlistBook(title: 'Buy me')),
      );
      expect(saved.id, isNot(WishlistBook.emptyId));
    });

    test('M15: rejects a priority outside 0..2', () async {
      final r = await AddWishlistBookUseCase(repo)(
        const WishlistBook(title: 'X', priority: 7),
      );
      expect(err(r), isA<ValidationFailure>());
    });

    test('M15: rejects a non-finite priceEstimate', () async {
      final r = await AddWishlistBookUseCase(repo)(
        const WishlistBook(title: 'X', priceEstimate: double.infinity),
      );
      expect(err(r), isA<ValidationFailure>());
    });
  });

  group('UpdateWishlistBookUseCase', () {
    test('rejects blank title and missing id', () async {
      final uc = UpdateWishlistBookUseCase(repo);
      final ins = ok(await repo.insert(const WishlistBook(title: 'Y')));
      expect(err(await uc(ins.copyWith(title: ''))), isA<ValidationFailure>());
      expect(
        err(await uc(const WishlistBook(title: 'unsaved'))),
        isA<NotFoundFailure>(),
      );
    });

    test('rejects an addedDate change (immutable)', () async {
      final uc = UpdateWishlistBookUseCase(repo);
      final ins = ok(
        await repo.insert(const WishlistBook(title: 'Z', addedDate: 1000)),
      );
      final r = await uc(ins.copyWith(addedDate: 2000, title: 'Z2'));
      expect(err(r), isA<ValidationFailure>());
    });

    test('updates when addedDate is unchanged', () async {
      final uc = UpdateWishlistBookUseCase(repo);
      final ins = ok(
        await repo.insert(const WishlistBook(title: 'Keep', addedDate: 5)),
      );
      final saved = ok(await uc(ins.copyWith(title: 'Kept', addedDate: 5)));
      expect(saved.title, 'Kept');
    });

    test('M15: rejects a negative priceEstimate on update', () async {
      final uc = UpdateWishlistBookUseCase(repo);
      final ins = ok(await repo.insert(const WishlistBook(title: 'Y')));
      final r = await uc(ins.copyWith(priceEstimate: -1));
      expect(err(r), isA<ValidationFailure>());
    });
  });

  group('MarkWishlistPurchasedUseCase', () {
    test('flips purchased flag and stamps date (no move)', () async {
      final ins = ok(await repo.insert(const WishlistBook(title: 'Want')));
      final outcome = ok(
        await MarkWishlistPurchasedUseCase(repo)(ins.id, now: 1234),
      );
      expect(outcome, isA<MarkPurchasedSuccess>());
      final saved = (outcome as MarkPurchasedSuccess).entry;
      expect(saved.purchased, isTrue);
      expect(saved.purchasedDate, 1234);
    });

    test('missing entry is NotFound', () async {
      final r = await MarkWishlistPurchasedUseCase(repo)(42424);
      expect(err(r), isA<NotFoundFailure>());
    });

    test('moveToLibrary inserts a fresh library book', () async {
      final books = _MemBookRepo();
      final ins = ok(
        await repo.insert(const WishlistBook(title: 'Move', isbn: '111')),
      );
      final outcome = ok(
        await MarkWishlistPurchasedUseCase(repo, books: books)(
          ins.id,
          moveToLibrary: true,
          now: 5,
        ),
      );
      expect(outcome, isA<MarkPurchasedSuccess>());
      expect(books.stored.single.title, 'Move');
      expect(books.stored.single.addedDate, 5);
    });

    test(
      'moveToLibrary on an existing ISBN returns AlreadyInLibrary',
      () async {
        final books = _MemBookRepo()
          ..stored.add(const Book(id: 9, title: 'Dup', isbn: '222'));
        final ins = ok(
          await repo.insert(const WishlistBook(title: 'Move2', isbn: '222')),
        );
        final outcome = ok(
          await MarkWishlistPurchasedUseCase(repo, books: books)(
            ins.id,
            moveToLibrary: true,
          ),
        );
        expect(outcome, isA<MarkPurchasedAlreadyInLibrary>());
        expect((outcome as MarkPurchasedAlreadyInLibrary).existingBookId, 9);
        // No duplicate inserted.
        expect(books.stored.length, 1);
        // Entry is still marked purchased.
        expect(ok(await repo.getById(ins.id))!.purchased, isTrue);
      },
    );
  });

  // M13 (astra-review): the purchase + move must be ONE transaction. These
  // tests use REAL Drift for BOTH repositories on the same in-memory database
  // so a rollback is observable; the in-memory `_MemBookRepo` above cannot
  // prove that (its `runInTransaction` is a pass-through — M04 lesson).
  group('M13 — purchase/move is transactional and idempotent', () {
    late DriftBookRepository realBooks;

    setUp(() {
      realBooks = DriftBookRepository(db);
    });

    test('a failed library insert rolls the wishlist purchase back (row stays '
        'Wanted, no library book, typed Left returned)', () async {
      final ins = ok(
        await repo.insert(const WishlistBook(title: 'Half', isbn: '333')),
      );
      final books = _InsertFailsBookRepo(realBooks);
      final useCase = MarkWishlistPurchasedUseCase(repo, books: books);

      final r = await useCase(ins.id, moveToLibrary: true, now: 77);

      expect(err(r), isA<StorageFailure>());
      final row = ok(await repo.getById(ins.id))!;
      expect(row.purchased, isFalse, reason: 'purchase must roll back');
      expect(row.purchasedDate, isNull);
      expect(ok(await realBooks.getAll()), isEmpty);
    });

    test(
      'a vanished entry inside the move is NotFound; nothing is inserted',
      () async {
        final useCase = MarkWishlistPurchasedUseCase(repo, books: realBooks);
        final r = await useCase(424242, moveToLibrary: true);
        expect(err(r), isA<NotFoundFailure>());
        expect(ok(await realBooks.getAll()), isEmpty);
      },
    );

    test('a failed ISBN lookup is propagated: nothing is written', () async {
      final ins = ok(
        await repo.insert(const WishlistBook(title: 'Look', isbn: '444')),
      );
      final books = _LookupFailsBookRepo(realBooks);
      final useCase = MarkWishlistPurchasedUseCase(repo, books: books);

      final r = await useCase(ins.id, moveToLibrary: true);

      expect(err(r), isA<StorageFailure>());
      expect(books.insertCalls, 0, reason: 'must not insert after a Left');
      expect(ok(await repo.getById(ins.id))!.purchased, isFalse);
      expect(ok(await realBooks.getAll()), isEmpty);
    });

    test('two concurrent moves of a no-ISBN entry create exactly one library '
        'book; the loser is AlreadyPurchased', () async {
      final ins = ok(await repo.insert(const WishlistBook(title: 'Twice')));
      final useCase = MarkWishlistPurchasedUseCase(repo, books: realBooks);

      final results = await Future.wait([
        useCase(ins.id, moveToLibrary: true, now: 1),
        useCase(ins.id, moveToLibrary: true, now: 2),
      ]);

      final outcomes = results.map(ok).toList();
      expect(outcomes.whereType<MarkPurchasedSuccess>(), hasLength(1));
      expect(outcomes.whereType<MarkPurchasedAlreadyPurchased>(), hasLength(1));
      expect(ok(await realBooks.getAll()), hasLength(1));
      expect(ok(await repo.getById(ins.id))!.purchased, isTrue);
    });

    test(
      'an already-purchased entry is refused without writing (D1 = a)',
      () async {
        final ins = ok(
          await repo.insert(
            const WishlistBook(
              title: 'Done',
              purchased: true,
              purchasedDate: 10,
            ),
          ),
        );
        final useCase = MarkWishlistPurchasedUseCase(repo, books: realBooks);

        final move = ok(await useCase(ins.id, moveToLibrary: true, now: 99));
        final flagOnly = ok(await useCase(ins.id, now: 99));

        expect(move, isA<MarkPurchasedAlreadyPurchased>());
        expect(flagOnly, isA<MarkPurchasedAlreadyPurchased>());
        expect(ok(await realBooks.getAll()), isEmpty);
        final row = ok(await repo.getById(ins.id))!;
        expect(row.purchasedDate, 10, reason: 'stamp must not be rewritten');
      },
    );

    test('happy path on real Drift: row purchased AND book inserted', () async {
      final ins = ok(
        await repo.insert(
          const WishlistBook(
            title: 'Real',
            isbn: '555',
            coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
          ),
        ),
      );
      final useCase = MarkWishlistPurchasedUseCase(repo, books: realBooks);

      final outcome = ok(await useCase(ins.id, moveToLibrary: true, now: 5));

      expect(outcome, isA<MarkPurchasedSuccess>());
      expect(ok(await repo.getById(ins.id))!.purchased, isTrue);
      final book = ok(await realBooks.getAll()).single;
      expect(book.isbn, '555');
      expect(book.addedDate, 5);
      // The remote cover reference is handed over so M09's consent-gated
      // pipeline can materialise it for the new library row.
      expect(book.coverUrl, 'https://covers.openlibrary.org/b/id/1-L.jpg');
    });
  });
}

/// Decorator over a REAL [DriftBookRepository] that fails only `insert` —
/// everything else (including the transaction) is the real thing, so the test
/// proves the rollback actually happens in Drift.
class _InsertFailsBookRepo extends _DelegatingBookRepo {
  _InsertFailsBookRepo(super.inner);

  @override
  Future<Either<Failure, Book>> insert(Book book) async =>
      left(const StorageFailure('insert: disk full'));
}

/// Decorator that fails only the ISBN lookup and counts insert attempts.
class _LookupFailsBookRepo extends _DelegatingBookRepo {
  _LookupFailsBookRepo(super.inner);

  int insertCalls = 0;

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async =>
      left(const StorageFailure('findByIsbn: io error'));

  @override
  Future<Either<Failure, Book>> insert(Book book) {
    insertCalls++;
    return super.insert(book);
  }
}

/// Forwards every [BookRepository] call to [inner]; subclasses override the one
/// method they want to sabotage.
class _DelegatingBookRepo implements BookRepository {
  _DelegatingBookRepo(this.inner);

  final BookRepository inner;

  @override
  Future<Either<Failure, List<Book>>> getAll() => inner.getAll();
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) => inner.query(sort: sort, language: language);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() =>
      inner.distinctLanguages();
  @override
  Future<Either<Failure, Book?>> getById(int id) => inner.getById(id);
  @override
  Future<Either<Failure, Book>> insert(Book book) => inner.insert(book);
  @override
  Future<Either<Failure, Book>> update(Book book) => inner.update(book);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) =>
      inner.markRemoved(id, at);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) =>
      inner.restoreRemoved(id);
  @override
  Future<Either<Failure, Unit>> delete(int id) => inner.delete(id);
  @override
  Future<Either<Failure, List<Book>>> search(String query) =>
      inner.search(query);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) =>
      inner.findByIsbn(isbn);
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) =>
      inner.findByUid(bookUid);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => inner.runInTransaction(action);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) =>
      inner.insertAll(books);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) =>
      inner.replaceAll(books);
}

/// Minimal in-memory BookRepository for the move-to-library tests.
class _MemBookRepo implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<Book> stored = [];
  int _next = 1;

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async =>
      right(stored.where((b) => b.isbn == isbn).firstOrNull);
  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final saved = book.copyWith(id: _next++);
    stored.add(saved);
    return right(saved);
  }

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(stored);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(stored.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, Book>> update(Book book) async => right(book);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}
