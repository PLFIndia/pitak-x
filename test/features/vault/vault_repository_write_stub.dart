/// Shared test support: throwing defaults for the [VaultRepository] WRITE
/// methods (#25b).
///
/// Most existing tests only exercise the READ path (`unlockAndRead`). Rather
/// than copy six "not used here" stubs into every read-only fake, those fakes
/// mix in [VaultWriteUnsupported], which throws if a write is unexpectedly
/// called — keeping the write contract in one place and failing loudly if a
/// test routes through a write it didn't mean to.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/entities/biometric_enrolment.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

/// Mix into a read-only [VaultRepository] fake to satisfy the write methods
/// with loud "not expected" defaults.
mixin VaultWriteUnsupported implements VaultRepository {
  Never _unsupported(String method) =>
      throw UnimplementedError('$method not expected in this test');

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) => _unsupported('createVault');

  @override
  Future<Either<Failure, String>> changePassphrase({
    required SecretBytes oldPassphrase,
    required SecretBytes newPassphrase,
    required String blob,
  }) => _unsupported('changePassphrase');

  @override
  Future<Either<Failure, BiometricEnrolment>> wrapForBiometric({
    required SecretBytes activeSecret,
    required String blob,
  }) => _unsupported('wrapForBiometric');

  @override
  Future<Either<Failure, int>> insertBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) => _unsupported('insertBorrower');

  @override
  Future<Either<Failure, Unit>> updateBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Borrower borrower,
  }) => _unsupported('updateBorrower');

  @override
  Future<Either<Failure, Unit>> deleteBorrower({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) => _unsupported('deleteBorrower');

  @override
  Future<Either<Failure, int>> insertLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) => _unsupported('insertLoan');

  @override
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) => _unsupported('updateLoan');

  @override
  Future<Either<Failure, Unit>> deleteLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required int id,
  }) => _unsupported('deleteLoan');
}
