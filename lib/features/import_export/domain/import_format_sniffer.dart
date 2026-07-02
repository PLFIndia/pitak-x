/// Picks the right importer for a payload. Pure Dart port of Kotlin
/// `ImportFormatSniffer`.
///
/// Heuristic (deliberately conservative — refuse rather than misinterpret):
///  - text starting with `{` and containing `"schemaVersion"` → Pitaka JSON;
///  - text whose first line is comma-separated and contains `Exclusive Shelf`
///    or `Bookshelves` → Goodreads CSV;
///  - otherwise → null (caller reports "Unknown format").
library;

import 'dart:convert';

/// Interchange formats this app can detect.
enum ImportFormat {
  /// Pitaka JSON export (`PitakaExport`).
  pitakaJson,

  /// Pitaka bundle (.zip with `library.json` + covers).
  pitakaBundle,

  /// Goodreads library CSV export.
  goodreadsCsv,
}

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
