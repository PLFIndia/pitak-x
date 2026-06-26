import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
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
}

/// Minimal in-memory BookRepository for the move-to-library tests.
class _MemBookRepo implements BookRepository {
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
}
