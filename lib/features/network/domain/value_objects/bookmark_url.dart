/// The published-site URL allow-list (network domain, pure Dart;
/// libNetwork.md §6 "URL" row).
///
/// ONE rule decides which addresses the network feature trusts, and it is
/// used at every boundary: adding a library by URL, parsing a scanned card
/// QR, decoding a fetched `library.json` (site URLs, member URLs, memberOf
/// URLs), validating redirect hops inside the bounded fetcher, and restoring
/// `network.json` rows from a backup.
///
/// History: this class started life in the old bookmarks feature
/// (`features/bookmarks/domain/library_bookmark.dart`). ADR 0012 replaced
/// bookmarks with the network feature, so the allow-list moved here — the
/// class name is unchanged because the spec (§6) references it.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

/// Validates + normalizes a library site URL.
///
/// Policy (strict, mirrors `CoverUrlAllowList` hardening): `https` only; host
/// must be `github.io`/`*.github.io` or `pages.dev`/`*.pages.dev` (the only
/// places a Pitak catalogue is published); no userinfo (`https://x@host`)
/// credentials. Everything else → rejected. Custom domains are intentionally
/// NOT accepted.
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

  /// Returns the normalized URL string when [raw] is an accepted Pages link,
  /// otherwise null. Normalization is just a trim — the URL is kept verbatim
  /// otherwise so it round-trips exactly.
  static String? normalize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null; // reject https://user@host/…
    if (!uri.hasAuthority) return null;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;
    if (!_hostAllowed(host)) return null;

    return trimmed;
  }

  /// True when [normalize] would accept [raw].
  static bool isValid(String? raw) => normalize(raw) != null;

  static bool _hostAllowed(String host) {
    for (final suffix in allowedHostSuffixes) {
      if (host == suffix || host.endsWith('.$suffix')) return true;
    }
    return false;
  }
}
