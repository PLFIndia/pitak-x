/// May a return be taken back? (domain, pure Dart, AGENTS.md §3.1)
///
/// Why this exists (review finding P4-M3, decision D107): after "Mark
/// returned" the app offers "Undo". Taking a return back makes the loan
/// active again, and the offer can stay on screen for a while. If the same
/// copy was lent to somebody else in between, an Undo that checked nothing
/// would record one physical copy as being with two people.
///
/// So ONE thing is checked: a copy of the item is still free. Deliberately
/// NOT checked, although a new loan checks them (see lending_policy.dart):
///  - the borrower limit, and
///  - whether the item is marked as removed from the library.
/// Undo does not lend anything. It corrects a record: the book is with that
/// borrower whatever the rules for a NEW loan say, and a rule that refused
/// the correction would leave a wrong return standing with no way to fix it.
///
/// The rule lives here once, as a sealed decision (a closed set of outcomes
/// the compiler knows), in the manner of `LendDecision`. It is pure: it
/// reads what it is given and changes nothing.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// The sentence a refused Undo shows. Plain language, no name, no title, no
/// number (AGENTS.md §5), so it is safe wherever a message can appear.
const String reopenRefusedNoCopyFreeMessage =
    'This item was lent again in the meantime, so the return cannot be '
    'undone. Mark the new loan returned first.';

/// Outcome of asking whether the return of a loan may be taken back.
sealed class ReopenDecision {
  const ReopenDecision();

  /// Decides for [loan], whose item has [copyCount] copies, given the
  /// vault's current [loans] (any item's loans may be passed; others are
  /// ignored).
  ///
  /// [copyCount] is clamped to at least 1, as the lending rule does, so a
  /// malformed zero or negative count never frees or blocks a copy by
  /// accident. [loan] itself never counts against itself, in whatever state
  /// [loans] shows it.
  factory ReopenDecision.forLoan({
    required Loan loan,
    required int copyCount,
    required Iterable<Loan> loans,
  }) {
    final copies = copyCount < 1 ? 1 : copyCount;
    var out = 0;
    for (final other in loans) {
      if (other.id == loan.id) continue;
      if (other.itemId == loan.itemId && !other.isReturned) out++;
    }
    return out >= copies
        ? const ReopenRefusedNoCopyFree()
        : const ReopenAllowed();
  }

  /// A user-facing sentence explaining a refusal; null when allowed.
  String? get reason;
}

/// The return may be taken back: a copy of the item is free.
final class ReopenAllowed extends ReopenDecision {
  /// Creates the allowed decision.
  const ReopenAllowed();

  @override
  String? get reason => null;
}

/// Refused: every copy of the item is out with somebody else by now.
final class ReopenRefusedNoCopyFree extends ReopenDecision {
  /// Creates the refusal.
  const ReopenRefusedNoCopyFree();

  @override
  String get reason => reopenRefusedNoCopyFreeMessage;
}
