/// How a book cover is referenced. Pure Dart port of Kotlin `CoverPaths`.
///
/// A user-supplied cover lives on disk as `<filesDir>/covers/<uuid>.jpg` and
/// the row's `coverUrl` holds the relative reference `covers/<uuid>.jpg`. Three
/// shapes exist in the wild:
///  - new relative: `covers/<uuid>.jpg`
///  - legacy absolute: `file:///…/covers/<id>.jpg`
///  - remote: `https://…` (NOT local)
///
/// Pure (no IO) so it is trivially testable; callers pass an explicit base dir.
library;

/// Single source of truth for cover-reference classification + safe leaf
/// extraction (zip-slip / traversal defence for the bundle reader).
abstract final class CoverPaths {
  /// Sub-directory under the app docs dir where covers live.
  static const String coversDir = 'covers';

  /// Prefix of a new-style relative cover reference.
  static const String prefix = 'covers/';

  /// True when [coverUrl] points at a cover in our own app storage — the new
  /// relative form or a legacy `file://` form. Remote `http(s)://` is NOT
  /// local. Blank/null → false. (Kotlin `CoverPaths.isLocal`.)
  static bool isLocal(String? coverUrl) {
    final s = coverUrl?.trim() ?? '';
    if (s.isEmpty) return false;
    if (s.startsWith(prefix)) return true;
    if (s.startsWith('file://')) return true;
    return false;
  }

  /// Returns the validated remote cover URL when [coverUrl] is a fetchable
  /// `https://` reference, or null otherwise.
  ///
  /// Privacy/security (#31, AGENTS §2a.4): only `https://` is ever returned —
  /// `http://` is rejected so cover traffic is never sent in the clear. Local
  /// references (`covers/`, `file://`) and blank/null are NOT remote. The
  /// caller still gates fetching on the user's opt-in Settings switch; this
  /// method only classifies + enforces the transport rule.
  static String? remoteUrlOf(String? coverUrl) {
    final s = coverUrl?.trim() ?? '';
    if (s.isEmpty) return null;
    if (isLocal(s)) return null;
    if (!s.startsWith('https://')) return null;
    return s;
  }

  /// Extracts the validated leaf filename from a local cover reference, or null
  /// when [coverUrl] is not a safe local reference. Rejects path traversal,
  /// nested directories, and protocol smuggling (Kotlin `CoverPaths.leafOf`).
  static String? leafOf(String? coverUrl) {
    final s = coverUrl?.trim() ?? '';
    if (s.isEmpty) return null;
    final String leaf;
    if (s.startsWith(prefix)) {
      leaf = s.substring(prefix.length);
    } else if (s.startsWith('file://')) {
      leaf = s.split('/').last;
    } else {
      return null;
    }
    if (leaf.isEmpty) return null;
    if (leaf.contains('..')) return null;
    if (leaf.contains('/')) return null;
    if (leaf.contains(':')) return null;
    return leaf;
  }
}
