/// Marking a loan returned and taking that back, as ONE operation of the
/// application layer (review finding P4-M3, D107, D110). No session and no
/// widget here: the operation is a function, and everything it needs is
/// handed in.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/application/change_loan_return.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import 'vault_repository_write_stub.dart';

/// A vault that only writes loan updates down. Every other write throws.
class _RecordingVault with VaultWriteUnsupported implements VaultRepository {
  final List<Loan> written = [];

  /// When set, the next loan update answers this failure and writes nothing.
  Failure? failure;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) => throw UnimplementedError('no read is expected in this test');

  @override
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) async {
    final failed = failure;
    if (failed != null) return left(failed);
    written.add(loan);
    return right(unit);
  }
}

const _cancelled = ValidationFailure('the session ended');

void main() {
  // Loan 1: item 7, out. Loan 2: item 7, came back at 300.
  const out = Loan(
    id: 1,
    itemId: 7,
    borrowerId: 2,
    lentDate: 100,
    dueDate: 500,
    notes: 'a note',
  );
  const back = Loan(
    id: 2,
    itemId: 7,
    borrowerId: 3,
    lentDate: 100,
    dueDate: 500,
    returnedDate: 300,
    notes: 'a note',
  );

  late _RecordingVault vault;
  late SecretBytes passphrase;
  late List<int> itemReads;

  setUp(() {
    vault = _RecordingVault();
    passphrase = SecretBytes(Uint8List.fromList([1, 2, 3]));
    addTearDown(passphrase.dispose);
    itemReads = [];
  });

  /// Runs the operation over [loans] and an item that has [copies] copies
  /// (or cannot be read: [itemFailure]; or is not there: [itemMissing]).
  Future<Either<Failure, Unit>> run({
    required List<Loan> loans,
    required int loanId,
    required int? returnedAt,
    int copies = 1,
    Failure? itemFailure,
    bool itemMissing = false,
    bool Function()? isCurrent,
  }) => changeLoanReturn(
    vault: vault,
    loadItem: (id) async {
      itemReads.add(id);
      if (itemFailure != null) return left(itemFailure);
      if (itemMissing) return right(null);
      return right(CatalogueItem(id: id, title: 'Godaan', copyCount: copies));
    },
    currentLoans: () => loans,
    isCurrent: isCurrent ?? () => true,
    cancelled: _cancelled,
    passphrase: passphrase,
    blob: 'blob',
    dbPath: 'db',
    loanId: loanId,
    returnedAt: returnedAt,
  );

  group('marking returned', () {
    test('writes the date and keeps every other field', () async {
      final result = await run(loans: const [out], loanId: 1, returnedAt: 400);

      expect(result.isRight(), isTrue);
      final row = vault.written.single;
      expect(row.returnedDate, 400);
      expect(row.id, 1);
      expect(row.itemId, 7);
      expect(row.borrowerId, 2);
      expect(row.lentDate, 100);
      expect(row.dueDate, 500);
      expect(row.notes, 'a note');
    });

    test('does not read the item: a return is never refused', () async {
      await run(loans: const [out], loanId: 1, returnedAt: 400);

      expect(itemReads, isEmpty);
    });

    test('a loan that is already returned: success, nothing written, the '
        'FIRST date stays', () async {
      final result = await run(loans: const [back], loanId: 2, returnedAt: 999);

      expect(result.isRight(), isTrue);
      expect(vault.written, isEmpty);
    });

    test('a loan that is gone: NotFoundFailure, nothing written', () async {
      final result = await run(loans: const [out], loanId: 55, returnedAt: 400);

      expect(result.swap().toNullable(), isA<NotFoundFailure>());
      expect(vault.written, isEmpty);
    });

    test("the vault's own failure is passed on", () async {
      vault.failure = const StorageFailure('synthetic');

      final result = await run(loans: const [out], loanId: 1, returnedAt: 400);

      expect(result.swap().toNullable(), isA<StorageFailure>());
    });

    test('the row written is built from the loans as they are NOW, not from '
        'a copy the caller holds: the caller hands in an id', () async {
      // The loan's due date was changed after some screen was built. The
      // operation only gets the id, so it cannot write the old date back.
      const changed = Loan(id: 1, itemId: 7, borrowerId: 2, lentDate: 100);

      await run(loans: const [changed], loanId: 1, returnedAt: 400);

      expect(vault.written.single.dueDate, isNull);
      expect(vault.written.single.notes, isNull);
    });
  });

  group('taking a return back', () {
    test(
      'writes the loan without a date and keeps every other field',
      () async {
        final result = await run(
          loans: const [back],
          loanId: 2,
          returnedAt: null,
        );

        expect(result.isRight(), isTrue);
        final row = vault.written.single;
        expect(row.returnedDate, isNull);
        expect(row.isReturned, isFalse);
        expect(row.id, 2);
        expect(row.itemId, 7);
        expect(row.borrowerId, 3);
        expect(row.lentDate, 100, reason: 'the first loan keeps its dates');
        expect(row.dueDate, 500);
        expect(row.notes, 'a note');
        expect(itemReads, [7], reason: 'the item is read for its copies');
      },
    );

    test('a loan that is still out: success, nothing written, no read of '
        'the item', () async {
      final result = await run(loans: const [out], loanId: 1, returnedAt: null);

      expect(result.isRight(), isTrue);
      expect(vault.written, isEmpty);
      expect(itemReads, isEmpty);
    });

    test('a loan that is gone: NotFoundFailure, nothing written', () async {
      final result = await run(
        loans: const [back],
        loanId: 55,
        returnedAt: null,
      );

      expect(result.swap().toNullable(), isA<NotFoundFailure>());
      expect(vault.written, isEmpty);
    });

    test('the one copy was lent again in the meantime: refused with the '
        "rule's sentence, nothing written", () async {
      const lentAgain = Loan(id: 3, itemId: 7, borrowerId: 9, lentDate: 350);

      final result = await run(
        loans: const [back, lentAgain],
        loanId: 2,
        returnedAt: null,
      );

      final failure = result.swap().toNullable();
      expect(failure, isA<ValidationFailure>());
      expect(
        (failure! as ValidationFailure).message,
        reopenRefusedNoCopyFreeMessage,
      );
      expect(vault.written, isEmpty);
    });

    test("the item's own number of copies decides", () async {
      const lentAgain = Loan(id: 3, itemId: 7, borrowerId: 9, lentDate: 350);

      final result = await run(
        loans: const [back, lentAgain],
        loanId: 2,
        returnedAt: null,
        copies: 2,
      );

      expect(result.isRight(), isTrue);
      expect(vault.written.single.returnedDate, isNull);
    });

    test('the item cannot be read: that failure, nothing written (fail '
        'closed)', () async {
      final result = await run(
        loans: const [back],
        loanId: 2,
        returnedAt: null,
        itemFailure: const StorageFailure('synthetic'),
      );

      expect(result.swap().toNullable(), isA<StorageFailure>());
      expect(vault.written, isEmpty);
    });

    test('the item is not in the catalogue: it counts as one copy', () async {
      final alone = await run(
        loans: const [back],
        loanId: 2,
        returnedAt: null,
        itemMissing: true,
      );
      expect(alone.isRight(), isTrue, reason: 'nobody else has it');
      expect(vault.written, hasLength(1));

      const lentAgain = Loan(id: 3, itemId: 7, borrowerId: 9, lentDate: 350);
      final taken = await run(
        loans: const [back, lentAgain],
        loanId: 2,
        returnedAt: null,
        itemMissing: true,
      );
      expect(taken.isLeft(), isTrue, reason: 'one copy, and it is out');
      expect(vault.written, hasLength(1), reason: 'no second write');
    });

    test('the session ended while the item was read: cancelled, nothing '
        'written', () async {
      var current = true;

      final result = await changeLoanReturn(
        vault: vault,
        loadItem: (id) async {
          current = false; // the vault was locked during this wait
          return right(CatalogueItem(id: id, title: 'Godaan'));
        },
        currentLoans: () => const [back],
        isCurrent: () => current,
        cancelled: _cancelled,
        passphrase: passphrase,
        blob: 'blob',
        dbPath: 'db',
        loanId: 2,
        returnedAt: null,
      );

      expect(result.swap().toNullable(), same(_cancelled));
      expect(vault.written, isEmpty);
    });

    test(
      'the rule is applied to the loans as they are AFTER the wait',
      () async {
        // While the item is read, the copy is lent to somebody else.
        var loans = const <Loan>[back];

        final result = await changeLoanReturn(
          vault: vault,
          loadItem: (id) async {
            loans = const [
              back,
              Loan(id: 3, itemId: 7, borrowerId: 9, lentDate: 350),
            ];
            return right(CatalogueItem(id: id, title: 'Godaan'));
          },
          currentLoans: () => loans,
          isCurrent: () => true,
          cancelled: _cancelled,
          passphrase: passphrase,
          blob: 'blob',
          dbPath: 'db',
          loanId: 2,
          returnedAt: null,
        );

        expect(result.isLeft(), isTrue);
        expect(vault.written, isEmpty);
      },
    );

    test("the vault's own failure is passed on", () async {
      vault.failure = const StorageFailure('synthetic');

      final result = await run(
        loans: const [back],
        loanId: 2,
        returnedAt: null,
      );

      expect(result.swap().toNullable(), isA<StorageFailure>());
    });
  });
}
