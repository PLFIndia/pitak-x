/// Drift-backed implementation of [CatalogueItemRepository] (AGENTS.md §3.3).
///
/// Side effects live at this edge; expected failures are caught and returned as
/// typed [Failure]s (fail-closed). UUIDs are minted here at first persist,
/// mirroring Kotlin `BookMapper.toEntity`.
///
/// ## Ordering, filtering AND paging happen INSIDE SQLite (N10-d, review N10)
///
/// The one list read, [DriftCatalogueItemRepository.page], has two statements
/// behind it — a typed Drift select for a blank search box and a hand-written
/// FTS5 join for typed text — and both return rows in their FINAL order,
/// already narrowed to the language facet, already cut to the requested window.
/// Nothing is re-sorted, re-filtered or sliced in Dart afterwards. Why that
/// matters: a `LIMIT/OFFSET` page can only be correct if SQLite's rows
/// `offset..offset+limit` ARE the rows the user should see there. Until S29 the
/// Age-group sort ordered by the raw token in SQL (`above-10 < above-15 <
/// above-3`, alphabetical) and fixed the order in Dart — fine for a whole-table
/// read, wrong for any page. Until S30 the controller read the whole catalogue
/// on every load.
///
/// The ordering rules are the domain's `CatalogueItemSorter` contract (N05).
/// The SQL twin lives in `drift_catalogue_sql.dart` (`CatalogueSql`), and
/// `drift_catalogue_item_repository_test.dart` proves the two agree for every
/// sort × filter combination on a seeded fixture, read back through small
/// pages so every seam is crossed.
///
/// `hasMore` is decided here by asking for `limit + 1` rows and dropping the
/// extra one: one statement, no `COUNT(*)` (which over the FTS join would be
/// a second full walk of the index).
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_collisions.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_interchange.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_sql.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';
import 'package:uuid/uuid.dart';

/// Persists catalogue items of every kind in the Drift [AppDatabase]
/// (ADR 0013): the base row in `books`, an issue's detail row in
/// `magazine_issues` through [DriftItemDetails], both in one transaction.
class DriftCatalogueItemRepository implements CatalogueItemRepository {
  /// Creates the repository over [_db], optionally with a custom [Uuid].
  DriftCatalogueItemRepository(this._db, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      _details = DriftItemDetails(_db),
      _collisions = CatalogueCollisions(_db);

  final AppDatabase _db;
  final Uuid _uuid;
  final DriftItemDetails _details;
  final CatalogueCollisions _collisions;

  CatalogueItem _toDomain(TypedResult row) =>
      row.toCatalogueItem(_db, _details);

  /// Keeps the returned entity, D6 lookup and stored companion on the same
  /// canonical issue dates, even for a direct repository caller.
  CatalogueItem _normalizedDates(CatalogueItem book) {
    final issue = book.issue;
    return issue == null ? book : book.copyWith(details: issue.normalized());
  }

  /// One row by base-row [id] with its details, or null.
  Future<CatalogueItem?> _getById(int id) async {
    final row =
        await (CatalogueSql.joined(_db)
              ..where(_db.books.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  Future<List<TypedResult>> _allRows() => (CatalogueSql.joined(
    _db,
  )..orderBy([OrderingTerm.desc(_db.books.addedDate)])).get();

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async {
    try {
      final rows = await _allRows();
      return right(rows.map(_toDomain).toList());
    } on Object catch (e) {
      return left(StorageFailure('getAll: $e'));
    }
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async {
    try {
      final rows = await _allRows();
      for (final row in rows) {
        final failure = catalogueInterchangeIntegrityFailure(_db, row);
        if (failure != null) return left(failure);
      }
      return right(rows.map(_toDomain).toList());
    } on Object catch (e) {
      return left(StorageFailure('getAllForInterchange: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    // Boundary clamps (AGENTS.md §6.5): the window is produced by the
    // controller, never by the user, but a bug or a hostile caller must not
    // be able to ask SQLite for a negative window or the whole catalogue.
    final size = limit.clamp(1, maxLibraryPageSize);
    final skip = offset < 0 ? 0 : offset;
    try {
      // +1 probe row: if it comes back, another page exists. Dropped below.
      final rows = query.isSearch
          ? await CatalogueSql.searchRows(
              _db,
              _details,
              query,
              limit: size + 1,
              offset: skip,
            )
          : await _listRows(query, limit: size + 1, offset: skip);
      final hasMore = rows.length > size;
      final items = (hasMore ? rows.take(size) : rows).toList(growable: false);
      return right(CatalogueItemPage(items: items, hasMore: hasMore));
    } on Object catch (e) {
      return left(StorageFailure('page: $e'));
    }
  }

  /// Blank search box: typed Drift select over the join, narrowed to the
  /// facets ([CatalogueSql.facetPredicate]), ordered by
  /// [CatalogueSql.orderingTerms] — or, on a series page, by the issue
  /// rules ([CatalogueSql.issueOrderingTerms]) — and windowed by SQLite.
  Future<List<CatalogueItem>> _listRows(
    LibraryQuery query, {
    required int limit,
    required int offset,
  }) async {
    final q = CatalogueSql.joined(_db);
    final facets = CatalogueSql.facetPredicate(_db, query);
    if (facets != null) q.where(facets);
    final order = query.periodicalUid == null
        ? CatalogueSql.orderingTerms(
            query.sort,
          ).map((term) => term(_db.books)).toList()
        : CatalogueSql.issueOrderingTerms(_db);
    q
      ..orderBy(order)
      // Drift writes `LIMIT n OFFSET m` from these two ints (verified in
      // drift 2.28.2 `components/limit.dart`); they are clamped ints, never
      // user text.
      ..limit(limit, offset: offset);
    final rows = await q.get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    try {
      return right(await _storedLanguages());
    } on Object catch (e) {
      return left(StorageFailure('distinctLanguages: $e'));
    }
  }

  /// The distinct non-blank language spellings currently stored, A→Z
  /// case-insensitively. Shared by [distinctLanguages] and by every write,
  /// which snaps an incoming language to one of these (Session 33).
  Future<List<String>> _storedLanguages() async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT language FROM books '
          "WHERE language IS NOT NULL AND TRIM(language) != '' "
          'ORDER BY language COLLATE NOCASE ASC',
          readsFrom: {_db.books},
        )
        .get();
    return rows.map((r) => r.read<String>('language')).toList();
  }

  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async {
    try {
      // SQLite does the heavy lifting (one indexed-column scan, distinct,
      // sorted); the bound parameter is the enum's storage token, never user
      // text. `COLLATE NOCASE` orders case-insensitively (ASCII only — fine
      // for ORDER, the dedupe below is Unicode-aware).
      final rows = await _db
          .customSelect(
            'SELECT DISTINCT TRIM(source_detail) AS detail FROM books '
            'WHERE source_type = ? '
            "AND source_detail IS NOT NULL AND TRIM(source_detail) != '' "
            'ORDER BY detail COLLATE NOCASE ASC',
            variables: [Variable<String>(type.token)],
            readsFrom: {_db.books},
          )
          .get();
      // Collapse spellings that differ only by case into the first one seen
      // (sort order = the lower-cased-first spelling wins), keyed exactly as
      // the export filter compares, so every entry here matches a book.
      final seen = <String>{};
      final details = <String>[];
      for (final row in rows) {
        final detail = row.read<String>('detail');
        final key = CatalogueRules.sourceDetailKey(detail);
        if (key != null && seen.add(key)) details.add(detail);
      }
      return right(details);
    } on Object catch (e) {
      return left(StorageFailure('distinctSourceDetails: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    try {
      return right(await _getById(id));
    } on Object catch (e) {
      return left(StorageFailure('getById: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    try {
      // One transaction: the "which spellings exist" read and the insert
      // cannot interleave with another write, so two concurrent adds of
      // `english` and `English` still end up as one spelling.
      return await _db.transaction(() async {
        final resolver = LanguageResolver(await _storedLanguages());
        final resolved = resolver.resolve(_normalizedDates(book));
        final withUid = resolved.itemUid == null
            ? resolved.copyWith(itemUid: _uuid.v4())
            : resolved;
        final id = await _db.into(_db.books).insert(withUid.toCompanion());
        // The detail row (an issue's volume/number/dates) lands in the same
        // transaction as the base row: both or neither (ADR 0013 F4).
        await _details.write(id, withUid.details);
        return right<Failure, CatalogueItem>(withUid.copyWith(id: id));
      });
    } on Object catch (e) {
      // S34 race net: the UNIQUE isbn index may have refused this write (a
      // concurrent add slipped past the use-case pre-check). Instead of
      // parsing SQLite exception text, ask the table: if a colliding row
      // exists NOW, the honest user-facing failure is "already in your
      // library". Anything else keeps the opaque storage error.
      final duplicate = await _collisions.isbn(book.isbn);
      if (duplicate != null) return left(duplicate);
      // Same net for the two issue identity keys (ADR 0013 D6).
      final duplicateIssue = await _collisions.issue(book.issue);
      if (duplicateIssue != null) return left(duplicateIssue);
      return left(StorageFailure('insert: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    if (book.id == CatalogueItem.emptyId) {
      return left(const NotFoundFailure());
    }
    try {
      return await _db.transaction(() async {
        // Read the joined detail state, not just the base row: writing a
        // fail-soft display fallback back would turn a corrupt/unknown row
        // into a canonical book and destroy its original kind evidence.
        final existingRow =
            await (CatalogueSql.joined(_db)
                  ..where(_db.books.id.equals(book.id))
                  ..limit(1))
                .getSingleOrNull();
        if (existingRow == null) {
          return left<Failure, CatalogueItem>(const NotFoundFailure());
        }
        final integrity = catalogueInterchangeIntegrityFailure(
          _db,
          existingRow,
        );
        if (integrity != null) return left<Failure, CatalogueItem>(integrity);
        final existing = existingRow.readTable(_db.books);
        // Preserve the stable book_uid: an edit must never lose the
        // cross-device merge key. If the incoming book dropped it, recover it
        // from the row.
        // The row's own current spelling is part of the stored set, so
        // re-typing `english` on the only English book keeps `English`:
        // one spelling per language, consistently. (A library-wide
        // "rename language" is a separate feature, not an edit side-effect.)
        final resolver = LanguageResolver(await _storedLanguages());
        final resolved = resolver.resolve(_normalizedDates(book));
        final preserved = resolved.itemUid == null
            ? resolved.copyWith(itemUid: existing.itemUid)
            : resolved;
        // `update().replace` matches on the primary key; FTS5 stays in sync
        // via the AFTER UPDATE trigger in app_database.dart.
        await _db.update(_db.books).replace(preserved.toCompanion());
        await _details.write(preserved.id, preserved.details);
        return right<Failure, CatalogueItem>(preserved);
      });
    } on Object catch (e) {
      // S34 race net, same as [insert]: an edit moved onto ANOTHER row's ISBN
      // is refused by the UNIQUE index; report it as the duplicate it is.
      // The book's own id is excluded — keeping your own ISBN is no collision.
      final duplicate = await _collisions.isbn(book.isbn, excludeId: book.id);
      if (duplicate != null) return left(duplicate);
      final duplicateIssue = await _collisions.issue(
        book.issue,
        excludeId: book.id,
      );
      if (duplicateIssue != null) return left(duplicateIssue);
      return left(StorageFailure('update: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async {
    try {
      await (_db.update(_db.books)..where((t) => t.id.equals(id))).write(
        BooksCompanion(removed: const Value(true), removedAt: Value(at)),
      );
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('markRemoved: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    try {
      await (_db.delete(_db.books)..where((t) => t.id.equals(id))).go();
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('delete: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async {
    try {
      await (_db.update(_db.books)..where((t) => t.id.equals(id))).write(
        const BooksCompanion(removed: Value(false), removedAt: Value(null)),
      );
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('restoreRemoved: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async {
    try {
      // One explicit transaction around the spellings read + the batch, so
      // the whole import is all-or-nothing AND every row is snapped against
      // the same snapshot (plus the spellings accepted earlier in the batch).
      return await _db.transaction(() async {
        final resolver = LanguageResolver(await _storedLanguages());
        var count = 0;
        // Row by row (not a batch): an issue's detail row needs the id the
        // base-row insert assigns. Still one transaction, so the cost is one
        // statement per row inside a single commit.
        for (final book in books) {
          final resolved = resolver.resolve(_normalizedDates(book));
          final withUid = resolved.itemUid == null
              ? resolved.copyWith(itemUid: _uuid.v4())
              : resolved;
          final id = await _db.into(_db.books).insert(withUid.toCompanion());
          await _details.write(id, withUid.details);
          count++;
        }
        return right<Failure, int>(count);
      });
    } on Object catch (e) {
      return left(StorageFailure('insertAll: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async {
    try {
      // One explicit transaction: the deletes and the inserts commit together
      // or roll back together, so a mid-way failure (e.g. a UNIQUE violation
      // on a crafted file) can never leave a partially-replaced catalogue.
      return await _db.transaction(() async {
        // The FK cascade (schema v5) removes every detail row with its base
        // row, so one delete empties both tables.
        await _db.delete(_db.books).go();
        // The table is empty here, so spellings are resolved only against
        // earlier rows of the SAME file: first spelling in the file wins.
        final resolver = LanguageResolver(const []);
        var count = 0;
        for (final book in books) {
          final resolved = resolver.resolve(_normalizedDates(book));
          final withUid = resolved.itemUid == null
              ? resolved.copyWith(itemUid: _uuid.v4())
              : resolved;
          final id = await _db.into(_db.books).insert(withUid.toCompanion());
          await _details.write(id, withUid.details);
          count++;
        }
        return right<Failure, int>(count);
      });
    } on Object catch (e) {
      return left(StorageFailure('replaceAll: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async {
    if (isbn.trim().isEmpty) return right(null);
    try {
      final row =
          await (CatalogueSql.joined(_db)
                ..where(_db.books.isbn.equals(isbn))
                ..limit(1))
              .getSingleOrNull();
      return right(row == null ? null : _toDomain(row));
    } on Object catch (e) {
      return left(StorageFailure('findByIsbn: $e'));
    }
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async {
    final uid = itemUid.trim();
    if (uid.isEmpty) return right(null);
    try {
      final row =
          await (CatalogueSql.joined(_db)
                ..where(_db.books.itemUid.equals(uid))
                ..limit(1))
              .getSingleOrNull();
      return right(row == null ? null : _toDomain(row));
    } on Object catch (e) {
      return left(StorageFailure('findByUid: $e'));
    }
  }

  /// Drift transactions are zone-scoped: any query issued while [action] is
  /// running — through THIS repository or the wishlist one (same database) —
  /// joins the transaction. A `Left` result is turned into a throw so Drift
  /// rolls back, then handed back unchanged.
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    try {
      return await _db.transaction(() async {
        final result = await action();
        if (result.isLeft()) throw RollbackWith(result);
        return result;
      });
    } on RollbackWith catch (r) {
      // The typed failure that asked for the rollback, unchanged.
      return r.result as Either<Failure, T>;
    } on Object catch (e) {
      return left(StorageFailure('transaction: $e'));
    }
  }
}
