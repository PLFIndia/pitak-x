/// Writes the fields an issue inherits from its periodical onto the issue's
/// base row (periodicals domain, pure Dart; ADR 0013 D3).
///
/// Why project instead of reading through (beginner note): every existing
/// consumer — the paged list, FTS, publish, backup, merge, the vault's loan
/// titles — reads plain `CatalogueItem` columns. Copying the series' values
/// onto each issue at write time keeps all of them unchanged; the price is
/// that renaming a series must re-run this over its issues, which the
/// update use case does inside one transaction.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_title.dart';

/// Applies the series → issue projection.
abstract final class IssueProjection {
  /// Returns [item] with its derived fields rewritten from [periodical]:
  /// `title` (composed by `IssueTitle`), `titleTransliteration` (composed
  /// the same way from the series' transliteration, or null when the
  /// series has none), `publisher`, `language`, `ageGroup` (copied) and
  /// `publishedYear` (the issue date's year, or null).
  ///
  /// Idempotent: applying it twice gives the same row. A row that is not an
  /// issue is returned unchanged — there is nothing to project.
  static CatalogueItem apply(CatalogueItem item, Periodical periodical) {
    final issue = item.issue;
    if (issue == null) return item;
    final transliteration = periodical.titleTransliteration?.trim() ?? '';
    // `copyWith` cannot null a field, so the row is rebuilt explicitly:
    // a series that lost its publisher must clear it on every issue too.
    return CatalogueItem(
      id: item.id,
      itemUid: item.itemUid,
      title: IssueTitle.compose(periodical.title, issue),
      titleTransliteration: transliteration.isEmpty
          ? null
          : IssueTitle.compose(transliteration, issue),
      author: item.author,
      isbn: item.isbn,
      publisher: periodical.publisher,
      publishedYear: IssueTitle.yearOf(issue.issueDate),
      genre: item.genre,
      coverUrl: item.coverUrl,
      pageCount: item.pageCount,
      language: periodical.language,
      notes: item.notes,
      location: item.location,
      sourceType: item.sourceType,
      sourceDetail: item.sourceDetail,
      ageGroup: periodical.ageGroup,
      addedDate: item.addedDate,
      copyCount: item.copyCount,
      needsMetadata: item.needsMetadata,
      removed: item.removed,
      removedAt: item.removedAt,
      addedBy: item.addedBy,
      details: issue,
    );
  }
}
