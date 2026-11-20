/// Marking a loan returned, and taking that back, in ONE place
/// (application layer; review finding P4-M3, decisions D107 and D110).
///
/// Why this file exists (beginner note): until 2026-11 two screens each
/// built the "returned" row themselves, from the copy of the loan the screen
/// was drawn with, and handed it to a method that wrote whatever it was
/// given. A rule about loans was living in widgets, twice, and nothing
/// could be taken back. Now every screen hands in an ID, and this function:
///  - looks the loan up as it is NOW (so it can never write an old copy
///    back over a newer row);
///  - writes nothing when there is nothing to change (two fast taps, or the
///    same tap from two pages, are one return with one date);
///  - before taking a return back, applies the one rule of
///    [ReopenDecision]: a copy of the item must still be free.
///
/// It is called INSIDE the vault session's queue (see
/// `VaultSessionController`), in the manner of `insertLoanWithPolicy`: the
/// caller supplies its queue generation through `isCurrent`/`cancelled`, and
/// the wait in here rechecks it before a decision or a write can act on a
/// session that has ended.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

/// Marks the loan [loanId] returned at [returnedAt] (epoch millis), or, when
/// [returnedAt] is null, takes its return back.
///
/// Answers:
///  - `Right(unit)` after the write, and also when the loan is already in
///    the state asked for (then NOTHING is written; a loan that was already
///    returned keeps its first date);
///  - [NotFoundFailure] when no loan has that id any more;
///  - a [ValidationFailure] with a sentence for the user when a return
///    cannot be taken back (every copy is out again);
///  - [cancelled] when the session ended during the wait;
///  - whatever failure the item's read or the vault's write gives. Nothing
///    is written after a failure (fail closed).
///
/// [loadItem] reads one catalogue item; it is only called to take a return
/// back, for the item's number of copies. An item that is not in the
/// catalogue counts as ONE copy.
Future<Either<Failure, Unit>> changeLoanReturn({
  required VaultRepository vault,
  required Future<Either<Failure, CatalogueItem?>> Function(int itemId)
  loadItem,
  required List<Loan> Function() currentLoans,
  required bool Function() isCurrent,
  required ValidationFailure cancelled,
  required SecretBytes passphrase,
  required String blob,
  required String dbPath,
  required int loanId,
  required int? returnedAt,
}) async {
  final loan = _find(currentLoans(), loanId);
  if (loan == null) return left(const NotFoundFailure());

  final Loan changed;
  if (returnedAt != null) {
    // Mark returned. Already returned: one return, its first date stays.
    if (loan.isReturned) return right(unit);
    changed = loan.copyWith(returnedDate: returnedAt);
  } else {
    // Take the return back. Still out: there is nothing to take back.
    if (!loan.isReturned) return right(unit);
    final read = await loadItem(loan.itemId);
    if (!isCurrent()) return left(cancelled);
    if (read case Left(value: final failure)) return left(failure);
    final decision = ReopenDecision.forLoan(
      loan: loan,
      copyCount: read.toNullable()?.copyCount ?? 1,
      // Read again after the wait, not before it.
      loans: currentLoans(),
    );
    final reason = decision.reason;
    if (reason != null) return left(ValidationFailure(reason));
    changed = loan.reopened();
  }

  final written = await vault.updateLoan(
    passphrase: passphrase,
    blob: blob,
    dbPath: dbPath,
    loan: changed,
  );
  return written.map((_) => unit);
}

Loan? _find(List<Loan> loans, int id) {
  for (final loan in loans) {
    if (loan.id == id) return loan;
  }
  return null;
}
