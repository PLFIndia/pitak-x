/// The production [PublishedSiteVerifier] over the shared bounded fetcher
/// (publish infrastructure; Cloudflare plan R16).
///
/// Deliberately thin: every defence already lives in `BoundedHttpFetcher`
/// (streamed byte cap, abortable deadline, no automatic redirect following).
/// This adapter adds the two publish-specific rules:
///  1. the URL is built by `PublishedSiteUrlPolicy.readBackUrl`, so it can only
///     ever be `<canonical site root><safe path>[?rb=…]`;
///  2. the fetcher's allow-list is bound to EXACTLY that URL, so any redirect
///     hop (a different URL) is refused outright.
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Reads published files under the site's own origin and directory.
final class BoundedPublishedSiteVerifier
    implements PublishedSiteVerifier, PublishedSiteReadVerifier {
  /// Creates the verifier over an injected (unauthenticated) [client].
  const BoundedPublishedSiteVerifier({
    required http.Client client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client;

  final http.Client _client;

  /// Whole-request deadline; the request is aborted, not merely abandoned.
  final Duration timeout;

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final outcome = await readOutcome(
      siteUrl: siteUrl,
      path: path,
      maxBytes: maxBytes,
      cacheBuster: cacheBuster,
    );
    return switch (outcome) {
      PublishedSiteReadBody(:final bytes) => bytes,
      // The original verifier port deliberately keeps every refusal as null.
      PublishedSiteReadAbsent() || PublishedSiteReadUnreadable() => null,
    };
  }

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    if (maxBytes <= 0) return const PublishedSiteReadUnreadable();
    final url = PublishedSiteUrlPolicy.readBackUrl(
      siteUrl,
      path,
      cacheBuster: cacheBuster,
    );
    if (url == null) return const PublishedSiteReadUnreadable();

    final fetcher = BoundedHttpFetcher(
      client: _client,
      // EXACT-URL allow-list: the initial URL passes, every redirect hop does
      // not (R16: publish verification refuses all redirects).
      sanitize: (candidate) => candidate == url ? url : null,
      timeout: timeout,
      maxBytes: maxBytes,
      maxRedirects: 0,
    );
    final outcome = await fetcher.fetch(url);
    return switch (outcome) {
      FetchedBytes(:final bytes) => PublishedSiteReadBody(bytes),
      // Only an actual 404 is absence. A redirect, 500, timeout, or oversized
      // body remains unreadable and can never authorize a fresh-site decision.
      FetchRefused(reason: FetchRefusal.httpStatus, statusCode: 404) =>
        const PublishedSiteReadAbsent(),
      FetchRefused() => const PublishedSiteReadUnreadable(),
    };
  }
}
