/// Bookmarks feature — pure domain (AGENTS.md §3.1).
///
/// A bookmark is a user-saved link to ANOTHER library's published site, with a
/// label. URLs are restricted to GitHub Pages / Cloudflare Pages hosts (the only
/// places a Pitak catalogue is published), validated by [BookmarkUrl] — the
/// single source of truth for what a bookmark may point at. Pure Dart: no
/// Flutter/IO/Riverpod.
library;

/// Validates + normalizes a library bookmark URL.
///
/// Policy (strict, mirrors `CoverUrlAllowList` hardening): `https` only; host
/// must be `github.io`/`*.github.io` or `pages.dev`/`*.pages.dev`; no userinfo
/// (`https://x@host`) credentials. Everything else → rejected. Custom domains
/// are intentionally NOT accepted.
abstract final class BookmarkUrl {
  /// Hosts (suffixes) allowed for a bookmark. A host matches when it equals one
  /// of these or ends with `.` + one of these (so `foo.github.io` is allowed,
  /// `github.io.evil.com` is not).
  static const Set<String> allowedHostSuffixes = {'github.io', 'pages.dev'};

  /// Returns the normalized URL string when [raw] is an accepted Pages link,
  /// otherwise null. Normalization is just a trim — the URL is kept verbatim
  /// otherwise so it round-trips exactly.
  static String? normalize(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;

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

/// One saved library bookmark: a [label] + an accepted [url].
final class LibraryBookmark {
  /// Creates a bookmark from already-validated values (e.g. JSON round-trip).
  const LibraryBookmark({required this.label, required this.url});

  /// Maximum label length (a short name, not prose).
  static const int maxLabelLength = 80;

  /// User-facing name for the link.
  final String label;

  /// The accepted `https://…github.io|pages.dev/…` URL.
  final String url;

  /// Builds a bookmark, validating + bounding the label and validating the URL
  /// against [BookmarkUrl]. Returns null when the URL is not an accepted Pages
  /// link or the label is blank / too long.
  static LibraryBookmark? create({required String label, required String url}) {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) return null;
    if (trimmedLabel.length > maxLabelLength) return null;
    final normalized = BookmarkUrl.normalize(url);
    if (normalized == null) return null;
    return LibraryBookmark(label: trimmedLabel, url: normalized);
  }

  /// JSON map.
  Map<String, dynamic> toJson() => {'label': label, 'url': url};

  /// Parses one bookmark from JSON, re-validating, or null when invalid.
  static LibraryBookmark? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final label = json['label'];
    final url = json['url'];
    if (label is! String || url is! String) return null;
    return create(label: label, url: url);
  }
}
