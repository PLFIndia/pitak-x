/// Book availability from vault loans (domain, pure Dart, AGENTS.md §3.1).
///
/// Mirrors the Kotlin `LibraryViewModel` rule: a book is "not available" when
/// the number of its ACTIVE loans (loans not yet returned) is at least its
/// `copyCount` — i.e. every copy is currently out. This is only meaningful when
/// the vault is unlocked (loans are encrypted); when locked, availability is
/// unknown and no badge should show.
library;

import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Counts active (not-yet-returned) loans per `bookId` from [loans].
Map<int, int> activeLoanCountsByBook(Iterable<Loan> loans) {
  final counts = <int, int>{};
  for (final loan in loans) {
    if (loan.isReturned) continue;
    counts.update(loan.bookId, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// True when [bookId] has at least [copyCount] active loans (all copies out),
/// given the precomputed [activeCounts]. [copyCount] is clamped to a minimum of
/// 1 so a malformed zero/negative count never makes a book permanently
/// available or unavailable by accident.
bool isBookUnavailable({
  required int bookId,
  required int copyCount,
  required Map<int, int> activeCounts,
}) {
  final out = activeCounts[bookId] ?? 0;
  final copies = copyCount < 1 ? 1 : copyCount;
  return out >= copies;
}
