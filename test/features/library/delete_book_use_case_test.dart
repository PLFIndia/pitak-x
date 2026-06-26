import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/delete_book_use_case.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// Minimal book repo recording deletes; only `delete` is exercised here.
class _FakeBooks implements BookRepository {
  final List<int> deleted = [];
  Failure? deleteFailure;

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
    this.loansForBook = false,
    this.purgeFailure,
  });

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
}
