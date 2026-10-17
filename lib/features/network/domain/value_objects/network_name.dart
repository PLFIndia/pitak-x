/// Validation for library names that cross a trust boundary (network domain,
/// pure Dart; libNetwork.md §6 "Name" row).
///
/// A network name arrives from hostile sources: a fetched `library.json`, a
/// scanned card QR, a backup archive entry. It is rendered in lists, map pin
/// sheets and dialogs, so the rules are strict:
///  - 1–80 characters after trimming (a name, not prose — same bound the old
///    bookmark label used);
///  - no C0 control characters (code units < 0x20) and no DEL (0x7F): they
///    can hide or mangle text in logs and terminals;
///  - no Unicode bidi embedding/override characters (U+202A–U+202E) and no
///    bidi isolate controls (U+2066–U+2069): these can VISUALLY REORDER a
///    string, letting a hostile name read as something it is not (the classic
///    "Trojan Source" trick) — the single most important rejection here.
library;

/// Normalizes and validates a library name for network use.
abstract final class NetworkName {
  /// Minimum length after trimming.
  static const int minLength = 1;

  /// Maximum length after trimming (UTF-16 code units, matching the bound the
  /// old `LibraryBookmark.maxLabelLength` used).
  static const int maxLength = 80;

  /// Returns [raw] trimmed when it is an acceptable network name, or null
  /// when it is blank, too long, or contains a forbidden character (§6).
  static String? normalizeOrNull(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null) return null;
    if (trimmed.length < minLength || trimmed.length > maxLength) return null;
    for (var i = 0; i < trimmed.length; i++) {
      if (_isForbidden(trimmed.codeUnitAt(i))) return null;
    }
    return trimmed;
  }

  /// True when [normalizeOrNull] would accept [raw].
  static bool isValid(String? raw) => normalizeOrNull(raw) != null;

  static bool _isForbidden(int c) =>
      c < 0x20 || // C0 controls (\n, \t, NUL, …)
      c == 0x7F || // DEL
      (c >= 0x202A && c <= 0x202E) || // bidi embeddings/overrides
      (c >= 0x2066 && c <= 0x2069); // bidi isolate controls
}
