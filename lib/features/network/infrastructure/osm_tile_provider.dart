/// OpenStreetMap tile configuration for the network map (infrastructure,
/// libNetwork.md §5.9).
///
/// ONE place owns everything the map needs to talk to the OSM tile CDN:
/// the URL template, the User-Agent header, and the caching behaviour.
/// Keeping it here (not in the page) means a future tile-server change is a
/// one-file edit, and tests can read the same constants the widget uses.
///
/// Caching: [NetworkTileProvider]'s default is flutter_map's built-in
/// on-disk cache, which honours the server's HTTP freshness headers
/// (`Cache-Control: max-age` / `Expires`) and falls back to a fixed 7-day
/// TTL when the server sends none — exactly the §5.9 requirement, so no
/// `cachingProvider` override is passed. Tiles are fetched only for the
/// visible viewport (no prefetch of any kind — OSM tile-usage policy), and
/// no `Cache-Control: no-cache` request header is ever sent.
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:pitaka/core/network/app_user_agent.dart';

/// Constants for the OpenStreetMap raster tile endpoint.
abstract final class OsmTiles {
  /// The tile URL template; flutter_map fills `{z}/{x}/{y}` per tile.
  ///
  /// This is the ONLY place the endpoint is named (§5.9) — a configurable
  /// tile server is a deliberate non-goal (§10 deferred: add a settings
  /// field only if OSM ever blocks or throttles us).
  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}

/// Builds the map's one [TileLayer]: the OSM endpoint plus the app's single
/// honest User-Agent (the OSM tile policy REQUIRES a UA naming the app).
///
/// A plain function, not a widget: the layer is immutable configuration.
/// Tests override the DI provider with a layer whose `tileProvider` is an
/// in-memory blank — no HTTP ever happens in a test.
TileLayer buildOsmTileLayer() => TileLayer(
  urlTemplate: OsmTiles.urlTemplate,
  tileProvider: NetworkTileProvider(
    // NOT a const map: TileLayer's constructor does headers.putIfAbsent to
    // inject a fallback UA, and putIfAbsent throws on an unmodifiable map —
    // even when the key is already there.
    headers: {'User-Agent': AppUserAgent.value},
  ),
);
