/// May this book be lent right now? (domain, pure Dart, AGENTS.md §3.1)
///
/// Why this exists (review 2026-09-03, product decision Q4 "refuse lending
/// and inform the user"): the library list already shows a "Not available"
/// badge (see availability.dart), but nothing ENFORCED it — a single-copy
/// book could be lent to two people, and a removed (soft-deleted) book could
/// be lent at all. The rule now lives here, once, as a sealed decision the
/// use case applies and the UI renders. Pure and side-effect-free.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Outcome of asking whether a book can be lent right now.
sealed class LendDecision {
  const LendDecision();

  /// Decides for [book] given the vault's current [loans] (any book's loans
  /// may be passed; others are ignored).
  factory LendDecision.forBook(Book book, Iterable<Loan> loans) {
    if (book.removed) return const LendRefusedRemoved();
    final counts = activeLoanCountsByBook(loans);
    final out = counts[book.id] ?? 0;
    final copies = book.copyCount < 1 ? 1 : book.copyCount;
    if (out >= copies) {
      return LendRefusedAllCopiesOut(copies: copies, out: out);
    }
    return LendAllowed(copiesFree: copies - out);
  }

  /// A user-facing sentence explaining a refusal; null when allowed. Written
  /// as plain language, never a code or SQL text (AGENTS.md §5).
  String? get reason;
}

/// Lending may proceed; [copiesFree] copies are still on the shelf.
final class LendAllowed extends LendDecision {
  /// Creates an allowed decision.
  const LendAllowed({required this.copiesFree});

  /// How many copies are not currently out (≥ 1).
  final int copiesFree;

  @override
  String? get reason => null;
}

/// Refused: the book is marked removed from the library.
final class LendRefusedRemoved extends LendDecision {
  /// Creates the refusal.
  const LendRefusedRemoved();

  @override
  String get reason =>
      'This book is marked as removed from the library, so it cannot be '
      'lent. Restore it to the library first.';
}

/// Refused: every physical copy is already out on loan.
final class LendRefusedAllCopiesOut extends LendDecision {
  /// Creates the refusal.
  const LendRefusedAllCopiesOut({required this.copies, required this.out});

  /// Copies the library owns (≥ 1).
  final int copies;

  /// Copies currently out (≥ [copies]).
  final int out;

  @override
  String get reason => copies == 1
      ? 'This book is already out on loan. Mark it returned before lending '
            'it again.'
      : 'All $copies copies of this book are already out on loan. Mark one '
            'returned before lending it again.';
}
