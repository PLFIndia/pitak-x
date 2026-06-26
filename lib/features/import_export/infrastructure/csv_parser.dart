/// Minimal RFC 4180 CSV parser. Pure Dart, no external dependency.
///
/// Direct port of the Kotlin `parseCsv` (source app `data/import_/CsvParser.kt`)
/// so the Flutter Goodreads/CSV import behaves byte-for-byte the same. Handles:
///  - quoted fields with embedded commas, quotes (`""`), and newlines;
///  - bare unquoted fields;
///  - both `\r\n` and `\n` line endings;
///  - a trailing newline at EOF (no spurious empty final row).
library;

/// Parses [text] into rows of fields per RFC 4180.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  final current = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final n = text.length;

  while (i < n) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"' && i + 1 < n && text[i + 1] == '"') {
        field.write('"');
        i += 2;
      } else if (c == '"') {
        inQuotes = false;
        i++;
      } else {
        field.write(c);
        i++;
      }
    } else {
      switch (c) {
        case '"':
          inQuotes = true;
          i++;
        case ',':
          current.add(field.toString());
          field.clear();
          i++;
        case '\r':
          // Ignore; the \n that follows terminates the row.
          i++;
        case '\n':
          current.add(field.toString());
          field.clear();
          rows.add(List<String>.from(current));
          current.clear();
          i++;
        default:
          field.write(c);
          i++;
      }
    }
  }

  // Final field / row (no trailing newline case).
  if (field.isNotEmpty || current.isNotEmpty) {
    current.add(field.toString());
    rows.add(List<String>.from(current));
  }

  return rows;
}
