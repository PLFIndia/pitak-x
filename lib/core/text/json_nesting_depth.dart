/// String-aware JSON nesting-depth scan (core text helper, pure Dart).
///
/// Why this exists (beginner note): `jsonDecode` is a recursive-descent parser.
/// A hostile file made of tens of thousands of `[[[[…` opens a stack frame per
/// bracket and can crash the app before the document is even understood. Both
/// wire readers (`library.json` and `books.json`) therefore scan the TEXT for
/// its deepest bracket nesting and refuse the file when the limit is exceeded —
/// a plain loop with two counters costs one pass and allocates nothing.
///
/// The scan is STRING-AWARE: `{`/`[` inside a quoted value must not count, or a
/// library named "Books {{{{" would be refused as a bomb. Escapes inside the
/// string are honoured (`"a\"[[[["` is one string).
///
/// Extracted from `LibraryDescriptorCodec._maxDepth` (2026-10 viewer plan S1)
/// so descriptor and published-catalogue decoding share ONE implementation of
/// this security code instead of a copy.
library;

/// Scans JSON text for its deepest `{`/`[` nesting.
abstract final class JsonNestingDepth {
  /// Returns the deepest open-bracket nesting in [text], skipping string
  /// contents.
  ///
  /// Malformed input is not validated here: an unterminated string simply
  /// stops the scan at the opening quote, and a stray closing bracket never
  /// pushes the depth below zero. `jsonDecode` rejects such documents right
  /// after, so a conservative count is all this needs to be.
  static int maxDepthOf(String text) {
    var depth = 0;
    var max = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          // 0x5C is '\': the next code unit is escaped.
          escaped = true;
        } else if (c == 0x22) {
          // 0x22 is '"': the string ends here.
          inString = false;
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x5B || c == 0x7B) {
        // '[' or '{'
        depth++;
        if (depth > max) max = depth;
      } else if (c == 0x5D || c == 0x7D) {
        // ']' or '}'
        if (depth > 0) depth--;
      }
    }
    return max;
  }
}
