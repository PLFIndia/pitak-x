import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';

/// Books by id; everything else unused here.
class _Books implements BookRepository {
  _Books(this.byId);

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final Map<int, Book> byId;

  @override
  Future<Either<Failure, Book?>> getById(int id) async => right(byId[id]);
  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
      right(byId.values.toList());
  @override
  Future<Either<Failure, List<Book>>> search(String q) async => right(const []);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => getAll();
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, Book>> insert(Book b) async => right(b);
  @override
  Future<Either<Failure, Book>> update(Book b) async => right(b);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> b) async => right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<Book> b) async =>
      right(b.length);
}

/// Records writes; `loans` is what the policy sees; `failLoan` simulates a
/// vault write failure.
class _Vault implements VaultLender {
  _Vault({this.loans = const []});
  List<Loan>? loans;
  final addedBorrowers = <Borrower>[];
  final addedLoans = <Loan>[];
  bool failLoan = false;
  int nextBorrowerId = 100;

  @override
  List<Loan>? get currentLoans => loans;

  @override
  Future<Either<Failure, int>> addBorrower(Borrower borrower) async {
    addedBorrowers.add(borrower);
    return right(nextBorrowerId++);
  }

  @override
  Future<Either<Failure, Unit>> addLoan(Loan loan) async {
    if (failLoan) return left(const StorageFailure('disk full'));
    addedLoans.add(loan);
    return right(unit);
  }
}

void main() {
  const single = Book(id: 1, title: 'One copy');
  const triple = Book(id: 2, title: 'Three copies', copyCount: 3);
  const removed = Book(id: 3, title: 'Gone', removed: true);
  Loan out(int bookId) => Loan(bookId: bookId, borrowerId: 9, lentDate: 1);
  Loan back(int bookId) =>
      Loan(bookId: bookId, borrowerId: 9, lentDate: 1, returnedDate: 2);

  group('LendDecision (pure policy)', () {
    test('allowed when copies are free; counts only ACTIVE loans', () {
      final d = LendDecision.forBook(triple, [out(2), back(2), back(2)]);
      expect(d, isA<LendAllowed>());
      expect((d as LendAllowed).copiesFree, 2);
      expect(d.reason, isNull);
    });

    test('refused when every copy is out, with a plain-language reason', () {
      final d1 = LendDecision.forBook(single, [out(1)]);
      expect(d1, isA<LendRefusedAllCopiesOut>());
      expect(d1.reason, contains('already out on loan'));

      final d3 = LendDecision.forBook(triple, [out(2), out(2), out(2)]);
      expect(d3, isA<LendRefusedAllCopiesOut>());
      expect(d3.reason, contains('All 3 copies'));
    });

    test('refused for a removed book regardless of loans', () {
      final d = LendDecision.forBook(removed, const []);
      expect(d, isA<LendRefusedRemoved>());
      expect(d.reason, contains('marked as removed'));
    });

    test('a malformed copyCount of 0 behaves like 1', () {
      const zero = Book(id: 4, title: 'Z', copyCount: 0);
      expect(LendDecision.forBook(zero, const []), isA<LendAllowed>());
      expect(
        LendDecision.forBook(zero, [out(4)]),
        isA<LendRefusedAllCopiesOut>(),
      );
    });
  });

  group('LendBookUseCase', () {
    final books = _Books({1: single, 2: triple, 3: removed});

    test('lends a free book to an existing borrower', () async {
      final vault = _Vault();
      final uc = LendBookUseCase(books: books, vault: vault);
      final r = await uc(
        bookId: 1,
        target: const ExistingBorrower(7),
        lentDate: 10,
        dueDate: 20,
        notes: 'n',
      );
      expect(r.isRight(), isTrue);
      expect(vault.addedLoans.single.borrowerId, 7);
      expect(vault.addedLoans.single.dueDate, 20);
      expect(vault.addedBorrowers, isEmpty);
    });

    test(
      'REFUSES a second loan of a single-copy book, explaining why',
      () async {
        final vault = _Vault(loans: [out(1)]);
        final uc = LendBookUseCase(books: books, vault: vault);
        final r = await uc(
          bookId: 1,
          target: const ExistingBorrower(7),
          lentDate: 10,
        );
        r.match(
          (f) => expect(
            (f as ValidationFailure).message,
            contains('already out on loan'),
          ),
          (_) => fail('must refuse'),
        );
        expect(vault.addedLoans, isEmpty, reason: 'nothing written');
      },
    );

    test('REFUSES lending a removed book', () async {
      final vault = _Vault();
      final uc = LendBookUseCase(books: books, vault: vault);
      final r = await uc(
        bookId: 3,
        target: const ExistingBorrower(7),
        lentDate: 10,
      );
      expect(r.isLeft(), isTrue);
      expect(vault.addedLoans, isEmpty);
    });

    test('creates the inline borrower and uses the RETURNED id', () async {
      final vault = _Vault()..nextBorrowerId = 42;
      final uc = LendBookUseCase(books: books, vault: vault);
      final r = await uc(
        bookId: 2,
        target: const NewBorrower('  Asha  '),
        lentDate: 10,
      );
      expect(r.isRight(), isTrue);
      expect(vault.addedBorrowers.single.name, 'Asha');
      expect(vault.addedLoans.single.borrowerId, 42);
    });

    test('blank inline name is a validation failure with no writes', () async {
      final vault = _Vault();
      final uc = LendBookUseCase(books: books, vault: vault);
      final r = await uc(
        bookId: 2,
        target: const NewBorrower('   '),
        lentDate: 10,
      );
      expect(r.isLeft(), isTrue);
      expect(vault.addedBorrowers, isEmpty);
    });

    test('a loan write failure after an inline borrower says so', () async {
      final vault = _Vault()..failLoan = true;
      final uc = LendBookUseCase(books: books, vault: vault);
      final r = await uc(
        bookId: 2,
        target: const NewBorrower('Asha'),
        lentDate: 10,
      );
      r.match(
        (f) => expect(
          (f as ValidationFailure).message,
          contains('borrower was added but the loan could not be saved'),
        ),
        (_) => fail('must fail'),
      );
    });

    test('locked vault and missing book are typed failures', () async {
      final locked = LendBookUseCase(
        books: books,
        vault: _Vault()..loans = null,
      );
      expect(
        (await locked(
          bookId: 1,
          target: const ExistingBorrower(7),
          lentDate: 1,
        )).isLeft(),
        isTrue,
      );
      final uc = LendBookUseCase(books: books, vault: _Vault());
      final r = await uc(
        bookId: 999,
        target: const ExistingBorrower(7),
        lentDate: 1,
      );
      r.match(
        (f) => expect(f, isA<NotFoundFailure>()),
        (_) => fail('must be not found'),
      );
    });
  });
}
