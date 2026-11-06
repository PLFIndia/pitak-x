/// Applies cover-download outcomes without retaining cleared nullable fields.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper_result.dart';

/// Nulls every same-site reference whose synthetic leaf was not retained.
/// Remote https references stay for the ordinary consent-gated display path.
PublishedCatalogueMapperResult retainPublishedCovers(
  PublishedCatalogueMapperResult mapped,
  Set<String> retainedLeaves,
) {
  String? keep(String? reference) {
    if (!CoverPaths.isLocal(reference)) return reference;
    final leaf = CoverPaths.leafOf(reference);
    return leaf != null && retainedLeaves.contains(leaf) ? reference : null;
  }

  return mapped.withPayload(
    ImportPayload(
      items: [
        for (final item in mapped.payload.items)
          CatalogueItem.validate(
            _itemWithCover(item, keep(item.coverUrl)),
          ).toNullable()!,
      ],
      periodicals: [
        for (final title in mapped.payload.periodicals)
          Periodical.validate(
            _periodicalWithCover(title, keep(title.coverUrl)),
          ).toNullable()!,
      ],
      warnings: mapped.payload.warnings,
    ),
  );
}

CatalogueItem _itemWithCover(CatalogueItem item, String? coverUrl) =>
    CatalogueItem(
      id: item.id,
      itemUid: item.itemUid,
      title: item.title,
      titleTransliteration: item.titleTransliteration,
      author: item.author,
      isbn: item.isbn,
      publisher: item.publisher,
      publishedYear: item.publishedYear,
      genre: item.genre,
      coverUrl: coverUrl,
      pageCount: item.pageCount,
      language: item.language,
      notes: item.notes,
      location: item.location,
      sourceType: item.sourceType,
      sourceDetail: item.sourceDetail,
      ageGroup: item.ageGroup,
      addedDate: item.addedDate,
      copyCount: item.copyCount,
      needsMetadata: item.needsMetadata,
      removed: item.removed,
      removedAt: item.removedAt,
      addedBy: item.addedBy,
      details: item.details,
    );

Periodical _periodicalWithCover(Periodical title, String? coverUrl) =>
    Periodical(
      id: title.id,
      periodicalUid: title.periodicalUid,
      title: title.title,
      titleTransliteration: title.titleTransliteration,
      issn: title.issn,
      publisher: title.publisher,
      language: title.language,
      coverUrl: coverUrl,
      frequency: title.frequency,
      subscriptionStart: title.subscriptionStart,
      subscriptionEnd: title.subscriptionEnd,
      notes: title.notes,
      location: title.location,
      sourceType: title.sourceType,
      sourceDetail: title.sourceDetail,
      ageGroup: title.ageGroup,
      addedDate: title.addedDate,
      removed: title.removed,
      removedAt: title.removedAt,
      addedBy: title.addedBy,
    );
