/// Drift-backed implementation of [BookRepository] (AGENTS.md §3.3).
///
/// Side effects live at this edge; expected failures are caught and returned as
/// typed [Failure]s (fail-closed). UUIDs are minted here at first persist,
/// mirroring Kotlin `BookMapper.toEntity`.
///
/// ## Ordering, filtering AND paging happen INSIDE SQLite (N10-d, review N10)
///
/// The one list read, [DriftBookRepository.page], has two statements behind
/// it — a typed Drift select for a blank search box and a hand-written FTS5
/// join for typed text — and both return rows in their FINAL order, already
/// narrowed to the language facet, already cut to the requested window.
/// Nothing is re-sorted, re-filtered or sliced in Dart afterwards. Why that
/// matters: a `LIMIT/OFFSET` page can only be correct if SQLite's rows
/// `offset..offset+limit` ARE the rows the user should see there. Until S29
/// the Age-group sort ordered by the raw token in SQL (`above-10 < above-15 <
/// above-3`, alphabetical) and fixed the order in Dart — fine for a
/// whole-table read, wrong for any page. Until S30 the controller read the
/// whole catalogue on every load.
///
/// The ordering rules are the domain's `BookSorter` contract (N05). The SQL
/// here is its twin, and `drift_book_repository_test.dart` proves the two
/// agree for every sort × filter combination on a seeded fixture, read back
/// through small pages so every seam is crossed.
///
/// `hasMore` is decided here by asking for `limit + 1` rows and dropping the
/// extra one: one statement, no `COUNT(*)` (which over the FTS join would be
/// a second full walk of the index).
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/book_mapper.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:uuid/uuid.dart';

/// Persists books in the Drift [AppDatabase].
class DriftBookRepository implements BookRepository {
  /// Creates the repository over [_db], optionally with a custom [Uuid].
  DriftBookRepository(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  @override
  Future<Either<Failure, List<Book>>> getAll() async {
    try {
      final query = _db.select(_db.books)
        ..orderBy([(t) => OrderingTerm.desc(t.addedDate)]);
      final rows = await query.get();
      return right(rows.map((r) => r.toDomain()).toList());
    } on Object catch (e) {
      return left(StorageFailure('getAll: $e'));
    }
  }

  @override
  Future<Either<Failure, BookPage>> page(
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
          ? await _searchRows(query, limit: size + 1, offset: skip)
          : await _listRows(query, limit: size + 1, offset: skip);
      final hasMore = rows.length > size;
      final items = (hasMore ? rows.take(size) : rows)
          .map((r) => r.toDomain())
          .toList(growable: false);
      return right(BookPage(items: items, hasMore: hasMore));
    } on Object catch (e) {
      return left(StorageFailure('page: $e'));
    }
  }

  /// Blank search box: typed Drift select, ordered by [_orderingTerms],
  /// narrowed to the facet, windowed by SQLite.
  Future<List<BookRow>> _listRows(
    LibraryQuery query, {
    required int limit,
    required int offset,
  }) {
    final q = _db.select(_db.books);
    final lang = query.language;
    if (lang != null) {
      // D1-a: exact match on the STORED string. The facet value comes from
      // `distinctLanguages()` (the stored spelling verbatim), so equality
      // is what the user tapped. SQLite's `lower()` is ASCII-only, so the
      // previous `lower(language) = lower(?)` silently missed every
      // non-Latin language name (e.g. `Ελληνικά`).
      q.where((t) => t.language.equals(lang));
    }
    q
      ..orderBy(_orderingTerms(query.sort))
      // Drift writes `LIMIT n OFFSET m` from these two ints (verified in
      // drift 2.28.2 `components/limit.dart`); they are clamped ints, never
      // user text.
      ..limit(limit, offset: offset);
    return q.get();
  }

  /// Age band as an integer rank, in SQL. `AgeGroup.sortRank` (not the token's
  /// alphabetical order) defines band order; NULL — and any token the domain
  /// parser would not recognise — falls to `ELSE` and sorts LAST, exactly as
  /// `AgeGroup.fromToken` → null does on the Dart side. Built from the enum
  /// so a new band is picked up without touching this file.
  static Expression<int> _ageRank($BooksTable t) => t.ageGroup.caseMatch<int>(
    when: {
      for (final band in AgeGroup.values)
        Constant<String>(band.token): Constant<int>(band.sortRank),
    },
    orElse: const Constant<int>(_unrankedAge),
  );

  /// Rank for rows with no (recognised) age band: after every real band.
  static const _unrankedAge = 1 << 30;

  /// 1 when the language is NULL or blank, else 0 — blanks sort LAST.
  static Expression<int> _languageBlank($BooksTable t) =>
      CaseWhenExpression<int>(
        cases: [
          CaseWhen(
            t.language.isNull() | t.language.trim().equals(''),
            then: const Constant(1),
          ),
        ],
        orElse: const Constant(0),
      );

  /// The language as `BookSorter` compares it: `(language ?? '').trim()`.
  /// Without the COALESCE, SQLite would put NULL before `''` inside the
  /// "blank" bucket, while the domain treats both as the same key.
  static Expression<String> _languageKey($BooksTable t) =>
      coalesce<String>([t.language, const Constant('')]).trim();

  /// The typed ORDER BY for [sort]. Every sort ends with the shared
  /// tie-breaks `added_date DESC, id ASC` so the order is TOTAL: two rows can
  /// never swap between two runs (or two pages) of the same statement.
  /// Twin of [_orderSql]; both must match `BookSorter` (tested).
  static List<_OrderingOf> _orderingTerms(BookSort sort) {
    final byKey = switch (sort) {
      BookSort.recentlyAdded => const <_OrderingOf>[],
      BookSort.languageAsc => <_OrderingOf>[
        (t) => OrderingTerm.asc(_languageBlank(t)),
        (t) => OrderingTerm.asc(_languageKey(t)),
      ],
      BookSort.ageGroupAsc => <_OrderingOf>[
        (t) => OrderingTerm.asc(_ageRank(t)),
      ],
    };
    return [
      ...byKey,
      (t) => OrderingTerm.desc(t.addedDate),
      (t) => OrderingTerm.asc(t.id),
    ];
  }

  /// The raw-SQL ORDER BY for [sort], for the FTS statement in [_searchRows]
  /// (hand-written SQL because `books_fts` is a virtual table Drift does not
  /// model). `b` is the alias of `books` in that statement. MUST order exactly
  /// like [_orderingTerms] — `drift_book_repository_test.dart` checks both
  /// paths against the same oracle. Contains only compile-time constants
  /// (enum tokens), never user input.
  static String _orderSql(BookSort sort) {
    final byKey = switch (sort) {
      BookSort.recentlyAdded => '',
      BookSort.languageAsc =>
        "CASE WHEN b.language IS NULL OR TRIM(b.language) = '' "
            'THEN 1 ELSE 0 END ASC, '
            "TRIM(COALESCE(b.language, '')) ASC, ",
      BookSort.ageGroupAsc => '${_ageRankSql('b.age_group')} ASC, ',
    };
    return 'ORDER BY ${byKey}b.added_date DESC, b.id ASC';
  }

  /// Textual twin of [_ageRank] over [column].
  static String _ageRankSql(String column) {
    final whens = AgeGroup.values
        .map((band) => "WHEN '${band.token}' THEN ${band.sortRank}")
        .join(' ');
    return 'CASE $column $whens ELSE $_unrankedAge END';
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT DISTINCT language FROM books '
            "WHERE language IS NOT NULL AND TRIM(language) != '' "
            'ORDER BY language COLLATE NOCASE ASC',
            readsFrom: {_db.books},
          )
          .get();
      return right(rows.map((r) => r.read<String>('language')).toList());
    } on Object catch (e) {
      return left(StorageFailure('distinctLanguages: $e'));
    }
  }

  @override
  Future<Either<Failure, Book?>> getById(int id) async {
    try {
      final row =
          await (_db.select(_db.books)
                ..where((t) => t.id.equals(id))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('getById: $e'));
    }
  }

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    try {
      final withUid = book.bookUid == null
          ? book.copyWith(bookUid: _uuid.v4())
          : book;
      final id = await _db.into(_db.books).insert(withUid.toCompanion());
      return right(withUid.copyWith(id: id));
    } on Object catch (e) {
      return left(StorageFailure('insert: $e'));
    }
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    if (book.id == Book.emptyId) {
      return left(const NotFoundFailure());
    }
    try {
      // Preserve the stable book_uid: an edit must never lose the cross-device
      // merge key. If the incoming book dropped it, recover it from the row.
      final existing =
          await (_db.select(_db.books)
                ..where((t) => t.id.equals(book.id))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) return left(const NotFoundFailure());
      final preserved = book.bookUid == null
          ? book.copyWith(bookUid: existing.bookUid)
          : book;
      // `update().replace` matches on the primary key; FTS5 stays in sync via
      // the AFTER UPDATE trigger in app_database.dart.
      await _db.update(_db.books).replace(preserved.toCompanion());
      return right(preserved);
    } on Object catch (e) {
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
  Future<Either<Failure, int>> insertAll(List<Book> books) async {
    try {
      var count = 0;
      // `batch` outside an explicit transaction implicitly runs in one
      // (drift docs, ConnectionUser.batch) — so this is all-or-nothing.
      await _db.batch((b) {
        for (final book in books) {
          final withUid = book.bookUid == null
              ? book.copyWith(bookUid: _uuid.v4())
              : book;
          b.insert(_db.books, withUid.toCompanion());
          count++;
        }
      });
      return right(count);
    } on Object catch (e) {
      return left(StorageFailure('insertAll: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async {
    try {
      // One explicit transaction: the deletes and the inserts commit together
      // or roll back together, so a mid-way failure (e.g. a UNIQUE violation
      // on a crafted file) can never leave a partially-replaced catalogue.
      return await _db.transaction(() async {
        await _db.delete(_db.books).go();
        var count = 0;
        for (final book in books) {
          final withUid = book.bookUid == null
              ? book.copyWith(bookUid: _uuid.v4())
              : book;
          await _db.into(_db.books).insert(withUid.toCompanion());
          count++;
        }
        return right<Failure, int>(count);
      });
    } on Object catch (e) {
      return left(StorageFailure('replaceAll: $e'));
    }
  }

  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async {
    if (isbn.trim().isEmpty) return right(null);
    try {
      final row =
          await (_db.select(_db.books)
                ..where((t) => t.isbn.equals(isbn))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('findByIsbn: $e'));
    }
  }

  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async {
    final uid = bookUid.trim();
    if (uid.isEmpty) return right(null);
    try {
      final row =
          await (_db.select(_db.books)
                ..where((t) => t.bookUid.equals(uid))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
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
        if (result.isLeft()) throw _RollbackWith(result);
        return result;
      });
    } on _RollbackWith catch (r) {
      // The typed failure that asked for the rollback, unchanged.
      return r.result as Either<Failure, T>;
    } on Object catch (e) {
      return left(StorageFailure('transaction: $e'));
    }
  }

  /// Typed search box: match the FTS5 index, join back to `books` for full
  /// rows, then narrow, order AND window in the SAME statement so the page
  /// is final (N10-d). The search text and the facet are bound variables
  /// (never interpolated); the ORDER BY text is built from enum constants
  /// only; LIMIT/OFFSET are bound clamped ints.
  Future<List<BookRow>> _searchRows(
    LibraryQuery query, {
    required int limit,
    required int offset,
  }) async {
    final lang = query.language;
    // Positional binding: ?1 match, ?2/?3 limit+offset when there is no
    // facet, or ?2 facet then ?3/?4 limit+offset. Built as a list so the
    // indices in the SQL text and the variables list cannot drift apart.
    final variables = <Variable<Object>>[
      Variable<String>(_ftsQuery(query.text)),
      if (lang != null) Variable<String>(lang),
      Variable<int>(limit),
      Variable<int>(offset),
    ];
    final limitIndex = lang == null ? 2 : 3;
    final rows = await _db
        .customSelect(
          'SELECT b.* FROM books_fts f '
          'JOIN books b ON b.id = f.rowid '
          'WHERE books_fts MATCH ?1 '
          '${lang == null ? '' : 'AND b.language = ?2 '}'
          '${_orderSql(query.sort)} '
          'LIMIT ?$limitIndex OFFSET ?${limitIndex + 1}',
          variables: variables,
          readsFrom: {_db.books},
        )
        .get();
    return rows.map((r) => _db.books.map(r.data)).toList(growable: false);
  }

  /// Turns free text into a safe FTS5 prefix query, quoting each token to
  /// neutralise FTS5 operators in user input (AGENTS.md §6.5 boundary input).
  String _ftsQuery(String raw) {
    final tokens = raw
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*');
    return tokens.join(' ');
  }
}

/// One ORDER BY term over the `books` table (Drift's `orderBy` callback shape).
typedef _OrderingOf = OrderingTerm Function($BooksTable t);

/// Carries a `Left` out of a Drift transaction so it rolls back; unwrapped by
/// [DriftBookRepository.runInTransaction]. Never escapes the repository.
final class _RollbackWith implements Exception {
  _RollbackWith(this.result);
  final Object result;
}
