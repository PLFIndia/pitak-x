/// The ONE publish path policy (publish domain, pure Dart; Cloudflare plan
/// R23).
///
/// Why one type instead of a private regex per host (beginner note): a path is
/// the difference between writing `covers/x.jpg` inside the site and writing
/// somewhere else entirely. GitHub, Cloudflare and the section merge all take
/// paths from the same builders, so they must agree on what a legal path is —
/// otherwise a path the merge accepted could be rejected mid-upload (or, worse,
/// be interpreted differently by two hosts). Before S5 the rule existed twice:
/// a private check in `publish_section.dart` and a regex in
/// `github_pages_url.dart`. Both now delegate here.
///
/// What is accepted (R23):
///  - relative — no leading `/`;
///  - non-empty, at most `SitePath.maxLength` characters;
///  - one or more `/`-separated segments, each non-empty and made ONLY of
///    `[A-Za-z0-9._-]`;
///  - no `.` or `..` segment (so `a/../b` cannot escape the site root);
///  - no backslash, no control character, no space.
///
/// The charset is an allow-list, which is what makes the rest automatic: `%`
/// is not allowed, so an ENCODED separator (`%2F`, `%2e%2e`) can never be
/// smuggled in; a non-ASCII name, a `?`/`#`, a `:` or a NUL byte is refused
/// for the same reason. Nothing here "fixes" a bad path by rewriting it —
/// callers get null and refuse the publish, because a silently repaired path
/// is a different file than the one the builder meant to write.
///
/// The leading-slash mapping Cloudflare's upload API needs (`books.json` →
/// `/books.json`) deliberately does NOT live here (plan B.2): only the
/// Cloudflare HTTP adapter may add it, so no other caller can start sending
/// absolute paths.
library;

/// One validated site-relative publish path.
final class SitePath {
  const SitePath._(this.value);

  /// Longest path this app will publish, in UTF-16 code units.
  ///
  /// Every path Pitak builds is short (fixed file names and 44-character
  /// salted cover ids), so this bound exists to cap the work a hostile record
  /// can cause, not to allow long ones. A longer path is refused.
  static const int maxLength = 512;

  /// The path exactly as validated (`books.json`, `covers/<sha>.jpg`).
  final String value;

  /// Validates [raw]; null when it is not a legal publish path.
  ///
  /// Returns the value unchanged — no trimming, no slash normalization. A
  /// caller with a pasted string must trim it first, deliberately.
  static SitePath? tryParse(String? raw) {
    if (raw == null || raw.isEmpty || raw.length > maxLength) return null;
    if (raw.startsWith('/') || raw.contains(r'\')) return null;
    for (final segment in raw.split('/')) {
      if (!_isSegment(segment)) return null;
    }
    return SitePath._(raw);
  }

  /// True when [raw] is a legal publish path.
  static bool isValid(String? raw) => tryParse(raw) != null;

  /// The extension of the last segment without its dot, or null when it has
  /// none.
  ///
  /// "None" covers `README` (no dot) and `.gitignore`/`trailing.` (an empty
  /// stem or an empty extension). Case is PRESERVED in [value]; callers that
  /// need Cloudflare's content type or asset hash decide what to do with it
  /// (R23/B.7: the hash formula keeps case, the content-type allow-list is
  /// case-sensitive on purpose).
  String? get extension {
    final last = value.split('/').last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return null;
    return last.substring(dot + 1);
  }

  /// The path as the site root sees it, e.g. `covers/x.jpg`.
  ///
  /// Identity is the string: two `SitePath`s are the same path when their
  /// [value] matches (`==` is deliberately not overridden in this pure
  /// domain, matching `GitHubPublishTarget`).
  @override
  String toString() => value;

  /// One segment: non-empty, not `.`/`..`, only `[A-Za-z0-9._-]`.
  static bool _isSegment(String segment) {
    if (segment.isEmpty || segment == '.' || segment == '..') return false;
    for (final unit in segment.codeUnits) {
      if (!_isAllowedUnit(unit)) return false;
    }
    return true;
  }

  /// True for ASCII letters, digits, `.`, `-` and `_` — the whole charset.
  static bool _isAllowedUnit(int unit) =>
      (unit >= 0x61 && unit <= 0x7a) || // a-z
      (unit >= 0x41 && unit <= 0x5a) || // A-Z
      (unit >= 0x30 && unit <= 0x39) || // 0-9
      unit == 0x2e || // .
      unit == 0x2d || // -
      unit == 0x5f; // _
}
