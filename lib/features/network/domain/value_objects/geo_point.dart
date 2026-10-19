/// A validated geographic coordinate pair (network domain, pure Dart).
///
/// Value Object (AGENTS.md §3.3): construction IS validation — there is no
/// public constructor, only the checking factories [GeoPoint.tryCreate] and
/// [GeoPoint.parse], so a `GeoPoint` in the codebase is always in range and
/// finite. This replaces the private `_parseLatLng` the publish contact
/// renderer used to carry (docs/ARCHITECTURE.md §5), so "lat, lng" is parsed by
/// exactly ONE rule everywhere: the published `index.html` pin, the network
/// `library.json` descriptor, and the map pins.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

import 'dart:math' as math;

/// How precisely this library shares its location (docs/ARCHITECTURE.md §6 location sharing).
///
/// One switch, one meaning: it governs BOTH the `library.json` descriptor and
/// the GPS pin on the published `index.html`. Default everywhere is "not
/// shared at all" (`AppSettings.publishLocationSharing` = off).
enum LocationPrecision {
  /// Coordinates rounded to 2 decimals (~1.1 km) — enough to show a pin on a
  /// city map, not enough to find the door.
  approximate,

  /// Full typed precision — the library chose to publish its exact position.
  exact,
}

/// A validated coordinate pair: [lat] ∈ [−90, 90], [lng] ∈ [−180, 180], both
/// finite. Immutable.
final class GeoPoint {
  // Private on purpose: the only way in is tryCreate/parse, which validate.
  const GeoPoint._(this.lat, this.lng);

  /// Mean Earth radius in kilometres (the IUGG "R1" mean radius). Fixed
  /// constant so every distance in the app is computed the same way.
  static const double earthRadiusKm = 6371.0088;

  /// Latitude in degrees, north positive.
  final double lat;

  /// Longitude in degrees, east positive.
  final double lng;

  /// Builds a point, or null when either value is NaN/infinite or out of
  /// range. NaN is rejected explicitly (`NaN < 90` is false, so a bare range
  /// check would let it through).
  static GeoPoint? tryCreate(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return null;
    if (lat < -90.0 || lat > 90.0) return null;
    if (lng < -180.0 || lng > 180.0) return null;
    return GeoPoint._(lat, lng);
  }

  /// Parses a user-typed "lat, lng" pair (e.g. `12.97, 77.59`), or null when
  /// [raw] is not exactly two comma-separated in-range numbers. Surrounding
  /// whitespace per part is allowed; anything else (`12;77`, `1, 2, 3`,
  /// `Infinity, 0`) is rejected.
  static GeoPoint? parse(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return tryCreate(lat, lng);
  }

  /// Rounds both coordinates to 2 decimals (~1.1 km at the equator) — the
  /// "approximate" precision of docs/ARCHITECTURE.md §6 location sharing. Rounding via
  /// `roundToDouble` (half away from zero) keeps negatives symmetric:
  /// 12.345 → 12.35 and −12.345 → −12.35 (see the unit tests).
  GeoPoint coarsen() => GeoPoint._(_round2(lat), _round2(lng));

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// Great-circle distance to [other] in kilometres (haversine formula —
  /// accurate enough for city-scale library distances and free of the
  /// ellipsoid maths a navigation app would need).
  double distanceKm(GeoPoint other) {
    final phi1 = lat * math.pi / 180;
    final phi2 = other.lat * math.pi / 180;
    final dPhi = (other.lat - lat) * math.pi / 180;
    final dLambda = (other.lng - lng) * math.pi / 180;
    final h =
        math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    // Clamp before asin: at (near-)antipodal points floating-point error can
    // push h a hair past 1.0 (1.0000000000000002), and asin of that is NaN
    // (review Lows) — a distance that came back "not a number" would poison
    // every sort and pin-sheet line using it.
    return 2 * earthRadiusKm * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  /// Value equality WITHOUT overriding `==`/`hashCode`: the repo's lint bar
  /// flags floating-point `==` on a class used as a map key candidate, and no
  /// caller needs hash identity. Compare with this method where it matters
  /// (e.g. "did the published pin move?").
  bool sameAs(GeoPoint other) => lat == other.lat && lng == other.lng;
}
