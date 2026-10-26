/// The viewer's lazy list (network presentation; viewer plan S4, V16).
///
/// One `SliverList.builder` over a FLATTENED row list: series headers and their
/// issues are separate rows, so a group with a hundred issues still builds only
/// the visible ones. Nothing here fetches, filters or sorts — the engine
/// already did, and this widget only paints.
///
/// Tapping a row opens the read-only detail page. There is no edit, lend,
/// import or delete action anywhere: the payload belongs to somebody else.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_item_page.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_badges.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_cover.dart';

/// One lazily-built display row.
sealed class PublishedDisplayRow {
  const PublishedDisplayRow();
}

/// A series header row.
final class PublishedSeriesHeaderRow extends PublishedDisplayRow {
  /// Wraps [series].
  const PublishedSeriesHeaderRow(this.series);

  /// The series to show.
  final PublishedPeriodical series;
}

/// An item row (plain item or one visible issue of a group).
final class PublishedItemDisplayRow extends PublishedDisplayRow {
  /// Wraps [item]; [series] is set when the row sits inside a group.
  const PublishedItemDisplayRow(this.item, {this.series});

  /// The item to show.
  final PublishedCatalogueItem item;

  /// The owning series when the item is displayed under a group header.
  final PublishedPeriodical? series;
}

/// The list for one computed view.
class PublishedCatalogueList extends StatelessWidget {
  /// Creates the list for [view]; [siteUrl] is the saved site root (covers).
  ///
  /// [coverRequestsPaused] is set while an accepted reload is in flight: the
  /// rows still paint the OLD payload, so they must not start cover downloads
  /// for it (review finding 2).
  const PublishedCatalogueList({
    required this.view,
    required this.siteUrl,
    this.coverRequestsPaused = false,
    super.key,
  });

  /// The computed view (entries already ordered/grouped).
  final PublishedCatalogueView view;

  /// The saved site root, used by the cover slot.
  final String siteUrl;

  /// When true, visible rows paint but never request a cover.
  final bool coverRequestsPaused;

  /// Flattens a grouped view into one row per widget, keeping display order.
  ///
  /// Public and static so a test can assert the lazy structure (a group is one
  /// header + N issue rows, never one widget per group).
  static List<PublishedDisplayRow> flatten(PublishedCatalogueView view) => [
    for (final entry in view.entries)
      if (entry case PublishedSeriesGroup(:final series, :final issues)) ...[
        PublishedSeriesHeaderRow(series),
        for (final issue in issues)
          PublishedItemDisplayRow(issue, series: series),
      ] else if (entry case PublishedItemEntry(:final item))
        PublishedItemDisplayRow(item),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = flatten(view);
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        PublishedSeriesHeaderRow(:final series) => _SeriesHeader(
          series: series,
        ),
        PublishedItemDisplayRow(:final item, :final series) => _ItemRow(
          item: item,
          series: series,
          siteUrl: siteUrl,
          coverRequestsPaused: coverRequestsPaused,
        ),
      },
    );
  }
}

/// The header for a series group (public metadata only).
class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({required this.series});

  final PublishedPeriodical series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (series.publisher != null) series.publisher!,
      if (series.issn != null) 'ISSN ${series.issn}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            series.title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (series.titleTransliteration != null)
            Text(
              series.titleTransliteration!,
              style: theme.textTheme.bodySmall,
            ),
          if (meta.isNotEmpty) Text(meta, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// One item row.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.series,
    required this.siteUrl,
    required this.coverRequestsPaused,
  });

  final PublishedCatalogueItem item;
  final PublishedPeriodical? series;
  final String siteUrl;
  final bool coverRequestsPaused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (item.author != null && item.author!.isNotEmpty) item.author!,
      if (item.publishedYear != null) '${item.publishedYear}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => PublishedCatalogueItemPage(
                item: item,
                siteUrl: siteUrl,
                series: series,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PublishedItemCover(
                  item: item,
                  siteUrl: siteUrl,
                  coverRequestsPaused: coverRequestsPaused,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleSmall,
                        // Long Indic titles wrap instead of being clipped.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.titleTransliteration != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.titleTransliteration!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      PublishedItemBadges(item: item),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
