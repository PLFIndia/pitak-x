/// Who has this item: one line for each of its loans that is still out,
/// each with "Mark returned" (presentation layer; review finding P4-M3,
/// decisions D103 and D104; ADR 0029).
///
/// It stands on the item's page, under the Lend button. An item can have
/// several copies, so there can be several lines; which loans they are and
/// in which order they stand is decided in `domain/item_active_loans.dart`.
///
/// Privacy (D104): a line names a borrower, so it is drawn ONLY while the
/// vault is unlocked NOW. This widget asks the session itself instead of
/// trusting whoever placed it, and it asks with `unwrapPrevious()`: a
/// session that is loading again or has failed still carries its LAST
/// value, and an earlier unlock must not put a name on the screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/text/display_date.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/item_active_loans.dart';
import 'package:pitaka/features/vault/presentation/widgets/loan_return_action.dart';

/// The lines of the item [itemId]; nothing at all when the vault is not
/// unlocked or no loan of the item is out.
class ItemActiveLoans extends ConsumerWidget {
  /// Creates the lines for the item [itemId].
  const ItemActiveLoans({required this.itemId, super.key});

  /// The catalogue item whose loans are shown.
  final int itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref
        .watch(vaultSessionControllerProvider)
        .unwrapPrevious()
        .valueOrNull;
    if (session is! VaultUnlocked) return const SizedBox.shrink();
    final loans = activeLoansOfItem(itemId: itemId, data: session.data);
    if (loans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in loans)
            // The key ties a line, and the busy state of its button, to its
            // LOAN. Without it Flutter matches lines by their place, and
            // when the first line goes the second would take over its state.
            _LoanLine(
              key: ValueKey('item-loan-${entry.loan.id}'),
              entry: entry,
            ),
        ],
      ),
    );
  }
}

/// One loan: who has the copy and when it is due, and "Mark returned".
///
/// A `Wrap`, as on the borrower's profile: the button stands beside the
/// sentence while both fit and moves under it when they do not, so the
/// words of the button stay whole on a narrow screen and with large text.
class _LoanLine extends StatelessWidget {
  const _LoanLine({required this.entry, super.key});

  final ActiveItemLoan entry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(_sentenceFor(entry)),
        MarkReturnedButton(loanId: entry.loan.id),
      ],
    );
  }
}

/// "Lent to Asha · due 12 November 2026". Words only; the rule about which
/// loans are shown is not here.
String _sentenceFor(ActiveItemLoan entry) {
  final borrower = entry.borrower;
  final who = borrower == null
      ? 'Lent, borrower not found'
      : 'Lent to ${borrower.name}';
  final due = entry.loan.dueDate;
  // A stored date outside the range a date can have is not formatted; it
  // gets a word instead of an error (the loan card does the same).
  final when = due == null
      ? 'no due date'
      : switch (formatDisplayDateOrNull(due)) {
          null => 'due date unavailable',
          final date => 'due $date',
        };
  return '$who · $when';
}
