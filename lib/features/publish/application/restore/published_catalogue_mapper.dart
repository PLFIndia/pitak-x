/// Maps the defensive viewer read into an authoritative restore payload.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper_result.dart';

/// Refuses lossy root conditions; valid rows still pass both ingress gates.
Either<Failure, PublishedCatalogueMapperResult> mapPublishedCatalogueForRestore(
  PublishedCatalogue catalogue, {
  required int addedDate,
}) {
  final warnings = catalogue.warnings;
  if (catalogue.hasNewerSchema) {
    return left(SchemaTooNewFailure(catalogue.declaredSchemaVersion));
  }
  if (warnings.hasUnknownKinds) {
    return left(
      const ValidationFailure(
        'This site contains item kinds this version of Pitak does not '
        'understand. Update Pitak before restoring so nothing is changed '
        'into the wrong kind.',
      ),
    );
  }
  if (warnings.itemsTruncated || warnings.periodicalsTruncated) {
    return left(
      const ValidationFailure(
        'This catalogue is too large to restore safely. Nothing was imported.',
      ),
    );
  }
  if (warnings.duplicateSeriesUids > 0) {
    return left(
      const ValidationFailure(
        'This site contains duplicate magazine-title identities. Pitak cannot '
        'tell which one is authoritative, so nothing was imported.',
      ),
    );
  }

  final coverSources = <String, String>{};
  final leafBySource = <String, String>{};
  final thirdParty = <String>{};
  String? cover(String? source) {
    if (source == null) return null;
    if (!source.startsWith(_sameSitePrefix)) {
      if (source.startsWith('https://')) thirdParty.add(source);
      return source;
    }
    final existing = leafBySource[source];
    if (existing != null) return '$_sameSitePrefix$existing';
    final leaf = 'restore-${coverSources.length}.jpg';
    leafBySource[source] = leaf;
    coverSources[leaf] = source;
    return '$_sameSitePrefix$leaf';
  }

  var droppedRows = warnings.droppedItems + warnings.droppedPeriodicals;
  final periodicals = <Periodical>[];
  for (final published in catalogue.periodicals) {
    final candidate = Periodical(
      periodicalUid: published.periodicalUid,
      title: published.title,
      titleTransliteration: published.titleTransliteration,
      issn: published.issn,
      publisher: published.publisher,
      language: published.language,
      coverUrl: cover(published.coverUrl),
      frequency: published.frequency,
      ageGroup: published.ageGroup,
      addedDate: addedDate,
    );
    final checked = Periodical.validate(candidate);
    if (checked.isLeft()) {
      droppedRows++;
    } else {
      periodicals.add(checked.toNullable()!);
    }
  }
  final seriesUids = {for (final title in periodicals) title.periodicalUid};
  var issuesFiledAsBooks = 0;
  final items = <CatalogueItem>[];
  for (final published in catalogue.items) {
    ItemDetails? details;
    switch (published.kind) {
      case PublishedItemKind.book:
        details = null;
      case PublishedItemKind.other:
        details = const OtherItemOf();
      case PublishedItemKind.magazineIssue:
        final issue = published.issue;
        final uid = issue?.periodicalUid;
        if (issue != null && uid != null && seriesUids.contains(uid)) {
          details = IssueOf(
            periodicalUid: uid,
            volume: issue.volume,
            issueNumber: issue.issueNumber,
            issueDate: issue.issueDate,
            boundUntil: issue.boundUntil,
            label: issue.label,
          );
        } else {
          issuesFiledAsBooks++;
        }
      case PublishedItemKind.unknown:
        return left(
          const ValidationFailure('Unknown item kind. Nothing was imported.'),
        );
    }
    final isOther = published.kind == PublishedItemKind.other;
    final candidate = CatalogueItem(
      title: published.title,
      titleTransliteration: isOther ? null : published.titleTransliteration,
      author: isOther ? null : published.author,
      isbn: isOther ? null : published.isbn,
      publisher: isOther ? null : published.publisher,
      publishedYear: isOther ? null : published.publishedYear,
      genre: isOther ? null : published.genre,
      language: published.language,
      coverUrl: cover(published.coverUrl),
      ageGroup: published.ageGroup,
      addedDate: addedDate,
      details: details,
    );
    final checked = CatalogueItem.validate(candidate);
    if (checked.isLeft()) {
      droppedRows++;
    } else {
      items.add(checked.toNullable()!);
    }
  }
  if (items.isEmpty && periodicals.isEmpty) {
    return left(
      const ValidationFailure(
        'The site has no readable catalogue items to restore. Nothing was '
        'imported.',
      ),
    );
  }
  final payloadWarnings = <String>[
    if (droppedRows > 0) '$droppedRows catalogue row(s) were not readable.',
    if (warnings.invalidOptionalFields > 0)
      '${warnings.invalidOptionalFields} optional field(s) were not readable.',
  ];
  return right(
    PublishedCatalogueMapperResult(
      payload: ImportPayload(
        items: items,
        periodicals: periodicals,
        warnings: payloadWarnings,
      ),
      coverSources: Map.unmodifiable(coverSources),
      droppedRows: droppedRows,
      droppedFields: warnings.invalidOptionalFields,
      issuesFiledAsBooks: issuesFiledAsBooks,
      thirdPartyCoverLinks: thirdParty.length,
    ),
  );
}

const String _sameSitePrefix = 'covers/';
