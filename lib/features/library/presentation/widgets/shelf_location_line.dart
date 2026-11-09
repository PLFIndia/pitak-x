/// The shelf-location line shown on library list rows and grid cards — the
/// "where is it, and can I get it?" line.
///
/// Purpose: let the user see *where* an item is without opening it. A small
/// icon plus bold text, because a bare "A3" under an author line is
/// ambiguous and a "Shelf:" prefix on every card is noise. Screen readers
/// get the full meaning ("Shelf location: A3").
///
/// It also carries availability in the library (there is no separate
/// "Not available" pill there any more; the published pages keep theirs).
/// When every copy is out on loan the line turns the "Not available" red
/// ([AvailabilityColors]) AND the icon changes from a shelf to an "out" tray.
/// Why both (beginner note): colour alone can't carry meaning — people with
/// colour blindness may not see red — so the icon gives a second, shape-based
/// signal, and screen readers hear ", not available". An item with no shelf
/// set still needs the signal, so the line then reads "Not available".
///
/// A removed item is dimmed like its title, never red.
///
/// The line sizes to its content (it does not stretch to the full width), so
/// a caller can place pills right after it in a `Wrap`; a location longer
/// than the available width wraps onto a second line
/// (`ShelfLocationLine.maxLines`).
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

  /// Every copy is out on loan: the "Not available" red and the out icon.
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

/// The shelf-location line, the "Not available" fallback, or nothing.
class ShelfLocationLine extends StatelessWidget {
  /// Creates the line for [location] in [tone]; see [isVisibleFor] for when
  /// it renders anything at all.
  const ShelfLocationLine({
    required this.location,
    required this.tone,
    required this.style,
    super.key,
  });

  /// The item's free-form shelf location.
  final String? location;

  /// Which colour and icon the line takes (see [ShelfLocationTone]).
  final ShelfLocationTone tone;

  /// Base text style (row: `bodyMedium`, grid: `bodySmall`); weight and
  /// colour are applied here so both callers look the same.
  final TextStyle? style;

  /// The most lines the location text may take before "…". The grid uses
  /// this to reserve height, so it is the single source of truth.
  static const int maxLines = 2;

  /// Fallback text when no shelf is set but every copy is out.
  static const String notAvailableLabel = 'Not available';

  /// Icon size relative to the text so it reads as part of the line.
  static const double _iconSize = 14;

  /// Whether the line shows anything: a shelf is set, or (with no shelf)
  /// every copy is out. Callers use it to skip an empty bottom line.
  static bool isVisibleFor({
    required String? location,
    required ShelfLocationTone tone,
  }) =>
      (location?.trim().isNotEmpty ?? false) ||
      tone == ShelfLocationTone.unavailable;

  @override
  Widget build(BuildContext context) {
    if (!isVisibleFor(location: location, tone: tone)) {
      return const SizedBox.shrink();
    }
    final shelf = location?.trim() ?? '';
    final out = tone == ShelfLocationTone.unavailable;
    final theme = Theme.of(context);
    final color = switch (tone) {
      ShelfLocationTone.normal => theme.colorScheme.onSurface,
      ShelfLocationTone.unavailable => AvailabilityColors.unavailableForeground(
        theme.brightness,
      ),
      ShelfLocationTone.removed => theme.colorScheme.onSurfaceVariant,
    };
    final text = shelf.isEmpty ? notAvailableLabel : shelf;
    final semantics = shelf.isEmpty
        ? notAvailableLabel
        : 'Shelf location: $shelf${out ? ', not available' : ''}';
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Row(
        // Content-sized, so pills can sit right after a short shelf name.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Nudges the icon onto the first text line's centre.
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              out ? Icons.outbox : Icons.shelves,
              size: _iconSize,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
