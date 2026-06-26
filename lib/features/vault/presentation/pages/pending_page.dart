/// Pending / reminders screen (presentation layer, AGENTS.md §3.1).
///
/// Vault-gated dashboard (Kotlin D26b): overdue loans, loans due soon, and
/// books that still need metadata. Reads the computed pending snapshot from
/// the unlocked session; shows a friendly empty state when there's nothing to
/// act on. Pure presentation — no business logic here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';

/// The pending / reminders screen.
class PendingPage extends ConsumerWidget {
  /// Creates the pending page.
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingSnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pending')),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => const Center(child: Text("Couldn't load reminders.")),
        data: (snapshot) {
          if (snapshot == null) {
            return const Center(
              child: Text('Unlock the vault to see reminders.'),
            );
          }
          if (snapshot.isEmpty) {
            return const Center(
              child: Text('All caught up — nothing pending.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (snapshot.overdue.isNotEmpty)
                _Section(
                  title: 'Overdue',
                  children: [
                    for (final loan in snapshot.overdue)
                      _LoanTile(
                        bookId: loan.bookId,
                        dueDate: loan.dueDate,
                        emphasize: true,
                      ),
                  ],
                ),
              if (snapshot.dueSoon.isNotEmpty)
                _Section(
                  title: 'Due soon',
                  children: [
                    for (final loan in snapshot.dueSoon)
                      _LoanTile(bookId: loan.bookId, dueDate: loan.dueDate),
                  ],
                ),
              if (snapshot.staleMetadataBooks.isNotEmpty)
                _Section(
                  title: 'Needs info',
                  children: [
                    for (final book in snapshot.staleMetadataBooks)
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(book.title),
                        subtitle: book.author == null
                            ? null
                            : Text(book.author!),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ...children,
      ],
    );
  }
}

class _LoanTile extends StatelessWidget {
  const _LoanTile({
    required this.bookId,
    required this.dueDate,
    this.emphasize = false,
  });

  final int bookId;
  final int? dueDate;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        emphasize ? Icons.warning_amber : Icons.schedule,
        color: emphasize ? scheme.error : null,
      ),
      title: Text('Book #$bookId'),
      subtitle: Text(
        dueDate == null ? 'No due date' : 'Due ${_date(dueDate!)}',
      ),
    );
  }

  static String _date(int epochMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
