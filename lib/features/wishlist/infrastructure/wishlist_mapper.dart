/// Maps between Drift `WishlistRow` and the `WishlistBook` domain entity.
///
/// All DTO↔domain translation happens here at the infrastructure boundary
/// (AGENTS.md §3.3). Enum↔token conversion uses the tolerant domain parser.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Translation from [WishlistRow] to [WishlistBook].
extension WishlistRowMapper on WishlistRow {
  /// Persistence row → domain entity. Tolerant of unknown source tokens.
  WishlistBook toDomain() => WishlistBook(
    id: id,
    title: title,
    titleTransliteration: titleTransliteration,
    author: author,
    isbn: isbn,
    publisher: publisher,
    publishedYear: publishedYear,
    coverUrl: coverUrl,
    priceEstimate: priceEstimate,
    priority: priority,
    notes: notes,
    source: WishlistSourceX.fromToken(source),
    addedDate: addedDate,
    purchased: purchased,
    purchasedDate: purchasedDate,
    needsMetadata: needsMetadata,
  );
}

/// Translation from [WishlistBook] to a Drift insert/update companion.
extension WishlistCompanionMapper on WishlistBook {
  /// Domain entity → Drift companion.
  WishlistBooksCompanion toCompanion() => WishlistBooksCompanion(
    id: id == WishlistBook.emptyId ? const Value.absent() : Value(id),
    title: Value(title),
    titleTransliteration: Value(titleTransliteration),
    author: Value(author),
    isbn: Value(isbn),
    publisher: Value(publisher),
    publishedYear: Value(publishedYear),
    coverUrl: Value(coverUrl),
    priceEstimate: Value(priceEstimate),
    priority: Value(priority),
    notes: Value(notes),
    source: Value(source.token),
    addedDate: Value(addedDate),
    purchased: Value(purchased),
    purchasedDate: Value(purchasedDate),
    needsMetadata: Value(needsMetadata),
  );
}
