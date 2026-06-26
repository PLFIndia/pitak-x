/// Redaction for the world-facing publish payload (pure domain, #32, F-01).
///
/// Port of Kotlin `redactForPublish` + `PublishBook.fromRedacted`, fused into
/// one pure function mapping a private `Book` to a world-facing `PublishBook`.
/// Doing the mapping directly (rather than mutating a `Book`) avoids relying on
/// `copyWith` to null-out fields and makes the stripped set explicit.
///
/// Stripped (never leaves the device): id, notes, location, sourceType,
/// sourceDetail, addedDate, addedBy, needsMetadata, copyCount.
/// Preserved (the viewer reads these): title, titleTransliteration, author,
/// publisher, publishedYear, isbn, genre, language, ageGroup token.
///
/// The cover URL is decided entirely by `resolveCoverUrl` — it receives the
/// original `Book` (id intact, so callers can hash/look it up) and returns the
/// value to publish, or null to drop the cover.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';

/// Maps [book] to a redacted [PublishBook]. [availability] is the coarse,
/// vault-derived status ([PublishBook.available]/[PublishBook.out]) or null.
PublishBook redactForPublish(
  Book book, {
  required String? Function(Book) resolveCoverUrl,
  String? availability,
}) {
  final coverUrl = resolveCoverUrl(book);
  return PublishBook(
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
