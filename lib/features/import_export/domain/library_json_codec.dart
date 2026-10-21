/// Domain ports for the Pitaka-JSON library interchange codec (review finding
/// N14: JSON serialization used to live inside the domain layer).
///
/// JSON serialization is kept OUT of the domain layer (AGENTS.md §3.1): the
/// concrete `PitakaJsonImporter` / `PitakaJsonExporter` live in
/// `infrastructure/`, and use cases depend on these narrow ports, receiving
/// the implementations via DI. The payload/envelope types stay in domain —
/// they are pure data.
library;

import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Parses Pitaka-JSON library files (schema v3) without throwing.
abstract interface class LibraryJsonParser {
  /// Parses [text] into an [ImportPayload]; malformed rows are collected as
  /// [ImportPayload.parseErrors] rather than thrown.
  ImportPayload parse(String text);

  /// Reads only the merge-namespace envelope fields (library id/name)
  /// without parsing any rows.
  ({String libraryId, String libraryName}) parseEnvelope(String text);
}

/// Serialises library + wishlist rows to the Pitaka-JSON export format.
/// Single-method, but kept as an interface (matching [LibraryJsonParser] and
/// the existing [Importer] port style) so the use case depends on the
/// abstraction, not the infrastructure codec.
// ignore: one_member_abstracts
abstract interface class LibraryJsonEncoder {
  /// Builds a pretty-printed schema-v3 export document. Blank
  /// [libraryId]/[libraryName] are omitted (merge gate treats them as
  /// "unknown library").
  String export({
    required List<CatalogueItem> books,
    required List<WishlistBook> wishlist,
    required int exportedAt,
    String libraryId,
    String libraryName,
  });
}
