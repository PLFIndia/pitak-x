import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// Minimal book repo recording deletes; only `delete` is exercised here.
class _FakeBooks implements BookRepository {
  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<int> deleted = [];
  Failure? deleteFailure;

  /// The row the use case reads (for its cover) before deleting; null = gone.
  Book? row;

  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(row?.id == id ? row : null);

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (deleteFailure != null) return left(deleteFailure!);
    deleted.add(id);
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _FakePurger implements VaultLoanPurger {
  _FakePurger({
    required this.isUnlocked,
    this.vaultExists = true,
    this.loansForBook = false,
    this.purgeFailure,
  });

  @override
  bool vaultExists;
  @override
  bool isUnlocked;
  bool loansForBook;
  Failure? purgeFailure;
  int purgeCalls = 0;

  @override
  bool hasLoansForBook(int bookId) => loansForBook;

  @override
  Future<Either<Failure, Unit>> purgeLoansForBook(int bookId) async {
    purgeCalls++;
    if (purgeFailure != null) return left(purgeFailure!);
    return right(unit);
  }
}

void main() {
  // M12 regression: a catalogue-only user (vault never created) used to be
  // told to "unlock the borrowers vault first" — an unlock that can never
  // happen because there is no vault. They must be able to delete directly.
  test(
    'no vault on device (M12) → deletes directly, no unlock demanded',
    () async {
      final books = _FakeBooks();
      final purger = _FakePurger(isUnlocked: false, vaultExists: false);
      final useCase = DeleteBookUseCase(books: books, vault: purger);

      final result = await useCase(9);
      expect(result.getOrElse((_) => fail('right')), DeleteBookOutcome.deleted);
      expect(books.deleted, [9]);
      expect(purger.purgeCalls, 0);
    },
  );

  test('locked vault → requiresVaultUnlock, nothing deleted', () async {
    final books = _FakeBooks();
    final purger = _FakePurger(isUnlocked: false);
    final useCase = DeleteBookUseCase(books: books, vault: purger);

    final result = await useCase(1);
    expect(
      result.getOrElse((_) => fail('expected right')),
      DeleteBookOutcome.requiresVaultUnlock,
    );
    expect(books.deleted, isEmpty);
    expect(purger.purgeCalls, 0);
  });

  test('unlocked, no loans → deletes book without purging', () async {
    final books = _FakeBooks();
    final purger = _FakePurger(isUnlocked: true);
    final useCase = DeleteBookUseCase(books: books, vault: purger);

    final result = await useCase(7);
    expect(result.getOrElse((_) => fail('right')), DeleteBookOutcome.deleted);
    expect(books.deleted, [7]);
    expect(purger.purgeCalls, 0);
  });

  test('unlocked with loans → purges first, then deletes', () async {
    final books = _FakeBooks();
    final purger = _FakePurger(isUnlocked: true, loansForBook: true);
    final useCase = DeleteBookUseCase(books: books, vault: purger);

    final result = await useCase(3);
    expect(result.getOrElse((_) => fail('right')), DeleteBookOutcome.deleted);
    expect(purger.purgeCalls, 1);
    expect(books.deleted, [3]);
  });

  test(
    'purge failure aborts before the book is deleted (fail-closed)',
    () async {
      final books = _FakeBooks();
      final purger = _FakePurger(
        isUnlocked: true,
        loansForBook: true,
        purgeFailure: const CryptoFailure('boom'),
      );
      final useCase = DeleteBookUseCase(books: books, vault: purger);

      final result = await useCase(3);
      expect(result.isLeft(), isTrue);
      expect(books.deleted, isEmpty); // book row untouched
    },
  );

  // Decision Q12 (review 2026-09-03): a hard delete releases the book's cover
  // file — AFTER the row is gone, and never when the delete failed.
  test('a successful delete releases the cover reference', () async {
    final books = _FakeBooks()
      ..row = const Book(id: 5, title: 'X', coverUrl: 'covers/a.jpg');
    final released = <String?>[];
    final useCase = DeleteBookUseCase(
      books: books,
      vault: _FakePurger(isUnlocked: true),
      releaseCover: (ref) async => released.add(ref),
    );
    final result = await useCase(5);
    expect(result.isRight(), isTrue);
    expect(released, ['covers/a.jpg']);
  });

  test('a failed delete does NOT release the cover', () async {
    final books = _FakeBooks()
      ..row = const Book(id: 5, title: 'X', coverUrl: 'covers/a.jpg')
      ..deleteFailure = const StorageFailure('locked');
    final released = <String?>[];
    final useCase = DeleteBookUseCase(
      books: books,
      vault: _FakePurger(isUnlocked: true),
      releaseCover: (ref) async => released.add(ref),
    );
    expect((await useCase(5)).isLeft(), isTrue);
    expect(released, isEmpty);
  });
}
