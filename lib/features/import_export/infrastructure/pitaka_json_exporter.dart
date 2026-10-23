/// Writes the Pitaka JSON interchange format (infrastructure, AGENTS.md §3.1).
///
/// The inverse of `PitakaJsonImporter`: emits a schema-v4 document (ADR 0014
/// W1) our own importer round-trips losslessly. Field names mirror the
/// importer's reads exactly. Null/default fields are omitted to keep the file
/// compact (the importer tolerates their absence).
///
/// v4 (ADR 0014): every row carries `kind` (the stable token); an issue row
/// nests its `IssueOf` fields under `issue{}`; magazine titles go top-level
/// in `periodicals[]`. An issue's base row is exported AS STORED — its title
/// and publisher are the projected values (D3), so a plain reader sees the
/// same text the app shows. Older builds refuse the file (schema gate, P1:
/// a silent import would drop kinds).
///
/// Cover references are written as-is (`coverUrl`); the bundle exporter (which
/// packages the actual cover bytes) is a separate, deferred concern.
library;

import 'dart:convert';

import 'package:pitaka/features/import_export/domain/library_json_codec.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart'
    show kPitakaSchemaVersion;
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Serialises library + wishlist rows to a Pitaka JSON export string.
class PitakaJsonExporter implements LibraryJsonEncoder {
  /// Creates the exporter.
  const PitakaJsonExporter();

  /// Builds a pretty-printed JSON export for [books], [periodicals] and
  /// [wishlist]. [exportedAt] is the epoch-millis stamp recorded in the file.
  ///
  /// [libraryId]/[libraryName] are the merge namespace fields (PLAN-merge.md
  /// D40): the recipient's merge gate compares the file's [libraryId] against
  /// its own to decide match-vs-decision. Blank values are omitted (an older
  /// file with no ID is treated as "unknown library" by the merge gate).
  @override
  String export({
    required List<CatalogueItem> books,
    required List<Periodical> periodicals,
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
      if (periodicals.isNotEmpty)
        'periodicals': periodicals.map(_periodical).toList(),
      // JSON key stays `books` (wire contract, ADR 0014).
      'books': books.map(_book).toList(),
      'wishlist': wishlist.map(_wishlist).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Map<String, dynamic> _book(CatalogueItem b) => _compact({
    // JSON key stays `bookUid` (wire contract, ADR 0014).
    'bookUid': b.itemUid,
    // W1: every row names its kind explicitly (absent ⇒ book on read, but an
    // explicit token is what a future viewer facets on).
    'kind': b.kind.token,
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
    // An issue nests its kind-specific fields (W1); books and others carry
    // no object (O1: an other's description is the shared `notes`).
    if (b.details case final IssueOf issue) 'issue': _issue(issue),
  });

  Map<String, dynamic> _issue(IssueOf issue) => _compact({
    'periodicalUid': issue.periodicalUid,
    'volume': issue.volume,
    'issueNumber': issue.issueNumber,
    'issueDate': issue.issueDate,
    'boundUntil': issue.boundUntil,
    'label': issue.label,
  });

  Map<String, dynamic> _periodical(Periodical p) => _compact({
    'periodicalUid': p.periodicalUid,
    'title': p.title,
    'titleTransliteration': p.titleTransliteration,
    'issn': p.issn,
    'publisher': p.publisher,
    'language': p.language,
    'coverUrl': p.coverUrl,
    'frequency': p.frequency?.token,
    'subscriptionStart': p.subscriptionStart,
    'subscriptionEnd': p.subscriptionEnd,
    'notes': p.notes,
    'location': p.location,
    'sourceType': p.sourceType?.token,
    'sourceDetail': p.sourceDetail,
    'ageGroup': p.ageGroup?.token,
    'addedDate': p.addedDate,
    'removed': p.removed,
    'removedAt': p.removedAt,
    'addedBy': p.addedBy,
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
