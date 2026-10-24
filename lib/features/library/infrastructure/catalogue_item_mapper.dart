/// Maps between the Drift `BookRow` (persistence) and the `CatalogueItem`
/// domain entity.
///
/// DTOs never leak into domain/presentation (AGENTS.md §3.3): all translation
/// happens here at the infrastructure boundary. Enum↔token conversion uses the
/// tolerant domain parsers so legacy/odd stored values never crash a read.
///
/// Since schema v5 a catalogue row is the base row of ANY kind (ADR 0013):
/// the entity's `details` come from the joined `magazine_issues` row through
/// `DriftItemDetails`, and the companion carries the kind token.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';

/// Translation between [BookRow] and [CatalogueItem].
extension CatalogueItemRowMapper on BookRow {
  /// Persistence row → domain entity. Tolerant of unknown enum tokens (→
  /// null). [details] is the kind-specific part already read through
  /// `DriftItemDetails.read` (null for a book — and for an unknown kind,
  /// which reads fail-soft as a book, ADR 0013 F6).
  CatalogueItem toDomain({ItemDetails? details}) => CatalogueItem(
    id: id,
    itemUid: itemUid,
    title: title,
    titleTransliteration: titleTransliteration,
    author: author,
    isbn: isbn,
    publisher: publisher,
    publishedYear: publishedYear,
    genre: genre,
    coverUrl: coverUrl,
    pageCount: pageCount,
    language: language,
    notes: notes,
    location: location,
    sourceType: ItemSourceTypeX.fromToken(sourceType),
    sourceDetail: sourceDetail,
    ageGroup: AgeGroup.fromToken(ageGroup),
    addedDate: addedDate,
    copyCount: copyCount,
    needsMetadata: needsMetadata,
    removed: removed,
    removedAt: removedAt,
    addedBy: addedBy,
    details: details,
  );
}

/// A base row with its joined detail row, as every repository read produces
/// it (LEFT JOIN `magazine_issues`; the detail row is null for non-issues).
extension JoinedCatalogueRowMapper on TypedResult {
  /// Reads the `books` row and its optional `magazine_issues` row from a
  /// joined select and maps them to one entity through [details].
  CatalogueItem toCatalogueItem(AppDatabase db, DriftItemDetails details) {
    final base = readTable(db.books);
    final issue = readTableOrNull(db.magazineIssues);
    return base.toDomain(details: details.read(base.kind, issue));
  }
}

/// Translation from [CatalogueItem] to a Drift insert/update companion.
extension CatalogueItemCompanionMapper on CatalogueItem {
  /// Domain entity → Drift companion. Computes the Unicode-aware sort shadows
  /// (lowercase) the same way the Kotlin `BookMapper` does — NOT SQLite
  /// `LOWER()`, so non-ASCII scripts fold correctly.
  BooksCompanion toCompanion() => BooksCompanion(
    id: id == CatalogueItem.emptyId ? const Value.absent() : Value(id),
    itemUid: Value(itemUid),
    title: Value(title),
    titleTransliteration: Value(titleTransliteration),
    author: Value(author),
    titleSort: Value(title.toLowerCase()),
    authorSort: Value((author ?? '').toLowerCase()),
    // Blank ISBNs are stored as NULL, never '': the UNIQUE index on isbn is
    // documented "unique among non-null" and SQLite lets any number of NULLs
    // through, while two '' rows would collide. Only crafted import files
    // produce a blank-string ISBN (the UI trims to null), but the mapper is
    // the single persistence choke point, so the invariant lives here
    // (REVIEW_FINDINGS_2 S5).
    isbn: Value(isbn == null || isbn!.trim().isEmpty ? null : isbn),
    publisher: Value(publisher),
    publishedYear: Value(publishedYear),
    genre: Value(genre),
    coverUrl: Value(coverUrl),
    pageCount: Value(pageCount),
    language: Value(language),
    notes: Value(notes),
    location: Value(location),
    sourceType: Value(sourceType?.token),
    sourceDetail: Value(sourceDetail),
    ageGroup: Value(ageGroup?.token),
    addedDate: Value(addedDate),
    copyCount: Value(copyCount),
    needsMetadata: Value(needsMetadata),
    removed: Value(removed),
    removedAt: Value(removedAt),
    addedBy: Value(addedBy),
    // Derived from `details` (ADR 0013 F5), so the column can never disagree
    // with the detail row written next to it.
    kind: Value(kind.token),
  );
}
