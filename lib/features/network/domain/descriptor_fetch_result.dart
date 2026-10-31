/// Typed outcome of fetching + parsing one `library.json` (network domain,
/// pure Dart; docs/ARCHITECTURE.md §5).
///
/// Same shape as the publish-side `CoverFetchResult`: a sealed result the
/// refresh use case folds into per-row `FetchStatus`es, with a COARSE refusal
/// enum that never carries the URL or response text (§6: refusal reasons are
/// developer diagnostics, not user data).
library;

import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';

/// Why a descriptor fetch/parse was refused. The transport half mirrors the
/// core `FetchRefusal` set 1:1; [invalid] and [schemaTooNew] are added by the
/// `LibraryDescriptorCodec` parse step.
enum DescriptorRefusal {
  /// The URL failed the `BookmarkUrl` allow-list.
  disallowedUrl,

  /// A redirect pointed outside the allow-list, or lacked a Location.
  redirectRefused,

  /// More redirect hops than the fetcher follows.
  tooManyRedirects,

  /// The final response was not 2xx, and not 404/410 (for example a server
  /// error, a rate limit or a refused request): "try again later".
  httpStatus,

  /// The host answered 404 or 410: this address serves no `library.json` at
  /// all (a site that never published one, or a Pitak moved page after a
  /// completed move). Unlike [httpStatus] this is a POSITIVE answer about the
  /// address, which is why it may replace a stale identity-conflict badge
  /// (handoff §12, decided 2026-10-31). Never produced by the parse step.
  notPublished,

  /// The body exceeded the 64 KiB descriptor cap.
  tooLarge,

  /// The whole request exceeded the 15 s deadline.
  timedOut,

  /// Transport fault (DNS, TLS, reset, …).
  transport,

  /// Bytes arrived but did not decode to a valid schema-1 descriptor.
  invalid,

  /// The descriptor declares a newer schema than this build can read.
  schemaTooNew,

  /// WRITE-side refusal (never produced by a fetch): the descriptor to
  /// encode would exceed the 64 KiB body cap, so every peer would refuse it
  /// in full. The publish fails instead of uploading an unreadable file.
  contentTooLarge,
}

/// Outcome of one descriptor fetch.
sealed class DescriptorFetchResult {
  const DescriptorFetchResult();
}

/// A complete, validated descriptor arrived.
final class DescriptorFetched extends DescriptorFetchResult {
  /// Creates a success carrying the [descriptor].
  const DescriptorFetched(this.descriptor);

  /// The parsed `library.json`.
  final LibraryDescriptor descriptor;
}

/// The fetch or parse was refused; no descriptor.
final class DescriptorRefused extends DescriptorFetchResult {
  /// Creates a refusal for [reason].
  const DescriptorRefused(this.reason);

  /// Which defence (or fault) refused.
  final DescriptorRefusal reason;
}
