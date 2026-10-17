import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Boundary tests for the [GeoPoint] value object (libNetwork.md S1):
/// range checks, NaN/∞ rejection, "lat, lng" parse variants, coarsen
/// rounding (including negatives) and haversine against two known pairs.
void main() {
  group('tryCreate', () {
    test('accepts in-range finite coordinates', () {
      final p = GeoPoint.tryCreate(12.9716, 77.5946);
      expect(p, isNotNull);
      expect(p!.lat, 12.9716);
      expect(p.lng, 77.5946);
    });

    test('accepts the range extremes', () {
      expect(GeoPoint.tryCreate(90, 180), isNotNull);
      expect(GeoPoint.tryCreate(-90, -180), isNotNull);
      expect(GeoPoint.tryCreate(0, 0), isNotNull);
    });

    test('rejects out-of-range lat/lng', () {
      expect(GeoPoint.tryCreate(90.0001, 0), isNull);
      expect(GeoPoint.tryCreate(-90.0001, 0), isNull);
      expect(GeoPoint.tryCreate(0, 180.0001), isNull);
      expect(GeoPoint.tryCreate(0, -180.0001), isNull);
      expect(GeoPoint.tryCreate(999, 0), isNull);
    });

    test('rejects NaN and infinity (a bare range check would not)', () {
      expect(GeoPoint.tryCreate(double.nan, 0), isNull);
      expect(GeoPoint.tryCreate(0, double.nan), isNull);
      expect(GeoPoint.tryCreate(double.infinity, 0), isNull);
      expect(GeoPoint.tryCreate(0, double.negativeInfinity), isNull);
    });
  });

  group('parse', () {
    test('accepts "12.5,77" and "12.5 , 77.0" (whitespace per part)', () {
      final a = GeoPoint.parse('12.5,77');
      expect(a, isNotNull);
      expect(a!.lat, 12.5);
      expect(a.lng, 77.0);

      final b = GeoPoint.parse('12.5 , 77.0');
      expect(b, isNotNull);
      expect(b!.lat, 12.5);
      expect(b.lng, 77.0);
    });

    test('rejects a non-comma separator: "12;77"', () {
      expect(GeoPoint.parse('12;77'), isNull);
    });

    test('rejects the wrong part count', () {
      expect(GeoPoint.parse('12.5'), isNull);
      expect(GeoPoint.parse('1, 2, 3'), isNull);
      expect(GeoPoint.parse(''), isNull);
      expect(GeoPoint.parse(','), isNull);
    });

    test('rejects non-numeric and hostile numeric spellings', () {
      expect(GeoPoint.parse('abc, 77'), isNull);
      expect(GeoPoint.parse('12.5, xyz'), isNull);
      // double.tryParse accepts these spellings — the range/finite check
      // must still refuse them.
      expect(GeoPoint.parse('Infinity, 0'), isNull);
      expect(GeoPoint.parse('NaN, 0'), isNull);
      expect(GeoPoint.parse('1e999, 0'), isNull); // parses to infinity
    });

    test('rejects out-of-range values', () {
      expect(GeoPoint.parse('999, 0'), isNull);
      expect(GeoPoint.parse('0, 999'), isNull);
    });
  });

  group('coarsen', () {
    test('rounds to 2 decimals (~1.1 km)', () {
      final p = GeoPoint.parse('12.9876, 77.5946')!.coarsen();
      expect(p.lat, 12.99);
      expect(p.lng, 77.59);
    });

    test('rounds negatives symmetrically (half away from zero)', () {
      final p = GeoPoint.parse('-12.345, -77.5678')!.coarsen();
      expect(p.lat, -12.35);
      expect(p.lng, -77.57);
    });

    test('keeps exact values and the extremes valid', () {
      expect(GeoPoint.parse('90, -180')!.coarsen().lat, 90);
      expect(GeoPoint.parse('90, -180')!.coarsen().lng, -180);
      expect(GeoPoint.parse('0, 0')!.coarsen().lat, 0);
    });
  });

  group('distanceKm (haversine, R = 6371.0088)', () {
    test('Bengaluru → Mysuru ≈ 128 km', () {
      final a = GeoPoint.parse('12.9716, 77.5946')!;
      final b = GeoPoint.parse('12.2958, 76.6394')!;
      expect(a.distanceKm(b), closeTo(128.017, 0.01));
    });

    test('London → Paris ≈ 343.6 km', () {
      final a = GeoPoint.parse('51.5074, -0.1278')!;
      final b = GeoPoint.parse('48.8566, 2.3522')!;
      expect(a.distanceKm(b), closeTo(343.557, 0.01));
    });

    test('is zero to itself and symmetric', () {
      final a = GeoPoint.parse('12.9716, 77.5946')!;
      final b = GeoPoint.parse('12.2958, 76.6394')!;
      expect(a.distanceKm(a), 0);
      expect(a.distanceKm(b), b.distanceKm(a));
    });
  });

  group('sameAs', () {
    test('compares values without overriding ==', () {
      final a = GeoPoint.parse('12.5, 77.5')!;
      final b = GeoPoint.parse('12.5, 77.5')!;
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(GeoPoint.parse('12.5, 77.6')!), isFalse);
    });
  });

  test('LocationPrecision has exactly the two published modes', () {
    // Wire contract (§3.1): the descriptor parser accepts only these tokens.
    expect(LocationPrecision.values, [
      LocationPrecision.approximate,
      LocationPrecision.exact,
    ]);
  });
}
