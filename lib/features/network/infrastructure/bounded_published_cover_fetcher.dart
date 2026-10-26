/// Bounded fetcher + decoder for published covers (network infrastructure;
/// ADR 0015 V11, viewer plan S5).
///
/// Shares the viewer's HTTP client and the shared [BoundedHttpFetcher], so the
/// same three defences apply as everywhere else:
///  1. the resolver's sanitizer runs on the initial URL and every redirect hop
///     (same-site: origin + directory; third-party: the cover allow-list);
///  2. a 15 s abortable deadline — the caller's signal (dropped row, reload,
///     route close) tears the socket down too;
///  3. an 8 MiB streamed cap, aborted the moment it is exceeded.
///
/// Then the bytes are decoded OFF the UI isolate with
/// [ImageDownscaler.downscaleJpegAsync]: header dimension/pixel guards, FRAME 0
/// only, at most 400×600 JPEG output, EXIF stripped. Only the downscaled JPEG
/// ever leaves this class; a decode failure is `null` (placeholder), never the
/// raw download (no raw fallback).
///
/// A same-site and a third-party cover have DIFFERENT allow-lists, and
/// `BoundedHttpFetcher` binds its allow-list at construction. So each request
/// gets a thin per-request wrapper over the SAME shared client — one
/// connection pool, the right policy per hop.
///
/// Requests carry the app's fixed User-Agent and nothing else: no cookies, no
/// auth headers.
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';

/// Fetches and downscales cover images under strict limits.
final class BoundedPublishedCoverFetcher {
  /// Creates the fetcher over the viewer's [client].
  ///
  /// [decode] is injectable so a test can prove "only downscaled bytes reach
  /// the cache" without spawning a real worker isolate; production uses
  /// [ImageDownscaler.downscaleJpegAsync].
  BoundedPublishedCoverFetcher({
    required http.Client client,
    this.timeout = defaultTimeout,
    this.maxBytes = defaultMaxBytes,
    this.maxRedirects = defaultMaxRedirects,
    this.decode = ImageDownscaler.downscaleJpegAsync,
  }) : _client = client;

  final http.Client _client;

  /// Whole-request deadline (abortable).
  final Duration timeout;

  /// Streamed body cap.
  final int maxBytes;

  /// Redirect hops followed (each re-validated by the request's sanitizer).
  final int maxRedirects;

  /// The decode step (worker isolate in production).
  final Future<Uint8List?> Function(List<int> bytes) decode;

  /// Default deadline for one cover request.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Default cover-body cap: 8 MiB (the shared fetcher default).
  static const int defaultMaxBytes = BoundedHttpFetcher.defaultMaxBytes;

  /// Default redirect budget.
  static const int defaultMaxRedirects = BoundedHttpFetcher.defaultMaxRedirects;

  /// Fetches + downscales [request]. Returns null for every expected failure.
  Future<Uint8List?> fetch(
    PublishedCoverRequest request, {
    Future<void>? abortTrigger,
  }) async {
    final scoped = BoundedHttpFetcher(
      client: _client,
      sanitize: request.sanitize,
      timeout: timeout,
      maxBytes: maxBytes,
      maxRedirects: maxRedirects,
      // Deliberately the CORE default headers (the app's fixed User-Agent and
      // nothing else): a cover request never carries cookies or auth.
    );
    final outcome = await scoped.fetch(request.url, abortTrigger: abortTrigger);
    return switch (outcome) {
      FetchedBytes(:final bytes) => await decode(bytes),
      FetchRefused() => null,
    };
  }
}
