/// Redaction for the world-facing publish payload (pure domain, #32, F-01).
///
/// Port of Kotlin `redactForPublish` + `PublishBook.fromRedacted`, fused into
/// one pure function mapping a private `CatalogueItem` to a world-facing
/// `PublishItem` — plus the ADR 0014 W3 twin mapping a private `Periodical`
/// to a world-facing `PublishPeriodical`. Doing the mapping directly (rather
/// than mutating the entity) avoids relying on `copyWith` to null-out fields
/// and makes the stripped set explicit.
///
/// Stripped from an item (never leaves the device): id, notes, location,
/// sourceType, sourceDetail, addedDate, addedBy, needsMetadata, copyCount.
/// Books/issues preserve title, kind, issue{} identity, titleTransliteration,
/// author, publisher, publishedYear, isbn, genre, language, ageGroup and the
/// coarse availability flag. ADR 0013 O2 deliberately narrows an Other to
/// title, kind, resolved cover, language and ageGroup — nothing else.
///
/// Stripped from a periodical: the subscription window, notes, location,
/// sourceType/sourceDetail, addedDate/addedBy, removed*, and the per-device
/// id. Preserved: periodicalUid (the viewer's grouping key), title,
/// titleTransliteration, issn, publisher, language, coverUrl, frequency and
/// ageGroup tokens.
///
/// The cover URL is decided entirely by the `resolveCoverUrl` callback — it
/// receives the original entity (id/uid intact, so callers can hash/look it
/// up) and returns the value to publish, or null to drop the cover.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';

/// Maps [book] to a redacted [PublishItem]. [availability] is the coarse,
/// vault-derived status ([PublishItem.available]/[PublishItem.out]) or null.
/// It applies only to books and issues; ADR 0013 O2 excludes it from Others.
PublishItem redactForPublish(
  CatalogueItem book, {
  required String? Function(CatalogueItem) resolveCoverUrl,
  String? availability,
}) {
  final coverUrl = resolveCoverUrl(book);
  final issue = book.issue;
  return switch (book.details) {
    OtherItemOf() => PublishItem(
      title: book.title,
      kind: book.kind.token,
      language: book.language,
      coverUrl: coverUrl,
      ageGroup: book.ageGroup?.token,
    ),
    IssueOf() || null => PublishItem(
      title: book.title,
      kind: book.kind.token,
      issue: issue == null
          ? null
          : PublishIssue(
              periodicalUid: issue.periodicalUid,
              volume: issue.volume,
              issueNumber: issue.issueNumber,
              issueDate: issue.issueDate,
              boundUntil: issue.boundUntil,
              label: issue.label,
            ),
      titleTransliteration: book.titleTransliteration,
      author: book.author,
      isbn: book.isbn,
      publisher: book.publisher,
      publishedYear: book.publishedYear,
      genre: book.genre,
      language: book.language,
      coverUrl: coverUrl,
      ageGroup: book.ageGroup?.token,
      availability: availability,
    ),
  };
}

/// Maps [periodical] to a redacted [PublishPeriodical] (ADR 0014 W3). The
/// private fields (subscription window, notes, location, source, added*) are
/// not parameters of [PublishPeriodical] at all — there is nothing to leak.
PublishPeriodical redactPeriodicalForPublish(
  Periodical periodical, {
  required String? Function(Periodical) resolveCoverUrl,
}) {
  return PublishPeriodical(
    // A persisted periodical always carries its uid (the mapper fails closed
    // without one); the payload simply has no entry for an unpersisted row.
    periodicalUid: periodical.periodicalUid ?? '',
    title: periodical.title,
    titleTransliteration: periodical.titleTransliteration,
    issn: periodical.issn,
    publisher: periodical.publisher,
    language: periodical.language,
    coverUrl: resolveCoverUrl(periodical),
    frequency: periodical.frequency?.token,
    ageGroup: periodical.ageGroup?.token,
  );
}
