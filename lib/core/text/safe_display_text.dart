/// ONE rule for text this app renders from an untrusted source (core, pure
/// Dart).
///
/// Why (beginner note): a name can arrive from a fetched `library.json`, a
/// scanned card, a backup archive or the Cloudflare API. Some characters are
/// invisible but change what the user reads:
///  - C0 controls (`\n`, `\t`, NUL, …) and DEL: they hide or mangle text in
///    logs and terminals;
///  - C1 controls (U+0080–U+009F): terminal/format control characters;
///  - U+200B–U+200F: zero-width space/non-joiner/joiner and the bidi marks;
///  - U+202A–U+202E and U+2066–U+2069: bidi embedding, override and isolate
///    controls — the "Trojan Source" trick that can VISUALLY REORDER a string
///    so a hostile name reads as something it is not;
///  - U+2028/U+2029: line and paragraph separators that some renderers treat
///    as a newline;
///  - U+FEFF: a zero-width no-break space (byte-order mark) that hides at the
///    start of a name.
///
/// This helper is the ONE copy of that list. `NetworkName` uses it for library
/// names and `CloudflareAccount` for account display names, so the two cannot
/// drift (fix-plan L14). Length bounds stay with each caller: they are about a
/// field's meaning, not about what is safe to draw.
library;

/// A shared, side-effect-free text rule.
abstract final class SafeDisplayText {
  /// True when [value] contains no character this app refuses to render.
  static bool isSafe(String value) {
    for (final unit in value.codeUnits) {
      if (_isForbidden(unit)) return false;
    }
    return true;
  }

  /// The first forbidden code unit in [value], or null when it is safe.
  ///
  /// Tests use this to prove which character made a name unsafe without
  /// echoing the name itself.
  static int? firstForbiddenUnit(String value) {
    for (final unit in value.codeUnits) {
      if (_isForbidden(unit)) return unit;
    }
    return null;
  }

  static bool _isForbidden(int unit) =>
      unit < 0x20 || // C0 controls
      unit == 0x7f || // DEL
      (unit >= 0x80 && unit <= 0x9f) || // C1 controls
      (unit >= 0x200b && unit <= 0x200f) || // zero-width + bidi marks
      (unit >= 0x202a && unit <= 0x202e) || // bidi embedding/override
      unit == 0x2028 || // line separator
      unit == 0x2029 || // paragraph separator
      (unit >= 0x2066 && unit <= 0x2069) || // bidi isolate controls
      unit == 0xfeff; // zero-width no-break space / BOM
}
