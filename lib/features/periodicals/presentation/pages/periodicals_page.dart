/// The Magazines screen — every magazine title with its issue summary and
/// subscription badge (periodicals presentation layer, AGENTS.md §3.1;
/// ADR 0013 U2).
///
/// Pure presentation: reads [PeriodicalsController] state and forwards user
/// input to it. No business logic, no direct repository access. Mirrors the
/// Library screen's shape (list, empty state, safe error state) so the two
/// screens feel like one app.
///
/// The controller re-reads the list on the minute tick (N04) so a badge can
/// roll from "Expiring soon" to "Lapsed" while the page stays open. Such a
/// reload keeps the previous value, and this page renders through
/// `valueOrNull` — the list never flashes a spinner once it has loaded.
///
/// The FAB and the empty state's button open the series form (S16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/subscription_badge.dart';

/// The magazine-titles list screen.
class PeriodicalsPage extends ConsumerWidget {
  /// Creates the page.
  const PeriodicalsPage({super.key});

  /// Opens the (empty) series form to add a new magazine title.
  void _addPeriodical(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PeriodicalFormPage()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(periodicalsControllerProvider);
    // See the header: a tick-triggered reload carries the previous list, so
    // render the value whenever there is one and keep the spinner for the
    // FIRST load only.
    final entries = entriesAsync.valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Magazines')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New magazine title',
        onPressed: () => _addPeriodical(context),
        child: const Icon(Icons.add),
      ),
      body: entries != null
          ? entries.isEmpty
                ? _EmptyState(onAdd: () => _addPeriodical(context))
                : _PeriodicalList(entries: entries)
          : entriesAsync.hasError
          ? _LoadError(
              onRetry: () =>
                  ref.read(periodicalsControllerProvider.notifier).refresh(),
            )
          : const Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}

/// The loaded list of series, in the controller's (title, id) order.
class _PeriodicalList extends StatelessWidget {
  const _PeriodicalList({required this.entries});

  final List<PeriodicalListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _PeriodicalRow(
          entry: entry,
          // N03: the detail page observes the series by id; the tapped row is
          // only the first frame's content.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PeriodicalDetailPage(
                periodicalId: entry.periodical.id,
                initialPeriodical: entry.periodical,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One magazine-title row: cover, title, publisher, issue summary, and the
/// status badges (subscription, removed).
class _PeriodicalRow extends StatelessWidget {
  const _PeriodicalRow({required this.entry, required this.onTap});

  final PeriodicalListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final periodical = entry.periodical;
    // A removed title is dimmed (visible-but-inert), mirroring the library
    // row's rule for removed books (Kotlin D39).
    final titleColor = periodical.removed
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            // A remote series cover is materialised against the periodical
            // itself; issues may inherit it without becoming its owner.
            ItemCover(
              title: periodical.title,
              coverUrl: periodical.coverUrl,
              owner: periodical.periodicalUid == null
                  ? null
                  : CoverOwners.periodical(periodical.periodicalUid!),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    periodical.title,
                    style: textTheme.titleMedium?.copyWith(color: titleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (periodical.publisher?.trim().isNotEmpty ?? false)
                    Text(
                      periodical.publisher!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    _summaryLine(entry),
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Trailing status markers. Constrained + wrapping so badges flow
            // onto a second line instead of overflowing (same rule as the
            // library row).
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  SubscriptionBadge(status: entry.status),
                  if (periodical.removed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        'Removed',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "12 issues · latest 2026-09" — the count always, the newest issue's
  /// month when any issue carries a date.
  static String _summaryLine(PeriodicalListEntry entry) {
    final count = entry.issueCount;
    final issues = count == 1 ? '1 issue' : '$count issues';
    final latest = entry.latestIssueDate;
    if (latest == null) return issues;
    final date = CalendarDate.fromEpochMillisOrNull(latest);
    if (date == null) return issues;
    final mm = date.month.toString().padLeft(2, '0');
    return '$issues · latest ${date.year}-$mm';
  }
}

/// Shown when no magazine title exists yet. The add action matches the FAB.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.newspaper_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('No magazine titles yet', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add a magazine title to start cataloguing its issues.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('New magazine title'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Safe error state — never shows raw exception text (AGENTS.md §5).
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Couldn't load your magazine titles. Please try again.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
