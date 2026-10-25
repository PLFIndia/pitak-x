/// Which cover URL the viewer may request, and under which policy (network
/// domain, pure Dart; ADR 0015 V11/V18, viewer plan S5).
///
/// Two origin classes, each with its own rule set:
///
///  - **Same-site** — a relative `covers/<leaf>` reference produced by the
///    Pitak publisher. It resolves against the saved site root and must stay
///    inside that site's origin AND directory, including on every redirect.
///  - **Third-party** — an absolute https URL, accepted ONLY when it is on the
///    existing cover allow-list (`CoverUrlAllowList.remoteHttpsOf`), and every
///    redirect hop must pass `CoverUrlAllowList.sanitize` again (that keeps the
///    Open Library → Internet Archive path working).
///
/// A Pages URL does NOT become an allowed absolute cover merely because it is
/// on a Pages host: an absolute reference is always classified as third-party
/// and must pass the cover allow-list. Likewise a same-site cover can never
/// wander into another library or another Pages host.
///
/// Consent is a SEPARATE gate (the scheduler's): this resolver only answers
/// "may this reference be requested at all?".
library;

import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// One requestable cover, with the sanitizer its redirects must pass.
sealed class PublishedCoverRequest {
  const PublishedCoverRequest();

  /// The absolute URL to request.
  Uri get uri;

  /// The absolute URL as a string (the dedupe/cache key).
  String get url => uri.toString();

  /// Re-validates one URL for this request's class (initial URL and every
  /// redirect hop). Returns the verbatim URL to fetch, or null to refuse.
  String? sanitize(String? candidate);
}

/// A cover served by the SAVED library's own site.
final class SameSiteCoverRequest extends PublishedCoverRequest {
  /// Creates a same-site request for [uri] belonging to [siteUrl].
  const SameSiteCoverRequest(this.uri, this.siteUrl);

  @override
  final Uri uri;

  /// The saved site root the reference resolved against.
  final String siteUrl;

  @override
  String? sanitize(String? candidate) =>
      PublishedSiteUrlPolicy.sanitizeForSite(siteUrl, candidate);
}

/// A cover served by an allow-listed public cover host (Open Library, Google
/// Books, the Internet Archive).
final class ThirdPartyCoverRequest extends PublishedCoverRequest {
  /// Creates a third-party request for [uri] (already allow-listed).
  const ThirdPartyCoverRequest(this.uri);

  @override
  final Uri uri;

  @override
  String? sanitize(String? candidate) => CoverUrlAllowList.sanitize(candidate);
}

/// Classifies a published cover reference, or returns null when it must never
/// be requested.
abstract final class PublishedCoverResolver {
  /// The prefix the Pitak publisher writes for a bundled cover.
  static const String sameSitePrefix = 'covers/';

  /// Resolves [rawCoverUrl] against the saved site root [siteUrl].
  static PublishedCoverRequest? resolve(String siteUrl, String? rawCoverUrl) {
    final trimmed = rawCoverUrl?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith(sameSitePrefix)) {
      // Reuse the publisher's own reference sanitizer first (leaf only, no
      // traversal, no nesting) — then prove the RESOLVED url is still inside
      // this library.
      final reference = CoverUrlAllowList.sanitize(trimmed);
      if (reference == null) return null;
      // `Uri.resolve` turns a backslash into a path separator, so a raw one
      // would silently become a nested path. A query/fragment smuggled into
      // the leaf must not become a request parameter either. The publisher
      // writes a bare `covers/<leaf>`, so any of these is a refusal.
      if (reference.contains(r'\') ||
          reference.contains('?') ||
          reference.contains('#')) {
        return null;
      }
      final resolved = Uri.tryParse(siteUrl)?.resolve(reference);
      if (resolved == null) return null;
      final safe = PublishedSiteUrlPolicy.sanitizeForSite(
        siteUrl,
        resolved.toString(),
      );
      if (safe == null) return null;
      return SameSiteCoverRequest(Uri.parse(safe), siteUrl);
    }

    // Everything absolute must be on the existing third-party cover list.
    final absolute = CoverUrlAllowList.remoteHttpsOf(trimmed);
    if (absolute == null) return null;
    final uri = Uri.tryParse(absolute);
    if (uri == null) return null;
    // The shared cover allow-list does not police ports; a cover does not need
    // one, so a non-default port is refused (fail closed).
    if (uri.hasPort && uri.port != 443) return null;
    return ThirdPartyCoverRequest(uri);
  }
}
