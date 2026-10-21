/// Redaction for the world-facing publish payload (pure domain, #32, F-01).
///
/// Port of Kotlin `redactForPublish` + `PublishBook.fromRedacted`, fused into
/// one pure function mapping a private `CatalogueItem` to a world-facing
/// `PublishItem`. Doing the mapping directly (rather than mutating a
/// `CatalogueItem`) avoids relying on `copyWith` to null-out fields and makes
/// the stripped set explicit.
///
/// Stripped (never leaves the device): id, notes, location, sourceType,
/// sourceDetail, addedDate, addedBy, needsMetadata, copyCount.
/// Preserved (the viewer reads these): title, titleTransliteration, author,
/// publisher, publishedYear, isbn, genre, language, ageGroup token.
///
/// The cover URL is decided entirely by `resolveCoverUrl` — it receives the
/// original `CatalogueItem` (id intact, so callers can hash/look it up) and returns the
/// value to publish, or null to drop the cover.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';

/// Maps [book] to a redacted [PublishItem]. [availability] is the coarse,
/// vault-derived status ([PublishItem.available]/[PublishItem.out]) or null.
PublishItem redactForPublish(
  CatalogueItem book, {
  required String? Function(CatalogueItem) resolveCoverUrl,
  String? availability,
}) {
  final coverUrl = resolveCoverUrl(book);
  return PublishItem(
    title: book.title,
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
  );
}
