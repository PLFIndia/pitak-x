/// Cover-URL sanitiser for published JSON (pure domain, AGENTS.md §3.1, #32).
///
/// Port of Kotlin `CoverUrlAllowList` (F-09). Threat: a poisoned `coverUrl`
/// silently exfiltrates every visitor of the published page (IP/UA/Referer) via
/// a cross-origin `<img src>`. HTML-escaping stops scripts but not image loads,
/// so origins must be allow-listed.
///
/// Policy: allow only relative `covers/…` paths produced by the publisher, and
/// https URLs to a tight host allow-list. Everything else → null (cover
/// dropped; the viewer falls back to a placeholder).
///
/// This is the single source of truth for cover origins; the viewer's CSP
/// `img-src` MUST mirror `allowedHosts`. A snapshot test guards the lockstep.
///
/// M09: the same host policy governs the on-device display path. A book's
/// remote cover is fetched (once, then stored as a local cover) only when
/// `CoverUrlAllowList.remoteHttpsOf` accepts it — so `PRIVACY.md`'s "fixed
/// allow-list of cover hosts" holds for every packet the app sends for
/// covers, not just publish.
library;

/// Sanitises cover URLs against the publish allow-list.
abstract final class CoverUrlAllowList {
  /// Hosts allowed for remote cover URLs. Case-insensitive exact match;
  /// subdomains are NOT implicitly allowed.
  static const Set<String> allowedHosts = {
    'covers.openlibrary.org',
    'books.google.com',
    'books.googleusercontent.com',
  };

  /// Returns [raw] when safe to publish, otherwise null.
  static String? sanitize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

    // Locally-produced bundled covers. Reject traversal / nesting / smuggling.
    if (trimmed.startsWith('covers/')) {
      final rest = trimmed.substring('covers/'.length);
      if (rest.isEmpty) return null;
      if (rest.contains('..')) return null;
      if (rest.contains('/')) return null;
      if (rest.contains(':')) return null;
      return trimmed;
    }

    return _allowListedHttps(trimmed);
  }

  /// Returns the trimmed URL when [raw] is a FETCHABLE remote cover — https,
  /// no userinfo, host exactly on [allowedHosts] — otherwise null. Unlike
  /// [sanitize] it never accepts a local `covers/…` path: this is the question
  /// "may the device send a request for this?", and local refs are not
  /// requests.
  static String? remoteHttpsOf(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return _allowListedHttps(trimmed);
  }

  static String? _allowListedHttps(String trimmed) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null; // reject https://x@host/…
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    if (!allowedHosts.contains(host)) return null;
    return trimmed;
  }
}
