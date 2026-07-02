/// Parses a Goodreads "Export library" CSV. Pure Dart port of Kotlin
/// `GoodreadsCsvImporter` (source app).
///
/// Mapping decisions (verified against Kotlin source §3):
///  - `Exclusive Shelf == "to-read"` → Wishlist; everything else → Library.
///  - ISBN columns come wrapped as `="..."` (Excel leading-zero guard); we
///    strip the wrapper. `ISBN13` preferred over `ISBN`; both empty → null.
///  - Per-row failures are collected, not raised (Kotlin D26).
///  - Required headers: `Title` and `Exclusive Shelf`.
library;

import 'package:pitaka/features/import_export/domain/csv_parser.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Imports a Goodreads library CSV export.
final class GoodreadsCsvImporter implements Importer {
  /// Creates the importer.
  const GoodreadsCsvImporter({this.limits = ImportLimits.defaults});

  /// Hostile-input caps (M4). Single source of truth: [ImportLimits.defaults].
  final ImportLimits limits;

  static const List<String> _requiredHeaders = ['Title', 'Exclusive Shelf'];

  @override
  ImportPayload parse(String text) {
    // M4: reject an oversized file before the full-string CSV scan.
    if (text.length > limits.maxTextChars) {
      return const ImportPayload(
        parseErrors: ['File is too large to import safely.'],
      );
    }

    final rows = parseCsv(text);
    if (rows.isEmpty) {
      return const ImportPayload(parseErrors: ['CSV file is empty.']);
    }

    final header = rows.first.map((h) => h.trim()).toList();
    final index = <String, int>{
      for (var i = 0; i < header.length; i++) header[i]: i,
    };

    final missing = _requiredHeaders.where((h) => !header.contains(h)).toList();
    if (missing.isNotEmpty) {
      return ImportPayload(
        parseErrors: [
          'Not a Goodreads CSV — missing columns: ${missing.join(', ')}',
        ],
      );
    }

    final books = <Book>[];
    final wishlist = <WishlistBook>[];
    final errors = <String>[];

    for (var i = 1; i < rows.length; i++) {
      // M4: stop ingesting past the row cap; report once and keep what's valid.
      if (books.length + wishlist.length >= limits.maxRows) {
        errors.add(
          'Only the first ${limits.maxRows} rows were imported; the rest '
          'were skipped.',
        );
        break;
      }
      final row = rows[i];
      final rowNum = i + 1; // 1-indexed including header.

      final title = _cell(row, index, 'Title');
      if (title == null || title.trim().isEmpty) {
        errors.add('Row $rowNum: missing title.');
        continue;
      }

      final author = _nonBlank(_cell(row, index, 'Author'));
      final isbn13 = _unwrapIsbn(_cell(row, index, 'ISBN13'));
      final isbn10 = _unwrapIsbn(_cell(row, index, 'ISBN'));
      final isbn = (isbn13 != null && isbn13.isNotEmpty)
          ? isbn13
          : (isbn10 != null && isbn10.isNotEmpty ? isbn10 : null);
      final publisher = _nonBlank(_cell(row, index, 'Publisher'));
      final year =
          int.tryParse(_cell(row, index, 'Year Published')?.trim() ?? '') ??
          int.tryParse(
            _cell(row, index, 'Original Publication Year')?.trim() ?? '',
          );
      final pages = int.tryParse(
        _cell(row, index, 'Number of Pages')?.trim() ?? '',
      );
      final notes = _nonBlank(_cell(row, index, 'My Review'));
      final shelf = _cell(row, index, 'Exclusive Shelf')?.toLowerCase().trim();

      // M4: clamp every persisted text field at the boundary.
      if (shelf == 'to-read') {
        wishlist.add(
          WishlistBook(
            title: limits.clampField(title)!,
            author: limits.clampField(author),
            isbn: limits.clampField(isbn),
            publisher: limits.clampField(publisher),
            publishedYear: year,
            notes: limits.clampField(notes),
          ),
        );
      } else {
        books.add(
          Book(
            title: limits.clampField(title)!,
            author: limits.clampField(author),
            isbn: limits.clampField(isbn),
            publisher: limits.clampField(publisher),
            publishedYear: year,
            pageCount: pages,
            notes: limits.clampField(notes),
          ),
        );
      }
    }

    return ImportPayload(books: books, wishlist: wishlist, parseErrors: errors);
  }

  static String? _cell(List<String> row, Map<String, int> index, String name) {
    final i = index[name];
    if (i == null || i >= row.length) return null;
    return row[i];
  }

  static String? _nonBlank(String? v) {
    if (v == null) return null;
    return v.trim().isEmpty ? null : v;
  }

  /// Strips Goodreads' Excel guard wrapper `="..."` and separators.
  static String? _unwrapIsbn(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.startsWith('=')) s = s.substring(1);
    return s.replaceAll('"', '').replaceAll('-', '').replaceAll(' ', '');
  }
}
