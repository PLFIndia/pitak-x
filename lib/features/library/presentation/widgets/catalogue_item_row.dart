/// A single library list row (presentation layer).
///
/// Parity with Kotlin `LibraryScreen.BookRow`: title (2 lines), author, and the
/// status badges — removed (dimmed + badge), needs-metadata, copy-count "×N",
/// and the vault "Not available" badge (every copy is out on loan, shown only
/// when the vault is unlocked so availability is known).
///
/// S14 (ADR 0013): a non-book row also carries a KIND badge ("Issue" /
/// "Bound volume" / "Other"), and a magazine issue without its own cover
/// shows its series' cover (ADR 0014 W4) — resolved through the shared
/// [periodicalCoversProvider] map, so the whole list costs ONE `listAll`
/// read no matter how many issue rows are on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

/// One tappable book row.
class CatalogueItemRow extends ConsumerWidget {
  /// Creates a row for [book]; [onTap] opens its detail.
  const CatalogueItemRow({
    required this.book,
    required this.onTap,
    this.unavailable = false,
    super.key,
  });

  /// The book to render.
  final CatalogueItem book;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  /// True when every copy is out on loan (vault unlocked). Shows a badge.
  final bool unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Removed books are dimmed (visible-but-inert), mirroring Kotlin D39.
    final titleColor = book.removed
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    // W4 cover fallback (issues only): the series cover stands in when the
    // issue has none of its own — the same rule `IssueCover.resolve` applies,
    // here fed from the {uid: coverUrl} map because the row has no Periodical
    // object. `maybeWhen` + `orElse` keeps the row rendering its own cover
    // while the map loads or if it failed.
    final seriesCovers = ref
        .watch(periodicalCoversProvider)
        .maybeWhen(data: (map) => map, orElse: () => const <String, String>{});
    final issue = book.issue;
    final hasOwnCover = book.coverUrl?.trim().isNotEmpty ?? false;
    final inheritedUid = issue != null && !hasOwnCover
        ? issue.periodicalUid
        : null;
    final coverUrl = inheritedUid != null
        ? seriesCovers[inheritedUid]
        : book.coverUrl;
    // Display fallback does not transfer ownership: only an issue's OWN cover
    // may be written back to the issue row.
    final coverOwner = inheritedUid != null
        ? CoverOwners.periodical(inheritedUid)
        : CoverOwners.item(book.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            ItemCover(title: book.title, coverUrl: coverUrl, owner: coverOwner),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: textTheme.titleMedium?.copyWith(color: titleColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null && book.author!.trim().isNotEmpty)
                    Text(
                      book.author!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Trailing status markers. Constrained + wrapping so several badges
            // (or large text scales) flow onto a second line instead of
            // overflowing the row off-screen.
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_kindLabel(book) case final label?)
                    // Kind badges use the surface-variant tones so they read
                    // as *classifiers*, not alerts — the status badges keep
                    // the stronger container colours.
                    _Badge(
                      label: label,
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurfaceVariant,
                    ),
                  if (book.removed)
                    _Badge(
                      label: 'Removed',
                      background: scheme.errorContainer,
                      foreground: scheme.onErrorContainer,
                    ),
                  if (unavailable && !book.removed)
                    _Badge(
                      label: 'Not available',
                      background: scheme.secondaryContainer,
                      foreground: scheme.onSecondaryContainer,
                    ),
                  if (book.needsMetadata)
                    _Badge(
                      label: 'Needs info',
                      background: scheme.tertiaryContainer,
                      foreground: scheme.onTertiaryContainer,
                    ),
                  if (book.copyCount > 1)
                    Text(
                      '×${book.copyCount}',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
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

  /// The kind badge text for a non-book row (ADR 0013 U1): "Issue" for a
  /// single magazine issue, "Bound volume" for a bound range (D4), "Other"
  /// for an other-kind item. A book — the default kind — shows nothing.
  static String? _kindLabel(CatalogueItem book) {
    return switch (book.kind) {
      ItemKind.book => null,
      ItemKind.magazineIssue =>
        book.issue?.isBound ?? false ? 'Bound volume' : 'Issue',
      ItemKind.other => 'Other',
    };
  }
}

/// Small pill badge used for row status markers.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    // Spacing between badges is handled by the parent Wrap; no inner margin.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
