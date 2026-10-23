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
/// - [SeriesOverflowMenu]: the app-bar overflow — the hard delete with its
///   typed refusal (D8);
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

/// The series page's app-bar overflow: the hard delete with its typed
/// refusal (D8).
///
/// The refusal path is the point (beginner note): a series that still has
/// issues cannot be deleted — the use case answers a typed
/// `PeriodicalHasIssuesFailure`, and the page shows its wording in a
/// snackbar next to the action instead of blanking a perfectly good list
/// with an error state. On success the controller has already refreshed the
/// list and the page just pops.
class SeriesOverflowMenu extends ConsumerWidget {
  /// Creates the overflow for the CURRENT [periodical] (the observed row).
  const SeriesOverflowMenu({required this.periodical, super.key});

  /// The observed series the delete acts on.
  final Periodical periodical;

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
    return PopupMenuButton<String>(
      tooltip: 'More actions',
      onSelected: (_) => _delete(context, ref),
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'delete',
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
