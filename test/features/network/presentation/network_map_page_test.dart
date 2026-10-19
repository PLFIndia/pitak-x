import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/osm_tiles.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/presentation/pages/network_map_page.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:pitaka/features/network/presentation/widgets/map_pin_label.dart';
import 'package:pitaka/features/network/presentation/widgets/map_viewport.dart';
import 'package:pitaka/features/network/presentation/widgets/osm_attribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/a11y.dart';

/// Tests for the network map (libNetwork.md §7 S5): the consent gate (the
/// map never builds without consent), the tile-layer configuration (UA
/// header — over the config constants and the built widget, never HTTP),
/// the attribution, the pin sheet, pin labels (permanent for own + hubs,
/// tap-toggled for the rest), hub detection, the viewport math, and the
/// a11y trio.
///
/// No test ever touches the network: the map's DI-owned tile HTTP client is
/// overridden with a MockClient answering a 1×1 transparent PNG (M4 seam).
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  late _FakeRepo repo;

  /// In-memory tiles: the map's DI-owned HTTP client is replaced by a
  /// [MockClient] that answers every tile request with the same 1×1
  /// transparent PNG, so the REAL NetworkTileProvider path runs with no
  /// HTTP (review M4 — the seam moved from "override the layer" to
  /// "override the client" because the page now builds the layer per mount).
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
          osmTileHttpClientProvider.overrideWithValue(
            MockClient(
              (_) async => Response.bytes(
                _transparentPng,
                200,
                headers: const {'content-type': 'image/png'},
              ),
            ),
          ),
          // No on-disk tile cache in tests: the built-in cache resolves a
          // path_provider directory and spawns a worker isolate.
          osmTileDiskCacheProvider.overrideWithValue(false),
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
    test('the endpoint constant targets OSM and the headers carry the app '
        'User-Agent', () {
      expect(
        OsmTiles.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      // The OSM tile policy REQUIRES a UA naming the app; this is the one
      // place it is set, so pin it with a test.
      expect(OsmTiles.headers()['User-Agent'], AppUserAgent.value);
      // No cache-busting: the built-in cache honours server freshness
      // headers (7-day fallback) — never send no-cache (§5.9).
      expect(OsmTiles.headers(), isNot(contains('Cache-Control')));
      // A FRESH mutable map per call: TileLayer's constructor does
      // headers.putIfAbsent, which throws on an unmodifiable map.
      final a = OsmTiles.headers()..putIfAbsent('X-Test', () => 'ok');
      expect(identical(a, OsmTiles.headers()), isFalse);
    });

    testWidgets('the map builds its TileLayer per mount from the DI-owned '
        'client (M4)', (tester) async {
      await pumpPage(tester, prefs: const {'network_map_tiles_consent': true});
      await openMapTab(tester);

      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.urlTemplate, OsmTiles.urlTemplate);
      final provider = layer.tileProvider;
      expect(provider, isA<NetworkTileProvider>());
      expect(provider.headers['User-Agent'], AppUserAgent.value);
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
      // M3 / OSM tile policy: the full credit is on screen from the FIRST
      // frame — nothing to tap open, nothing hidden behind a toggle.
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

  group('pins, labels and the pin sheet', () {
    testWidgets('a pinned row shows a marker; tapping toggles its label and '
        'tapping the label opens the sheet with badges, distance and actions', (
      tester,
    ) async {
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
      // A non-hub label is hidden until its pin is tapped.
      expect(find.text('Member Library'), findsNothing);

      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();
      expect(find.text('Member Library'), findsOneWidget);

      // A second tap on the SAME pin hides the label again.
      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();
      expect(find.text('Member Library'), findsNothing);

      // Tap to select, then tap the label to open the sheet.
      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member Library'));
      await tester.pumpAndSettle();

      // The label is still on the map under the sheet (2 instances).
      expect(find.text('Member Library'), findsNWidgets(2));
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('km from your own pin'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Open site'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Directions'), findsOneWidget);
    });

    testWidgets('a hub pin carries a permanent label and its pin tap opens '
        'the sheet directly (no toggle)', (tester) async {
      repo.rows = [
        NetworkLibrary(
          id: 1,
          siteUrl: 'https://hub.github.io/h/',
          name: 'Hub Library',
          location: GeoPoint.tryCreate(12.97, 77.59),
          precision: LocationPrecision.exact,
          membership: MembershipState.confirmed,
        ),
      ];
      await pumpPage(tester, prefs: const {'network_map_tiles_consent': true});
      await openMapTab(tester);

      // No tap needed: the hub's name is on the map from the first frame.
      expect(find.text('Hub Library'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();

      // Sheet opened directly: the title plus the still-visible label.
      expect(find.text('Hub Library'), findsNWidgets(2));
      expect(find.text('My hub'), findsOneWidget);
    });

    testWidgets('your own pin carries your library name', (tester) async {
      await pumpPage(
        tester,
        prefs: const {
          'network_map_tiles_consent': true,
          'publish_contact_gps': '12.9, 77.6',
          'library_name': 'My Home Library',
        },
      );
      await openMapTab(tester);
      expect(find.text('My Home Library'), findsOneWidget);
    });

    testWidgets('a blank library name falls back to the "My library" caption', (
      tester,
    ) async {
      // (A fresh test, not a re-pump: SharedPreferences.getInstance() caches
      // per process, so new mock values mid-test would not be re-read.)
      await pumpPage(
        tester,
        prefs: const {
          'network_map_tiles_consent': true,
          'publish_contact_gps': '12.9, 77.6',
        },
      );
      await openMapTab(tester);
      expect(find.text('My library'), findsOneWidget);
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
      await tester.tap(find.text('Pinned'));
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsNWidgets(2));
      expect(find.textContaining('km from your own pin'), findsNothing);
    });
  });

  group('hub detection (map_pin_label.dart)', () {
    test('hubSiteUrls collects every listedByHubUrl target', () {
      const rows = [
        NetworkLibrary(
          siteUrl: 'https://a.github.io/x/',
          listedByHubUrl: 'https://hub.github.io/h/',
        ),
        NetworkLibrary(siteUrl: 'https://b.github.io/y/'),
      ];
      expect(hubSiteUrls(rows), {'https://hub.github.io/h/'});
    });

    test('isHubRow: a row that lists me, or that listed someone else', () {
      const me = NetworkLibrary(
        siteUrl: 'https://hub.github.io/h/',
        membership: MembershipState.pending,
      );
      const listed = NetworkLibrary(siteUrl: 'https://hub.github.io/h/');
      const plain = NetworkLibrary(siteUrl: 'https://a.github.io/x/');
      const hubs = {'https://hub.github.io/h/'};

      expect(isHubRow(me, const {}), isTrue); // lists me (any state)
      expect(isHubRow(listed, hubs), isTrue); // listed someone else
      expect(isHubRow(plain, hubs), isFalse);
    });
  });

  group('initial viewport (§5.9)', () {
    test('no pins → world view', () {
      final options = MapViewport.forPoints(const []);
      expect(options.initialZoom, 2);
      expect(options.initialCameraFit, isNull);
    });

    test('one pin → centred on it at city zoom', () {
      final options = MapViewport.forPoints(const [LatLng(12.9, 77.6)]);
      expect(options.initialCenter.latitude, 12.9);
      expect(options.initialCenter.longitude, 77.6);
      expect(options.initialZoom, 12);
      expect(options.initialCameraFit, isNull);
    });

    test('several pins → bounds fit covering all of them', () {
      final options = MapViewport.forPoints(const [
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

    // A selected pin's tappable label must pass the same trio (48 dp target
    // via the transparent padding, semantic label on the pill).
    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pumpAndSettle();
    expect(find.text('Member Library'), findsOneWidget);
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

/// A minimal valid 1×1 transparent PNG (68 bytes, CRCs computed) — the
/// MockClient's answer to every tile request.
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
