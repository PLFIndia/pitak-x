/// A single library *grid* card (presentation layer, AGENTS.md §3.1).
///
/// The wide-screen counterpart to `CatalogueItemRow`: a cover-forward card used
/// by the library grid on tablets/desktops. Same data and tap contract as the
/// row, but status markers (kind / Removed / Needs info / "Copies: 2 · 1 out")
/// are shown as small overlay pills on the cover so the text below stays
/// uncluttered. Under the cover: title (up to 3 lines), author (up to 2) and
/// the shelf line ([ShelfLocationLine], up to 2), which also carries
/// "not available" (red + out icon) — there is no availability pill in the
/// library any more. Pure presentation — no business logic.
///
/// Sizing (beginner note): grid cells all have one height, so the card cannot
/// grow to fit its text. Instead the grid (`CatalogueGridDelegate`) asks this
/// card how tall it must be — a book-shaped cover for the cell's width plus
/// the text block at its line caps, measured at the user's font size
/// (`reservedTextHeight`, `cellHeight`). Short titles leave a little blank
/// space; long ones never overflow and never squash the cover.
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

/// One tappable book card for the wide-screen grid.
class CatalogueItemGridCard extends ConsumerWidget {
  /// Creates a card for [book]; [onTap] opens its detail.
  const CatalogueItemGridCard({
    required this.book,
    required this.onTap,
    this.unavailable = false,
    this.copiesOut = 0,
    super.key,
  });

  /// The book to render.
  final CatalogueItem book;

  /// Called when the card is tapped.
  final VoidCallback onTap;

  /// True when every copy is out on loan (vault unlocked): the shelf line
  /// turns red with the out icon.
  final bool unavailable;

  /// Active loans for this item while the vault is unlocked (0 when none or
  /// locked); shown as "· N out" in the copies pill.
  final int copiesOut;

  /// Width : height of the cover — `ItemCover`'s own default (40 × 56), so a
  /// cover has the same book shape in the list and in the grid.
  static const double coverAspectRatio = 40 / 56;

  /// Padding inside the card, on every side.
  static const double _padding = 8;

  /// Space between the cover and the title.
  static const double _coverGap = 8;

  /// Space between the author and the shelf line.
  static const double _shelfGap = 4;

  /// Measuring text: Latin plus one letter from each Indian script the app
  /// meets, so on a real device the measured line is as tall as the tallest
  /// font that could be used (some scripts render taller than Latin).
  static const String _measureSample = 'Hgअঅஅఅಅഅਅઅଅ𑀅';

  /// Height of the text block under the cover when every text is at its
  /// line cap (title, author, shelf), at the user's current font size.
  ///
  /// The grid reserves this much for every card, which is what guarantees no
  /// overflow at large font sizes.
  static double reservedTextHeight(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double linesOf(TextStyle? style, int lines) {
      final painter = TextPainter(
        text: TextSpan(
          text: List.filled(lines, _measureSample).join('\n'),
          style: style,
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: lines,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return _coverGap +
        linesOf(textTheme.titleSmall, CatalogueCardText.titleMaxLines) +
        linesOf(textTheme.bodySmall, CatalogueCardText.authorMaxLines) +
        _shelfGap +
        linesOf(
          textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ShelfLocationLine.maxLines,
        );
  }

  /// The whole card's height for a grid cell [cellWidth] wide: padding, a
  /// book-shaped cover as wide as the card's content, and the reserved text.
  static double cellHeight({
    required double cellWidth,
    required double reservedTextHeight,
  }) {
    final coverWidth = (cellWidth - 2 * _padding).clamp(0.0, double.infinity);
    return 2 * _padding + coverWidth / coverAspectRatio + reservedTextHeight;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // Same rule as CatalogueItemRow: removed wins over "not available".
    final shelfTone = ShelfLocationTone.of(
      removed: book.removed,
      unavailable: unavailable,
    );
    // Removed books are dimmed (visible-but-inert), mirroring Kotlin D39.
    final titleColor = book.removed
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    // W4 cover fallback, same rule as CatalogueItemRow: an issue without its
    // own cover shows its series' cover from the shared map.
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
    final coverOwner = inheritedUid != null
        ? CoverOwners.periodical(inheritedUid)
        : CoverOwners.item(book.id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(_padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book-shaped cover. Flexible = fail-soft: the cell is sized for
            // this cover plus the reserved text, but if some script renders
            // taller than measured, the cover gives up a few pixels instead
            // of the card overflowing.
            Flexible(
              child: AspectRatio(
                aspectRatio: coverAspectRatio,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.expand(
                          // ItemCover scales to fill the available cell width.
                          child: ItemCover(
                            title: book.title,
                            coverUrl: coverUrl,
                            owner: coverOwner,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                    ),
                    // Status pills overlaid on the cover's top edge. Wrap so
                    // any number of badges flow to a new line instead of
                    // overflowing.
                    Positioned(
                      top: 4,
                      left: 4,
                      right: 4,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (_kindLabel(book) case final kindLabel?)
                            // Same classifier tone as the row's kind badge.
                            _Pill(
                              label: kindLabel,
                              background: scheme.surfaceContainerHighest,
                              foreground: scheme.onSurfaceVariant,
                            ),
                          if (book.removed)
                            _Pill(
                              label: 'Removed',
                              background: scheme.errorContainer,
                              foreground: scheme.onErrorContainer,
                            ),
                          if (book.needsMetadata)
                            _Pill(
                              label: 'Needs info',
                              background: scheme.tertiaryContainer,
                              foreground: scheme.onTertiaryContainer,
                            ),
                          if (CopiesLabel.isVisibleFor(book.copyCount))
                            _Pill(
                              background: scheme.surfaceContainerHighest,
                              foreground: scheme.onSurface,
                              child: CopiesLabel(
                                copyCount: book.copyCount,
                                copiesOut: copiesOut,
                                style: textTheme.labelSmall,
                                color: scheme.onSurface,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: _coverGap),
            Text(
              book.title,
              style: textTheme.titleSmall?.copyWith(color: titleColor),
              maxLines: CatalogueCardText.titleMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
            if (book.author != null && book.author!.trim().isNotEmpty)
              Text(
                book.author!,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: CatalogueCardText.authorMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            if (ShelfLocationLine.isVisibleFor(
              location: book.location,
              tone: shelfTone,
            ))
              Padding(
                padding: const EdgeInsets.only(top: _shelfGap),
                child: ShelfLocationLine(
                  location: book.location,
                  tone: shelfTone,
                  style: textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The kind badge text for a non-book card (same rule as the row's,
  /// ADR 0013 U1); a book shows nothing.
  static String? _kindLabel(CatalogueItem book) {
    return switch (book.kind) {
      ItemKind.book => null,
      ItemKind.magazineIssue =>
        book.issue?.isBound ?? false ? 'Bound volume' : 'Issue',
      ItemKind.other => 'Other',
    };
  }
}

/// Small pill badge overlaid on the cover for grid-card status markers:
/// either a plain [label] or a ready-made [child] (the copies label).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.background,
    required this.foreground,
    this.label,
    this.child,
  }) : assert(
         (label == null) != (child == null),
         'give a _Pill exactly one of label or child',
       );

  final String? label;
  final Widget? child;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child:
          child ??
          Text(
            label!,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: foreground),
          ),
    );
  }
}
