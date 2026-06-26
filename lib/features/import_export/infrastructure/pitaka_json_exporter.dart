/// Writes the Pitaka JSON interchange format (infrastructure, AGENTS.md §3.1).
///
/// The inverse of `PitakaJsonImporter`: emits a schema-v3 document our own
/// importer round-trips losslessly. Field names mirror the importer's reads
/// exactly. Null/default fields are omitted to keep the file compact (the
/// importer tolerates their absence).
///
/// Cover references are written as-is (`coverUrl`); the bundle exporter (which
/// packages the actual cover bytes) is a separate, deferred concern.
library;

import 'dart:convert';

import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart'
    show kPitakaSchemaVersion;
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Serialises library + wishlist rows to a Pitaka JSON export string.
class PitakaJsonExporter {
  /// Creates the exporter.
  const PitakaJsonExporter();

  /// Builds a pretty-printed JSON export for [books] and [wishlist].
  /// [exportedAt] is the epoch-millis stamp recorded in the file.
  ///
  /// [libraryId]/[libraryName] are the merge namespace fields (PLAN-merge.md
  /// D40): the recipient's merge gate compares the file's [libraryId] against
  /// its own to decide match-vs-decision. Blank values are omitted (an older
  /// file with no ID is treated as "unknown library" by the merge gate).
  String export({
    required List<Book> books,
    required List<WishlistBook> wishlist,
    required int exportedAt,
    String libraryId = '',
    String libraryName = '',
  }) {
    final doc = <String, dynamic>{
      'schemaVersion': kPitakaSchemaVersion,
      'exportedAt': exportedAt,
      if (libraryId.trim().isNotEmpty) 'libraryId': libraryId.trim(),
      if (libraryName.trim().isNotEmpty) 'libraryName': libraryName.trim(),
      'books': books.map(_book).toList(),
      'wishlist': wishlist.map(_wishlist).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Map<String, dynamic> _book(Book b) => _compact({
    'bookUid': b.bookUid,
    'title': b.title,
    'titleTransliteration': b.titleTransliteration,
    'author': b.author,
    'isbn': b.isbn,
    'publisher': b.publisher,
    'publishedYear': b.publishedYear,
    'genre': b.genre,
    'coverUrl': b.coverUrl,
    'pageCount': b.pageCount,
    'language': b.language,
    'notes': b.notes,
    'location': b.location,
    'sourceType': b.sourceType?.token,
    'sourceDetail': b.sourceDetail,
    'ageGroup': b.ageGroup?.token,
    'addedDate': b.addedDate,
    'copyCount': b.copyCount,
    'needsMetadata': b.needsMetadata,
    'removed': b.removed,
    'removedAt': b.removedAt,
    'addedBy': b.addedBy,
  });

  Map<String, dynamic> _wishlist(WishlistBook w) => _compact({
    'title': w.title,
    'titleTransliteration': w.titleTransliteration,
    'author': w.author,
    'isbn': w.isbn,
    'publisher': w.publisher,
    'publishedYear': w.publishedYear,
    'coverUrl': w.coverUrl,
    'priceEstimate': w.priceEstimate,
    'priority': w.priority,
    'notes': w.notes,
    'source': w.source.token,
    'addedDate': w.addedDate,
    'purchased': w.purchased,
    'purchasedDate': w.purchasedDate,
    'needsMetadata': w.needsMetadata,
  });

  /// Drops null values so the export stays compact (importer tolerates gaps).
  Map<String, dynamic> _compact(Map<String, dynamic> m) {
    m.removeWhere((_, v) => v == null);
    return m;
  }
}
