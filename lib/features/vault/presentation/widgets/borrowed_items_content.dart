/// Unlocked Borrowed Items content: template selector, filters and loan list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/layout/breakpoints.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_grid_card.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_row.dart';

/// User-visible active-loan filters.
enum BorrowedItemsFilter {
  /// Every resolved active loan.
  all,

  /// Only overdue loans.
  overdue,

  /// Only loans due within the rolling 72-hour window.
  dueSoon,

  /// Only open-ended loans.
  noDueDate,
}

/// Snapshot-driven content. The parent owns filter and per-loan busy state.
final class BorrowedItemsContent extends ConsumerWidget {
  /// Creates unlocked content over the borrowed-items provider.
  const BorrowedItemsContent({
    required this.filter,
    required this.onFilterChanged,
    required this.busyLoanIds,
    required this.onOpen,
    required this.onCall,
    required this.onShare,
    required this.onWhatsAppText,
    super.key,
  });

  /// Currently selected filter.
  final BorrowedItemsFilter filter;

  /// Called when a filter chip is selected.
  final ValueChanged<BorrowedItemsFilter> onFilterChanged;

  /// Loan IDs whose reminder action is currently busy.
  final Set<int> busyLoanIds;

  /// Opens the catalogue detail for one loan.
  final ValueChanged<BorrowedLoan> onOpen;

  /// Launches the sanitized borrower dialer URI.
  final ValueChanged<BorrowedLoan> onCall;

  /// Prepares a generic share using the tapped button for iPad anchoring.
  final void Function(BorrowedLoan entry, BuildContext buttonContext) onShare;

  /// Opens the borrower's WhatsApp conversation with text only.
  final ValueChanged<BorrowedLoan> onWhatsAppText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(borrowedItemsSnapshotProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) => _LoadError(
        onRetry: () => ref.invalidate(borrowedItemsSnapshotProvider),
      ),
      data: (snapshot) {
        if (snapshot == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (!snapshot.hasActiveLoans) {
          return const Center(child: Text('Nothing is currently borrowed.'));
        }
        final entries = snapshot.entries
            .where((entry) {
              return switch (filter) {
                BorrowedItemsFilter.all => true,
                BorrowedItemsFilter.overdue =>
                  entry.urgency == LoanUrgency.overdue,
                BorrowedItemsFilter.dueSoon =>
                  entry.urgency == LoanUrgency.dueSoon,
                BorrowedItemsFilter.noDueDate =>
                  entry.urgency == LoanUrgency.noDueDate,
              };
            })
            .toList(growable: false);
        return Column(
          children: [
            const _TemplateSelector(),
            _FilterChips(selected: filter, onChanged: onFilterChanged),
            if (snapshot.unresolvedCount > 0)
              _UnresolvedWarning(count: snapshot.unresolvedCount),
            Expanded(
              child: entries.isEmpty
                  ? _EmptyFilteredOrUnresolved(
                      isFiltered: filter != BorrowedItemsFilter.all,
                      unresolvedCount: snapshot.unresolvedCount,
                    )
                  : _LoanList(
                      entries: entries,
                      busyLoanIds: busyLoanIds,
                      onOpen: onOpen,
                      onCall: onCall,
                      onShare: onShare,
                      onWhatsAppText: onWhatsAppText,
                    ),
            ),
          ],
        );
      },
    );
  }
}

final class _TemplateSelector extends ConsumerWidget {
  const _TemplateSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reminderTemplatesControllerProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Expanded(child: Text("Couldn't load message templates.")),
            TextButton(
              onPressed: () =>
                  ref.invalidate(reminderTemplatesControllerProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (settings) {
        final selected = settings.selectedTemplate;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selected == null
                    ? 'Reminder template: unavailable — choose one'
                    : 'Reminder template: ${selected.name}',
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: selected == null ? null : settings.selectedTemplateId,
                hint: const Text('Choose a message template'),
                items: [
                  for (final template in settings.allTemplates)
                    DropdownMenuItem(
                      value: template.id,
                      child: Text(template.name),
                    ),
                ],
                onChanged: (id) async {
                  if (id == null) return;
                  final result = await ref
                      .read(reminderTemplatesControllerProvider.notifier)
                      .select(id);
                  if (!context.mounted) return;
                  result.match(
                    (_) => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Couldn't save the template selection."),
                      ),
                    ),
                    (_) {},
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onChanged});
  final BorrowedItemsFilter selected;
  final ValueChanged<BorrowedItemsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final filter in BorrowedItemsFilter.values)
            ChoiceChip(
              label: Text(switch (filter) {
                BorrowedItemsFilter.all => 'All',
                BorrowedItemsFilter.overdue => 'Overdue',
                BorrowedItemsFilter.dueSoon => 'Due soon (72 hours)',
                BorrowedItemsFilter.noDueDate => 'No due date',
              }),
              selected: selected == filter,
              onSelected: (_) => onChanged(filter),
            ),
        ],
      ),
    );
  }
}

final class _LoanList extends StatelessWidget {
  const _LoanList({
    required this.entries,
    required this.busyLoanIds,
    required this.onOpen,
    required this.onCall,
    required this.onShare,
    required this.onWhatsAppText,
  });

  final List<BorrowedLoan> entries;
  final Set<int> busyLoanIds;
  final ValueChanged<BorrowedLoan> onOpen;
  final ValueChanged<BorrowedLoan> onCall;
  final void Function(BorrowedLoan, BuildContext) onShare;
  final ValueChanged<BorrowedLoan> onWhatsAppText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = constraints.maxWidth >= largeScreenMinWidth;
        if (grid) {
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 480,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return BorrowedLoanGridCard(
                key: ValueKey('borrowed-loan-${entry.loan.id}'),
                entry: entry,
                busy: busyLoanIds.contains(entry.loan.id),
                onTap: () => onOpen(entry),
                onCall: _callCallback(entry),
                onShare: (buttonContext) => onShare(entry, buttonContext),
                onWhatsAppText: _whatsAppTextCallback(entry),
              );
            },
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return BorrowedLoanRow(
              key: ValueKey('borrowed-loan-${entry.loan.id}'),
              entry: entry,
              busy: busyLoanIds.contains(entry.loan.id),
              onTap: () => onOpen(entry),
              onCall: _callCallback(entry),
              onShare: (buttonContext) => onShare(entry, buttonContext),
              onWhatsAppText: _whatsAppTextCallback(entry),
            );
          },
        );
      },
    );
  }

  VoidCallback? _callCallback(BorrowedLoan entry) {
    final tel = BorrowerContact.decode(entry.borrower.contact).telUri;
    return tel == null ? null : () => onCall(entry);
  }

  VoidCallback? _whatsAppTextCallback(BorrowedLoan entry) {
    final uri = BorrowerContact.decode(entry.borrower.contact).whatsappUri;
    return uri == null ? null : () => onWhatsAppText(entry);
  }
}

final class _UnresolvedWarning extends StatelessWidget {
  const _UnresolvedWarning({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '$count active ${count == 1 ? 'loan has' : 'loans have'} unresolved '
        'catalogue or borrower references.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

final class _EmptyFilteredOrUnresolved extends StatelessWidget {
  const _EmptyFilteredOrUnresolved({
    required this.isFiltered,
    required this.unresolvedCount,
  });
  final bool isFiltered;
  final int unresolvedCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          isFiltered
              ? 'No loans match this filter.'
              : unresolvedCount > 0
              ? 'Active loans need catalogue or borrower repairs before they '
                    'can be shown.'
              : 'No loans match.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

final class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load borrowed items."),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
