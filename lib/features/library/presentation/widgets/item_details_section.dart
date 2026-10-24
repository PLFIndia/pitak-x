/// The kind-specific block of the item detail page (presentation layer,
/// AGENTS.md §3.1; ADR 0013 F5, plan S17).
///
/// `switch (item.details)` is EXHAUSTIVE on the sealed `ItemDetails` union —
/// a future kind fails to compile here until its block exists, so no kind
/// can be silently ignored:
///
/// - an **issue** ([IssueOf]) shows what the base row does not carry: which
///   magazine title it belongs to (with an "Open series" action, U2), its
///   volume/number, its cover date — or, for a bound volume (D4), the
///   "issues from / to" range — and its free-text label;
/// - an **other** ([OtherItemOf]) shows nothing: its description IS the
///   shared notes block the page already renders (O1);
/// - a **book** (`details == null`) has no kind-specific fields at all.
///
/// The widget carries its own top spacing only when it renders a block, so
/// books and others leave no gap in the page's row sequence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/widgets/detail_row.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';

/// The kind-specific detail block for [item] (nothing for books/others).
class ItemDetailsSection extends ConsumerWidget {
  /// Creates the section for the CURRENT observed [item].
  const ItemDetailsSection({required this.item, super.key});

  /// The observed row whose details drive the block.
  final CatalogueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (item.details) {
      final IssueOf issue => _IssueSection(issue: issue),
      // O1: an Other's description is the shared Notes block below; a book
      // has no kind-specific section. Render nothing — not even spacing.
      OtherItemOf() || null => const SizedBox.shrink(),
    };
  }
}

/// The issue block: series membership + the fields of [IssueOf].
class _IssueSection extends ConsumerWidget {
  const _IssueSection({required this.issue});

  final IssueOf issue;

  /// Formats a canonical UTC calendar day as `YYYY-MM-DD`; an unset or
  /// unrepresentable value renders as no row instead of throwing.
  static String? _formatDate(int? epochMillis) =>
      CalendarDate.fromEpochMillisOrNull(epochMillis)?.toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    // Resolve the series by its cross-device uid (the key the issue carries,
    // D2). Fail SOFT: while loading, on a read error, or when the series is
    // gone (a series cannot be hard-deleted while issues reference it, D8,
    // but a partial restore can produce one) the issue's own fields still
    // render — only the series row and its action are absent.
    final series = ref
        .watch(periodicalByUidProvider(issue.periodicalUid))
        .valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Same wording as the library row's kind badge (S14).
        Text(
          issue.isBound ? 'Bound volume' : 'Magazine issue',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (series != null) ...[
          DetailRow(label: 'Magazine title', value: series.title),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  // N03: the series page observes the row by id from here;
                  // the resolved entity is only the first frame.
                  builder: (_) => PeriodicalDetailPage(
                    periodicalId: series.id,
                    initialPeriodical: series,
                  ),
                ),
              ),
              icon: const Icon(Icons.newspaper_outlined, size: 18),
              label: const Text('Open series'),
            ),
          ),
        ],
        DetailRow(label: 'Volume', value: issue.volume?.toString()),
        DetailRow(label: 'Issue number', value: issue.issueNumber?.toString()),
        if (issue.isBound) ...[
          DetailRow(label: 'Issues from', value: _formatDate(issue.issueDate)),
          DetailRow(label: 'Issues to', value: _formatDate(issue.boundUntil)),
        ] else
          DetailRow(label: 'Cover date', value: _formatDate(issue.issueDate)),
        DetailRow(label: 'Label', value: issue.label),
      ],
    );
  }
}
