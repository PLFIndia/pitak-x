/// A single library list row (presentation layer).
///
/// Layout (2026-11-09 text-fit redesign): the cover, then ONE text column
/// that uses all the remaining width — title (up to 3 lines), author (up to
/// 2 lines), and a bottom line that wraps: the shelf location
/// ([ShelfLocationLine]), the status pills (kind, Removed, Needs info) and
/// "**Copies:** 2 · 1 out" ([CopiesLabel]).
///
/// Why no badge column on the right any more (beginner note): it sat in a
/// `Flexible` next to the text's `Expanded`, and Flutter splits free space
/// between flex children by their flex factor — so the text got only half
/// the space even when there were no badges, and long titles were cut short.
///
/// Availability (vault unlocked only) has no pill here: the shelf line turns
/// red with an "out" icon when every copy is on loan, and the copies label
/// counts partial loans. The published pages keep their own tags.
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
import 'package:pitaka/features/library/presentation/widgets/catalogue_card_text.dart';
import 'package:pitaka/features/library/presentation/widgets/copies_label.dart';
import 'package:pitaka/features/library/presentation/widgets/shelf_location_line.dart';

/// One tappable book row.
class CatalogueItemRow extends ConsumerWidget {
  /// Creates a row for [book]; [onTap] opens its detail.
  const CatalogueItemRow({
    required this.book,
    required this.onTap,
    this.unavailable = false,
    this.copiesOut = 0,
    super.key,
  });

  /// The book to render.
  final CatalogueItem book;

  /// Called when the row is tapped.
  final VoidCallback onTap;

  /// True when every copy is out on loan (vault unlocked): the shelf line
  /// turns red with the out icon.
  final bool unavailable;

  /// Active loans for this item while the vault is unlocked (0 when none or
  /// locked); shown as "· N out" next to the copy count.
  final int copiesOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // ONE rule for "paint it as not available"; a removed item is dimmed
    // instead, never red (ShelfLocationTone.of applies the precedence).
    final shelfTone = ShelfLocationTone.of(
      removed: book.removed,
      unavailable: unavailable,
    );
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

    // The bottom line, in reading order: where it is, what it is, how many.
    final bottomLine = <Widget>[
      if (ShelfLocationLine.isVisibleFor(
        location: book.location,
        tone: shelfTone,
      ))
        ShelfLocationLine(
          location: book.location,
          tone: shelfTone,
          style: textTheme.bodyMedium,
        ),
      if (_kindLabel(book) case final label?)
        // Kind badges use the surface-variant tones so they read as
        // *classifiers*, not alerts — the status badges keep the stronger
        // container colours.
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
      if (book.needsMetadata)
        _Badge(
          label: 'Needs info',
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        ),
      if (CopiesLabel.isVisibleFor(book.copyCount))
        CopiesLabel(
          copyCount: book.copyCount,
          copiesOut: copiesOut,
          style: textTheme.labelLarge,
          color: scheme.onSurfaceVariant,
        ),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          // Top-aligned: with up to six text lines the cover belongs beside
          // the title, not floating in the middle.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ItemCover(title: book.title, coverUrl: coverUrl, owner: coverOwner),
            const SizedBox(width: 12),
            // The ONLY flexible child, so the text gets all the remaining
            // width (see the library comment above).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: textTheme.titleMedium?.copyWith(color: titleColor),
                    maxLines: CatalogueCardText.titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null && book.author!.trim().isNotEmpty)
                    Text(
                      book.author!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: CatalogueCardText.authorMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (bottomLine.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      // Wraps: a long shelf takes its own line(s) and the
                      // pills flow onto the next line only when needed.
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: bottomLine,
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
