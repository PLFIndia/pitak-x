/// Reads a legacy Room `books.db` / `wishlist.db` exhaustively and maps every
/// row+column into the Flutter domain entities (PLAN.md Option B: one-time
/// translation at restore, then Flutter owns its Drift schema).
///
/// These DBs carry NO secrets (the encrypted vault is a separate `borrowers.db`
/// read by the Rust core), so they are opened with plain `sqlite3` read-only.
///
/// Column contract verified against `app/schemas/.../BooksDatabase/10.json`
/// (25 cols) and `WishlistDatabase/1.json` (16 cols). Crucially we **preserve**
/// the legacy `id` and `book_uid`:
///  - `book_uid` is the stable cross-device identity (never re-mint it);
///  - `id` keeps the vault's `loans.book_id` references resolvable across the
///    Drift/vault boundary after restore.
///
/// This is the opposite of JSON/CSV *import* (which mints fresh ids): a backup
/// restore is an authoritative overwrite of local state, not an additive merge.
library;

import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';

/// Exhaustive reader over the legacy plain SQLite library/wishlist DBs.
class LegacyDbReader {
  /// Creates a reader over an already-open database (caller owns lifecycle).
  const LegacyDbReader(this._db);

  final CommonDatabase _db;

  /// Reads every row of the `books` table into [Book] entities, preserving
  /// `id` and `book_uid`. Tolerant enum tokens (unknown → null).
  List<Book> readBooks() {
    final result = _db.select(
      'SELECT id, book_uid, title, title_transliteration, author, isbn, '
      'publisher, published_year, genre, cover_url, page_count, language, '
      'notes, location, source_type, source_detail, age_group, added_date, '
      'copy_count, needs_metadata, removed, removed_at, added_by FROM books',
    );
    return result.map(_book).toList();
  }

  /// Reads every row of the `wishlist_books` table into [WishlistBook]
  /// entities, preserving `id`.
  List<WishlistBook> readWishlist() {
    final result = _db.select(
      'SELECT id, title, title_transliteration, author, isbn, publisher, '
      'published_year, cover_url, price_estimate, priority, notes, source, '
      'added_date, purchased, purchased_date, needs_metadata '
      'FROM wishlist_books',
    );
    return result.map(_wishlistBook).toList();
  }

  Book _book(Row r) => Book(
    id: _int(r['id']) ?? Book.emptyId,
    bookUid: _str(r['book_uid']),
    title: _str(r['title']) ?? '',
    titleTransliteration: _str(r['title_transliteration']),
    author: _str(r['author']),
    isbn: _str(r['isbn']),
    publisher: _str(r['publisher']),
    publishedYear: _int(r['published_year']),
    genre: _str(r['genre']),
    coverUrl: _str(r['cover_url']),
    pageCount: _int(r['page_count']),
    language: _str(r['language']),
    notes: _str(r['notes']),
    location: _str(r['location']),
    sourceType: BookSourceTypeX.fromToken(_str(r['source_type'])),
    sourceDetail: _str(r['source_detail']),
    ageGroup: AgeGroup.fromToken(_str(r['age_group'])),
    addedDate: _int(r['added_date']) ?? 0,
    copyCount: _int(r['copy_count']) ?? 1,
    needsMetadata: _bool(r['needs_metadata']),
    removed: _bool(r['removed']),
    removedAt: _int(r['removed_at']),
    addedBy: _str(r['added_by']),
  );

  WishlistBook _wishlistBook(Row r) => WishlistBook(
    id: _int(r['id']) ?? WishlistBook.emptyId,
    title: _str(r['title']) ?? '',
    titleTransliteration: _str(r['title_transliteration']),
    author: _str(r['author']),
    isbn: _str(r['isbn']),
    publisher: _str(r['publisher']),
    publishedYear: _int(r['published_year']),
    coverUrl: _str(r['cover_url']),
    priceEstimate: _double(r['price_estimate']),
    priority: _int(r['priority']) ?? WishlistBook.priorityMed,
    notes: _str(r['notes']),
    source: WishlistSourceX.fromToken(_str(r['source'])),
    addedDate: _int(r['added_date']) ?? 0,
    purchased: _bool(r['purchased']),
    purchasedDate: _int(r['purchased_date']),
    needsMetadata: _bool(r['needs_metadata']),
  );

  // --- tolerant column coercion (SQLite is dynamically typed) ---

  static String? _str(Object? v) => v is String ? v : null;

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Room stores booleans as INTEGER 0/1; any non-zero is true.
  static bool _bool(Object? v) {
    if (v is int) return v != 0;
    if (v is bool) return v;
    if (v is String) return v == '1' || v == 'true';
    return false;
  }
}
