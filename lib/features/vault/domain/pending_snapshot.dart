/// Pending / reminders snapshot (domain, pure Dart, AGENTS.md §3.1).
///
/// Port of Kotlin `GetPendingUseCase` (D26b), the vault-gated reminders view.
/// Kotlin surfaces five things; we port the three that map onto our current
/// model from already-available data:
///  - overdue loans (out, past due at `now`),
///  - loans due soon (out, due within `dueSoonWithinDays`),
///  - books flagged `needsMetadata` (cross-feature: from the library).
///
/// Deferred (recorded, not yet ported): the two backup nudges
/// (`backupPassphraseNeeded`, `backupStaleDays`). The first does not fit our
/// single-passphrase model (an unlocked vault necessarily has a passphrase);
/// the second needs a persisted "last backup at" timestamp we do not track yet
/// (a Settings/VaultStore addition for a later step).
///
/// Pure and side-effect-free: computed over the decrypted session loans + the
/// library books, so it is trivially unit-testable.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

/// Default window (days) for the "due soon" bucket (Kotlin default = 3).
const int kDueSoonWithinDays = 3;

/// A consolidated reminders snapshot.
class PendingSnapshot {
  /// Creates a snapshot.
  const PendingSnapshot({
    required this.overdue,
    required this.dueSoon,
    required this.staleMetadataBooks,
  });

  /// Loans that are out and past their due date at `now`.
  final List<Loan> overdue;

  /// Loans that are out and due within the window (not yet overdue).
  final List<Loan> dueSoon;

  /// Library books flagged as needing metadata.
  final List<Book> staleMetadataBooks;

  /// True when there is nothing to act on.
  bool get isEmpty =>
      overdue.isEmpty && dueSoon.isEmpty && staleMetadataBooks.isEmpty;

  /// Total number of pending items across all buckets.
  int get count => overdue.length + dueSoon.length + staleMetadataBooks.length;
}

/// Builds a [PendingSnapshot] from the unlocked vault [loans] and library
/// [books] at time [now] (epoch millis).
///
/// Overdue = out and `now > dueDate`. Due-soon = out, not overdue, and
/// `dueDate <= now + window`. Both are ordered by due date ascending (soonest
/// first). Stale-metadata = non-removed books with `needsMetadata`.
PendingSnapshot buildPendingSnapshot({
  required List<Loan> loans,
  required List<Book> books,
  required int now,
  int dueSoonWithinDays = kDueSoonWithinDays,
}) {
  final withinMs = dueSoonWithinDays * 24 * 60 * 60 * 1000;
  final soonCutoff = now + withinMs;

  final overdue = <Loan>[];
  final dueSoon = <Loan>[];
  for (final loan in loans) {
    if (loan.isReturned || loan.dueDate == null) continue;
    final due = loan.dueDate!;
    if (now > due) {
      overdue.add(loan);
    } else if (due <= soonCutoff) {
      dueSoon.add(loan);
    }
  }
  overdue.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  dueSoon.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

  final stale = books
      .where((b) => b.needsMetadata && !b.removed)
      .toList(growable: false);

  return PendingSnapshot(
    overdue: overdue,
    dueSoon: dueSoon,
    staleMetadataBooks: stale,
  );
}
