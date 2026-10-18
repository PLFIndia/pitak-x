/// Builds the `geo:` URI the map's "Directions" action hands to the OS map
/// app (network domain, pure Dart; libNetwork.md §5.9).
///
/// Why a separate helper instead of string interpolation in the page:
/// building this URI has two traps that only show up on real data, and both
/// are easy to unit-test here and impossible to see in a widget test.
///
///  1. `double.toString()` switches to scientific notation for tiny values
///     (`0.0000001.toString()` is `1e-7`), which no map app parses. The
///     coordinates are therefore always formatted with `formatCoordinate`
///     (fixed six decimals ≈ 11 cm — more than any published pin carries).
///  2. `Uri.encodeComponent` deliberately leaves `(` and `)` unencoded
///     (RFC 2396 "mark" characters), but in the Android `q=lat,lng(label)`
///     form the parentheses are the delimiters of the label. A library named
///     `Books (Annex)` would end the label early and leave `Annex)` dangling.
///     `encodeLabel` therefore percent-encodes both parentheses explicitly.
///
/// The output is `geo:LAT,LNG?q=LAT,LNG(LABEL)`, or without the `(LABEL)`
/// suffix when the label is blank — never a dangling empty `()`.
library;

import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Pure `geo:` URI builder. All members are static; the class is a namespace.
abstract final class GeoUri {
  /// Decimal places for a coordinate in the URI. Six places ≈ 11 cm at the
  /// equator, which is finer than the `exact` precision ever published, so
  /// no information is lost — and `toStringAsFixed` never emits `1e-5`.
  static const int coordinateDecimals = 6;

  /// The `geo:` URI for [point], labelled with [label] (a library name or,
  /// when the caller has no name, its site URL). A blank label after
  /// trimming drops the label part entirely.
  static Uri directions(GeoPoint point, {required String label}) {
    final lat = formatCoordinate(point.lat);
    final lng = formatCoordinate(point.lng);
    final trimmed = label.trim();
    final suffix = trimmed.isEmpty ? '' : '(${encodeLabel(trimmed)})';
    // Built as a string and parsed once: the Uri constructor would try to
    // "normalise" a hand-built query and the exact byte form matters here.
    return Uri.parse('geo:$lat,$lng?q=$lat,$lng$suffix');
  }

  /// Fixed-point coordinate text (see [coordinateDecimals]). Negative zero
  /// prints as `-0.000000`, which every geo: consumer accepts.
  static String formatCoordinate(double value) =>
      value.toStringAsFixed(coordinateDecimals);

  /// Percent-encodes [label] for the `q=lat,lng(label)` position:
  /// `Uri.encodeComponent` first (spaces, `&`, `#`, non-ASCII …), then the
  /// two characters it leaves alone that would break the label delimiters.
  static String encodeLabel(String label) =>
      Uri.encodeComponent(label).replaceAll('(', '%28').replaceAll(')', '%29');
}
