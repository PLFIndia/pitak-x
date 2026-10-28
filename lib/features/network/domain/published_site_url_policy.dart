/// Where one published catalogue may live (network domain, pure Dart;
/// ADR 0015 V18, docs/ARCHITECTURE.md §5.6).
///
/// Why a second policy on top of `BookmarkUrl` (beginner note): the Pages
/// allow-list answers "may this host be contacted?". A saved library's own
/// payload needs a narrower answer — "is this address still MY library?".
/// Without it a saved site could redirect the viewer to another Pages host, or
/// to a different library's directory on the same host, and the app would
/// happily fetch unrelated (or tracking) content because the host was allowed.
///
/// So every catalogue request — the initial `<site>books.json` and every
/// redirect hop — must:
///  1. pass [BookmarkUrl.sanitize] (https, no userinfo, Pages host,
///     no non-default port);
///  2. keep the saved site's ORIGIN (scheme + host + effective port);
///  3. stay inside the saved site's DIRECTORY;
///  4. contain no query, fragment or backslash, and no `.`/`..` segment that
///     could be decoded later by the server (`%2e%2e`, `%2f`, …).
///
/// The site URL itself must already be canonical ([BookmarkUrl.normalize]
/// result), because that string is the family key and the identity everywhere
/// else. A corrupted row fails closed rather than guessing.
library;

import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// The "may this catalogue URL be requested for this saved library?" policy.
abstract final class PublishedSiteUrlPolicy {
  /// The exact `books.json` address for [siteUrl], or null when [siteUrl] is
  /// not an already-canonical, usable site root.
  static String? catalogueUrl(String siteUrl) =>
      _fileUrl(siteUrl, 'books.json');

  /// The exact `events.json` address for [siteUrl], or null under the same
  /// canonical-site rule as [catalogueUrl]. Events publish independently, so
  /// this is a sibling file rather than part of the catalogue payload.
  static String? eventsUrl(String siteUrl) => _fileUrl(siteUrl, 'events.json');

  static String? _fileUrl(String siteUrl, String fileName) {
    if (!_isCanonicalSiteRoot(siteUrl)) return null;
    return Uri.parse(siteUrl).resolve(fileName).toString();
  }

  /// Returns [candidate] (trimmed, verbatim) when it may be requested on
  /// behalf of the library saved at [siteUrl], else null.
  ///
  /// Verbatim matters: a redirect to `…/books.json` must be fetched exactly as
  /// given, never rewritten to the site root (same rule as the descriptor
  /// fetch).
  static String? sanitizeForSite(String siteUrl, String? candidate) {
    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final safe = BookmarkUrl.sanitize(trimmed);
    if (safe == null) return null;
    if (!_isCanonicalSiteRoot(siteUrl)) return null;

    final site = Uri.parse(siteUrl);
    final target = Uri.parse(safe);
    if (!_sameOrigin(site, target)) return null;
    if (target.hasQuery || target.hasFragment) return null;
    // A backslash is read as a path separator by some servers, which can turn
    // a "file" name into a directory escape.
    if (target.path.contains(r'\')) return null;

    final siteSegments = _pathSegments(site.path);
    final targetSegments = _pathSegments(target.path);
    if (siteSegments == null || targetSegments == null) return null;
    if (targetSegments.length < siteSegments.length) return null;
    for (var i = 0; i < siteSegments.length; i++) {
      if (targetSegments[i] != siteSegments[i]) return null;
    }
    return safe;
  }

  /// The PUBLISH read-back address for [path] under [siteUrl], or null.
  /// An empty [path] means the canonical root itself (used for moved pages).
  ///
  /// Why a separate entry point (Cloudflare plan R16): publish verification
  /// may append a generated `rb` cache-buster so a CDN cannot serve a stale
  /// copy of the file we JUST wrote. That is the ONLY relaxation, it is
  /// opt-in per call, and it never touches [sanitizeForSite] — the viewer's
  /// no-query rule stays exactly as it was.
  ///
  /// Every other rule is shared: canonical site root, same origin, inside the
  /// site's directory, no fragment, no backslash, no dot segments.
  static String? readBackUrl(
    String siteUrl,
    String path, {
    String? cacheBuster,
  }) {
    if (!_isCanonicalSiteRoot(siteUrl)) return null;
    if (path.isNotEmpty && !_isSafeRelativePath(path)) return null;
    final bare = path.isEmpty
        ? Uri.parse(siteUrl)
        : Uri.parse(siteUrl).resolve(path);
    // Containment is checked on the QUERY-FREE URL: `sanitizeForSite`
    // refuses queries by design (the viewer's rule), and re-checking the
    // exact same origin/directory is what matters here.
    final safe = sanitizeForSite(siteUrl, bare.toString());
    if (safe == null) return null;
    // The buster is a short opaque token chosen by the caller; anything that
    // could smuggle a second parameter or a fragment is refused.
    if (cacheBuster == null) return safe;
    if (!_isSafeQueryValue(cacheBuster)) return null;
    return Uri.parse(
      safe,
    ).replace(queryParameters: {'rb': cacheBuster}).toString();
  }

  /// A cache-buster value: 1–64 chars of `[A-Za-z0-9._-]`.
  static bool _isSafeQueryValue(String value) {
    if (value.isEmpty || value.length > 64) return false;
    for (final unit in value.codeUnits) {
      final ok =
          (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a) ||
          unit == 0x2e ||
          unit == 0x5f ||
          unit == 0x2d;
      if (!ok) return false;
    }
    return true;
  }

  /// A fixed, site-relative file path: 1–3 segments of `[A-Za-z0-9._-]`, no
  /// leading slash, no `..`/`.` segment, no backslash (R23's `SitePath` rule
  /// arrives in S5; this is the same rule for the read-back subset).
  static bool _isSafeRelativePath(String path) {
    if (path.isEmpty || path.length > 256) return false;
    if (path.startsWith('/') || path.contains(r'\')) return false;
    final segments = path.split('/');
    if (segments.length > 3) return false;
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') return false;
      for (final unit in segment.codeUnits) {
        final ok =
            (unit >= 0x30 && unit <= 0x39) ||
            (unit >= 0x41 && unit <= 0x5a) ||
            (unit >= 0x61 && unit <= 0x7a) ||
            unit == 0x2e ||
            unit == 0x5f ||
            unit == 0x2d;
        if (!ok) return false;
      }
    }
    return true;
  }

  /// The form `BoundedHttpFetcher` wants: one tear-off per site, applied to
  /// the initial URL and to every redirect `Location`.
  static String? Function(String?) sanitizerFor(String siteUrl) =>
      (candidate) => sanitizeForSite(siteUrl, candidate);

  /// True when [siteUrl] is exactly what [BookmarkUrl.normalize] would produce
  /// AND its path is a plain directory (no dot segments, no empty segments).
  static bool _isCanonicalSiteRoot(String siteUrl) {
    final canonical = BookmarkUrl.normalize(siteUrl);
    if (canonical == null || canonical != siteUrl) return false;
    final uri = Uri.parse(canonical);
    if (uri.hasQuery || uri.hasFragment) return false;
    if (!uri.path.endsWith('/')) return false;
    final segments = _pathSegments(uri.path);
    // A site root with a dot segment in its own path is not something this
    // build will resolve against: fail closed instead of guessing.
    return segments != null;
  }

  static bool _sameOrigin(Uri site, Uri target) {
    if (site.scheme.toLowerCase() != target.scheme.toLowerCase()) return false;
    if (site.host.toLowerCase() != target.host.toLowerCase()) return false;
    return site.port == target.port;
  }

  /// Decoded path segments, or null when the path is unsafe to reason about:
  /// no `.`/`..` survival, no empty interior segment, no encoded separator.
  ///
  /// Why decode (beginner note): a server resolves `%2e%2e` exactly like `..`.
  /// Comparing the raw encoded strings would let `/pitak/%2e%2e/other/` pass a
  /// prefix check and then escape the library's directory once the server
  /// decodes it.
  static List<String>? _pathSegments(String path) {
    if (!path.startsWith('/')) return null;
    final raw = path.split('/');
    // `path.split('/')` always yields a leading empty segment for an absolute
    // path; the trailing slash (if any) yields a final empty one, dropped
    // below because a directory boundary does not depend on it.
    final segments = <String>[];
    for (var i = 1; i < raw.length; i++) {
      final part = raw[i];
      if (part.isEmpty) {
        // A trailing empty segment is the directory slash; anything else is a
        // doubled slash that servers may normalize unpredictably.
        if (i == raw.length - 1) continue;
        return null;
      }
      // Two different kinds of bad escape, both refused:
      //  1. malformed SYNTAX (`%`, `%2`, `%zz`) — checked here so it never
      //     reaches a decoder at all;
      //  2. syntactically valid escapes whose BYTES are not valid UTF-8
      //     (`%FF`, overlong `%C0%AF`, a truncated multibyte sequence) — the
      //     decoder throws a `FormatException` for those, which we turn into a
      //     refusal. A path we cannot decode safely is not requestable.
      if (!_hasValidEscapes(part)) return null;
      final String decoded;
      try {
        decoded = Uri.decodeComponent(part);
      } on FormatException {
        // Narrow on purpose: only "these bytes are not UTF-8" is a refusal.
        // `Error`s and unexpected exceptions stay uncaught so a real bug is
        // never disguised as hostile input.
        return null;
      }
      if (decoded.isEmpty) return null;
      if (decoded == '.') continue;
      if (decoded == '..') {
        if (segments.isEmpty) return null;
        segments.removeLast();
        continue;
      }
      if (decoded.contains('/') || decoded.contains(r'\')) return null;
      segments.add(decoded);
    }
    return segments;
  }

  /// True when every `%` in [part] starts a two-hex-digit escape.
  static bool _hasValidEscapes(String part) {
    for (var i = 0; i < part.length; i++) {
      if (part.codeUnitAt(i) != 0x25) continue; // '%'
      if (i + 2 >= part.length) return false;
      if (!_isHex(part.codeUnitAt(i + 1))) return false;
      if (!_isHex(part.codeUnitAt(i + 2))) return false;
      i += 2;
    }
    return true;
  }

  static bool _isHex(int unit) =>
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      (unit >= 0x41 && unit <= 0x46) || // A-F
      (unit >= 0x61 && unit <= 0x66); // a-f
}
