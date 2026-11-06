/// Structured output of the authoritative published-catalogue mapper.
library;

import 'package:pitaka/features/import_export/domain/import_payload.dart';

/// Payload plus structured loss and cover information.
final class PublishedCatalogueMapperResult {
  /// Creates an immutable mapper result.
  const PublishedCatalogueMapperResult({
    required this.payload,
    required this.coverSources,
    required this.droppedRows,
    required this.droppedFields,
    required this.issuesFiledAsBooks,
    required this.thirdPartyCoverLinks,
  });

  /// Rows ready for bundle validation; recoverable drops are NOT parse errors.
  final ImportPayload payload;

  /// Synthetic `.jpg` leaf -> original same-site `covers/<leaf>` reference.
  /// Synthetic names keep crash orphans inside the janitor's recognised shape.
  final Map<String, String> coverSources;

  /// Reader and validation drops, summed once.
  final int droppedRows;

  /// Optional fields the defensive reader omitted.
  final int droppedFields;

  /// Issues degraded to books because their series was absent.
  final int issuesFiledAsBooks;

  /// Distinct remote cover links retained but deliberately not downloaded.
  final int thirdPartyCoverLinks;

  /// Keeps counts and cover mapping while replacing the pruned payload.
  PublishedCatalogueMapperResult withPayload(ImportPayload next) =>
      PublishedCatalogueMapperResult(
        payload: next,
        coverSources: coverSources,
        droppedRows: droppedRows,
        droppedFields: droppedFields,
        issuesFiledAsBooks: issuesFiledAsBooks,
        thirdPartyCoverLinks: thirdPartyCoverLinks,
      );
}
