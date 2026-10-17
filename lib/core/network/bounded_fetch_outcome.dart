/// Typed outcome of one bounded HTTP fetch (core; libNetwork.md D14/§5.12).
///
/// The generic `BoundedHttpFetcher` lives in `core/network` because TWO
/// features need the exact same security-critical behaviour (streaming byte
/// cap, abortable deadline, per-hop redirect re-validation): the publish cover
/// download and the network `library.json` descriptor fetch. D14: 150 lines of
/// security code are not copy-pasted — the shared fetcher returns THIS core
/// outcome, and each feature adapts it to its own domain result type
/// (`CoverFetchResult` for publish, `DescriptorFetchResult` for network).
///
/// Like `CoverRefusal`, [FetchRefusal] is a coarse developer diagnostic: it
/// never carries the URL, host, or response text.
library;

import 'dart:typed_data';

/// Why a bounded fetch was refused. Same reason set as the publish-domain
/// `CoverRefusal`, minus `notAnImage` (image decoding is a cover-specific step
/// that happens AFTER the fetch, in the publish adapter/DI).
enum FetchRefusal {
  /// The URL failed the caller's allow-list (scheme, userinfo or host).
  disallowedUrl,

  /// A redirect pointed outside the allow-list, or lacked a Location.
  redirectRefused,

  /// More redirect hops than the fetcher follows.
  tooManyRedirects,

  /// The final response was not 2xx.
  httpStatus,

  /// The body exceeded the byte cap (declared or actual).
  tooLarge,

  /// The whole request exceeded the deadline (and was aborted).
  timedOut,

  /// Connection reset, DNS failure, TLS error, or any other transport fault.
  transport,
}

/// Outcome of one bounded fetch.
sealed class BoundedFetchOutcome {
  const BoundedFetchOutcome();
}

/// The allow-listed body arrived, complete and within the cap.
final class FetchedBytes extends BoundedFetchOutcome {
  /// Creates a success carrying the [bytes].
  const FetchedBytes(this.bytes);

  /// The response body.
  final Uint8List bytes;
}

/// The fetch was refused or failed; no bytes.
final class FetchRefused extends BoundedFetchOutcome {
  /// Creates a refusal for [reason].
  const FetchRefused(this.reason);

  /// Which defence (or fault) refused the fetch.
  final FetchRefusal reason;
}
