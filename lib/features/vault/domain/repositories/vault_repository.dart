/// Domain-side interface for the encrypted borrowers vault (AGENTS.md §3.3).
///
/// Declared in `domain`, implemented in `infrastructure` over the Rust FFI
/// core. Returns `Either<Failure, T>`; never throws across the layer. The
/// 32-byte vault key never crosses into Dart — only decrypted rows do.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/entities/biometric_enrolment.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';

/// Read + write access to an encrypted `borrowers.db` through the Rust core.
///
/// Every method takes the passphrase + blob + db path: the 32-byte vault key is
/// unwrapped inside Rust per call and never crosses into Dart (the same trust
/// boundary as the read path). The caller owns the passphrase and disposes it;
/// the bytes are copied across FFI and the Rust side wipes its own copy.
///
/// Write-failure mapping (mirrors Kotlin vault use-case results):
///  - wrong passphrase / GCM tag fail → [WrongPassphraseFailure]
///  - malformed blob → [BackupCorruptFailure]
///  - SQLCipher open/key error → [CryptoFailure]
///  - FK ON DELETE RESTRICT / NOT NULL violation → [ValidationFailure]
///    (e.g. "borrower still has active loans")
///  - update/delete of a missing id → [NotFoundFailure]
abstract interface class VaultRepository {
  /// Unwraps [blob] (Argon2id→AES-GCM) with [passphrase], opens the SQLCipher
  /// `borrowers.db` at [dbPath] in the Rust core, and returns every borrower +
  /// loan row.
  ///
  /// Failure mapping (mirrors Kotlin `BackupRestore.Result`):
  ///  - wrong passphrase / GCM tag fail → [WrongPassphraseFailure]
  ///  - malformed blob / corrupt archive → [BackupCorruptFailure]
  ///  - SQLCipher open/read error → [CryptoFailure]
  ///  - a Room `notNull` column came back null → [BackupCorruptFailure]
  ///
  /// The caller owns [passphrase] and must dispose it; this method does not
  /// take ownership (the bytes are copied across the FFI boundary, then the
  /// Rust side zeroes its own copy).
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  });

  /// Creates a brand-new empty encrypted vault at [dbPath] and returns its
  /// `backup_blob` (the wrapped key, already ciphertext) for the caller to
  /// persist at rest. The 32-byte key is generated + wrapped inside Rust and
  /// never crosses into Dart.
  ///
  /// Failure mapping:
  ///  - a file already exists at [dbPath] / DB couldn't be created →
  ///    [StorageFailure]
  ///  - keying / schema / wrap (crypto) failed → [CryptoFailure]
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  });

  /// Changes the vault passphrase WITHOUT re-encrypting `borrowers.db` (#28A).
  ///
  /// Re-wraps the stable 32-byte vault key from ([oldPassphrase], [blob]) under
  /// [newPassphrase], returning the NEW `backup_blob` for the caller to persist
  /// at rest. The vault key and the database are unchanged — every existing row
  /// stays readable under the new blob. The key never crosses into Dart.
  ///
  /// Failure mapping:
  ///  - [oldPassphrase] did not unwrap the blob → [WrongPassphraseFailure]
  ///  - malformed/corrupt blob → [BackupCorruptFailure]
  ///  - re-wrap (KDF/AEAD) failed → [CryptoFailure]
  ///
  /// The caller owns both passphrases and disposes them (bytes are copied
  /// across FFI; the Rust side wipes its own copies).
  Future<Either<Failure, String>> changePassphrase({
    required SecretBytes oldPassphrase,
    required SecretBytes newPassphrase,
    required String blob,
  });

  /// Enrolls biometric unlock (#34 B2) WITHOUT storing the user passphrase.
  ///
  /// Unwraps the vault key (MK) from ([activeSecret], [blob]) — where
  /// [activeSecret] is the currently-held unlock secret (the passphrase, or an
  /// existing biometric secret) — generates a fresh random secret S, and
  /// returns S together with `blob_bio = wrap(S, MK)`. The caller stores S in
  /// hardware-backed storage behind a biometric gate and persists `blob_bio`.
  /// MK never crosses into Dart; only S (which is meant to be stored) does.
  ///
  /// Returns ([BiometricEnrolment]) on success.
  ///
  /// Failure mapping:
  ///  - [activeSecret] did not unwrap the blob → [WrongPassphraseFailure]
  ///  - malformed/corrupt blob → [BackupCorruptFailure]
  ///  - generate/wrap failed → [CryptoFailure]
  Future<Either<Failure, BiometricEnrolment>> wrapForBiometric({
    required SecretBytes activeSecret,
    required String blob,
  });

  /// Inserts [borrower] (its `id` is ignored) and returns the new id.
  Future<Either<Failure, int>> insertBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  });

  /// Updates the borrower identified by [borrower] `id`.
  Future<Either<Failure, Unit>> updateBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  });

  /// Deletes the borrower with [id]. Fails with [ValidationFailure] if loans
  /// still reference them (FK ON DELETE RESTRICT).
  Future<Either<Failure, Unit>> deleteBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  });

  /// Inserts [loan] (its `id` is ignored) and returns the new id.
  Future<Either<Failure, int>> insertLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  });

  /// Updates the loan identified by [loan] `id`.
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  });

  /// Deletes the loan with [id].
  Future<Either<Failure, Unit>> deleteLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  });
}
