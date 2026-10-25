/// Read-only detail of one published item (network presentation; ADR 0015 V2,
/// viewer plan S4).
///
/// Every decoded public field is shown, plus a larger cover slot. There is no
/// action: no edit, lend, delete, import or membership control — the row lives
/// on somebody else's published site, and viewing it must never look like
/// owning it.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_badges.dart';
import 'package:pitaka/features/network/presentation/widgets/published_item_cover.dart';

/// The detail page for one [item].
class PublishedCatalogueItemPage extends StatelessWidget {
  /// Creates the page. [series] is the public series entry when the item is a
  /// grouped issue; [siteUrl] is the saved site root (cover resolution base).
  const PublishedCatalogueItemPage({
    required this.item,
    required this.siteUrl,
    this.series,
    super.key,
  });

  /// The item to display.
  final PublishedCatalogueItem item;

  /// The saved site root.
  final String siteUrl;

  /// The owning public series, when known.
  final PublishedPeriodical? series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = item.issue;
    return Scaffold(
      appBar: AppBar(title: const Text('Published item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: PublishedItemCover(
              item: item,
              siteUrl: siteUrl,
              width: 120,
              height: 180,
            ),
          ),
          const SizedBox(height: 16),
          Text(item.title, style: theme.textTheme.headlineSmall),
          if (item.titleTransliteration != null) ...[
            const SizedBox(height: 4),
            Text(item.titleTransliteration!, style: theme.textTheme.titleSmall),
          ],
          const SizedBox(height: 8),
          PublishedItemBadges(item: item),
          const Divider(height: 28),
          if (item.author != null)
            _DetailField(label: 'Author', value: item.author!),
          if (item.isbn != null) _DetailField(label: 'ISBN', value: item.isbn!),
          if (item.publisher != null)
            _DetailField(label: 'Publisher', value: item.publisher!),
          if (item.publishedYear != null)
            _DetailField(label: 'Published', value: '${item.publishedYear}'),
          if (item.genre != null)
            _DetailField(label: 'Genre', value: item.genre!),
          if (item.language != null)
            _DetailField(label: 'Language', value: item.language!),
          if (item.ageGroup != null)
            _DetailField(
              label: 'Age group',
              value: publishedAgeGroupLabel(item.ageGroup!),
            ),
          if (item.availability != null)
            _DetailField(
              label: 'Availability',
              value: item.availability == PublishedAvailability.available
                  ? 'Available at publish time'
                  : 'All copies out at publish time',
            ),
          if (issue != null) ...[
            const Divider(height: 28),
            Text('Issue', style: theme.textTheme.titleMedium),
            if (series != null)
              _DetailField(label: 'Series', value: series!.title),
            if (issue.volume != null)
              _DetailField(label: 'Volume', value: '${issue.volume}'),
            if (issue.issueNumber != null)
              _DetailField(
                label: 'Issue number',
                value: '${issue.issueNumber}',
              ),
            if (issue.issueDate != null)
              _DetailField(
                label: issue.isBound ? 'First issue' : 'Issue date',
                value: _formatDay(issue.issueDate),
              ),
            if (issue.boundUntil != null)
              _DetailField(
                label: 'Last issue',
                value: _formatDay(issue.boundUntil),
              ),
            if (issue.label != null)
              _DetailField(label: 'Label', value: issue.label!),
          ],
          const SizedBox(height: 20),
          Text(
            'This is a read-only view of a published catalogue. Availability '
            'is the snapshot from publish time, not a live loan check.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// A normalized calendar day as a plain date, or an em dash when the stored
  /// value is not representable (defence in depth: the reader rejects those).
  static String _formatDay(int? millis) {
    final day = CalendarDate.fromEpochMillisOrNull(millis);
    return day == null ? '—' : day.toString();
  }
}

/// One "Label: value" line. Uses `SelectableText` for values so a user can
/// copy an ISBN without any edit affordance.
class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
