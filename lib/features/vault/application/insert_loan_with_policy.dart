/// Serialized loan insertion with item and borrower policy enforcement.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy_store.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

/// Inserts [loan] after checking current state. The caller supplies its FIFO
/// generation through [isCurrent]/[cancelled]; every asynchronous gap rechecks
/// it before policy decisions or a write can authorize stale work.
Future<Either<Failure, Unit>> insertLoanWithPolicy({
  required VaultRepository vault,
  required Future<CatalogueItemRepository> Function() loadBooks,
  required Future<BorrowerLimitPolicyStore> Function() loadPolicyStore,
  required List<Loan> Function() currentLoans,
  required bool Function() isCurrent,
  required ValidationFailure cancelled,
  required SecretBytes passphrase,
  required String blob,
  required String dbPath,
  required Loan loan,
}) async {
  final books = await loadBooks();
  if (!isCurrent()) return left(cancelled);
  final found = await books.getById(loan.itemId);
  if (!isCurrent()) return left(cancelled);
  if (found.isLeft()) return found.map((_) => unit);
  final book = found.toNullable();
  if (book == null) return left(const NotFoundFailure());

  if (loan.returnedDate == null) {
    final loans = currentLoans();
    final decision = LendDecision.forItem(book, loans);
    if (decision is! LendAllowed) {
      return left(ValidationFailure(decision.reason!));
    }
    final policyStore = await loadPolicyStore();
    if (!isCurrent()) return left(cancelled);
    final loadedPolicy = policyStore.load();
    if (loadedPolicy.isLeft()) {
      return left(const ValidationFailure(borrowerLimitPolicyRecoveryMessage));
    }
    final policy = loadedPolicy.toNullable() ?? BorrowerLimitPolicy.off;
    final limit = policy.maxActiveLoans;
    if (limit != null && policy.action == BorrowerLimitAction.refuse) {
      final active = activeLoanCountForBorrower(loans, loan.borrowerId);
      if (policy.check(activeLoans: active) == BorrowerLimitCheck.refused) {
        return left(
          ValidationFailure(
            borrowerLimitRefusalMessage(activeLoans: active, limit: limit),
          ),
        );
      }
    }
  }

  final written = await vault.insertLoan(
    passphrase: passphrase,
    blob: blob,
    dbPath: dbPath,
    loan: loan,
  );
  return written.map((_) => unit);
}
