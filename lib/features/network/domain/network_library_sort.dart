/// Display ordering for the Libraries tab (network domain, pure Dart;
/// libNetwork.md §7 S4).
///
/// Moved out of the page (review M12): ordering is a domain policy — "which
/// library is most relevant" — not a widget concern, and as a pure function
/// it is unit-testable without pumping a screen.
///
/// The rule: when this library publishes a pin of its own (settings GPS ×
/// sharing — the D7 mapping, never a device location), rows with
/// coordinates sort nearest-first and pin-less rows follow by name; without
/// an own pin, everything sorts by name. The title falls back to the URL so
/// the order is always total and deterministic.
library;

import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// The Libraries-tab display order.
abstract final class NetworkLibrarySort {
  /// Returns a NEW list (the input is the window's immutable snapshot) with
  /// pinned rows nearest-first and everything else by title. Ties break on
  /// the title because `List.sort` is not stable: without a total order the
  /// list would shuffle between rebuilds when two pins are equally far away.
  static List<NetworkLibrary> byDistanceThenName(
    List<NetworkLibrary> rows,
    GeoPoint? own,
  ) {
    String titleOf(NetworkLibrary row) =>
        (row.name.isEmpty ? row.siteUrl : row.name).toLowerCase();
    int byTitle(NetworkLibrary a, NetworkLibrary b) =>
        titleOf(a).compareTo(titleOf(b));
    if (own == null) return [...rows]..sort(byTitle);
    final pinned = [...rows.where((row) => row.location != null)]
      ..sort((a, b) {
        final byDistance = own
            .distanceKm(a.location!)
            .compareTo(own.distanceKm(b.location!));
        if (byDistance != 0) return byDistance;
        return byTitle(a, b);
      });
    final unpinned = [...rows.where((row) => row.location == null)]
      ..sort(byTitle);
    return [...pinned, ...unpinned];
  }
}
