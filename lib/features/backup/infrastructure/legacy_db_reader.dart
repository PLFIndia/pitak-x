/// Reads a legacy Room `books.db` / `wishlist.db` exhaustively and maps every
/// row+column into the Flutter domain entities (decision: one-time translation
/// at restore, then Flutter owns its Drift schema — rather than keeping the
/// Room schema live).
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
///
/// M15 (astra-review.md): every row is passed through `Book.validate` /
/// `WishlistBook.validate` BEFORE it is returned. A backup is untrusted input
/// — anyone can hand the user a `.pitabak` file — and coercion is not
/// validation: an out-of-range `added_date` used to persist and then throw
/// `RangeError` on the detail page; a `priority` of 7 trips the edit form's
/// dropdown assertion; a NaN `price_estimate` makes the next JSON export
/// throw. Because restore is an authoritative overwrite (it replaces the
/// whole catalogue atomically), there is no honest "skip this row" semantic:
/// a backup with a rejected row is a backup that would silently lose that
/// book. So the FIRST invalid row REFUSES the whole archive with a typed
/// [ValidationFailure] naming the table, row id and field — never the value.
/// Cover references are the one exception: they are NORMALISED (dropped to
/// null) and counted, never a rejection, so a real pre-M15 backup carrying a
/// now-disallowed https host still restores (see `Book.validate`).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';

/// The validated result of reading one legacy table: the rows (already
/// normalised by `Book.validate` / `WishlistBook.validate`) and how many
/// cover references were dropped because they pointed to an unsupported site.
final class LegacyRows<T> {
  /// Creates a validated row set.
  const LegacyRows(this.books, {this.coversDropped = 0});

  /// The validated entities, in row order.
  final List<T> books;

  /// Cover references normalised to null (see `Book.validate`).
  final int coversDropped;
}

/// Exhaustive reader over the legacy plain SQLite library/wishlist DBs.
class LegacyDbReader {
  /// Creates a reader over an already-open database (caller owns lifecycle).
  const LegacyDbReader(this._db);

  final CommonDatabase _db;

  /// Reads every row of the `books` table into validated [Book] entities,
  /// preserving `id` and `book_uid`. Tolerant enum tokens (unknown → null).
  ///
  /// Returns a Left on the first row that fails `Book.validate`; the caller
  /// refuses the whole archive. A Right carries the validated rows and the
  /// count of cover references that were normalised to null.
  Either<Failure, LegacyRows<Book>> readBooks() {
    final result = _db.select(
      'SELECT id, book_uid, title, title_transliteration, author, isbn, '
      'publisher, published_year, genre, cover_url, page_count, language, '
      'notes, location, source_type, source_detail, age_group, added_date, '
      'copy_count, needs_metadata, removed, removed_at, added_by FROM books',
    );
    final books = <Book>[];
    var coversDropped = 0;
    for (final row in result) {
      final built = _book(row);
      final checked = Book.validate(built);
      final validated = checked.fold<Book?>((errors) => null, (book) => book);
      if (validated == null) {
        return left(
          _refusal('books', built.id, checked.getLeft().toNullable()!),
        );
      }
      if (built.coverUrl != null && validated.coverUrl == null) {
        coversDropped++;
      }
      books.add(validated);
    }
    return right(LegacyRows(books, coversDropped: coversDropped));
  }

  /// Reads every row of the `wishlist_books` table into validated
  /// [WishlistBook] entities, preserving `id`. Same refuse-on-first-invalid
  /// contract as [readBooks].
  Either<Failure, LegacyRows<WishlistBook>> readWishlist() {
    final result = _db.select(
      'SELECT id, title, title_transliteration, author, isbn, publisher, '
      'published_year, cover_url, price_estimate, priority, notes, source, '
      'added_date, purchased, purchased_date, needs_metadata '
      'FROM wishlist_books',
    );
    final books = <WishlistBook>[];
    var coversDropped = 0;
    for (final row in result) {
      final built = _wishlistBook(row);
      final checked = WishlistBook.validate(built);
      final validated = checked.fold<WishlistBook?>(
        (errors) => null,
        (book) => book,
      );
      if (validated == null) {
        return left(
          _refusal('wishlist_books', built.id, checked.getLeft().toNullable()!),
        );
      }
      if (built.coverUrl != null && validated.coverUrl == null) {
        coversDropped++;
      }
      books.add(validated);
    }
    return right(LegacyRows(books, coversDropped: coversDropped));
  }

  /// Builds the user-facing refusal. Names the table, row id and every
  /// failing field's plain-English label — never the offending value, so no
  /// hostile content reaches the snackbar.
  static ValidationFailure _refusal(
    String table,
    int rowId,
    List<FieldError> errors,
  ) {
    final fields = errors.map((e) => e.userMessage).join(' ');
    return ValidationFailure(
      'This backup can’t be restored: $table row $rowId is invalid. $fields '
      'The backup file may be damaged or was not written by Pitak.',
    );
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
    // M15: a PRESENT but uncoercible added_date (e.g. REAL Infinity) must not
    // silently become the "unset" sentinel 0 — that is coercion, not
    // validation. `_requiredDateMillis` returns null for it, and the row is
    // then refused because null is not a valid required date.
    addedDate: _requiredDateMillis(r['added_date']),
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
    addedDate: _requiredDateMillis(r['added_date']),
    purchased: _bool(r['purchased']),
    purchasedDate: _int(r['purchased_date']),
    needsMetadata: _bool(r['needs_metadata']),
  );

  // --- tolerant column coercion (SQLite is dynamically typed) ---

  static String? _str(Object? v) => v is String ? v : null;

  /// Coerces a column to int. SQLite is dynamically typed, so an INTEGER
  /// column can hold a REAL: `1e400` is stored as +Inf and `0.0/0.0` as NaN,
  /// and Dart `double.toInt()` on a non-finite value THROWS
  /// (`UnsupportedError`). A hostile file must never crash the reader, so —
  /// exactly like `BackupManifest._asInt` — only finite values in the safe
  /// integer range are accepted; anything else is null and the row is then
  /// refused by validation (a required date) or kept as "unset" (optional).
  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is double) {
      if (!v.isFinite || v.abs() > 9007199254740991) return null;
      return v.toInt();
    }
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// A required epoch-millis date column. NULL (absent) maps to the `0`
  /// "unset" sentinel; a present, valid value is kept; a present but
  /// UNCOERCIBLE value (REAL Infinity, an unparseable string) maps to null so
  /// the row is refused by `Book.validate` / `WishlistBook.validate` instead
  /// of being silently rewritten to "unset".
  static int _requiredDateMillis(Object? v) {
    if (v == null) return 0;
    return _int(v) ?? -1; // -1 is always invalid → validation refuses the row
  }

  /// Coerces a column to double. NaN/Infinity are returned as-is on purpose:
  /// `CatalogueRules.isValidPrice` rejects them downstream, and the typed
  /// refusal is the visible behaviour we want — not a silent null.
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
