/// Typed outcome of a bounded remote-cover fetch (N08; N11 D4-b).
///
/// Lives in the publish DOMAIN (pure Dart) so both consumers of the fetcher
/// — the publish use case and the library's cover materialiser (application
/// layer) — can name the result without importing infrastructure
/// (AGENTS.md §3.1). The infrastructure `BoundedCoverFetcher` produces it.
///
/// The refusal reason is a DEVELOPER diagnostic. M09 decision: a missing
/// thumbnail is not an error the user can act on, so no UI shows it; it is
/// coarse on purpose and never carries the URL or host.
library;

/// Why a cover fetch was refused. Coarse on purpose: enough to tell a broken
/// allow-list from a slow host in a debug log, never enough to identify the
/// book or the URL.
enum CoverRefusal {
  /// The URL failed the allow-list (scheme, userinfo or host).
  disallowedUrl,

  /// A redirect pointed outside the allow-list, or lacked a Location.
  redirectRefused,

  /// More redirect hops than the fetcher follows.
  tooManyRedirects,

  /// The final response was not 2xx.
  httpStatus,

  /// The body exceeded the byte cap (declared or actual).
  tooLarge,

  /// The whole request exceeded the deadline.
  timedOut,

  /// Connection reset, DNS failure, TLS error, or any other transport fault.
  transport,

  /// The bytes arrived but could not be decoded / re-encoded as an image.
  notAnImage,
}

/// Outcome of one bounded cover fetch.
sealed class CoverFetchResult {
  const CoverFetchResult();
}

/// The allow-listed body, complete and within the cap.
final class CoverFetched extends CoverFetchResult {
  /// Creates a success carrying the [bytes].
  const CoverFetched(this.bytes);

  /// Image bytes (raw from the fetcher; downscaled JPEG from the DI port).
  final List<int> bytes;
}

/// The fetch was refused or failed; no cover.
final class CoverRefused extends CoverFetchResult {
  /// Creates a refusal for [reason].
  const CoverRefused(this.reason);

  /// Which defence (or fault) refused the cover.
  final CoverRefusal reason;
}
