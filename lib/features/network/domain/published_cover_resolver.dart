/// Which cover URL the viewer may request, and under which policy (network
/// domain, pure Dart; ADR 0015 V11/V18, viewer plan S5).
///
/// Two origin classes, each with its own rule set:
///
///  - **Same-site** — a relative `covers/<leaf>` reference produced by the
///    Pitak publisher. It resolves against the saved site root and must stay
///    inside that site's origin AND directory, including on every redirect.
///  - **Third-party** — an absolute https URL, accepted ONLY when it is on the
///    existing cover allow-list (`CoverUrlAllowList.remoteHttpsOf`), with no
///    explicit port other than 443, and every redirect hop must pass the same
///    rule again (that keeps the Open Library → Internet Archive path working).
///    Fragments are discarded before the URL is requested or used as a cache
///    key, so `#a`/`#b` variants collapse into one request.
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
  String? sanitize(String? candidate) => _sanitizeThirdPartyCover(candidate);
}

/// The ONE policy for a third-party cover URL — the initial reference and
/// every redirect hop, so the two can never drift apart.
///
/// Three steps, in this order:
///  1. the shared publish allow-list answers "may this URL be requested at
///     all?": https only, no userinfo, host on [CoverUrlAllowList.allowedHosts]
///     (or an Internet Archive storage node);
///  2. the VIEWER's extra rule: a cover needs no port, so any explicit port
///     other than 443 is refused. This deliberately stays here — putting it in
///     the shared list would silently change publishing and local covers;
///  3. canonicalisation: the fragment is REMOVED (not rejected) and the
///     fragment-free URL is both requested and used as the cache key.
///
/// Why discard rather than reject the fragment (beginner note): an HTTP client
/// never sends the bit after `#`, so `cover.jpg#a` and `cover.jpg#b` would
/// download the same bytes under two cache keys — one wasted download and a
/// duplicate entry. Discarding makes them one request, one key, one image.
String? _sanitizeThirdPartyCover(String? candidate) {
  final allowListed = CoverUrlAllowList.remoteHttpsOf(candidate);
  if (allowListed == null) return null;
  final uri = Uri.tryParse(allowListed);
  if (uri == null) return null;
  if (uri.hasPort && uri.port != 443) return null;
  // Path and query are preserved: the Internet Archive redirect needs its
  // `?…` parameters, so `removeFragment` (not "rebuild from host") is the
  // only safe canonicalisation.
  return uri.removeFragment().toString();
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

    // Everything absolute must be on the existing third-party cover list. The
    // SAME helper the redirects use decides the initial request too, so an
    // initial URL can never be more permissive than a later hop.
    final canonical = _sanitizeThirdPartyCover(trimmed);
    if (canonical == null) return null;
    return ThirdPartyCoverRequest(Uri.parse(canonical));
  }
}
