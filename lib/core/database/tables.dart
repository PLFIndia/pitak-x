/// Drift table definitions for the NON-secret stores (books, wishlist).
///
/// Every column the Kotlin Room schema had is carried here (verified against
/// `app/schemas/.../BooksDatabase/10.json` and `WishlistDatabase/1.json`), with
/// idiomatic Drift naming via `.named()` to keep the on-disk column names
/// identical to Room — so the migration reader maps 1:1. The encrypted vault
/// (borrowers/loans) is NOT here; it lives in the Rust core (PLAN.md Q3).
library;

import 'package:drift/drift.dart';

/// Library books. Mirrors Room `books` (25 columns, schema v10).
@DataClassName('BookRow')
class Books extends Table {
  @override
  String get tableName => 'books';

  /// Per-device autoincrement id.
  IntColumn get id => integer().autoIncrement()();

  /// Stable cross-device UUID (unique among non-null). Minted at first persist.
  TextColumn get bookUid => text().named('book_uid').nullable()();

  /// Required title (native script).
  TextColumn get title => text()();

  /// Roman-script search aid.
  TextColumn get titleTransliteration =>
      text().named('title_transliteration').nullable()();

  /// Author.
  TextColumn get author => text().nullable()();

  /// Unicode-aware lowercase shadow of title for sorting (not SQL LOWER()).
  TextColumn get titleSort =>
      text().named('title_sort').withDefault(const Constant(''))();

  /// Unicode-aware lowercase shadow of author for sorting.
  TextColumn get authorSort =>
      text().named('author_sort').withDefault(const Constant(''))();

  /// ISBN (unique among non-null values).
  TextColumn get isbn => text().nullable()();

  /// Publisher.
  TextColumn get publisher => text().nullable()();

  /// Year of publication.
  IntColumn get publishedYear => integer().named('published_year').nullable()();

  /// Genre.
  TextColumn get genre => text().nullable()();

  /// Cover reference (relative/file/remote).
  TextColumn get coverUrl => text().named('cover_url').nullable()();

  /// Page count.
  IntColumn get pageCount => integer().named('page_count').nullable()();

  /// Language.
  TextColumn get language => text().nullable()();

  /// Private notes.
  TextColumn get notes => text().nullable()();

  /// Private shelf location.
  TextColumn get location => text().nullable()();

  /// Provenance category (enum name), private.
  TextColumn get sourceType => text().named('source_type').nullable()();

  /// Free-form provenance detail, private.
  TextColumn get sourceDetail => text().named('source_detail').nullable()();

  /// Age band token (e.g. `above-3`), public.
  TextColumn get ageGroup => text().named('age_group').nullable()();

  /// Epoch millis at insert.
  IntColumn get addedDate => integer().named('added_date')();

  /// Physical copy count.
  IntColumn get copyCount =>
      integer().named('copy_count').withDefault(const Constant(1))();

  /// Metadata-pending flag.
  BoolColumn get needsMetadata =>
      boolean().named('needs_metadata').withDefault(const Constant(false))();

  /// Soft-delete flag.
  BoolColumn get removed => boolean().withDefault(const Constant(false))();

  /// Epoch millis when removed; null when active.
  IntColumn get removedAt => integer().named('removed_at').nullable()();

  /// Maintainer attribution handle.
  TextColumn get addedBy => text().named('added_by').nullable()();
}

/// Wishlist books. Mirrors Room `wishlist_books` (16 columns, schema v1).
@DataClassName('WishlistRow')
class WishlistBooks extends Table {
  @override
  String get tableName => 'wishlist_books';

  /// Per-device autoincrement id.
  IntColumn get id => integer().autoIncrement()();

  /// Required title.
  TextColumn get title => text()();

  /// Roman-script search aid.
  TextColumn get titleTransliteration =>
      text().named('title_transliteration').nullable()();

  /// Author.
  TextColumn get author => text().nullable()();

  /// ISBN (unique among non-null values).
  TextColumn get isbn => text().nullable()();

  /// Publisher.
  TextColumn get publisher => text().nullable()();

  /// Year of publication.
  IntColumn get publishedYear => integer().named('published_year').nullable()();

  /// Cover reference.
  TextColumn get coverUrl => text().named('cover_url').nullable()();

  /// Estimated price (REAL in Room).
  RealColumn get priceEstimate => real().named('price_estimate').nullable()();

  /// Priority: 0=low, 1=med (default), 2=high.
  IntColumn get priority => integer().withDefault(const Constant(1))();

  /// Notes.
  TextColumn get notes => text().nullable()();

  /// How added (enum name); Room default is non-null.
  TextColumn get source => text().withDefault(const Constant('MANUAL'))();

  /// Epoch millis at insert.
  IntColumn get addedDate => integer().named('added_date')();

  /// Purchased flag.
  BoolColumn get purchased => boolean().withDefault(const Constant(false))();

  /// Epoch millis when purchased; null otherwise.
  IntColumn get purchasedDate => integer().named('purchased_date').nullable()();

  /// Metadata-pending flag.
  BoolColumn get needsMetadata =>
      boolean().named('needs_metadata').withDefault(const Constant(false))();
}
