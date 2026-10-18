/// The network map's initial viewport (presentation, libNetwork.md §5.9).
///
/// A pure, static helper — extracted from the page (review M12) so the
/// bounds maths is unit-testable without rendering a map and the widget's
/// `build` carries no geometry logic. It returns flutter_map's `MapOptions`,
/// which is why it lives in presentation (not domain): it is pure Dart, but
/// over UI types.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Computes the map's opening camera.
abstract final class MapViewport {
  /// The initial viewport (§5.9): the bounds of every [points] pin when
  /// there are at least two; centred on the single pin when there is one; a
  /// world view when nothing has a coordinate yet.
  static MapOptions forPoints(List<LatLng> points) {
    if (points.isEmpty) {
      // World view.
      return const MapOptions(initialCenter: LatLng(20, 0), initialZoom: 2);
    }
    if (points.length == 1) {
      return MapOptions(initialCenter: points.single, initialZoom: 12);
    }
    var south = points.first.latitude;
    var north = south;
    var west = points.first.longitude;
    var east = west;
    for (final p in points.skip(1)) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return MapOptions(
      initialCenter: points.first,
      initialCameraFit: CameraFit.bounds(
        bounds: LatLngBounds(LatLng(south, west), LatLng(north, east)),
        padding: const EdgeInsets.all(48),
        // Pins are city-scale; never zoom closer than a street map on open.
        maxZoom: 15,
      ),
    );
  }
}
