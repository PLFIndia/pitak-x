/// Bounded fetcher for a library's published `books.json` (network
/// infrastructure; ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// A thin adapter over the shared [BoundedHttpFetcher] — the same three
/// defences the descriptor fetch uses — plus the viewer's own policies:
///
///  1. ORIGIN + DIRECTORY: `PublishedSiteUrlPolicy.sanitizeForSite` replaces
///     the plain Pages allow-list. The initial URL and every redirect hop must
///     stay on the saved library's origin AND inside its directory (V18), so
///     one saved site can never redirect the reader into another library.
///  2. DEADLINE: 30 s for the whole request, ABORTABLE — a larger catalogue
///     than a 64 KiB descriptor needs more time, but a slow-loris host still
///     loses its socket (also when the screen closes: caller abort).
///  3. BYTE CAP: 64 MiB streamed and aborted over cap, matching the app's
///     outer interchange ceiling; declared `Content-Length` is rejected early
///     but actual bytes are still counted.
///
/// Request headers mirror the web viewer's revalidation intent:
/// `Cache-Control: no-cache`, no cache-busting query, the app User-Agent
/// (custom headers REPLACE the core defaults, so it is listed explicitly), and
/// no cookies/auth on any hop.
///
/// Decoding runs in a worker isolate: a large JSON document and its object
/// graph would otherwise stall frames. Only public bytes and public view
/// models cross the isolate boundary. Tests inject a synchronous decoder.
library;

import 'dart:isolate';

import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';

/// Decodes a catalogue body off the UI isolate (injectable for tests).
typedef PublishedCatalogueBodyDecoder =
    Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> Function(
      List<int> bytes,
    );

/// Fetches and decodes one library's `books.json` under strict limits.
final class BoundedPublishedCatalogueFetcher {
  /// Creates the fetcher for the library saved at [siteUrl] (canonical site
  /// root). Production wiring always passes the viewer-owned client.
  BoundedPublishedCatalogueFetcher({
    required http.Client client,
    required String siteUrl,
    this.timeout = defaultTimeout,
    this.maxBytes = defaultMaxBytes,
    this.maxRedirects = defaultMaxRedirects,
    this.codec = const PublishedCatalogueCodec(),
    PublishedCatalogueBodyDecoder? decode,
  }) : _decodeOverride = decode,
       _fetcher = BoundedHttpFetcher(
         client: client,
         sanitize: PublishedSiteUrlPolicy.sanitizerFor(siteUrl),
         timeout: timeout,
         maxBytes: maxBytes,
         maxRedirects: maxRedirects,
         headers: requestHeaders,
       );

  final BoundedHttpFetcher _fetcher;
  final PublishedCatalogueBodyDecoder? _decodeOverride;

  /// Whole-request deadline. 30 s covers a large catalogue on mobile data
  /// while still ending a dead socket; the request is ABORTED, not abandoned.
  final Duration timeout;

  /// Streamed body cap. Must match [codec]'s own cap; the decoder re-checks it
  /// because tests and future non-HTTP callers can reach it directly.
  final int maxBytes;

  /// Redirect hops followed (each re-validated by the site policy).
  final int maxRedirects;

  /// The pure decoder.
  final PublishedCatalogueCodec codec;

  /// Default deadline for one catalogue fetch.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Default body cap — the codec's own limit, in one place.
  static const int defaultMaxBytes =
      PublishedCatalogueCodec.defaultMaxBodyBytes;

  /// Default redirect budget.
  static const int defaultMaxRedirects = 3;

  /// Headers sent on the initial request and every redirect hop. The app
  /// User-Agent is required (the core default set would be replaced), and the
  /// cache directive asks Pages hosts to revalidate instead of serving a stale
  /// copy — the web viewer's `cache: "no-cache"`, without a query parameter.
  static const Map<String, String> requestHeaders = {
    'User-Agent': AppUserAgent.value,
    'Cache-Control': 'no-cache',
  };

  /// Fetches [url] (already resolved by the use case) and decodes the body.
  ///
  /// Never throws for expected failures. [abortTrigger] cancels the actual
  /// request; a caller-aborted fetch may come back as the coarse transport
  /// reason, which the controller discards because its revision is superseded.
  Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> fetch(
    String url, {
    Future<void>? abortTrigger,
  }) async {
    final outcome = await _fetcher.fetch(url, abortTrigger: abortTrigger);
    return switch (outcome) {
      FetchedBytes(:final bytes) => await _decode(bytes),
      FetchRefused(:final reason) => Left(
        PublishedCatalogueFailure(mapRefusal(reason)),
      ),
    };
  }

  /// The transport refusal set maps 1:1 onto the catalogue failure reasons.
  static PublishedCatalogueFailureReason mapRefusal(FetchRefusal reason) =>
      switch (reason) {
        FetchRefusal.disallowedUrl =>
          PublishedCatalogueFailureReason.disallowedUrl,
        FetchRefusal.redirectRefused =>
          PublishedCatalogueFailureReason.redirectRefused,
        FetchRefusal.tooManyRedirects =>
          PublishedCatalogueFailureReason.tooManyRedirects,
        FetchRefusal.httpStatus => PublishedCatalogueFailureReason.httpStatus,
        FetchRefusal.tooLarge => PublishedCatalogueFailureReason.tooLarge,
        FetchRefusal.timedOut => PublishedCatalogueFailureReason.timedOut,
        FetchRefusal.transport => PublishedCatalogueFailureReason.transport,
      };

  /// Decode the body on a worker isolate unless a test injected a decoder.
  Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> _decode(
    List<int> bytes,
  ) {
    final override = _decodeOverride;
    if (override != null) return override(bytes);
    // Capture LOCALS only: a closure over `this` would try to send the HTTP
    // client's object graph to the isolate and fail. Codec + bytes are plain
    // data (no secrets), so crossing the boundary is safe.
    final codec = this.codec;
    return Isolate.run(
      () => codec.decode(bytes),
      debugName: 'pitaka-published-catalogue-decode',
    );
  }
}
