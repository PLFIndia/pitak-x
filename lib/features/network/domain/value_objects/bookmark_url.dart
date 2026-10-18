/// The published-site URL allow-list AND canonical form (network domain, pure
/// Dart; libNetwork.md §6 "URL" row, D13 "the URL is the identity").
///
/// ONE rule decides which addresses the network feature trusts, and it is
/// used at every boundary: adding a library by URL, parsing a scanned card
/// QR, decoding a fetched `library.json` (site URLs, member URLs, memberOf
/// URLs), validating redirect hops inside the bounded fetcher, and restoring
/// `network.json` rows from a backup.
///
/// Two jobs, two methods — keep them apart:
///
///  - `sanitize` — ALLOW-LIST ONLY. "May this exact URL be fetched?" Returns
///    the trimmed URL verbatim or null. The bounded fetcher applies it to the
///    initial URL and to every redirect `Location`, so it must never rewrite
///    the address it is asked about (a redirect to `…/library.json` has to
///    stay `…/library.json`).
///  - `normalize` — allow-list PLUS canonical SITE-ROOT form. "Which library
///    does this address name?" The result is the natural key stored in the
///    `network_libraries` table and compared everywhere, so two spellings of
///    one site must collapse to one string: `https://A.github.io/x`,
///    `https://a.github.io/x/`, `https://a.github.io/x/?utm=1` and
///    `https://a.github.io/x/#top` all become `https://a.github.io/x/`.
///    The trailing `/` is what makes `Uri.resolve('library.json')` land on
///    `…/x/library.json` instead of the parent directory (§5.6).
///
/// History: this class started life in the old bookmarks feature
/// (`features/bookmarks/domain/library_bookmark.dart`). ADR 0012 replaced
/// bookmarks with the network feature, so the allow-list moved here — the
/// class name is unchanged because the spec (§6) references it.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

/// Validates (+ canonicalizes) a library site URL.
///
/// Policy (strict, mirrors `CoverUrlAllowList` hardening): `https` only; host
/// must be `github.io`/`*.github.io` or `pages.dev`/`*.pages.dev` (the only
/// places a Pitak catalogue is published); no userinfo (`https://x@host`)
/// credentials; no explicit port other than 443. Everything else → rejected.
/// Custom domains are intentionally NOT accepted.
abstract final class BookmarkUrl {
  /// Hosts (suffixes) allowed for a network library. A host matches when it
  /// equals one of these or ends with `.` + one of these (so
  /// `foo.github.io` is allowed, `github.io.evil.com` is not).
  static const Set<String> allowedHostSuffixes = {'github.io', 'pages.dev'};

  /// Length cap (libNetwork.md §6 "URL" row): a legitimate Pages address is
  /// far shorter; the cap bounds the work every parser does on a hostile
  /// string (a multi-megabyte "URL" from a QR code or descriptor is refused
  /// before `Uri.tryParse` ever sees it).
  static const int maxLength = 2048;

  /// The one file name a pasted site address may end with and still mean
  /// "the site root": `https://x.github.io/lib/index.html` IS the site at
  /// `https://x.github.io/lib/` (Pages serves `index.html` for the directory).
  static const String _indexFile = 'index.html';

  /// ALLOW-LIST ONLY: returns [raw] trimmed when it is an acceptable Pages
  /// address, otherwise null. The URL is returned verbatim — use this where
  /// the exact address matters (the fetcher's initial URL and redirect hops).
  static String? sanitize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) return null;
    return _parseAllowed(trimmed) == null ? null : trimmed;
  }

  /// ALLOW-LIST + CANONICAL SITE ROOT: returns the one spelling of the site
  /// [raw] names, or null when [raw] is not an acceptable Pages address.
  ///
  /// Canonical form (every step is a deliberate "same site, one key" rule):
  ///  1. scheme and host lower-cased (both are case-insensitive by RFC 3986;
  ///     the PATH is case-sensitive on GitHub Pages and is kept as typed);
  ///  2. query (`?…`) and fragment (`#…`) dropped — a site root has neither,
  ///     and a hostile descriptor could otherwise mint unlimited "different"
  ///     rows for one site (`…/x/?1`, `…/x/?2`, …);
  ///  3. a trailing `index.html` segment dropped (same page as the directory);
  ///  4. a trailing `/` guaranteed — a site URL is a DIRECTORY, so
  ///     `Uri.resolve('library.json')` lands inside it, not beside it.
  static String? normalize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) return null;

    final uri = _parseAllowed(trimmed);
    if (uri == null) return null;

    final segments = [...uri.pathSegments];
    // `Uri.pathSegments` of "/x/" is ["x", ""] — the empty tail is the
    // trailing slash; "/x/index.html" is ["x", "index.html"]. Strip both so
    // the loop below can rebuild one canonical directory path.
    while (segments.isNotEmpty &&
        (segments.last.isEmpty || segments.last == _indexFile)) {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';

    // Rebuilt from parts, not patched as a string: `Uri` re-encodes the
    // path consistently (e.g. a stray space becomes `%20` exactly once), and
    // userinfo/query/fragment are simply not carried over.
    return Uri(
      scheme: 'https',
      host: uri.host.toLowerCase(),
      path: path,
    ).toString();
  }

  /// True when [normalize] would accept [raw].
  static bool isValid(String? raw) => normalize(raw) != null;

  /// The shared allow-list check: a parsed [Uri] when [trimmed] is an
  /// https, credential-free, default-port, allow-listed-host address; null
  /// otherwise. Both public methods go through here so the policy cannot
  /// drift between "may fetch" and "may store".
  static Uri? _parseAllowed(String trimmed) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null; // reject https://user@host/…
    if (!uri.hasAuthority) return null;
    // An explicit port other than 443 is never a Pages site — refuse it
    // (fail closed). `:443` itself is the https default, which `Uri` folds
    // away, so `https://x.github.io:443/` and `https://x.github.io/` agree.
    if (uri.hasPort && uri.port != 443) return null;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    if (!_hostAllowed(host)) return null;
    return uri;
  }

  static bool _hostAllowed(String host) {
    for (final suffix in allowedHostSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) return true;
    }
    return false;
  }
}
