/// Lend a library book to a borrower (application layer, AGENTS.md §4).
///
/// Before this use case existed the lend screen wrote the loan itself, so the
/// availability rule the library list DISPLAYS was never ENFORCED: a
/// single-copy book could be lent twice and a removed book could be lent at
/// all (review 2026-09-03, decision Q4: "refuse lending and inform the user").
///
/// Order of operations (fail closed, no partial state where avoidable):
///  1. load the book — a vanished book is `NotFoundFailure`;
///  2. apply `LendDecision` against the CURRENT unlocked loans — a refusal is
///     a `ValidationFailure` whose message is the human-readable reason;
///  3. resolve the borrower: an existing id, or create one inline (the vault
///     returns the new id, so no name look-up guesswork);
///  4. write the loan.
/// Step 3 and 4 are two vault writes; if the loan write fails after an inline
/// borrower was created, that borrower stays (harmless, visible, deletable)
/// and the failure says so — we never silently drop the user's input.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/lending_policy.dart';

/// The vault operations lending needs — a narrow port so the use case does
/// not depend on the Riverpod session controller directly (same pattern as
/// `VaultLoanPurger` in the library feature).
abstract interface class VaultLender {
  /// Loans currently loaded in the unlocked session; null while locked.
  List<Loan>? get currentLoans;

  /// Inserts [borrower] and returns the new id.
  Future<Either<Failure, int>> addBorrower(Borrower borrower);

  /// Inserts [loan].
  Future<Either<Failure, Unit>> addLoan(Loan loan);
}

/// Who receives the book: an existing borrower or a new one named inline.
sealed class LendTarget {
  const LendTarget();
}

/// An existing borrower.
final class ExistingBorrower extends LendTarget {
  /// Creates the target.
  const ExistingBorrower(this.id);

  /// The borrower id.
  final int id;
}

/// A borrower to create first, with just a name.
final class NewBorrower extends LendTarget {
  /// Creates the target.
  const NewBorrower(this.name);

  /// The (already trimmed, non-empty) name.
  final String name;
}

/// Lends a book, enforcing the lending policy.
class LendBookUseCase {
  /// Creates the use case.
  const LendBookUseCase({required this.books, required this.vault});

  /// Library repository (to load the book's `removed` + `copyCount`).
  final BookRepository books;

  /// Vault side (current loans + writes).
  final VaultLender vault;

  /// Lends [bookId] to [target]. [lentDate] and [dueDate] are epoch millis.
  ///
  /// Returns `Right(unit)` on success; `Left(ValidationFailure)` with the
  /// plain-language reason when the policy refuses; other failures pass
  /// through from the repositories.
  Future<Either<Failure, Unit>> call({
    required int bookId,
    required LendTarget target,
    required int lentDate,
    int? dueDate,
    String? notes,
  }) async {
    final loans = vault.currentLoans;
    if (loans == null) {
      return left(const ValidationFailure('Vault is locked.'));
    }

    final found = await books.getById(bookId);
    final book = found.toNullable();
    if (found.isLeft()) return found.map((_) => unit);
    if (book == null) return left(const NotFoundFailure());

    final decision = LendDecision.forBook(book, loans);
    if (decision is! LendAllowed) {
      return left(ValidationFailure(decision.reason!));
    }

    final int borrowerId;
    switch (target) {
      case ExistingBorrower(:final id):
        borrowerId = id;
      case NewBorrower(:final name):
        final trimmed = name.trim();
        if (trimmed.isEmpty) {
          return left(
            const ValidationFailure('Pick a borrower or enter a new name.'),
          );
        }
        final created = await vault.addBorrower(Borrower(name: trimmed));
        final createdId = created.toNullable();
        if (createdId == null) return created.map((_) => unit);
        borrowerId = createdId;
    }

    final written = await vault.addLoan(
      Loan(
        bookId: bookId,
        borrowerId: borrowerId,
        lentDate: lentDate,
        dueDate: dueDate,
        notes: notes,
      ),
    );
    if (written.isLeft() && target is NewBorrower) {
      // The borrower row landed but the loan did not: say so plainly rather
      // than let the user think nothing happened. ValidationFailure carries a
      // user-facing message by contract (see core/error/failure.dart).
      return left(
        const ValidationFailure(
          'The borrower was added but the loan could not be saved. '
          'Try lending again from their profile.',
        ),
      );
    }
    return written;
  }
}
