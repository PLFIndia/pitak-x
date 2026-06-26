/// Maps between the Drift `BookRow` (persistence) and the `Book` domain entity.
///
/// DTOs never leak into domain/presentation (AGENTS.md §3.3): all translation
/// happens here at the infrastructure boundary. Enum↔token conversion uses the
/// tolerant domain parsers so legacy/odd stored values never crash a read.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

/// Translation between [BookRow] and [Book].
extension BookRowMapper on BookRow {
  /// Persistence row → domain entity. Tolerant of unknown enum tokens (→ null).
  Book toDomain() => Book(
    id: id,
    bookUid: bookUid,
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
    sourceType: BookSourceTypeX.fromToken(sourceType),
    sourceDetail: sourceDetail,
    ageGroup: AgeGroup.fromToken(ageGroup),
    addedDate: addedDate,
    copyCount: copyCount,
    needsMetadata: needsMetadata,
    removed: removed,
    removedAt: removedAt,
    addedBy: addedBy,
  );
}

/// Translation from [Book] to a Drift insert/update companion.
extension BookCompanionMapper on Book {
  /// Domain entity → Drift companion. Computes the Unicode-aware sort shadows
  /// (lowercase) the same way the Kotlin `BookMapper` does — NOT SQLite
  /// `LOWER()`, so non-ASCII scripts fold correctly.
  BooksCompanion toCompanion() => BooksCompanion(
    id: id == Book.emptyId ? const Value.absent() : Value(id),
    bookUid: Value(bookUid),
    title: Value(title),
    titleTransliteration: Value(titleTransliteration),
    author: Value(author),
    titleSort: Value(title.toLowerCase()),
    authorSort: Value((author ?? '').toLowerCase()),
    isbn: Value(isbn),
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
  );
}
