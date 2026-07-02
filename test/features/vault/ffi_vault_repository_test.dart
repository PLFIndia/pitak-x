import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/infrastructure/ffi_vault_repository.dart';
import 'package:pitaka/src/rust/api.dart' as ffi;

/// Tests the Dart-side adapter without loading the native library: the FFI
/// `unlock` function is injected. We verify row mapping, fail-closed handling
/// of NOT NULL columns, and Rust-error → Failure translation.
void main() {
  SecretBytes pass() => SecretBytes(Uint8List.fromList([1, 2, 3]));

  // Builds a repo whose injected FFI call returns [contents].
  FfiVaultRepository returning(ffi.VaultContents contents) =>
      FfiVaultRepository(
        unlock:
            ({required passphraseUtf8, required blob, required dbPath}) async =>
                contents,
      );

  // Builds a repo whose injected FFI call throws [error].
  FfiVaultRepository throwing(ffi.VaultUnlockError error) => FfiVaultRepository(
    unlock: ({required passphraseUtf8, required blob, required dbPath}) async =>
        throw error,
  );

  Future<Either<Failure, VaultData>> run(FfiVaultRepository repo) async {
    final p = pass();
    final result = await repo.unlockAndRead(
      passphrase: p,
      blob: 'b',
      dbPath: 'x.db',
    );
    p.dispose();
    return result;
  }

  group('FfiVaultRepository.unlockAndRead', () {
    test('maps borrowers and loans into domain entities', () async {
      final repo = returning(
        const ffi.VaultContents(
          borrowers: [
            ffi.Borrower(id: 1, name: 'Asha', contact: '999', notes: 'n'),
          ],
          loans: [
            ffi.Loan(
              id: 5,
              bookId: 2,
              borrowerId: 1,
              lentDate: 1000,
              dueDate: 2000,
              notes: 'good',
            ),
          ],
        ),
      );

      final p = pass();
      final result = await repo.unlockAndRead(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
      );
      p.dispose();

      final data = result.getOrElse((_) => throw StateError('expected right'));
      expect(data.borrowers.single.name, 'Asha');
      expect(data.borrowers.single.id, 1);
      expect(data.loans.single.bookId, 2);
      expect(data.loans.single.lentDate, 1000);
      expect(data.loans.single.isReturned, isFalse);
    });

    test('fails closed when a NOT NULL borrower.name is null', () async {
      final result = await run(
        returning(
          const ffi.VaultContents(
            // Explicit null on a NOT NULL column is the whole point here.
            // ignore: avoid_redundant_argument_values
            borrowers: [ffi.Borrower(id: 1, name: null)],
            loans: [],
          ),
        ),
      );
      result.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected a corrupt failure'),
      );
    });

    test('fails closed when a NOT NULL loan.lent_date is null', () async {
      final result = await run(
        returning(
          const ffi.VaultContents(
            borrowers: [ffi.Borrower(id: 1, name: 'Asha')],
            // Explicit null on a NOT NULL column is the whole point here.
            // ignore: avoid_redundant_argument_values
            loans: [ffi.Loan(id: 5, bookId: 2, borrowerId: 1, lentDate: null)],
          ),
        ),
      );
      result.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected a corrupt failure'),
      );
    });

    test('maps WrongPassphrase error to WrongPassphraseFailure', () async {
      final result = await run(
        throwing(const ffi.VaultUnlockError.wrongPassphrase()),
      );
      result.match(
        (f) => expect(f, isA<WrongPassphraseFailure>()),
        (_) => fail('expected wrong-passphrase failure'),
      );
    });

    test('maps Corrupt error to BackupCorruptFailure', () async {
      final result = await run(
        throwing(const ffi.VaultUnlockError.corrupt('bad blob')),
      );
      result.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected corrupt failure'),
      );
    });

    test('maps VaultOpen error to CryptoFailure', () async {
      final result = await run(
        throwing(const ffi.VaultUnlockError.vaultOpen('sqlite3_key rc=1')),
      );
      result.match(
        (f) => expect(f, isA<CryptoFailure>()),
        (_) => fail('expected crypto failure'),
      );
    });
  });

  group('FfiVaultRepository.createVault (#26.1)', () {
    test('returns the blob and forwards the db path', () async {
      late String sentDbPath;
      final repo = FfiVaultRepository(
        createVault: ({required passphraseUtf8, required dbPath}) async {
          sentDbPath = dbPath;
          return 'salt.iv.ct';
        },
      );
      final p = pass();
      final result = await repo.createVault(
        passphrase: p,
        dbPath: '/docs/borrowers.db',
      );
      p.dispose();
      expect(sentDbPath, '/docs/borrowers.db');
      expect(result.getOrElse((_) => 'WRONG'), 'salt.iv.ct');
    });

    test('AlreadyExists maps to StorageFailure', () async {
      final repo = FfiVaultRepository(
        createVault: ({required passphraseUtf8, required dbPath}) async =>
            throw const ffi.VaultCreateError.alreadyExists('exists'),
      );
      final p = pass();
      final result = await repo.createVault(passphrase: p, dbPath: 'x.db');
      p.dispose();
      result.match(
        (f) => expect(f, isA<StorageFailure>()),
        (_) => fail('expected storage failure'),
      );
    });

    test('Wrap/VaultOpen crypto errors map to CryptoFailure', () async {
      final repo = FfiVaultRepository(
        createVault: ({required passphraseUtf8, required dbPath}) async =>
            throw const ffi.VaultCreateError.wrap('kdf failed'),
      );
      final p = pass();
      final result = await repo.createVault(passphrase: p, dbPath: 'x.db');
      p.dispose();
      result.match(
        (f) => expect(f, isA<CryptoFailure>()),
        (_) => fail('expected crypto failure'),
      );
    });
  });

  group('FfiVaultRepository.changePassphrase (#28A)', () {
    test('returns the new blob and forwards old+new+blob', () async {
      late List<int> sentOld;
      late List<int> sentNew;
      late String sentBlob;
      final repo = FfiVaultRepository(
        rewrapBlob:
            ({
              required oldPassphraseUtf8,
              required newPassphraseUtf8,
              required blob,
            }) async {
              // Snapshot at call time: the repository wipes these buffers as
              // soon as the FFI call returns (§6.1), so retaining the list
              // itself would observe zeros.
              sentOld = List.of(oldPassphraseUtf8);
              sentNew = List.of(newPassphraseUtf8);
              sentBlob = blob;
              return 'new.blob.ct';
            },
      );
      final oldP = SecretBytes(Uint8List.fromList([1, 2]));
      final newP = SecretBytes(Uint8List.fromList([3, 4, 5]));
      final result = await repo.changePassphrase(
        oldPassphrase: oldP,
        newPassphrase: newP,
        blob: 'old.blob.ct',
      );
      oldP.dispose();
      newP.dispose();
      expect(sentOld, [1, 2]);
      expect(sentNew, [3, 4, 5]);
      expect(sentBlob, 'old.blob.ct');
      expect(result.getOrElse((_) => 'WRONG'), 'new.blob.ct');
    });

    test('WrongPassphrase maps to WrongPassphraseFailure', () async {
      final repo = FfiVaultRepository(
        rewrapBlob:
            ({
              required oldPassphraseUtf8,
              required newPassphraseUtf8,
              required blob,
            }) async => throw const ffi.VaultRewrapError.wrongPassphrase(),
      );
      final oldP = pass();
      final newP = pass();
      final result = await repo.changePassphrase(
        oldPassphrase: oldP,
        newPassphrase: newP,
        blob: 'b',
      );
      oldP.dispose();
      newP.dispose();
      result.match(
        (f) => expect(f, isA<WrongPassphraseFailure>()),
        (_) => fail('expected wrong-passphrase failure'),
      );
    });

    test('Corrupt → BackupCorruptFailure, Wrap → CryptoFailure', () async {
      final corruptRepo = FfiVaultRepository(
        rewrapBlob:
            ({
              required oldPassphraseUtf8,
              required newPassphraseUtf8,
              required blob,
            }) async => throw const ffi.VaultRewrapError.corrupt('bad'),
      );
      final wrapRepo = FfiVaultRepository(
        rewrapBlob:
            ({
              required oldPassphraseUtf8,
              required newPassphraseUtf8,
              required blob,
            }) async => throw const ffi.VaultRewrapError.wrap('kdf failed'),
      );
      final oldP = pass();
      final newP = pass();
      final corrupt = await corruptRepo.changePassphrase(
        oldPassphrase: oldP,
        newPassphrase: newP,
        blob: 'b',
      );
      final wrap = await wrapRepo.changePassphrase(
        oldPassphrase: pass(),
        newPassphrase: pass(),
        blob: 'b',
      );
      oldP.dispose();
      newP.dispose();
      corrupt.match(
        (f) => expect(f, isA<BackupCorruptFailure>()),
        (_) => fail('expected corrupt failure'),
      );
      wrap.match(
        (f) => expect(f, isA<CryptoFailure>()),
        (_) => fail('expected crypto failure'),
      );
    });
  });

  group('FfiVaultRepository write path (#25b)', () {
    test('insertBorrower returns the new id and forwards fields', () async {
      int? sentBookContactCheck;
      late String sentName;
      String? sentContact;
      final repo = FfiVaultRepository(
        insertBorrower:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required name,
              contact,
              notes,
            }) async {
              sentName = name;
              sentContact = contact;
              sentBookContactCheck = 1;
              return 42;
            },
      );
      final p = pass();
      final result = await repo.insertBorrower(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
        borrower: const Borrower(name: 'Asha', contact: '999'),
      );
      p.dispose();
      expect(sentBookContactCheck, 1);
      expect(sentName, 'Asha');
      expect(sentContact, '999');
      expect(result.getOrElse((_) => -1), 42);
    });

    test('insertLoan forwards all fields and returns the new id', () async {
      late int sentBookId;
      late int sentBorrowerId;
      late int sentLentDate;
      final repo = FfiVaultRepository(
        insertLoan:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required bookId,
              required borrowerId,
              required lentDate,
              dueDate,
              returnedDate,
              notes,
            }) async {
              sentBookId = bookId;
              sentBorrowerId = borrowerId;
              sentLentDate = lentDate;
              return 7;
            },
      );
      final p = pass();
      final result = await repo.insertLoan(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
        loan: const Loan(bookId: 2, borrowerId: 1, lentDate: 1000),
      );
      p.dispose();
      expect(sentBookId, 2);
      expect(sentBorrowerId, 1);
      expect(sentLentDate, 1000);
      expect(result.getOrElse((_) => -1), 7);
    });

    test('Constraint error maps to ValidationFailure', () async {
      final repo = FfiVaultRepository(
        deleteBorrower:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required id,
            }) async => throw const ffi.VaultWriteError.constraint('has loans'),
      );
      final p = pass();
      final result = await repo.deleteBorrower(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
        id: 1,
      );
      p.dispose();
      result.match(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected validation failure'),
      );
    });

    test('NotFound error maps to NotFoundFailure', () async {
      final repo = FfiVaultRepository(
        deleteLoan:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required id,
            }) async => throw const ffi.VaultWriteError.notFound(),
      );
      final p = pass();
      final result = await repo.deleteLoan(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
        id: 99,
      );
      p.dispose();
      result.match(
        (f) => expect(f, isA<NotFoundFailure>()),
        (_) => fail('expected not-found failure'),
      );
    });

    test('WrongPassphrase on a write maps to WrongPassphraseFailure', () async {
      final repo = FfiVaultRepository(
        updateBorrower:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required id,
              required name,
              contact,
              notes,
            }) async => throw const ffi.VaultWriteError.wrongPassphrase(),
      );
      final p = pass();
      final result = await repo.updateBorrower(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
        borrower: const Borrower(id: 1, name: 'X'),
      );
      p.dispose();
      result.match(
        (f) => expect(f, isA<WrongPassphraseFailure>()),
        (_) => fail('expected wrong-passphrase failure'),
      );
    });
  });

  group('§6.1: Dart-side FFI passphrase copies are wiped after the call', () {
    test('unlockAndRead wipes the marshalled copy (success path)', () async {
      late List<int> captured;
      final repo = FfiVaultRepository(
        unlock:
            ({required passphraseUtf8, required blob, required dbPath}) async {
              captured = passphraseUtf8;
              expect(passphraseUtf8, [1, 2, 3]); // live during the call
              return const ffi.VaultContents(borrowers: [], loans: []);
            },
      );
      final p = pass();
      await repo.unlockAndRead(passphrase: p, blob: 'b', dbPath: 'x.db');
      p.dispose();
      expect(captured.every((b) => b == 0), isTrue);
    });

    test('unlockAndRead wipes the copy on the error path too', () async {
      late List<int> captured;
      final repo = FfiVaultRepository(
        unlock:
            ({required passphraseUtf8, required blob, required dbPath}) async {
              captured = passphraseUtf8;
              throw const ffi.VaultUnlockError.wrongPassphrase();
            },
      );
      final p = pass();
      final result = await repo.unlockAndRead(
        passphrase: p,
        blob: 'b',
        dbPath: 'x.db',
      );
      p.dispose();
      expect(result.isLeft(), isTrue);
      expect(captured.every((b) => b == 0), isTrue);
    });

    test('changePassphrase wipes BOTH marshalled copies', () async {
      late List<int> capturedOld;
      late List<int> capturedNew;
      final repo = FfiVaultRepository(
        rewrapBlob:
            ({
              required oldPassphraseUtf8,
              required newPassphraseUtf8,
              required blob,
            }) async {
              capturedOld = oldPassphraseUtf8;
              capturedNew = newPassphraseUtf8;
              return 'new.blob';
            },
      );
      final oldP = pass();
      final newP = pass();
      await repo.changePassphrase(
        oldPassphrase: oldP,
        newPassphrase: newP,
        blob: 'b',
      );
      oldP.dispose();
      newP.dispose();
      expect(capturedOld.every((b) => b == 0), isTrue);
      expect(capturedNew.every((b) => b == 0), isTrue);
    });

    test('a write call wipes the marshalled copy', () async {
      late List<int> captured;
      final repo = FfiVaultRepository(
        deleteLoan:
            ({
              required passphraseUtf8,
              required blob,
              required dbPath,
              required id,
            }) async {
              captured = passphraseUtf8;
            },
      );
      final p = pass();
      await repo.deleteLoan(passphrase: p, blob: 'b', dbPath: 'x.db', id: 1);
      p.dispose();
      expect(captured.every((b) => b == 0), isTrue);
    });

    test('wrapForBiometric wipes the FFI-owned secret S list', () async {
      final ffiSecret = Uint8List.fromList([7, 7, 7, 7]);
      final repo = FfiVaultRepository(
        wrapForBiometric: ({required activeSecretUtf8, required blob}) async =>
            ffi.BiometricWrap(secret: ffiSecret, blob: 'bio.blob'),
      );
      final p = pass();
      final result = await repo.wrapForBiometric(activeSecret: p, blob: 'b');
      p.dispose();
      // The SecretBytes copy carries S; the raw FFI list must be zeroed.
      expect(ffiSecret.every((b) => b == 0), isTrue);
      result.match((f) => fail('expected enrolment, got $f'), (enrolment) {
        expect(enrolment.secret.use((b) => b), [7, 7, 7, 7]);
        enrolment.secret.dispose();
      });
    });
  });
}
