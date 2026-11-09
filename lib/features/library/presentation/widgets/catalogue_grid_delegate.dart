/// Grid layout for the library's cover grid (tablets, foldables, desktop).
///
/// Columns follow Flutter's own "max cross-axis extent" rule (as many
/// columns as fit, each at most `maxCrossAxisExtent` wide) — the same maths
/// as `SliverGridDelegateWithMaxCrossAxisExtent` in the Flutter SDK
/// (`rendering/sliver_grid.dart`). What differs is the cell HEIGHT: instead
/// of a fixed number it is computed from the cell's width — a book-shaped
/// cover — plus the text block reserved at the user's font size
/// (`CatalogueItemGridCard.cellHeight`).
///
/// Why a custom delegate (beginner note): `SliverGridDelegate` is Flutter's
/// documented extension point for grid layouts. The built-in delegates only
/// offer a fixed height or a fixed width:height ratio, and our card is
/// neither: its cover scales with the width while its text block depends on
/// the font size, not the width.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';

/// Max-cross-axis-extent columns with width-and-font-aware cell heights.
final class CatalogueGridDelegate extends SliverGridDelegate {
  /// Creates the delegate with the text block height measured by
  /// `CatalogueItemGridCard.reservedTextHeight` for the current context.
  const CatalogueGridDelegate({required this.reservedTextHeight});

  /// Target (maximum) column width; Flutter picks the column count that fits.
  static const double maxCrossAxisExtent = 200;

  /// Gap between cells, both directions.
  static const double spacing = 12;

  /// Height reserved under each cover for title, author and shelf.
  final double reservedTextHeight;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    // Column maths copied from SliverGridDelegateWithMaxCrossAxisExtent.
    final columns = math.max(
      1,
      (constraints.crossAxisExtent / (maxCrossAxisExtent + spacing)).ceil(),
    );
    final usableWidth = math.max(
      0,
      constraints.crossAxisExtent - spacing * (columns - 1),
    );
    final cellWidth = usableWidth / columns;
    final cellHeight = CatalogueItemGridCard.cellHeight(
      cellWidth: cellWidth,
      reservedTextHeight: reservedTextHeight,
    );
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: cellHeight + spacing,
      crossAxisStride: cellWidth + spacing,
      childMainAxisExtent: cellHeight,
      childCrossAxisExtent: cellWidth,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CatalogueGridDelegate oldDelegate) =>
      oldDelegate.reservedTextHeight != reservedTextHeight;
}
