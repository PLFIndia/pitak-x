/// Bounded, allow-listed remote cover fetcher (infra, #32, F-09/M1; N08).
///
/// Why this exists (security audit M1): publishing fetches each book's
/// `coverUrl` from the *publisher's* device. A poisoned `coverUrl` (planted via
/// a hostile import or a lookup) would otherwise make the device issue a GET to
/// an arbitrary host — leaking the publisher's IP / User-Agent / "publishing
/// now" timing — and, with an unbounded buffered read, let that host hang the
/// publish or stream gigabytes into memory (DoS).
///
/// The three defences (origin allow-list, ABORTABLE
/// whole-request deadline, streaming byte cap with per-hop redirect
/// re-validation and never draining rejected bodies) live in the shared
/// `BoundedHttpFetcher` (`lib/core/network/bounded_http_fetcher.dart`), which
/// the network descriptor fetch uses too — 150 lines of security code are not
/// copy-pasted. This class is now the cover-specific ADAPTER: it pins the
/// allow-list to [CoverUrlAllowList.sanitize] and maps the generic
/// [BoundedFetchOutcome] onto the publish-domain [CoverFetchResult].
///
/// The result is a sealed [CoverFetchResult] (publish domain): bytes, or a
/// [CoverRefusal] naming WHICH defence refused. The reason is a developer
/// diagnostic (M09: a missing thumbnail is not an error the user can act on)
/// and never carries the URL.
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Fetches a remote cover under strict origin / time / size limits.
final class BoundedCoverFetcher {
  /// Creates the fetcher over an injected [client].
  ///
  /// Not `const`: the allow-list is a tear-off of [CoverUrlAllowList.sanitize],
  /// and Dart function references are never compile-time constants. Nothing
  /// needs a const instance (DI and tests both construct at runtime).
  BoundedCoverFetcher({
    required http.Client client,
    this.timeout = const Duration(seconds: 15),
    this.maxBytes = maxCoverBytes,
  }) : _fetcher = BoundedHttpFetcher(
         client: client,
         sanitize: CoverUrlAllowList.sanitize,
         timeout: timeout,
         maxBytes: maxBytes,
       );

  final BoundedHttpFetcher _fetcher;

  /// Whole-request deadline (connect + headers + body, across all redirect
  /// hops). On expiry the in-flight request is ABORTED and
  /// [CoverRefusal.timedOut] is returned.
  final Duration timeout;

  /// Hard cap on bytes read from the body. Streaming stops and the request is
  /// aborted the instant this is exceeded.
  final int maxBytes;

  /// Default body cap: 8 MiB. A book cover is downscaled to a ~tens-of-KB JPEG
  /// downstream, so 8 MiB is a generous ceiling that still bounds memory.
  static const int maxCoverBytes = 8 * 1024 * 1024;

  /// Max redirect hops followed per fetch. Each hop's `Location` is
  /// re-validated against the allow-list before any packet is sent.
  static const int maxRedirects = BoundedHttpFetcher.defaultMaxRedirects;

  /// Fetches the cover for [rawUrl]. Never throws for expected failures: every
  /// refusal, timeout or transport fault is a [CoverRefused].
  Future<CoverFetchResult> fetch(String rawUrl) async {
    return switch (await _fetcher.fetch(rawUrl)) {
      FetchedBytes(:final bytes) => CoverFetched(bytes),
      FetchRefused(:final reason) => CoverRefused(_toCoverRefusal(reason)),
    };
  }

  /// The generic core refusal names map 1:1 onto the publish-domain ones (the
  /// core set is exactly [CoverRefusal] minus the cover-only `notAnImage`,
  /// which is decided downstream by the image decoder, not by the fetch).
  static CoverRefusal _toCoverRefusal(FetchRefusal reason) => switch (reason) {
    FetchRefusal.disallowedUrl => CoverRefusal.disallowedUrl,
    FetchRefusal.redirectRefused => CoverRefusal.redirectRefused,
    FetchRefusal.tooManyRedirects => CoverRefusal.tooManyRedirects,
    FetchRefusal.httpStatus => CoverRefusal.httpStatus,
    FetchRefusal.tooLarge => CoverRefusal.tooLarge,
    FetchRefusal.timedOut => CoverRefusal.timedOut,
    FetchRefusal.transport => CoverRefusal.transport,
  };
}
