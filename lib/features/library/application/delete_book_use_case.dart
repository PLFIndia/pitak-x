/// Hard-delete a library book (application layer, AGENTS.md §4).
///
/// Port of Kotlin `DeleteBookUseCase` (D3). A permanent delete must also purge
/// the book's loan rows in the encrypted vault — a vault-write op — so it is
/// gated on an unlocked vault:
///  - vault unlocked → purge the book's loans, then delete the book row;
///  - vault locked AND the book has loan history → [DeleteBookOutcome.
///    requiresVaultUnlock] (the UI prompts unlock and re-invokes);
///  - vault locked but the book has no loans → delete straight away.
///
/// We avoid any unencrypted "loan count per book" index that would leak vault
/// state while locked (Kotlin's same §1.1 reasoning); when locked we cannot
/// know whether loans exist, so a locked delete of a book that MIGHT have loans
/// must route through unlock. We model that conservatively: when locked we
/// require unlock (the safe, no-leak choice), matching Kotlin's behaviour of
/// surfacing RequiresVaultUnlock whenever it can't confirm there are no loans.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// The vault operations the delete flow needs, kept as a narrow interface so
/// the use case does not depend on the Riverpod session controller directly.
abstract interface class VaultLoanPurger {
  /// Whether the vault is currently unlocked.
  bool get isUnlocked;

  /// Whether the unlocked vault has any loan for [bookId]. Only meaningful
  /// when [isUnlocked]; callers must not rely on it while locked.
  bool hasLoansForBook(int bookId);

  /// Purges every loan referencing [bookId]. Vault must be unlocked.
  Future<Either<Failure, Unit>> purgeLoansForBook(int bookId);
}

/// Outcome of a hard delete.
enum DeleteBookOutcome {
  /// The book (and any loans) were deleted.
  deleted,

  /// The vault is locked; the UI must unlock and re-invoke before deleting.
  requiresVaultUnlock,
}

/// Permanently deletes a book, purging its vault loans when needed.
class DeleteBookUseCase {
  /// Creates the use case.
  const DeleteBookUseCase({required this.books, required this.vault});

  /// Library repository (owns the hard `delete`).
  final BookRepository books;

  /// Vault side (loan purge + unlock state).
  final VaultLoanPurger vault;

  /// Deletes the book with [id]. Returns the [DeleteBookOutcome] on success or
  /// a [Failure] if a step failed (the book row is only deleted AFTER loans are
  /// purged, so a purge failure leaves everything intact — fail-closed).
  Future<Either<Failure, DeleteBookOutcome>> call(int id) async {
    if (!vault.isUnlocked) {
      // Locked: we cannot confirm there are no loans without leaking vault
      // state, so require unlock (Kotlin's conservative RequiresVaultUnlock).
      return right(DeleteBookOutcome.requiresVaultUnlock);
    }
    if (vault.hasLoansForBook(id)) {
      final purged = await vault.purgeLoansForBook(id);
      if (purged.isLeft()) {
        return purged.map((_) => DeleteBookOutcome.deleted);
      }
    }
    final deleted = await books.delete(id);
    return deleted.map((_) => DeleteBookOutcome.deleted);
  }
}
