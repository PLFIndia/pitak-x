/// Same-UID update semantics shared by the import orchestrator.
library;

import 'package:pitaka/features/library/domain/cover_precedence.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// Keeps the local database id/UID and applies incoming public fields.
///
/// Vault loans reference the local id. Cover precedence keeps a local photo
/// over a remote URL, and a file with no cover does not erase the local one.
CatalogueItem mergeImportedCatalogueItem({
  required CatalogueItem existing,
  required CatalogueItem incoming,
}) {
  final cover = resolveIncomingCover(
    existing: existing.coverUrl,
    incoming: incoming.coverUrl,
  );
  final merged = CatalogueItem(
    id: existing.id,
    itemUid: existing.itemUid,
    title: incoming.title,
    titleTransliteration: incoming.titleTransliteration,
    author: incoming.author,
    isbn: incoming.isbn,
    publisher: incoming.publisher,
    publishedYear: incoming.publishedYear,
    genre: incoming.genre,
    coverUrl: cover,
    pageCount: incoming.pageCount,
    language: incoming.language,
    notes: incoming.notes,
    location: incoming.location,
    sourceType: incoming.sourceType,
    sourceDetail: incoming.sourceDetail,
    ageGroup: incoming.ageGroup,
    addedDate: incoming.addedDate == 0
        ? existing.addedDate
        : incoming.addedDate,
    copyCount: incoming.copyCount,
    needsMetadata: incoming.needsMetadata,
    removed: incoming.removed,
    removedAt: incoming.removedAt,
    addedBy: incoming.addedBy ?? existing.addedBy,
    // The caller proved both rows are the same kind, so a missing v3 kind
    // cannot delete a stored issue or other-item marker.
    details: incoming.details,
  );
  // Defence in depth: even the update path revalidates its constructed row.
  return CatalogueItem.validate(merged).toNullable()!;
}
