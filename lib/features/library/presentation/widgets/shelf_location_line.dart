/// The one-line shelf location shown on library list rows and grid cards.
///
/// Purpose: let the user see *where* an item is without opening it. A small
/// icon plus bold text, because a bare "A3" under an author line is
/// ambiguous and a "Shelf:" prefix on every card is noise. The icon carries
/// no meaning on its own: screen readers get the full "Shelf location: A3".
///
/// Colour follows [ShelfLocationTone]: the same red as the "Not available"
/// tag ([AvailabilityColors]) when every copy is out on loan, so the two
/// signals agree; dimmed like the title when the item is removed; otherwise
/// the ordinary `onSurface` text colour — not literal black, which would
/// vanish in the dark theme.
///
/// Shelf location is private library-operations data (`CatalogueItem.location`
/// is stripped at publish); this widget only ever renders inside the app.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/theme/availability_colors.dart';

/// How the shelf line is coloured. An enum rather than two bools so an
/// impossible mix ("removed AND not available") can't be expressed: a
/// removed item is dimmed, never red — the same rule as the row's badges.
enum ShelfLocationTone {
  /// Ordinary text colour.
  normal,

  /// Every copy is out on loan: the "Not available" red.
  unavailable,

  /// The item is removed (visible-but-inert): dimmed like its title.
  removed;

  /// The tone for an item; [removed] wins over [unavailable].
  static ShelfLocationTone of({
    required bool removed,
    required bool unavailable,
  }) {
    if (removed) return ShelfLocationTone.removed;
    if (unavailable) return ShelfLocationTone.unavailable;
    return ShelfLocationTone.normal;
  }
}

/// The shelf-location line, or nothing when [location] is blank.
class ShelfLocationLine extends StatelessWidget {
  /// Creates the line for [location]; renders nothing when it is null/blank.
  const ShelfLocationLine({
    required this.location,
    required this.tone,
    required this.style,
    super.key,
  });

  /// The item's free-form shelf location.
  final String? location;

  /// Which colour the line takes (see [ShelfLocationTone]).
  final ShelfLocationTone tone;

  /// Base text style (row: `bodyMedium`, grid: `bodySmall`); weight and
  /// colour are applied here so both callers look the same.
  final TextStyle? style;

  /// Icon size relative to the text so it reads as part of the line.
  static const double _iconSize = 14;

  @override
  Widget build(BuildContext context) {
    final text = location?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = switch (tone) {
      ShelfLocationTone.normal => theme.colorScheme.onSurface,
      ShelfLocationTone.unavailable => AvailabilityColors.unavailableForeground(
        theme.brightness,
      ),
      ShelfLocationTone.removed => theme.colorScheme.onSurfaceVariant,
    };
    return Semantics(
      label: 'Shelf location: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(Icons.shelves, size: _iconSize, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: style?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
