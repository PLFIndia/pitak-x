/// The network map (presentation, libNetwork.md §5.9).
///
/// Two pieces:
///  - [NetworkMapGate] — the consent gate. The map never builds (and no
///    tile request ever leaves the device) until
///    `AppSettings.networkMapTilesConsent` is true. Without consent the gate
///    asks once per visit via
///    [TilesConsentDialog]; Accept persists the setting, anything else
///    returns the user to the Libraries tab. A quiet "Show map" button stays
///    behind so a later visit can ask again.
///  - [NetworkMapPage] — the flutter_map view itself: one pin per saved
///    library that publishes coordinates, this library's own pin when it
///    publishes one (the same D7 mapping the list tab uses — NEVER a device
///    location), the permanent OSM attribution, and a bottom sheet per pin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/network/osm_tiles.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/geo_uri.dart';
import 'package:pitaka/features/network/domain/value_objects/geo_point.dart';
import 'package:pitaka/features/network/presentation/widgets/membership_badge.dart';
import 'package:pitaka/features/network/presentation/widgets/osm_attribution.dart';
import 'package:pitaka/features/network/presentation/widgets/tiles_consent_dialog.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// The consent gate in front of the map (see the library doc above).
class NetworkMapGate extends ConsumerStatefulWidget {
  /// Creates the gate.
  const NetworkMapGate({super.key});

  @override
  ConsumerState<NetworkMapGate> createState() => _NetworkMapGateState();
}

class _NetworkMapGateState extends ConsumerState<NetworkMapGate> {
  /// Whether this mount has already auto-asked. Once per visit: the dialog
  /// pops when the tab is first opened; after that the placeholder's button
  /// is the way to ask again (the tab may stay alive beside the list tab).
  bool _asked = false;

  Future<void> _ask() async {
    final accepted = await TilesConsentDialog.ask(context);
    if (!mounted) return;
    if (accepted) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setNetworkMapTilesConsent(enabled: true);
    } else {
      // §5.9: Decline returns to the list (tab 0). Anything but an explicit
      // Accept — including dismissing the dialog — means no consent.
      DefaultTabController.of(context).animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final consent = settings.valueOrNull?.networkMapTilesConsent ?? false;
    if (consent) return const NetworkMapPage();
    if (settings.isLoading && !settings.hasValue) {
      // Consent unknown yet — say nothing until the first load lands.
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (!_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ask();
      });
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'The map shows your saved libraries on OpenStreetMap images. '
              'It downloads nothing until you say yes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _ask,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Show map'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The map of saved libraries. Built only behind [NetworkMapGate].
class NetworkMapPage extends ConsumerWidget {
  /// Creates the map view.
  const NetworkMapPage({super.key});

  /// The initial viewport (§5.9): the bounds of every pin when there are at
  /// least two; centred on the single pin when there is one; a world view
  /// when nothing has a coordinate yet. [points] = library pins + own pin.
  /// Pure and static so tests can pin it down without rendering a map.
  static MapOptions initialOptions(List<LatLng> points) {
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

  /// Plain-words distance for the pin sheet ("12 km" / "3.4 km").
  static String formatDistance(double km) =>
      km >= 10 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';

  Future<void> _openSite(BuildContext context, NetworkLibrary row) async {
    final ok = await launchUrl(
      Uri.parse(row.siteUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  Future<void> _openDirections(BuildContext context, NetworkLibrary row) async {
    final location = row.location;
    if (location == null) return;
    // geo: URI with a labelled query pin — the OS map app picks it up
    // (§5.9). GeoUri owns the formatting rules (fixed decimals, encoded
    // parentheses); see its doc for why plain interpolation was wrong.
    final uri = GeoUri.directions(
      location,
      label: row.name.isEmpty ? row.siteUrl : row.name,
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open directions.")),
      );
    }
  }

  void _showPinSheet(BuildContext context, NetworkLibrary row, GeoPoint? own) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final title = row.name.isEmpty ? row.siteUrl : row.name;
        final location = row.location;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (row.name.isNotEmpty)
                  Text(
                    row.siteUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 8),
                MembershipBadge(row),
                if (own != null && location != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'About ${formatDistance(own.distanceKm(location))} '
                    'from your own pin.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openSite(sheetContext, row),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open site'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openDirections(sheetContext, row),
                      icon: const Icon(Icons.directions_outlined),
                      label: const Text('Directions'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The tile HTTP client is owned by DI (opened on first watch, closed via
    // ref.onDispose); the TileLayer built AROUND it is per-mount, so a
    // layer dispose never closes the shared client out from under a future
    // mount (review M4).
    final tileClient = ref.watch(osmTileHttpClientProvider);
    // Whether the tile layer may use the on-disk cache (tests disable it:
    // the built-in cache needs path_provider and spawns a worker isolate).
    final tileDiskCache = ref.watch(osmTileDiskCacheProvider);
    final rows =
        ref.watch(networkControllerProvider).valueOrNull?.rows ?? const [];
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    // The own pin = the location THIS library publishes (D7 mapping in its
    // one home). The map never reads a device location (D6).
    final own = settings == null
        ? null
        : BuildOwnDescriptor.ownLocation(
            sharing: settings.publishLocationSharing,
            gps: settings.publishContactGps,
          );
    final pinned = [
      for (final row in rows)
        if (row.location != null) row,
    ];
    final scheme = Theme.of(context).colorScheme;
    // The Semantics label is load-bearing, not decorative: flutter_map's
    // gesture layer registers tap/longPress recognizers (and an autofocus
    // Focus) whose semantics ACTIONS merge into the nearest ancestor
    // semantics node. Without a label here that is the tab panel — an
    // unlabelled tappable node that fails the a11y gate depending on test
    // ordering (found while fixing M3). A bare label-only Semantics merges
    // upward, so the panel node itself gains the label.
    return Semantics(
      label: 'Map of saved libraries',
      child: FlutterMap(
        options: initialOptions([
          for (final row in pinned)
            LatLng(row.location!.lat, row.location!.lng),
          if (own != null) LatLng(own.lat, own.lng),
        ]),
        children: [
          TileLayer(
            urlTemplate: OsmTiles.urlTemplate,
            tileProvider: NetworkTileProvider(
              httpClient: tileClient,
              headers: OsmTiles.headers(),
              cachingProvider: tileDiskCache
                  // null = production default: the built-in
                  // HTTP-freshness cache.
                  ? null
                  : const DisabledMapCachingProvider(),
            ),
          ),
          MarkerLayer(
            markers: [
              for (final row in pinned)
                Marker(
                  point: LatLng(row.location!.lat, row.location!.lng),
                  // 48×48: the a11y minimum tap target (the icon itself stays
                  // 40 — the padding around it is still tappable).
                  width: 48,
                  height: 48,
                  // Bottom-centre anchor: the icon's tip sits ON the
                  // coordinate.
                  alignment: Alignment.bottomCenter,
                  child: Semantics(
                    button: true,
                    label:
                        'Show details for '
                        '${row.name.isEmpty ? row.siteUrl : row.name}',
                    child: GestureDetector(
                      onTap: () => _showPinSheet(context, row, own),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: row.fetchStatus == FetchStatus.identityConflict
                            ? scheme.error
                            : scheme.primary,
                      ),
                    ),
                  ),
                ),
              if (own != null)
                Marker(
                  point: LatLng(own.lat, own.lng),
                  width: 48,
                  height: 48,
                  alignment: Alignment.bottomCenter,
                  child: Tooltip(
                    message: 'Your library',
                    child: Icon(
                      Icons.location_on,
                      size: 40,
                      color: scheme.tertiary,
                    ),
                  ),
                ),
            ],
          ),
          // Permanent, bottom-right — the OSM tile policy requires the credit.
          const OsmAttribution(),
        ],
      ),
    );
  }
}
