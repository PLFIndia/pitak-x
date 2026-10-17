import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:latlong2/latlong.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/infrastructure/osm_tile_provider.dart';
import 'package:pitaka/features/network/presentation/pages/network_map_page.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/network/presentation/widgets/osm_attribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/a11y.dart';

/// Tests for the network map (libNetwork.md §7 S5): the consent gate (the
/// map never builds without consent), the tile-layer configuration (UA
/// header — a unit test over the config, never HTTP), the attribution, the
/// pin sheet, the viewport math, and the a11y trio.
///
/// No test ever touches the network: the map's tile layer is overridden with
/// an in-memory blank provider ( [_BlankTileProvider] ).
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  late _FakeRepo repo;

  /// Pumps the whole [NetworkPage] (the map lives in its Map tab) with the
  /// real provider chain; only the edges are faked (repository, descriptor
  /// fetcher, tile layer).
  Future<void> pumpPage(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'library_id': rawId, ...prefs});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWith((ref) async => repo),
          publishedSiteUrlProvider.overrideWith((ref) async => null),
          descriptorFetcherProvider.overrideWithValue(
            (url) async =>
                const DescriptorRefused(DescriptorRefusal.httpStatus),
          ),
          osmTileLayerProvider.overrideWithValue(
            TileLayer(
              urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
              tileProvider: _BlankTileProvider(),
            ),
          ),
        ],
        child: const MaterialApp(home: NetworkPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMapTab(WidgetTester tester) async {
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = _FakeRepo([]));

  group('tile layer configuration (§5.9)', () {
    test('the production layer targets OSM with the app User-Agent', () {
      final layer = buildOsmTileLayer();
      expect(layer.urlTemplate, OsmTiles.urlTemplate);
      expect(
        OsmTiles.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      final provider = layer.tileProvider;
      expect(provider, isA<NetworkTileProvider>());
      // The OSM tile policy REQUIRES a UA naming the app; this is the one
      // place it is set, so pin it with a test.
      expect(provider.headers['User-Agent'], AppUserAgent.value);
      // No cache-busting: the built-in cache honours server freshness
      // headers (7-day fallback) — never send no-cache (§5.9).
      expect(provider.headers, isNot(contains('Cache-Control')));
    });
  });

  group('consent gating', () {
    testWidgets('without consent the Map tab asks; Decline returns to the '
        'list and the map never builds', (tester) async {
      await pumpPage(tester);
      await openMapTab(tester);

      // The consent dialog popped over the placeholder.
      expect(find.text('Show the network map?'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap'), findsWidgets);
      expect(find.byType(FlutterMap), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'No thanks'));
      await tester.pumpAndSettle();

      // Back on the Libraries tab; the map was never built, and the consent
      // key was never written (fail closed).
      expect(find.text('Never refreshed yet.'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('network_map_tiles_consent'), isNull);
    });

    testWidgets('Accept persists the consent and the map builds with its '
        'attribution', (tester) async {
      await pumpPage(tester);
      await openMapTab(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Show the map'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('network_map_tiles_consent'), isTrue);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(OsmAttribution), findsOneWidget);
      // The full credit lives in the popup behind the permanent toggle.
      await tester.tap(find.byIcon(Icons.info_outlined));
      await tester.pumpAndSettle();
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });

    testWidgets('consent already given: the tab opens the map directly, no '
        'dialog', (tester) async {
      await pumpPage(tester, prefs: const {'network_map_tiles_consent': true});
      await openMapTab(tester);

      expect(find.text('Show the network map?'), findsNothing);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('dismissing the dialog (barrier tap) means no consent', (
      tester,
    ) async {
      await pumpPage(tester);
      await openMapTab(tester);
      expect(find.text('Show the network map?'), findsOneWidget);

      // Tap above the dialog = the barrier.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('network_map_tiles_consent'), isNull);
    });
  });

  group('pins and the pin sheet', () {
    testWidgets('a pinned row shows a marker; tapping it opens the sheet with '
        'badges, distance and actions', (tester) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: 'https://m.github.io/x/',
          name: 'Member Library',
          location: GeoPoint.tryCreate(12.97, 77.59),
          precision: LocationPrecision.exact,
          source: NetworkSource.card,
          isMember: true,
          memberVerified: true,
        ),
        const NetworkLibrary(
          id: 2,
          siteUrl: 'https://nopin.github.io/y/',
          name: 'No Pin Row',
        ),
      ];
      await pumpPage(
        tester,
        prefs: const {
          'network_map_tiles_consent': true,
          // Own pin: sharing key absent + GPS non-blank ⇒ first-read rule
          // yields `exact` (D7).
          'publish_contact_gps': '12.9, 77.6',
        },
      );
      await openMapTab(tester);

      // Two pins: the row's and the own pin. The pin-less row has none.
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();

      expect(find.text('Member Library'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('km from your own pin'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Open site'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Directions'), findsOneWidget);
    });

    testWidgets('without an own pin the sheet shows no distance line', (
      tester,
    ) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: 'https://m.github.io/x/',
          name: 'Pinned',
          location: GeoPoint.tryCreate(12.97, 77.59),
          precision: LocationPrecision.approximate,
        ),
      ];
      await pumpPage(tester, prefs: const {'network_map_tiles_consent': true});
      await openMapTab(tester);

      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsOneWidget);
      expect(find.textContaining('km from your own pin'), findsNothing);
    });
  });

  group('initial viewport (§5.9)', () {
    test('no pins → world view', () {
      final options = NetworkMapPage.initialOptions(const []);
      expect(options.initialZoom, 2);
      expect(options.initialCameraFit, isNull);
    });

    test('one pin → centred on it at city zoom', () {
      final options = NetworkMapPage.initialOptions(const [LatLng(12.9, 77.6)]);
      expect(options.initialCenter.latitude, 12.9);
      expect(options.initialCenter.longitude, 77.6);
      expect(options.initialZoom, 12);
      expect(options.initialCameraFit, isNull);
    });

    test('several pins → bounds fit covering all of them', () {
      final options = NetworkMapPage.initialOptions(const [
        LatLng(12.9, 77.6),
        LatLng(13.1, 77.4),
        LatLng(12.8, 77.9),
      ]);
      final fit = options.initialCameraFit;
      expect(fit, isNotNull);
    });
  });

  test('formatDistance keeps small values precise, rounds large ones', () {
    expect(NetworkMapPage.formatDistance(0.42), '0.4 km');
    expect(NetworkMapPage.formatDistance(3.45), '3.5 km');
    expect(NetworkMapPage.formatDistance(12.4), '12 km');
    expect(NetworkMapPage.formatDistance(871), '871 km');
  });

  testWidgets('meets accessibility guidelines (map with pins)', (tester) async {
    repo.rows = [
      NetworkLibrary(
        id: 1,
        siteUrl: 'https://m.github.io/x/',
        name: 'Member Library',
        location: GeoPoint.tryCreate(12.97, 77.59),
        precision: LocationPrecision.exact,
        isMember: true,
        memberVerified: true,
      ),
    ];
    await pumpPage(tester, prefs: const {'network_map_tiles_consent': true});
    await openMapTab(tester);
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (consent dialog)', (
    tester,
  ) async {
    await pumpPage(tester);
    await openMapTab(tester);
    expect(find.text('Show the network map?'), findsOneWidget);
    await expectMeetsA11yGuidelines(tester);
  });
}

/// In-memory blank tiles: every request resolves to the same 1×1 transparent
/// PNG, so the map renders its full widget tree without any HTTP.
class _BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPng);
}

/// A minimal valid 1×1 transparent PNG (68 bytes, CRCs computed).
final Uint8List _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// In-memory repository fake (same shape as the Libraries-tab tests).
class _FakeRepo implements NetworkRepository {
  _FakeRepo(this.rows);

  List<NetworkLibrary> rows;

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    rows.add(row.copyWith(id: rows.length + 1));
    return right(rows.last);
  }

  @override
  Future<Either<Failure, Unit>> removeById(int id) async {
    rows.removeWhere((r) => r.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered,
  ) async => right(unit);

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
