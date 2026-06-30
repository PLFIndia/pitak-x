/// Hostile-input limits for import parsers (pure domain, M4).
///
/// Why this exists (security audit M4): the JSON / CSV / Goodreads parsers
/// otherwise ingest an unbounded number of rows and unbounded field lengths. A
/// crafted file (millions of rows, or a single multi-megabyte field) can
/// exhaust memory or bloat the database — a denial-of-service on the data
/// store. This is the SINGLE SOURCE OF TRUTH for those caps; every importer
/// enforces the same `ImportLimits.defaults`.
///
/// Philosophy mirrors `BoundedZipExtractor`: cheap early rejects, then
/// fail-closed — but, matching the importers' "collect errors, never throw"
/// contract (Kotlin D26), enforcement TRUNCATES and reports rather than
/// throwing, so a partially-valid file still imports what it safely can.
library;

/// Caps applied to a single import operation.
final class ImportLimits {
  /// Creates limits; all values must be positive.
  const ImportLimits({
    required this.maxRows,
    required this.maxFieldChars,
    required this.maxTextChars,
  }) : assert(maxRows > 0, 'maxRows must be positive'),
       assert(maxFieldChars > 0, 'maxFieldChars must be positive'),
       assert(maxTextChars > 0, 'maxTextChars must be positive');

  /// Max number of data rows ingested per collection (books, wishlist, or CSV
  /// rows). Rows beyond this are dropped with a single reported error.
  final int maxRows;

  /// Max characters kept for any single text field. Longer values are clamped
  /// (defends against a multi-megabyte single cell bloating the DB).
  final int maxFieldChars;

  /// Max characters of raw input text accepted before parsing. A larger file is
  /// rejected outright (defends against a multi-GB file exhausting memory in
  /// `jsonDecode` / the CSV scan).
  final int maxTextChars;

  /// Defaults for the Pitaka import formats. 100k rows comfortably exceeds any
  /// real personal/community library; 8k chars is generous for a notes field;
  /// 64 MiB of text is far beyond a legitimate catalogue export.
  static const ImportLimits defaults = ImportLimits(
    maxRows: 100000,
    maxFieldChars: 8000,
    maxTextChars: 64 * 1024 * 1024,
  );

  /// Clamps [value] to [maxFieldChars], or returns it unchanged when null/short.
  /// Used by parsers to bound every persisted string field at the boundary.
  String? clampField(String? value) {
    if (value == null) return null;
    if (value.length <= maxFieldChars) return value;
    return value.substring(0, maxFieldChars);
  }
}
