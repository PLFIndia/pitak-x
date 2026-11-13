/// Picks the right importer for a payload. Pure Dart port of Kotlin
/// `ImportFormatSniffer`.
///
/// Heuristic (deliberately conservative — refuse rather than misinterpret):
///  - text starting with `{` and containing `"schemaVersion"` → Pitaka JSON;
///  - text whose first line is comma-separated and contains `Exclusive Shelf`
///    or `Bookshelves` → Goodreads CSV;
///  - otherwise → null (caller reports "Unknown format").
///
/// Import reads TEXT only (JSON and CSV). A ZIP file is told apart by its
/// first four bytes ([hasZipLocalFileHeader]) and refused, never unpacked
/// (backup rework BR7, decision D29).
library;

import 'dart:convert';

/// Interchange formats this app can detect.
enum ImportFormat {
  /// Pitaka JSON export (`PitakaExport`).
  pitakaJson,

  /// Rows that come together with their cover pictures. Today that is the
  /// restore from the user's own published site (ADR 0021). It is never
  /// found by looking at a text: [ImportFormatSniffer.detect] does not
  /// answer it, and no file of this kind is imported any more (D29).
  pitakaBundle,

  /// Goodreads library CSV export.
  goodreadsCsv,
}

/// True when [bytes] starts with the ZIP local-file-header magic
/// (`50 4B 03 04`, "PK\x03\x04").
///
/// The ONE place that knows these four bytes. Import uses it to refuse a
/// ZIP file with a sentence instead of reading it: the import controller
/// before it decodes anything, and the Import page before it loads the
/// picked file into memory.
bool hasZipLocalFileHeader(List<int> bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 && // 'P'
    bytes[1] == 0x4B && // 'K'
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Detects the [ImportFormat] of a text payload.
abstract final class ImportFormatSniffer {
  /// Returns the detected format, or null when unrecognised.
  static ImportFormat? detect(String text) {
    final head = text.length > 2000
        ? text.substring(0, 2000).trim()
        : text.trim();
    if (head.startsWith('{') && head.contains('"schemaVersion"')) {
      return ImportFormat.pitakaJson;
    }
    if (_looksLikeGoodreadsCsv(head)) {
      return ImportFormat.goodreadsCsv;
    }
    return null;
  }

  static bool _looksLikeGoodreadsCsv(String head) {
    final lines = const LineSplitter().convert(head);
    if (lines.isEmpty) return false;
    final firstLine = lines.first;
    return firstLine.contains(',') &&
        (firstLine.contains('Exclusive Shelf') ||
            firstLine.contains('Bookshelves'));
  }
}
