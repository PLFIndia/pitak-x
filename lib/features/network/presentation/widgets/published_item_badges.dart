/// Small display badges for a published item (network presentation; ADR 0015
/// V9, viewer plan S4).
///
/// The rules the badges encode, all of which come from the READER and are never
/// re-derived here:
///  - a book, and any kind this build does not understand, carries NO kind
///    badge (an unknown kind must not be presented as a book);
///  - a magazine issue is "Issue", a bound volume (a date range) is
///    "Bound volume";
///  - "Other" is labelled as such and never shows availability;
///  - availability is the coarse publish-time snapshot — the words never
///    promise a live loan.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// The plain-words label for a reader age band.
String publishedAgeGroupLabel(AgeGroup group) => switch (group) {
  AgeGroup.above3 => 'Above 3',
  AgeGroup.above6 => 'Above 6',
  AgeGroup.above10 => 'Above 10',
  AgeGroup.above15 => 'Above 15',
  AgeGroup.advanced => 'Advanced',
};

/// The one-line kind/age/availability badges for [item].
class PublishedItemBadges extends StatelessWidget {
  /// Creates the badge row for [item].
  const PublishedItemBadges({required this.item, super.key});

  /// The item whose badges are shown.
  final PublishedCatalogueItem item;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    final kindLabel = switch (item.kind) {
      PublishedItemKind.book => null,
      PublishedItemKind.magazineIssue =>
        item.issue?.isBound ?? false ? 'Bound volume' : 'Issue',
      PublishedItemKind.other => 'Other',
      PublishedItemKind.unknown => null,
    };
    if (kindLabel != null) badges.add(_Badge(label: kindLabel));
    final age = item.ageGroup;
    if (age != null) {
      badges.add(_Badge(label: publishedAgeGroupLabel(age)));
    }
    final availability = item.availability;
    if (availability != null) {
      badges.add(
        _Badge(
          label: availability == PublishedAvailability.available
              ? 'Available'
              : 'All out',
          emphasised: true,
        ),
      );
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }
}

/// One compact badge. Rendered as text with a tinted container so the badges
/// wrap instead of overflowing, and so screen readers read the label directly
/// (no icon-only meaning).
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.emphasised = false});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: emphasised
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: emphasised
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
