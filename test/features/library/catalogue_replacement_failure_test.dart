import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

import 'replacement_harness.dart';

class _InterceptBooks implements BookRepository {
  _InterceptBooks(this.delegate);
  final BookRepository delegate;
  Failure? readFailure;
  Future<void> Function()? afterRead;
  Future<void> Function()? afterReplace;
  @override
  Future<Either<Failure, List<Book>>> getAll() async {
    await afterRead?.call();
    return readFailure == null ? delegate.getAll() : left(readFailure!);
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async {
    final result = await delegate.replaceAll(books);
    await afterReplace?.call();
    return result;
  }

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => delegate.runInTransaction(action);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _book = Book(id: 7, bookUid: 'stable', title: 'Original');
const _decision = MergeDiffersDecision(
  incomingBooks: [Book(id: 99, bookUid: 'stable', title: 'Updated')],
  incomingLibraryId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  incomingLibraryName: 'Incoming',
  localLibraryName: 'Local',
  localIsEmpty: false,
);

void main() {
  late ReplacementHarness h;
  late _InterceptBooks books;
  late MergeLibraryUseCase useCase;
  setUp(() async {
    h = ReplacementHarness();
    books = _InterceptBooks(h.books);
    await h.books.insert(_book);
    await h.initialize();
    useCase = MergeLibraryUseCase(
      bookRepo: books,
      settings: h.settings,
      jsonParser: const PitakaJsonImporter(),
      replacementGuard: h.session,
    );
  });
  tearDown(() => h.close());

  test('catalogue read failure refuses and preserves all state', () async {
    books.readFailure = const StorageFailure('synthetic read failure');
    final result = await useCase.applyOverwrite(_decision);
    expect(result.getLeft().toNullable(), isA<StorageFailure>());
    expect((await h.books.getById(7)).toNullable()!.title, 'Original');
    expect(h.settings.id, 'local');
  });

  for (final afterWrite in [false, true]) {
    test(
      'lock ${afterWrite ? 'after' : 'before'} writes rolls merge back',
      () async {
        if (afterWrite) {
          books.afterReplace = () => h.session.lock();
        } else {
          books.afterRead = () => h.session.lock();
        }
        final result = await useCase.applyOverwrite(_decision);
        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect((await h.books.getById(7)).toNullable()!.title, 'Original');
        expect(h.settings.id, 'local');
      },
    );
  }

  test(
    'changed lending availability is enforced inside the vault FIFO',
    () async {
      const loan = Loan(bookId: 7, borrowerId: 1, lentDate: 1);
      expect((await h.session.addLoan(loan)).isRight(), isTrue);
      expect(
        (await h.session.addLoan(loan)).getLeft().toNullable(),
        isA<ValidationFailure>(),
      );
      expect(h.vault.writes, 1);
    },
  );

  test(
    'settings ID failure is surfaced without breaking preserved loans',
    () async {
      h.settings.failure = const StorageFailure('synthetic settings failure');
      expect(
        (await useCase.applyOverwrite(_decision)).getLeft().toNullable(),
        isA<StorageFailure>(),
      );
      // N07 is still separate: catalogue committed, namespace adoption failed.
      expect((await h.books.getById(7)).toNullable()!.title, 'Updated');
      expect(h.settings.id, 'local');
    },
  );
}
