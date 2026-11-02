/// Bounded fetcher for a saved library's optional `availability.json`
/// (network infrastructure; ADR 0019, ADR 0015 and ADR 0018 amendments).
///
/// It reuses the viewer-owned client, the same-origin/directory policy on the
/// first URL and every redirect, the abortable deadline and the no-cache
/// headers of the other two files. When a saved copy exists its entity tag is
/// sent as `If-None-Match`, so an unchanged file costs a `304`.
///
/// Mapping (ADR 0019 Decision 4, "treated as missing"):
///  - `200` with a file the codec accepts → fresh;
///  - `404`, a body over 1 MiB, or a file the codec refuses →
///    [PublishedFileMissing]: the file exists but must not be used, so the
///    viewer falls back to the inline tags and drops any older saved copy;
///  - every transport failure → [PublishedFileFailed] (a saved copy may then
///    be shown with its note).
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/infrastructure/published_availability_codec.dart';
import 'package:pitaka/features/network/infrastructure/published_fetch_problem.dart';

/// Fetches and decodes `availability.json` under strict transport limits.
final class BoundedPublishedAvailabilityFetcher {
  /// Creates the fetcher for one canonical saved [siteUrl].
  BoundedPublishedAvailabilityFetcher({
    required http.Client client,
    required String siteUrl,
    this.timeout = defaultTimeout,
    this.maxBytes = PublishedAvailabilityFile.maxBytes,
    this.maxRedirects = defaultMaxRedirects,
    this.codec = const PublishedAvailabilityCodec(),
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
  final PublishedAvailabilityCodec codec;

  /// Default deadline: the file is tiny, and the catalogue never waits for
  /// it, so a slow host only delays the newer tags.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Default redirect budget (the same as the other two files).
  static const int defaultMaxRedirects = 3;

  /// No cookies or credentials; ask the host to revalidate its copy.
  static const Map<String, String> requestHeaders = {
    'User-Agent': AppUserAgent.value,
    'Cache-Control': 'no-cache',
  };

  /// Fetches [url], sending [validator] as `If-None-Match` when non-null.
  Future<PublishedFileFetch<PublishedAvailabilityFile>> fetch(
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
            .match<PublishedFileFetch<PublishedAvailabilityFile>>(
              // Refused content is "treated as missing" (see the header).
              (_) => const PublishedFileMissing(),
              (file) => PublishedFileFetched(
                value: file,
                bytes: bytes,
                validator: entityTag,
              ),
            ),
      FetchNotModified() => const PublishedFileUnchanged(),
      FetchRefused(reason: FetchRefusal.httpStatus, statusCode: 404) ||
      FetchRefused(
        reason: FetchRefusal.tooLarge,
      ) => const PublishedFileMissing(),
      FetchRefused(:final reason) => PublishedFileFailed(
        failure: const NetworkFailure(),
        problem: publishedFileProblemFor(reason),
      ),
    };
  }
}
