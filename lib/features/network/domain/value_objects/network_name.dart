/// Validation for library names that cross a trust boundary (network domain,
/// pure Dart; docs/ARCHITECTURE.md §5.6 "Name").
///
/// A network name arrives from hostile sources: a fetched `library.json`, a
/// scanned card QR, a backup archive entry. It is rendered in lists, map pin
/// sheets and dialogs, so the rules are strict:
///  - 1–80 characters after trimming (a name, not prose — same bound the old
///    bookmark label used);
///  - no character refused by the SHARED display-text rule.
///
/// That forbidden-character rule lives in `core/text/safe_display_text.dart`
/// and is shared with Cloudflare account names (fix-plan L14): C0/C1 controls,
/// DEL, zero-width and bidi characters, line/paragraph separators and U+FEFF
/// are refused because they can hide or VISUALLY REORDER a string (the classic
/// "Trojan Source" trick) — the single most important rejection here.
library;

import 'package:pitaka/core/text/safe_display_text.dart';

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
    // One shared rule for untrusted display text (fix-plan L14); this type
    // supplies only its own length bound.
    if (!SafeDisplayText.isSafe(trimmed)) return null;
    return trimmed;
  }

  /// True when [normalizeOrNull] would accept [raw].
  static bool isValid(String? raw) => normalizeOrNull(raw) != null;
}
