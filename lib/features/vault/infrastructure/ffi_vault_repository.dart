/// FFI-backed implementation of [VaultRepository] (AGENTS.md §3.1).
///
/// Thin adapter over the generated `pitak_crypto` bindings: it calls
/// `unlockAndReadVault`, translates the Rust `VaultUnlockError` into our sealed
/// [Failure] hierarchy, and maps FFI rows into domain entities — failing closed
/// if a Room `notNull` column comes back null (treated as a corrupt archive).
///
/// The vault key never crosses FFI; only decrypted rows do (verified Step 0).
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/entities/biometric_enrolment.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/src/rust/api.dart' as ffi;

/// Signature of the `insertBorrower` FFI command. Injected so tests can
/// override it without loading the native library (as with the unlock fn).
typedef VaultInsertBorrowerFn =
    Future<int> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
      required String name,
      String? contact,
      String? notes,
    });

/// Signature of the `updateBorrower` FFI command (injectable for tests).
typedef VaultUpdateBorrowerFn =
    Future<void> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
      required int id,
      required String name,
      String? contact,
      String? notes,
    });

/// Signature of a delete-by-id FFI command (`deleteBorrower` / `deleteLoan`).
typedef VaultDeleteByIdFn =
    Future<void> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
      required int id,
    });

/// Signature of the `insertLoan` FFI command (injectable for tests).
typedef VaultInsertLoanFn =
    Future<int> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
      required int bookId,
      required int borrowerId,
      required int lentDate,
      int? dueDate,
      int? returnedDate,
      String? notes,
    });

/// Signature of the `updateLoan` FFI command (injectable for tests).
typedef VaultUpdateLoanFn =
    Future<void> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
      required int id,
      required int bookId,
      required int borrowerId,
      required int lentDate,
      int? dueDate,
      int? returnedDate,
      String? notes,
    });

/// Reads + writes the encrypted borrowers vault through the native Rust core.
final class FfiVaultRepository implements VaultRepository {
  /// Creates the repository. Each FFI function defaults to the generated
  /// binding; override any of them in tests to avoid the native library.
  const FfiVaultRepository({
    Future<ffi.VaultContents> Function({
      required List<int> passphraseUtf8,
      required String blob,
      required String dbPath,
    })?
    unlock,
    VaultInsertBorrowerFn? insertBorrower,
    VaultUpdateBorrowerFn? updateBorrower,
    VaultDeleteByIdFn? deleteBorrower,
    VaultInsertLoanFn? insertLoan,
    VaultUpdateLoanFn? updateLoan,
    VaultDeleteByIdFn? deleteLoan,
    Future<String> Function({
      required List<int> passphraseUtf8,
      required String dbPath,
    })?
    createVault,
    Future<String> Function({
      required List<int> oldPassphraseUtf8,
      required List<int> newPassphraseUtf8,
      required String blob,
    })?
    rewrapBlob,
    Future<ffi.BiometricWrap> Function({
      required List<int> activeSecretUtf8,
      required String blob,
    })?
    wrapForBiometric,
  }) : _unlock = unlock ?? ffi.unlockAndReadVault,
       _createVault = createVault ?? ffi.createVault,
       _rewrapBlob = rewrapBlob ?? ffi.rewrapBlob,
       _wrapForBiometric = wrapForBiometric ?? ffi.wrapForBiometric,
       _insertBorrower = insertBorrower ?? ffi.insertBorrower,
       _updateBorrower = updateBorrower ?? ffi.updateBorrower,
       _deleteBorrower = deleteBorrower ?? ffi.deleteBorrower,
       _insertLoan = insertLoan ?? ffi.insertLoan,
       _updateLoan = updateLoan ?? ffi.updateLoan,
       _deleteLoan = deleteLoan ?? ffi.deleteLoan;

  final Future<ffi.VaultContents> Function({
    required List<int> passphraseUtf8,
    required String blob,
    required String dbPath,
  })
  _unlock;
  final Future<String> Function({
    required List<int> passphraseUtf8,
    required String dbPath,
  })
  _createVault;
  final Future<String> Function({
    required List<int> oldPassphraseUtf8,
    required List<int> newPassphraseUtf8,
    required String blob,
  })
  _rewrapBlob;
  final Future<ffi.BiometricWrap> Function({
    required List<int> activeSecretUtf8,
    required String blob,
  })
  _wrapForBiometric;
  final VaultInsertBorrowerFn _insertBorrower;
  final VaultUpdateBorrowerFn _updateBorrower;
  final VaultDeleteByIdFn _deleteBorrower;
  final VaultInsertLoanFn _insertLoan;
  final VaultUpdateLoanFn _updateLoan;
  final VaultDeleteByIdFn _deleteLoan;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    try {
      // useAsync scopes a defensive copy to the FFI call and wipes it in a
      // finally — flutter_rust_bridge marshals its OWN copy to Rust (which
      // Rust zeroes), so without this the Dart-side copy would linger
      // un-wiped on the GC heap after every unlock (§6.1). The caller still
      // owns `passphrase` and disposes it.
      final contents = await passphrase.useAsync(
        (bytes) => _unlock(passphraseUtf8: bytes, blob: blob, dbPath: dbPath),
      );
      return _mapContents(contents);
    } on ffi.VaultUnlockError catch (e) {
      return left(_mapError(e));
    }
  }

  Either<Failure, VaultData> _mapContents(ffi.VaultContents contents) {
    final borrowers = <Borrower>[];
    for (final b in contents.borrowers) {
      // `name` is NOT NULL in BorrowersDatabase/1.json — null ⇒ corrupt vault.
      final name = b.name;
      if (name == null) {
        return left(
          const BackupCorruptFailure(
            'borrower.name was null (NOT NULL column)',
          ),
        );
      }
      borrowers.add(
        Borrower(id: b.id, name: name, contact: b.contact, notes: b.notes),
      );
    }

    final loans = <Loan>[];
    for (final l in contents.loans) {
      // `lent_date` is NOT NULL — null ⇒ corrupt vault, fail closed.
      final lentDate = l.lentDate;
      if (lentDate == null) {
        return left(
          const BackupCorruptFailure(
            'loan.lent_date was null (NOT NULL column)',
          ),
        );
      }
      loans.add(
        Loan(
          id: l.id,
          bookId: l.bookId,
          borrowerId: l.borrowerId,
          lentDate: lentDate,
          dueDate: l.dueDate,
          returnedDate: l.returnedDate,
          notes: l.notes,
        ),
      );
    }

    return right(VaultData(borrowers: borrowers, loans: loans));
  }

  Failure _mapError(ffi.VaultUnlockError e) => e.when(
    corrupt: BackupCorruptFailure.new,
    wrongPassphrase: WrongPassphraseFailure.new,
    vaultOpen: CryptoFailure.new,
  );

  // --- Vault creation (#26.1) --------------------------------------------

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async {
    try {
      final blob = await passphrase.useAsync(
        (bytes) => _createVault(passphraseUtf8: bytes, dbPath: dbPath),
      );
      return right(blob);
    } on ffi.VaultCreateError catch (e) {
      return left(_mapCreateError(e));
    }
  }

  Failure _mapCreateError(ffi.VaultCreateError e) => e.when(
    alreadyExists: StorageFailure.new,
    vaultOpen: CryptoFailure.new,
    wrap: CryptoFailure.new,
  );

  // --- Passphrase change / re-wrap (#28A) --------------------------------

  @override
  Future<Either<Failure, String>> changePassphrase({
    required SecretBytes oldPassphrase,
    required SecretBytes newPassphrase,
    required String blob,
  }) async {
    try {
      // Nested useAsync: BOTH passphrase copies are wiped when the call
      // returns, on every path.
      final newBlob = await oldPassphrase.useAsync(
        (oldBytes) => newPassphrase.useAsync(
          (newBytes) => _rewrapBlob(
            oldPassphraseUtf8: oldBytes,
            newPassphraseUtf8: newBytes,
            blob: blob,
          ),
        ),
      );
      return right(newBlob);
    } on ffi.VaultRewrapError catch (e) {
      return left(_mapRewrapError(e));
    }
  }

  Failure _mapRewrapError(ffi.VaultRewrapError e) => e.when(
    corrupt: BackupCorruptFailure.new,
    wrongPassphrase: WrongPassphraseFailure.new,
    wrap: CryptoFailure.new,
  );

  // --- Biometric enrolment (#34 B2) --------------------------------------

  @override
  Future<Either<Failure, BiometricEnrolment>> wrapForBiometric({
    required SecretBytes activeSecret,
    required String blob,
  }) async {
    try {
      final wrap = await activeSecret.useAsync(
        (bytes) => _wrapForBiometric(activeSecretUtf8: bytes, blob: blob),
      );
      // Take ownership of S as wipeable bytes, then wipe the FFI-owned list
      // so the only live copy of S on the Dart heap is the SecretBytes.
      final secret = SecretBytes(Uint8List.fromList(wrap.secret));
      SecretBytes.wipe(wrap.secret);
      return right(BiometricEnrolment(secret: secret, blobBio: wrap.blob));
    } on ffi.VaultBiometricError catch (e) {
      return left(_mapBiometricError(e));
    }
  }

  Failure _mapBiometricError(ffi.VaultBiometricError e) => e.when(
    corrupt: BackupCorruptFailure.new,
    wrongPassphrase: WrongPassphraseFailure.new,
    wrap: CryptoFailure.new,
  );

  // --- Write path (#25b) --------------------------------------------------

  @override
  Future<Either<Failure, int>> insertBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _insertBorrower(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        name: borrower.name,
        contact: borrower.contact,
        notes: borrower.notes,
      ),
    ),
  );

  @override
  Future<Either<Failure, Unit>> updateBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _updateBorrower(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        id: borrower.id,
        name: borrower.name,
        contact: borrower.contact,
        notes: borrower.notes,
      ),
    ),
  ).then((e) => e.map((_) => unit));

  @override
  Future<Either<Failure, Unit>> deleteBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _deleteBorrower(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        id: id,
      ),
    ),
  ).then((e) => e.map((_) => unit));

  @override
  Future<Either<Failure, int>> insertLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _insertLoan(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        bookId: loan.bookId,
        borrowerId: loan.borrowerId,
        lentDate: loan.lentDate,
        dueDate: loan.dueDate,
        returnedDate: loan.returnedDate,
        notes: loan.notes,
      ),
    ),
  );

  @override
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _updateLoan(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        id: loan.id,
        bookId: loan.bookId,
        borrowerId: loan.borrowerId,
        lentDate: loan.lentDate,
        dueDate: loan.dueDate,
        returnedDate: loan.returnedDate,
        notes: loan.notes,
      ),
    ),
  ).then((e) => e.map((_) => unit));

  @override
  Future<Either<Failure, Unit>> deleteLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) => _guardWrite(
    () => passphrase.useAsync(
      (bytes) => _deleteLoan(
        passphraseUtf8: bytes,
        blob: blob,
        dbPath: dbPath,
        id: id,
      ),
    ),
  ).then((e) => e.map((_) => unit));

  /// Runs a write FFI call, translating a thrown [ffi.VaultWriteError] into a
  /// typed [Failure]. Returns the call's value on success.
  Future<Either<Failure, T>> _guardWrite<T>(Future<T> Function() call) async {
    try {
      return right(await call());
    } on ffi.VaultWriteError catch (e) {
      return left(_mapWriteError(e));
    }
  }

  Failure _mapWriteError(ffi.VaultWriteError e) => e.when(
    corrupt: BackupCorruptFailure.new,
    wrongPassphrase: WrongPassphraseFailure.new,
    vaultOpen: CryptoFailure.new,
    // FK RESTRICT / NOT NULL → a validation problem the user can act on.
    constraint: ValidationFailure.new,
    notFound: NotFoundFailure.new,
  );
}
