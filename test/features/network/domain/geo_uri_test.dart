import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/geo_uri.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Unit tests for the pure `geo:` URI builder (review M8): fixed-point
/// coordinates (never scientific notation), parentheses in the label
/// percent-encoded so the Android `q=lat,lng(label)` form stays parseable,
/// and a blank label producing no dangling `()`.
void main() {
  GeoPoint point(double lat, double lng) => GeoPoint.tryCreate(lat, lng)!;

  group('formatCoordinate', () {
    test('always six fixed decimals', () {
      expect(GeoUri.formatCoordinate(12.9716), '12.971600');
      expect(GeoUri.formatCoordinate(-77.5946), '-77.594600');
      expect(GeoUri.formatCoordinate(0), '0.000000');
    });

    test('tiny values never become scientific notation', () {
      // Dart's shortest round-trip toString() switches to exponent form
      // below 1e-6 — the interpolation the page used to do would emit this.
      expect(0.0000001.toString(), '1e-7');
      expect(GeoUri.formatCoordinate(0.0000001), '0.000000');
      expect(GeoUri.formatCoordinate(0.00001), '0.000010');
      expect(GeoUri.formatCoordinate(-0.0000001), '-0.000000');
    });

    test('values beyond six decimals are rounded, not truncated', () {
      // Clear of the half-way point so binary float representation does
      // not decide the result.
      expect(GeoUri.formatCoordinate(12.97160051), '12.971601');
      expect(GeoUri.formatCoordinate(12.97160049), '12.971600');
    });
  });

  group('encodeLabel', () {
    test(
      'percent-encodes what encodeComponent does (space, &, #, non-ASCII)',
      () {
        expect(GeoUri.encodeLabel('City Library'), 'City%20Library');
        expect(GeoUri.encodeLabel('A & B #1'), 'A%20%26%20B%20%231');
        expect(GeoUri.encodeLabel('ಗ್ರಂಥಾಲಯ'), Uri.encodeComponent('ಗ್ರಂಥಾಲಯ'));
      },
    );

    test('ALSO encodes parentheses, which encodeComponent leaves alone', () {
      // The reason this helper exists: these are the label delimiters.
      expect(Uri.encodeComponent('Books (Annex)'), 'Books%20(Annex)');
      expect(GeoUri.encodeLabel('Books (Annex)'), 'Books%20%28Annex%29');
    });
  });

  group('directions', () {
    test('builds geo:lat,lng?q=lat,lng(label)', () {
      final uri = GeoUri.directions(
        point(12.9716, 77.5946),
        label: 'City Library',
      );
      expect(
        uri.toString(),
        'geo:12.971600,77.594600?q=12.971600,77.594600(City%20Library)',
      );
      expect(uri.scheme, 'geo');
      expect(uri.path, '12.971600,77.594600');
    });

    test('a label with parentheses survives intact', () {
      final uri = GeoUri.directions(
        point(12.9716, 77.5946),
        label: 'Books (Annex)',
      );
      expect(
        uri.toString(),
        'geo:12.971600,77.594600?q=12.971600,77.594600(Books%20%28Annex%29)',
      );
      // Round-trip: the query decodes back to the original label text.
      final q = uri.queryParameters['q']!;
      expect(q, '12.971600,77.594600(Books (Annex))');
    });

    test('a site-URL label (the no-name fallback) encodes its punctuation', () {
      final uri = GeoUri.directions(
        point(1, 2),
        label: 'https://x.github.io/lib/',
      );
      expect(
        uri.toString(),
        'geo:1.000000,2.000000?q=1.000000,2.000000'
        '(https%3A%2F%2Fx.github.io%2Flib%2F)',
      );
    });

    test('blank label → no label part at all (no dangling "()")', () {
      expect(
        GeoUri.directions(point(1, 2), label: '').toString(),
        'geo:1.000000,2.000000?q=1.000000,2.000000',
      );
      expect(
        GeoUri.directions(point(1, 2), label: '   ').toString(),
        'geo:1.000000,2.000000?q=1.000000,2.000000',
      );
    });

    test('negative coordinates keep their sign in both positions', () {
      expect(
        GeoUri.directions(point(-33.8688, -151.2093), label: 'S').toString(),
        'geo:-33.868800,-151.209300?q=-33.868800,-151.209300(S)',
      );
    });
  });
}
