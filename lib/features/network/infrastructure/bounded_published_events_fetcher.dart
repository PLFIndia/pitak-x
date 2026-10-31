/// Bounded fetcher for a saved library's optional `events.json` sibling file.
///
/// It reuses the viewer-owned client, same-origin/directory policy, redirect
/// checks, abortable deadline and no-cache headers. A 404 is
/// [PublishedFileMissing] (no events published); every other refusal stays a
/// typed [PublishedFileFailed]. When a saved copy exists its entity tag is
/// sent as `If-None-Match` (ADR 0018), so unchanged events cost a `304`.
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/infrastructure/published_events_codec.dart';
import 'package:pitaka/features/network/infrastructure/published_fetch_problem.dart';

/// Fetches and decodes public events under strict transport limits.
final class BoundedPublishedEventsFetcher {
  /// Creates the fetcher for one canonical saved [siteUrl].
  BoundedPublishedEventsFetcher({
    required http.Client client,
    required String siteUrl,
    this.timeout = defaultTimeout,
    this.maxBytes = PublishedEventsCodec.defaultMaxBodyBytes,
    this.maxRedirects = defaultMaxRedirects,
    this.codec = const PublishedEventsCodec(),
  }) : _fetcher = BoundedHttpFetcher(
         client: client,
         sanitize: PublishedSiteUrlPolicy.sanitizerFor(siteUrl),
         timeout: timeout,
         maxBytes: maxBytes,
         maxRedirects: maxRedirects,
         headers: requestHeaders,
       );

  final BoundedHttpFetcher _fetcher;

  /// Whole-request abortable deadline.
  final Duration timeout;

  /// Streamed body cap (the codec independently checks it too).
  final int maxBytes;

  /// Maximum same-site redirect hops.
  final int maxRedirects;

  /// Defensive payload reader.
  final PublishedEventsCodec codec;

  /// Default deadline for the small optional file.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Default redirect budget.
  static const int defaultMaxRedirects = 3;

  /// No cookies or credentials; ask Pages to revalidate the current snapshot.
  static const Map<String, String> requestHeaders = {
    'User-Agent': AppUserAgent.value,
    'Cache-Control': 'no-cache',
  };

  /// Fetches [url], sending [validator] as `If-None-Match` when non-null.
  /// Only 404 maps to [PublishedFileMissing]; it must not hide server
  /// failures.
  Future<PublishedFileFetch<PublishedEvents>> fetch(
    String url, {
    String? validator,
    Future<void>? abortTrigger,
  }) async {
    final outcome = await _fetcher.fetchConditional(
      url,
      ifNoneMatch: validator,
      abortTrigger: abortTrigger,
    );
    return switch (outcome) {
      FetchedBytes(:final bytes, :final entityTag) =>
        codec
            .decode(bytes)
            .match<PublishedFileFetch<PublishedEvents>>(
              (failure) => PublishedFileFailed(
                failure: failure,
                problem: PublishedFileProblem.unreadable,
              ),
              (events) => PublishedFileFetched(
                value: events,
                bytes: bytes,
                validator: entityTag,
              ),
            ),
      FetchNotModified() => const PublishedFileUnchanged(),
      FetchRefused(reason: FetchRefusal.httpStatus, statusCode: 404) =>
        const PublishedFileMissing(),
      FetchRefused(:final reason) => PublishedFileFailed(
        failure: const NetworkFailure(),
        problem: publishedFileProblemFor(reason),
      ),
    };
  }
}
