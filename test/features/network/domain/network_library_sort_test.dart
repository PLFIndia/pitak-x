import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/network_library_sort.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';

/// Unit tests for the Libraries-tab display order (review M12 — the sort
/// moved out of the widget into this pure domain function): distance order
/// with an own pin, name order without one, deterministic tie-breaking, and
/// the URL-as-title fallback.
void main() {
  NetworkLibrary row(
    int id,
    String name, {
    String? siteUrl,
    double? lat,
    double? lng,
  }) => NetworkLibrary(
    id: id,
    siteUrl: siteUrl ?? 'https://$id.github.io/x/',
    name: name,
    location: lat == null ? null : GeoPoint.tryCreate(lat, lng!),
    precision: lat == null ? null : LocationPrecision.exact,
  );

  List<String> names(List<NetworkLibrary> rows) =>
      rows.map((r) => r.name).toList();

  group('without an own pin', () {
    test('everything sorts by title, case-insensitively', () {
      final sorted = NetworkLibrarySort.byDistanceThenName([
        row(1, 'Zebra'),
        row(2, 'apple'),
        row(3, 'Mango'),
      ], null);
      expect(names(sorted), ['apple', 'Mango', 'Zebra']);
    });

    test('a blank name falls back to the site URL for ordering', () {
      final sorted = NetworkLibrarySort.byDistanceThenName([
        row(1, '', siteUrl: 'https://zzz.github.io/x/'),
        row(2, 'Beta'),
      ], null);
      // 'beta' < 'https://…' alphabetically.
      expect(sorted.map((r) => r.id), [2, 1]);
    });

    test('the input list is not mutated (window snapshots are immutable)', () {
      final input = [row(1, 'Zebra'), row(2, 'Apple')];
      NetworkLibrarySort.byDistanceThenName(input, null);
      expect(names(input), ['Zebra', 'Apple']);
    });
  });

  group('with an own pin', () {
    final own = GeoPoint.tryCreate(12.9, 77.6);

    test('pinned rows sort nearest-first; pin-less rows follow by title', () {
      final sorted = NetworkLibrarySort.byDistanceThenName([
        row(1, 'Far Away', lat: 13.9, lng: 78.9),
        row(2, 'No Pin'),
        row(3, 'Very Near', lat: 12.95, lng: 77.65),
      ], own);
      expect(names(sorted), ['Very Near', 'Far Away', 'No Pin']);
    });

    test('equal-distance pins tie-break by title (List.sort is unstable)', () {
      // Two pins at the SAME coordinates: distance 0 for both, so the order
      // must come from the title — never from sort stability luck.
      final sorted = NetworkLibrarySort.byDistanceThenName([
        row(1, 'B-Same', lat: 13, lng: 77.7),
        row(2, 'A-Same', lat: 13, lng: 77.7),
      ], own);
      expect(names(sorted), ['A-Same', 'B-Same']);
    });

    test('pinned rows outrank pin-less ones even with an earlier title', () {
      final sorted = NetworkLibrarySort.byDistanceThenName([
        row(1, 'Aardvark (no pin)'),
        row(2, 'Zulu (pinned)', lat: 15, lng: 80),
      ], own);
      expect(names(sorted), ['Zulu (pinned)', 'Aardvark (no pin)']);
    });
  });
}
