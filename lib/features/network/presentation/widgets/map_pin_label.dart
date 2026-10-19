/// Map pin labels (presentation): the small name pill shown above a pin.
///
/// Visibility rules (design discussion 2026-10-18):
///  - YOUR pin and HUB pins carry a permanent label;
///  - every other pin shows its label only while selected (tap the pin to
///    toggle it; tap the label to open the pin's bottom sheet).
///
/// There is no "hub" role in the data model (docs/ARCHITECTURE.md §6) — a hub is
/// DERIVED from the rows: a row is a hub when it lists YOU
/// (`membership != none`) or when another row was discovered through its
/// member list (`listedByHubUrl` points at it, §5.6 step 3). That is what
/// [hubSiteUrls]/[isHubRow] compute.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';

/// The siteUrls of every hub discoverable from [rows]: any URL another row
/// names as the hub that listed it. (The "lists me" direction is on the row
/// itself — see [isHubRow].)
Set<String> hubSiteUrls(List<NetworkLibrary> rows) => {
  for (final row in rows)
    if (row.listedByHubUrl != null) row.listedByHubUrl!,
};

/// Whether [row] acts as a hub: it lists me, or it listed someone else.
bool isHubRow(NetworkLibrary row, Set<String> hubUrls) =>
    row.membership != MembershipState.none || hubUrls.contains(row.siteUrl);

/// Builds the marker for one label pill, floating directly ABOVE the pin.
///
/// flutter_map's `Marker.alignment` is the marker's position RELATIVE TO the
/// point (verified in the installed source, marker.dart): topCenter puts the
/// whole box above the point, bottomCenter below. The pin's 48 dp box
/// occupies the 48 dp above the coordinate, so this label's 96 dp box is
/// anchored the same way and the pill aligns to its TOP — the label's own
/// 48 dp (pill + a11y padding) then ends exactly where the pin's box begins.
Marker pinLabelMarker({required LatLng point, required MapPinLabel label}) =>
    Marker(
      point: point,
      width: 150,
      height: 96,
      alignment: Alignment.topCenter,
      child: Align(alignment: Alignment.topCenter, child: label),
    );

/// The name pill shown above a map pin.
class MapPinLabel extends StatelessWidget {
  /// Creates the pill. [onTap] set ⇒ the pill is a button that opens the
  /// pin's bottom sheet; null ⇒ a plain caption (the own-library label).
  const MapPinLabel({required this.name, super.key, this.onTap});

  /// Display text; the page resolves the empty-name → siteUrl fallback.
  final String name;

  /// Opens the pin sheet when the pill is tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Container(
      // Names run to 80 chars (spec §6): one line, ellipsised, hard max.
      constraints: const BoxConstraints(maxWidth: 142),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        // Opaque, not translucent: the a11y contrast check reads composited
        // pixels and map tiles are arbitrary imagery (same reason as
        // OsmAttribution).
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall,
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Show details for $name',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          // The transparent colour makes the WHOLE box hit-test (a bare
          // SizedBox gap would not — ColoredBox hit-tests itself), padding
          // the small pill up to the 48×48 dp a11y tap-target minimum. The
          // padding reaches downward into the gap between pill and pin.
          color: Colors.transparent,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [pill]),
        ),
      ),
    );
  }
}
