/// OpenStreetMap tile configuration for the network map (pure Dart,
/// libNetwork.md §5.9).
///
/// ONE place owns everything the map needs to talk to the OSM tile CDN:
/// the URL template and the User-Agent header. It lives in `core/network`
/// (not the network feature's infrastructure) so PRESENTATION can read it
/// without crossing a layer boundary (AGENTS §3.1): after review M4 the
/// `TileLayer` widget is built per mount in the map page itself, because a
/// TileLayer's State disposes its tile provider — DI must hand out only
/// configuration and an externally-owned HTTP client, never the widget.
///
/// Caching: `NetworkTileProvider`'s default is flutter_map's built-in
/// on-disk cache, which honours the server's HTTP freshness headers
/// (`Cache-Control: max-age` / `Expires`) and falls back to a fixed 7-day
/// TTL when the server sends none — exactly the §5.9 requirement. Tiles are
/// fetched only for the visible viewport (no prefetch of any kind — OSM
/// tile-usage policy), and no `Cache-Control: no-cache` request header is
/// ever sent.
library;

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

  /// A FRESH headers map for one `TileLayer`: the app's single honest
  /// User-Agent (the OSM tile policy REQUIRES a UA naming the app).
  ///
  /// A new map per call, not a shared const: `TileLayer`'s constructor does
  /// `headers.putIfAbsent` to inject a fallback UA, and putIfAbsent throws
  /// on an unmodifiable map — even when the key is already there.
  static Map<String, String> headers() => {'User-Agent': AppUserAgent.value};
}
