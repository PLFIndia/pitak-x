/// Pure validation for a Pitak **library ID** (PLAN-merge.md D40). A faithful
/// port of Kotlin `dev.khoj.pitaka.domain.model.LibraryId`.
///
/// The library ID is the random namespace token that says WHICH library an
/// export file belongs to, so a recipient's merge gate can decide
/// match-vs-decision. This is the single source of truth for the ID's string
/// shape: every path that ADOPTS or PERSISTS an ID — file merge (Join/Overwrite),
/// regenerate, manual paste — funnels through here so a hand-crafted or corrupt
/// export can never inject a malformed ID that would then propagate into every
/// future export.
///
/// Shape (matches how we mint them): 16–64 characters of lowercase hex
/// `[0-9a-f]`. We mint 32-char hex (16 random bytes via a CSPRNG). The bound is
/// deliberately a touch wider than 32 so a future longer token still validates,
/// but tight enough to reject oversized blobs, control characters, uppercase,
/// separators, and prefix-on-junk values.
///
/// Pure Dart: no Flutter/IO/Riverpod (AGENTS.md §3.1).
library;

/// Validation helpers for a Pitak library ID.
abstract final class LibraryId {
  /// Minimum length of a valid library ID.
  static const int minLen = 16;

  /// Maximum length of a valid library ID.
  static const int maxLen = 64;

  /// True when [id] has the shape of a Pitak-minted library ID
  /// (16–64 lowercase-hex characters, no whitespace or separators).
  static bool isValid(String id) {
    if (id.length < minLen || id.length > maxLen) return false;
    for (var i = 0; i < id.length; i++) {
      final c = id.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39; // 0-9
      final isLowerHex = c >= 0x61 && c <= 0x66; // a-f
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }

  /// Returns [id] trimmed when it is a valid library ID, or null otherwise.
  /// Trims surrounding whitespace only; the ID itself is never rewritten (a
  /// valid ID has no internal whitespace anyway).
  static String? normalizeOrNull(String id) {
    final trimmed = id.trim();
    return isValid(trimmed) ? trimmed : null;
  }
}
