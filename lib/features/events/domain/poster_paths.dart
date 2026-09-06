/// Poster image reference format (domain, single source of truth).
///
/// A stored poster reference is always `posters/<leaf>.jpg`; the files live
/// under `<appDocs>/posters/`. Declared in domain so the application layer
/// can validate refs without importing the file-IO repository.
library;

/// Path constants + helpers for poster image references.
///
/// N14: pure string validation only — the domain layer must not depend on
/// `package:path` (a platform-context library), and the check below needs no
/// more than the reference's own characters.
abstract final class PosterPaths {
  /// Directory (and reference prefix) poster images live under.
  static const String postersDir = 'posters';

  /// Reference prefix including the separator (`posters/`).
  static const String prefix = '$postersDir/';

  /// Extracts the bare file leaf from a valid `posters/<leaf>` [ref], or null
  /// when the ref is not in the poster namespace or tries to escape it
  /// (defence against a crafted ref reaching file IO).
  static String? leafOf(String ref) {
    if (!ref.startsWith(prefix)) return null;
    final leaf = ref.substring(prefix.length);
    // Exactly ONE path segment: no further separators, no traversal, no
    // protocol smuggling, nothing empty.
    if (leaf.isEmpty) return null;
    if (leaf.contains('/')) return null;
    if (leaf.contains(r'\')) return null;
    if (leaf.contains('..')) return null;
    if (leaf.contains(':')) return null;
    return leaf;
  }
}
