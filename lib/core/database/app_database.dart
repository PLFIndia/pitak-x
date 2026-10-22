/// Drift database for the non-secret stores (books + wishlist + network +
/// periodicals).
///
/// The encrypted borrowers vault is NOT here — it is owned by the Rust core
/// (decision: secrets never live in Dart-side storage). FTS5 mirrors the
/// five-field search the Kotlin app derived from `books_fts` (FTS4
/// external-content); we rebuild it as FTS5 rather than migrating the virtual
/// table (decision: a derived index is rebuilt, not migrated).
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/tables.dart';
import 'package:pitaka/features/library/domain/value_objects/language_merge_plan.dart';

part 'app_database.g.dart';

/// Columns mirrored into the FTS5 index: the Kotlin `books_fts` five plus
/// `notes` since schema v5 (ADR 0013 D10 — an "other" item is described in
/// its notes, so the description must be searchable; search is on-device,
/// so indexing private notes leaks nothing).
const _ftsColumns =
    'title, title_transliteration, author, isbn, location, genre, notes';

/// The non-secret application database (books + wishlist + network +
/// periodicals).
@DriftDatabase(
  tables: [Books, WishlistBooks, NetworkLibraries, MagazineIssues, Periodicals],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the database over the given [executor].
  AppDatabase(super.executor);

  /// Schema history:
  ///  1 — initial (books + wishlist + FTS5).
  ///  2 — no shape change; data clean-up: one spelling per language
  ///      (Session 33, [_collapseLanguageSpellings]).
  ///  3 — `network_libraries` table added (docs/ARCHITECTURE.md §3 network): saved libraries
  ///      on the network replace the old prefs bookmarks (ADR 0012).
  ///  4 — `network_libraries.confirmed_by_member` added (design 2026-10-18):
  ///      reciprocal member→hub consent (`memberOf` link-back) for the
  ///      "Confirmed by member" badge.
  ///  5 — catalogue item kinds (ADR 0013): `books.kind` (default `'book'`),
  ///      detail table `magazine_issues` (FK → books, ON DELETE CASCADE) and
  ///      `periodicals`; the FTS5 index is dropped and rebuilt with `notes`
  ///      added to its columns (D10). `PRAGMA foreign_keys = ON` from here on.
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await _collapseLanguageSpellings();
      // v3: a brand-new empty table — drift creates it from the snapshot-
      // validated definition; the legacy bookmarks data migration into it
      // happens separately (prefs → rows, docs/ARCHITECTURE.md §3 network), not here.
      //
      // ELSE-IF, not two ifs: `createTable` builds the table at its CURRENT
      // definition, which already includes the v4 column — a v1/v2 database
      // taking the create branch must not also run `addColumn` (duplicate
      // column error, proven by the v1→current migration test).
      if (from < 3) {
        await m.createTable(networkLibraries);
      } else if (from < 4) {
        // v4: an additive boolean with a default — existing rows read as
        // "not confirmed" until the next refresh re-evaluates the link-back.
        await m.addColumn(networkLibraries, networkLibraries.confirmedByMember);
      }
      // v5 (ADR 0013): a SEPARATE `if` — every older version, including one
      // that just took the `createTable(networkLibraries)` branch above, must
      // also get the item-kind objects. Two new tables and one additive
      // column with a default (`books.kind`): existing rows read as books.
      if (from < 5) {
        await m.createTable(periodicals);
        await m.createTable(magazineIssues);
        await m.addColumn(books, books.kind);
        // D10: the FTS index gains `notes`. An FTS5 virtual table cannot
        // add a column, and it is a DERIVED index (rebuilt, not migrated), so
        // it is dropped here — with its triggers, which name the old column
        // list — and `beforeOpen` recreates both with the new list and
        // rebuilds the index from `books` (one-time cost, timed in the
        // migration test).
        for (final trigger in [
          'books_fts_ai',
          'books_fts_ad',
          'books_fts_au',
        ]) {
          await customStatement('DROP TRIGGER IF EXISTS $trigger');
        }
        await customStatement('DROP TABLE IF EXISTS books_fts');
      }
    },
    // Runs on EVERY open, after onCreate/onUpgrade: the raw-SQL objects
    // (unique indexes, FTS5 table, sync triggers) are an invariant, not a
    // migration step. They are invisible to drift's schema model, so a future
    // upgrade that rebuilds `books` (SQLite drops the triggers with the
    // table) would otherwise silently leave search broken. Every statement is
    // `IF NOT EXISTS` — a few sqlite_master lookups on a healthy database;
    // on a damaged one it heals, and a re-created FTS table starts empty, so
    // it is rebuilt from `books` (triggers only index future writes). The
    // migration tests prove search works after every historical upgrade path.
    beforeOpen: (details) async {
      // Schema v5 adds the first real foreign key (`magazine_issues.item_id`
      // → `books.id` ON DELETE CASCADE). SQLite enforces foreign keys only
      // while this pragma is on, and it is per-connection, so it is set on
      // every open. Safe for existing data: no earlier table declares a FK,
      // so nothing that was legal before becomes a violation now.
      await customStatement('PRAGMA foreign_keys = ON');
      final hadFts = await _hasFtsTable();
      await _createIndexesAndFts();
      if (!hadFts) await rebuildFts();
    },
  );

  Future<bool> _hasFtsTable() async {
    final rows = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'books_fts'",
    ).get();
    return rows.isNotEmpty;
  }

  /// v1 → v2: collapse `English` / `english` / `en` into ONE stored spelling
  /// per language, so the catalogue filter shows one chip and the exact-match
  /// facet (D1-a) finds every book. The decision (which spelling wins) is the
  /// pure `LanguageMergePlan`; this method only reads the counts and applies
  /// the renames. One transaction: either every rename lands or none does.
  /// Idempotent — on clean data the plan is empty and nothing is written.
  ///
  /// Why in Dart and not one SQL statement: "same language" must ignore case
  /// for non-Latin scripts too, and SQLite's `lower()` is ASCII-only.
  Future<void> _collapseLanguageSpellings() async {
    await transaction(() async {
      final rows = await customSelect(
        'SELECT language, COUNT(*) AS n FROM books '
        "WHERE language IS NOT NULL AND TRIM(language) != '' "
        'GROUP BY language',
      ).get();
      final usage = <String, int>{
        for (final r in rows) r.read<String>('language'): r.read<int>('n'),
      };
      for (final rename in LanguageMergePlan.plan(usage)) {
        await customUpdate(
          'UPDATE books SET language = ? WHERE language = ?',
          variables: [Variable(rename.to), Variable(rename.from)],
          updates: {books},
        );
      }
    });
  }

  Future<void> _createIndexesAndFts() async {
    // Unique indexes mirroring Room (ISBN + book_uid unique among non-null).
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_books_isbn ON books (isbn)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_books_book_uid '
      'ON books (book_uid)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS index_books_added_date ON books (added_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS index_books_title_sort ON books (title_sort)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS index_books_author_sort '
      'ON books (author_sort)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_wishlist_books_isbn '
      'ON wishlist_books (isbn)',
    );

    // Schema v5 (ADR 0013): kind facet, issue identity keys (D6) and the
    // periodical identities (D2, D7). The two issue keys are PARTIAL unique
    // indexes: a numbered single issue is unique per (series, volume-or-0,
    // number); a bound volume is unique per (series, first date, last date).
    // `COALESCE(volume, 0)` makes "no volume" one bucket instead of SQLite's
    // NULL-is-always-distinct rule. Raw SQL because drift cannot express a
    // partial or expression index; `index_periodicals_*` sit here with them
    // so the migration test's raw-object census covers all six.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS index_books_kind ON books (kind)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS index_magazine_issues_periodical_uid '
      'ON magazine_issues (periodical_uid)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_magazine_issues_number_key '
      'ON magazine_issues (periodical_uid, COALESCE(volume, 0), issue_number) '
      'WHERE issue_number IS NOT NULL AND bound_until IS NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_magazine_issues_bound_key '
      'ON magazine_issues (periodical_uid, issue_date, bound_until) '
      'WHERE bound_until IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_periodicals_periodical_uid '
      'ON periodicals (periodical_uid)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS index_periodicals_issn '
      'ON periodicals (issn)',
    );

    // FTS5 contentless-external index over books (rebuilt, not migrated).
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS books_fts USING fts5('
      '$_ftsColumns, content=books, content_rowid=id)',
    );
    // Triggers keep books_fts in sync (mirror Room's external-content sync).
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS books_fts_ai AFTER INSERT ON books BEGIN
        INSERT INTO books_fts(rowid, $_ftsColumns)
        VALUES (new.id, new.title, new.title_transliteration, new.author,
                new.isbn, new.location, new.genre, new.notes);
      END;''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS books_fts_ad AFTER DELETE ON books BEGIN
        INSERT INTO books_fts(books_fts, rowid, $_ftsColumns)
        VALUES ('delete', old.id, old.title, old.title_transliteration,
                old.author, old.isbn, old.location, old.genre, old.notes);
      END;''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS books_fts_au AFTER UPDATE ON books BEGIN
        INSERT INTO books_fts(books_fts, rowid, $_ftsColumns)
        VALUES ('delete', old.id, old.title, old.title_transliteration,
                old.author, old.isbn, old.location, old.genre, old.notes);
        INSERT INTO books_fts(rowid, $_ftsColumns)
        VALUES (new.id, new.title, new.title_transliteration, new.author,
                new.isbn, new.location, new.genre, new.notes);
      END;''');
  }

  /// Rebuilds the FTS5 index from current `books` rows.
  ///
  /// Used after a bulk restore/import where rows were inserted with triggers
  /// possibly disabled, to guarantee the index matches the table.
  Future<void> rebuildFts() async {
    await customStatement("INSERT INTO books_fts(books_fts) VALUES('rebuild')");
  }
}
