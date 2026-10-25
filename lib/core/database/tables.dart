/// Drift table definitions for the NON-secret stores (books, wishlist,
/// network, periodicals).
///
/// Every column the Kotlin Room schema had is carried here (verified against
/// `app/schemas/.../BooksDatabase/10.json` and `WishlistDatabase/1.json`), with
/// idiomatic Drift naming via `.named()` to keep the on-disk column names
/// identical to Room — so the migration reader maps 1:1. The encrypted vault
/// (borrowers/loans) is NOT here; it lives in the Rust core (decision: secrets
/// never live in Dart-side storage).
library;

import 'package:drift/drift.dart';

/// Catalogue items of every kind — the base row (ADR 0013 F1). Mirrors Room
/// `books` (25 columns, schema v10) plus `kind` (schema v5).
@DataClassName('BookRow')
class Books extends Table {
  @override
  String get tableName => 'books';

  /// Per-device autoincrement id.
  IntColumn get id => integer().autoIncrement()();

  /// Stable cross-device UUID (unique among non-null). Minted at first persist.
  /// The column stays `book_uid` (persisted contract, plan F7); only the Dart
  /// getter says "item" because the row is the base of every item kind.
  TextColumn get itemUid => text().named('book_uid').nullable()();

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

  /// What the row is: an `ItemKind` token (`book` | `magazine-issue` |
  /// `other`), schema v5 (ADR 0013 F3). Rows that predate the column read
  /// as books through the default; an unknown token is kept as stored (a
  /// newer build wrote it) and refused on write-back (F6).
  TextColumn get kind => text().withDefault(const Constant('book'))();
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

/// Saved libraries on the network (docs/ARCHITECTURE.md §5.4, schema v3).
///
/// One row per OTHER library the user cares about — a bookmark, a hub's
/// member added by card scan, or a library discovered through a fetched
/// descriptor. The row is the single truth the old bookmarks list was
/// replaced by (ADR 0012): `siteUrl` is the natural key (unique), and the
/// published identity is the `fingerprint` (never the raw library ID, D3).
///
/// Unlike books/wishlist this table is NOT Room-mirrored: nothing here needs
/// byte-compatibility with the Kotlin schema, so the uniqueness constraints
/// are declared drift-side (`uniqueKeys`, `.unique()`) and appear in the
/// schema snapshots — no raw-SQL indexes to babysit in `beforeOpen`.
@DataClassName('NetworkLibraryRow')
class NetworkLibraries extends Table {
  @override
  String get tableName => 'network_libraries';

  /// Per-device autoincrement id.
  IntColumn get id => integer().autoIncrement()();

  /// Published site root URL (`BookmarkUrl`-normalized) — the natural key.
  TextColumn get siteUrl => text().named('site_url').unique()();

  /// Display name ('' until known — a URL-added row before its first fetch).
  TextColumn get name => text().withDefault(const Constant(''))();

  /// Published identity fingerprint (64 lowercase hex), or NULL until a
  /// fetch/scan supplies it. UNIQUE among non-null values: SQLite treats
  /// NULLs as distinct in a UNIQUE constraint, so any number of
  /// not-yet-identified rows may coexist while two rows can never claim the
  /// same fingerprint.
  TextColumn get fingerprint => text().nullable()();

  /// Opted-in latitude, or NULL when the library publishes none.
  RealColumn get lat => real().nullable()();

  /// Opted-in longitude, or NULL when the library publishes none.
  RealColumn get lng => real().nullable()();

  /// `LocationPrecision` token for lat/lng ('approximate'|'exact'), NULL
  /// exactly when the coordinates are NULL.
  TextColumn get precision => text().nullable()();

  /// How the row got here: `NetworkSource` token
  /// ('bookmark'|'card'|'discovered').
  TextColumn get source => text()();

  /// True when I (as a hub) added this library by scanning its card.
  BoolColumn get isMember =>
      boolean().named('is_member').withDefault(const Constant(false))();

  /// True when a fetch confirmed the published fingerprint equals the one
  /// scanned from the card (in-person add + network agreement).
  BoolColumn get memberVerified =>
      boolean().named('member_verified').withDefault(const Constant(false))();

  /// For discovered rows: the hub site URL whose descriptor listed this
  /// library (NULL for seeds).
  TextColumn get listedByHubUrl =>
      text().named('listed_by_hub_url').nullable()();

  /// Am I a member of THIS row (when it is a hub)? `MembershipState` token
  /// ('none'|'pending'|'confirmed'|'declined').
  TextColumn get membership => text().withDefault(const Constant('none'))();

  /// Last descriptor-fetch outcome: `FetchStatus` token
  /// ('never'|'ok'|'unreachable'|'invalid'|'schemaTooNew'|'identityConflict').
  TextColumn get fetchStatus =>
      text().named('fetch_status').withDefault(const Constant('never'))();

  /// Epoch millis of the last successful descriptor fetch (NULL = never).
  IntColumn get fetchedAt => integer().named('fetched_at').nullable()();

  /// Epoch millis when the row was created on this device.
  IntColumn get createdAt => integer().named('created_at')();

  /// Display order among the user's own rows (preserves the old bookmark
  /// order through the one-time migration; new rows append).
  IntColumn get sortOrder => integer().named('sort_order')();

  /// For rows a hub listed (`listed_by_hub_url`): the member's OWN
  /// descriptor links back to that hub via `memberOf` — the reciprocal
  /// consent behind the "Confirmed by member" badge (schema v4).
  BoolColumn get confirmedByMember => boolean()
      .named('confirmed_by_member')
      .withDefault(const Constant(false))();

  /// Fingerprint is unique among non-null values (see the column doc). The
  /// drift-visible UNIQUE ends up in the schema snapshot, which the
  /// migration tests validate against — a raw-SQL index would be invisible
  /// there.
  @override
  List<Set<Column>> get uniqueKeys => [
    {fingerprint},
  ];
}

/// Kind-specific data of a magazine issue (ADR 0013 F4, D1): one row per
/// `books` row whose `kind` is `magazine-issue`, 1:1 through [itemId].
///
/// This is the first table with a REAL foreign key (`ON DELETE CASCADE`):
/// deleting the base row deletes its detail row, so a hard delete, a
/// `replaceAll` and a restore never leave an orphan detail. SQLite only
/// enforces foreign keys when `PRAGMA foreign_keys = ON`, which
/// `AppDatabase` sets in `beforeOpen` (schema v5; no earlier table declares
/// a FK, so turning it on changes nothing else). `periodicalUid` is a SOFT
/// link to `periodicals` (D8: deleting a periodical with issues fails closed
/// in the repository instead).
@DataClassName('MagazineIssueRow')
class MagazineIssues extends Table {
  @override
  String get tableName => 'magazine_issues';

  /// The base row (`books.id`); also the primary key.
  IntColumn get itemId => integer()
      .named('item_id')
      .references(Books, #id, onDelete: KeyAction.cascade)();

  /// `periodicals.periodical_uid` of the series (soft link).
  TextColumn get periodicalUid => text().named('periodical_uid')();

  /// Volume number, when the magazine numbers volumes.
  IntColumn get volume => integer().nullable()();

  /// Issue number, when known.
  IntColumn get issueNumber => integer().named('issue_number').nullable()();

  /// Cover calendar day at 00:00 UTC (epoch millis); first issue of a bound
  /// volume. This is a date-only value, not a local-midnight instant.
  IntColumn get issueDate => integer().named('issue_date').nullable()();

  /// Last issue calendar day at 00:00 UTC (epoch millis); NULL for a single
  /// issue. Range arithmetic and display use UTC calendar fields.
  IntColumn get boundUntil => integer().named('bound_until').nullable()();

  /// Free-text label ("Dasara special"). Not in the FTS index (D10).
  TextColumn get issueLabel => text().named('issue_label').nullable()();

  @override
  Set<Column> get primaryKey => {itemId};
}

/// Magazine titles (ADR 0013 D2), schema v5. Not Room-mirrored. The
/// cross-device identity is `periodical_uid`; the ISSN is unique among
/// non-null values (D7). Both UNIQUE indexes are raw SQL in
/// `AppDatabase._createIndexesAndFts`, next to the `books` ones, and listed
/// in the migration test's raw-object census.
@DataClassName('PeriodicalRow')
class Periodicals extends Table {
  @override
  String get tableName => 'periodicals';

  /// Per-device autoincrement id.
  IntColumn get id => integer().autoIncrement()();

  /// Stable cross-device UUID, minted at first persist (never NULL: the
  /// repository mints before the insert).
  TextColumn get periodicalUid => text().named('periodical_uid')();

  /// Required title (native script).
  TextColumn get title => text()();

  /// Roman-script search aid.
  TextColumn get titleTransliteration =>
      text().named('title_transliteration').nullable()();

  /// Unicode-aware lowercase shadow of title for sorting.
  TextColumn get titleSort =>
      text().named('title_sort').withDefault(const Constant(''))();

  /// Canonical ISSN `NNNN-NNNC`, unique among non-null values.
  TextColumn get issn => text().nullable()();

  /// Publisher.
  TextColumn get publisher => text().nullable()();

  /// Language.
  TextColumn get language => text().nullable()();

  /// Series cover reference (relative/file/remote).
  TextColumn get coverUrl => text().named('cover_url').nullable()();

  /// `PeriodicalFrequency` token.
  TextColumn get frequency => text().nullable()();

  /// Subscription start calendar day at 00:00 UTC (epoch millis), private.
  /// Date-only value; addedDate/removedAt remain instants.
  IntColumn get subscriptionStart =>
      integer().named('subscription_start').nullable()();

  /// Subscription end calendar day at 00:00 UTC (epoch millis), private;
  /// NULL = untracked (D5). The entire local end date remains in-window.
  IntColumn get subscriptionEnd =>
      integer().named('subscription_end').nullable()();

  /// Private notes.
  TextColumn get notes => text().nullable()();

  /// Private shelf location.
  TextColumn get location => text().nullable()();

  /// Provenance category (enum token), private.
  TextColumn get sourceType => text().named('source_type').nullable()();

  /// Free-form provenance detail, private.
  TextColumn get sourceDetail => text().named('source_detail').nullable()();

  /// Age band token (e.g. `above-3`), public; projected onto issues.
  TextColumn get ageGroup => text().named('age_group').nullable()();

  /// Epoch millis at insert.
  IntColumn get addedDate => integer().named('added_date')();

  /// Soft-delete flag.
  BoolColumn get removed => boolean().withDefault(const Constant(false))();

  /// Epoch millis when removed; null when active.
  IntColumn get removedAt => integer().named('removed_at').nullable()();

  /// Maintainer attribution handle.
  TextColumn get addedBy => text().named('added_by').nullable()();
}
