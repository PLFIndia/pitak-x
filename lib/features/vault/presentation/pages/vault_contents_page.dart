/// Vault contents view (presentation layer, AGENTS.md §3.1).
///
/// Read-only: lists each borrower with their loans. Loans carry a `bookId`
/// (a library book id); the title is resolved through the existing loan-row
/// read model (`bookTitleProvider`, N06) with a "Book #id" fallback when it
/// can't be found (e.g. the matching library book wasn't restored). The
/// vault itself is never mutated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';

/// Displays borrowers and their loans from an unlocked [VaultData].
class VaultContentsPage extends ConsumerWidget {
  /// Creates the contents page for [data].
  const VaultContentsPage({required this.data, super.key});

  /// The unlocked vault snapshot.
  final VaultData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansByBorrower = <int, List<Loan>>{};
    for (final loan in data.loans) {
      loansByBorrower.putIfAbsent(loan.borrowerId, () => []).add(loan);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Borrowers & loans')),
      body: data.borrowers.isEmpty
          ? const Center(child: Text('This vault has no borrowers.'))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final borrower in data.borrowers)
                  _BorrowerTile(
                    borrower: borrower,
                    loans: loansByBorrower[borrower.id] ?? const [],
                  ),
              ],
            ),
    );
  }
}

class _BorrowerTile extends ConsumerWidget {
  const _BorrowerTile({required this.borrower, required this.loans});

  final Borrower borrower;
  final List<Loan> loans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = loans.where((l) => !l.isReturned).length;
    final subtitle = [
      if (borrower.contact != null && borrower.contact!.trim().isNotEmpty)
        borrower.contact!,
      '${loans.length} loan${loans.length == 1 ? '' : 's'} · $active out',
    ].join(' · ');

    return ExpansionTile(
      title: Text(borrower.name),
      subtitle: Text(subtitle),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      children: loans.isEmpty
          ? [const ListTile(dense: true, title: Text('No loans'))]
          : [for (final loan in loans) _LoanRow(loan: loan)],
    );
  }
}

class _LoanRow extends ConsumerWidget {
  const _LoanRow({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // N04: injectable clock + tick watch, so the Overdue badge rolls over
    // while the page stays open (a loan due at 15:00 turns overdue at 15:00,
    // not at the next app start).
    ref.watch(nowTickProvider);
    final now = ref.watch(clockProvider)();
    final overdue = loan.isOverdue(now);

    final status = loan.isReturned
        ? 'Returned'
        : overdue
        ? 'Overdue'
        : 'Out';
    final statusColor = loan.isReturned
        ? scheme.onSurfaceVariant
        : overdue
        ? scheme.error
        : scheme.primary;

    // Title resolution lives behind a provider (S2 — the row only watches
    // it; no repository IO in presentation). Null (missing/unreadable book,
    // or still loading) falls back to the "Book #id" label — fail-soft for
    // a cosmetic label. The provider watches libraryControllerProvider, so a
    // rename while this page is open re-reads the row (N06).
    final title =
        ref.watch(bookTitleProvider(bookId: loan.bookId)).valueOrNull ??
        'Book #${loan.bookId}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text('Lent ${_date(loan.lentDate)}'),
      trailing: Text(
        status,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: statusColor),
      ),
    );
  }

  static String _date(int epochMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
