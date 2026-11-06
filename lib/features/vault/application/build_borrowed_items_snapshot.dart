/// Builds the strict Borrowed Items read model from unlocked vault data.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_cover.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_integrity.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';

/// Reads only catalogue rows referenced by active loans, sequentially.
final class BuildBorrowedItemsSnapshot {
  /// Creates the use case over domain repository ports.
  const BuildBorrowedItemsSnapshot({
    required CatalogueItemRepository items,
    required PeriodicalRepository periodicals,
  }) : _items = items,
       _periodicals = periodicals;

  final CatalogueItemRepository _items;
  final PeriodicalRepository _periodicals;

  /// Builds a snapshot at epoch-millisecond [now].
  Future<Either<Failure, BorrowedItemsSnapshot>> call({
    required VaultData data,
    required int now,
  }) async {
    final active = data.loans.where((loan) => !loan.isReturned).toList();
    if (active.isEmpty) return right(BorrowedItemsSnapshot.empty);

    final items = <int, CatalogueItem>{};
    for (final id in active.map((loan) => loan.itemId).toSet()) {
      final read = await _items.getById(id);
      final failure = read.swap().toNullable();
      if (failure != null) return left(failure);
      final item = read.toNullable();
      if (item != null) items[id] = item;
    }

    final borrowers = {
      for (final borrower in data.borrowers) borrower.id: borrower,
    };
    final unresolved = LoanIntegrity.findDangling(
      loans: active,
      knownBookIds: items.keys.toSet(),
      knownBorrowerIds: borrowers.keys.toSet(),
    ).map((dangling) => dangling.loan).toSet();
    final display = active.where((loan) => !unresolved.contains(loan)).toList();

    final series = await _seriesFallbacks(display, items);
    final seriesFailure = series.swap().toNullable();
    if (seriesFailure != null) return left(seriesFailure);
    final periodicals = series.toNullable()!;

    final entries = <BorrowedLoan>[
      for (final loan in display)
        BorrowedLoan(
          item: items[loan.itemId]!,
          loan: loan,
          borrower: borrowers[loan.borrowerId]!,
          urgency: loanUrgency(loan, now),
          coverUrl: IssueCover.resolve(
            items[loan.itemId]!,
            periodicals[items[loan.itemId]!.issue?.periodicalUid],
          ),
        ),
    ]..sort(_compare);
    return right(
      BorrowedItemsSnapshot(
        entries: List.unmodifiable(entries),
        unresolvedCount: unresolved.length,
      ),
    );
  }

  Future<Either<Failure, Map<String, Periodical>>> _seriesFallbacks(
    List<Loan> display,
    Map<int, CatalogueItem> items,
  ) async {
    final needed = display.any((loan) {
      final item = items[loan.itemId]!;
      return item.issue != null && (item.coverUrl?.trim().isEmpty ?? true);
    });
    if (!needed) return right(const {});

    final read = await _periodicals.listAll();
    final failure = read.swap().toNullable();
    if (failure != null) return left(failure);
    return right({
      for (final summary in read.toNullable()!)
        if (summary.periodical.periodicalUid case final uid?)
          uid: summary.periodical,
    });
  }
}

int _compare(BorrowedLoan a, BorrowedLoan b) {
  final aDue = a.loan.dueDate;
  final bDue = b.loan.dueDate;
  if (aDue == null && bDue != null) return 1;
  if (aDue != null && bDue == null) return -1;
  if (aDue != null && bDue != null) {
    final byDue = aDue.compareTo(bDue);
    if (byDue != 0) return byDue;
  }
  final byTitle = a.item.title.compareTo(b.item.title);
  if (byTitle != 0) return byTitle;
  final byBorrower = a.borrower.name.compareTo(b.borrower.name);
  if (byBorrower != 0) return byBorrower;
  return a.loan.id.compareTo(b.loan.id);
}
