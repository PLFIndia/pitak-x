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
/// `img-src` MUST mirror `allowedHosts` (+ `archiveNodePattern` as the
/// `*.us.archive.org` wildcard source). A snapshot test guards the lockstep.
///
/// D-3 (Session 13, verified on a device against the live service): Open
/// Library serves roughly half of its covers through a two-hop redirect,
/// `covers.openlibrary.org` → `archive.org/download/…` →
/// `ia<digits>.us.archive.org/view_archive.php?…` (a rotating pool of
/// Internet Archive storage nodes). The fetcher checks every hop against this
/// list, so until those hosts were admitted such covers silently stayed
/// placeholders. User decision: admit them. Privacy cost, stated in
/// PRIVACY.md: with the opt-in on, the Internet Archive can also see the
/// device's IP for those covers.
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
    // Internet Archive front door for Open Library's offloaded covers (D-3).
    'archive.org',
  };

  /// Internet Archive storage nodes that `archive.org/download/…` redirects
  /// to (D-3): exactly `ia` + digits + `.us.archive.org`, nothing else — not
  /// `web.archive.org`, not arbitrary `*.archive.org`. Anchored and
  /// case-insensitive; matched against the parsed host only, so userinfo /
  /// suffix tricks are handled by the URL checks before this runs.
  static final RegExp archiveNodePattern = RegExp(
    r'^ia[0-9]+\.us\.archive\.org$',
    caseSensitive: false,
  );

  /// The CSP `host-source` that admits [archiveNodePattern] hosts in the
  /// published viewer; the lockstep test checks it appears in `img-src`.
  static const String archiveNodeCspSource = 'https://*.us.archive.org';

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
    if (!allowedHosts.contains(host) && !archiveNodePattern.hasMatch(host)) {
      return null;
    }
    return trimmed;
  }
}
