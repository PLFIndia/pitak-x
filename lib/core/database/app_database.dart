/// Drift database for the non-secret stores (books + wishlist + network).
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

/// Columns mirrored into the FTS5 index (matches Kotlin `books_fts`).
const _ftsColumns =
    'title, title_transliteration, author, isbn, location, genre';

/// The non-secret application database (books + wishlist + network).
@DriftDatabase(tables: [Books, WishlistBooks, NetworkLibraries])
class AppDatabase extends _$AppDatabase {
  /// Opens the database over the given [executor].
  AppDatabase(super.executor);

  /// Schema history:
  ///  1 — initial (books + wishlist + FTS5).
  ///  2 — no shape change; data clean-up: one spelling per language
  ///      (Session 33, [_collapseLanguageSpellings]).
  ///  3 — `network_libraries` table added (libNetwork.md S3): saved libraries
  ///      on the network replace the old prefs bookmarks (ADR 0012).
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await _collapseLanguageSpellings();
      // v3: a brand-new empty table — drift creates it from the snapshot-
      // validated definition; the legacy bookmarks data migration into it
      // happens separately (prefs → rows, libNetwork.md S4), not here.
      if (from < 3) await m.createTable(networkLibraries);
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
                new.isbn, new.location, new.genre);
      END;''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS books_fts_ad AFTER DELETE ON books BEGIN
        INSERT INTO books_fts(books_fts, rowid, $_ftsColumns)
        VALUES ('delete', old.id, old.title, old.title_transliteration,
                old.author, old.isbn, old.location, old.genre);
      END;''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS books_fts_au AFTER UPDATE ON books BEGIN
        INSERT INTO books_fts(books_fts, rowid, $_ftsColumns)
        VALUES ('delete', old.id, old.title, old.title_transliteration,
                old.author, old.isbn, old.location, old.genre);
        INSERT INTO books_fts(rowid, $_ftsColumns)
        VALUES (new.id, new.title, new.title_transliteration, new.author,
                new.isbn, new.location, new.genre);
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
