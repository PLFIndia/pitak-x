/// The series detail page's section widgets (periodicals presentation layer,
/// AGENTS.md §3.1).
///
/// Extracted from `pages/periodical_detail_page.dart` so the page stays under
/// the 500-line file-size cap (the S14 precedent:
/// `library/presentation/widgets/catalogue_item_actions.dart`). Everything
/// here acts on the CURRENT observed series the page hands down (N03): no
/// widget keeps a snapshot of its own.
///
/// What lives here:
/// - [SeriesSubscriptionCard]: the derived subscription status (D5) with the
///   tracked dates and the publication cadence;
/// - [SeriesOverflowMenu]: the app-bar overflow — soft remove/restore and
///   the hard delete with its typed refusal (D8);
/// - [SeriesRemovedBadge]: the "Removed" marker for a soft-deleted title.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/presentation/catalogue_save_messages.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/subscription_badge.dart';

/// The subscription summary card: status badge plus the tracked dates and
/// the publication cadence. The page renders it only when there is something
/// to say (a tracked subscription or a known frequency).
class SeriesSubscriptionCard extends StatelessWidget {
  /// Creates the card for [periodical], deriving the status at [now] (the
  /// injected clock, N04 — tests pin it).
  const SeriesSubscriptionCard({
    required this.periodical,
    required this.now,
    super.key,
  });

  /// The observed series.
  final Periodical periodical;

  /// The "now" the status is derived at.
  final DateTime now;

  /// Formats epoch millis as a plain `YYYY-MM-DD`, or null when unset or
  /// out of range (same rule as the book detail page's "Added" row).
  static String? _formatDate(int? epochMillis) {
    if (epochMillis == null) return null;
    final d = CatalogueRules.dateFromMillisOrNull(epochMillis)?.toLocal();
    if (d == null) return null;
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    // The badge text comes from the DERIVED status (D5) — never stored.
    final status = SubscriptionStatus.of(periodical, now);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Subscription',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SubscriptionBadge(status: status),
              ],
            ),
            const SizedBox(height: 8),
            _CardRow(label: 'Frequency', value: periodical.frequency?.label),
            _CardRow(
              label: 'Started',
              value: _formatDate(periodical.subscriptionStart),
            ),
            _CardRow(
              label: 'Ends',
              value: _formatDate(periodical.subscriptionEnd),
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value row inside the subscription card. Renders nothing when
/// [value] is null/blank.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value!, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// What the overflow can do. An enum, not strings: `onSelected` switches
/// over it exhaustively, so a new entry fails to COMPILE until handled.
enum _SeriesAction { remove, restore, delete }

/// The series page's app-bar overflow: soft remove / restore (D8: a
/// removed title stays visible but actionless; its issues are untouched)
/// and the hard delete with its typed refusal.
///
/// The refusal path is the point (beginner note): a series that still has
/// issues cannot be deleted — the use case answers a typed
/// `PeriodicalHasIssuesFailure`, and the page shows its wording in a
/// snackbar next to the action instead of blanking a perfectly good list
/// with an error state. "Remove from library" is the way out that
/// wording offers. After a remove or restore the page STAYS: it observes
/// the row (N03) and re-renders with or without the Removed badge. On a
/// successful delete the controller has already refreshed the list and
/// the page just pops.
class SeriesOverflowMenu extends ConsumerWidget {
  /// Creates the overflow for the CURRENT [periodical] (the observed row).
  const SeriesOverflowMenu({required this.periodical, super.key});

  /// The observed series the actions act on.
  final Periodical periodical;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: const Text(
          'The magazine title stays in your records but is marked '
          'removed; its issues are not changed. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(periodicalsControllerProvider.notifier)
        .remove(periodical.id);
    if (context.mounted) _reportListError(context, ref);
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    await ref
        .read(periodicalsControllerProvider.notifier)
        .restoreRemoved(periodical.id);
    if (context.mounted) _reportListError(context, ref);
  }

  /// `remove` / `restoreRemoved` fold a failed write into the LIST's error
  /// state (fail closed, S13). Say it here as well, next to the action the
  /// user just took — a blanked list behind this page is not feedback.
  void _reportListError(BuildContext context, WidgetRef ref) {
    final error = ref.read(periodicalsControllerProvider).error;
    if (error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(catalogueSaveMessage(error, noun: 'magazine title')),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'This removes the magazine title for good. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(periodicalsControllerProvider.notifier)
        .delete(periodical.id);
    if (!context.mounted) return;
    result.match(
      // Expected refusal (or any other Left): say it in place, keep the page.
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(catalogueSaveMessage(failure, noun: 'magazine title')),
        ),
      ),
      // The controller already refreshed the list; nothing here to update.
      (_) => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_SeriesAction>(
      tooltip: 'More actions',
      onSelected: (action) => switch (action) {
        _SeriesAction.remove => _remove(context, ref),
        _SeriesAction.restore => _restore(context, ref),
        _SeriesAction.delete => _delete(context, ref),
      },
      itemBuilder: (context) => [
        if (periodical.removed)
          const PopupMenuItem(
            value: _SeriesAction.restore,
            child: Text('Restore to library'),
          )
        else
          const PopupMenuItem(
            value: _SeriesAction.remove,
            child: Text('Remove from library'),
          ),
        const PopupMenuItem(
          value: _SeriesAction.delete,
          child: Text('Delete permanently'),
        ),
      ],
    );
  }
}

/// The "Removed" pill of a soft-deleted series (visible-but-inert, D8).
class SeriesRemovedBadge extends StatelessWidget {
  /// Creates the badge.
  const SeriesRemovedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          'Removed',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onErrorContainer),
        ),
      ),
    );
  }
}
