/// Drift-backed implementation of [BookRepository] (AGENTS.md §3.3).
///
/// Side effects live at this edge; expected failures are caught and returned as
/// typed [Failure]s (fail-closed). UUIDs are minted here at first persist,
/// mirroring Kotlin `BookMapper.toEntity`.
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
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
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async {
    try {
      final q = _db.select(_db.books);
      final lang = language?.trim();
      if (lang != null && lang.isNotEmpty) {
        q.where((t) => t.language.lower().equals(lang.toLowerCase()));
      }
      switch (sort) {
        case BookSort.recentlyAdded:
          q.orderBy([(t) => OrderingTerm.desc(t.addedDate)]);
        case BookSort.languageAsc:
          // Blank/null languages sort LAST, then by language A→Z (mirrors the
          // Kotlin CASE-prefix; Drift's plain asc would put NULL first).
          q.orderBy([
            (t) => OrderingTerm.asc(
              CaseWhenExpression<int>(
                cases: [
                  CaseWhen(
                    t.language.isNull() | t.language.trim().equals(''),
                    then: const Constant(1),
                  ),
                ],
                orElse: const Constant(0),
              ),
            ),
            (t) => OrderingTerm.asc(t.language),
            (t) => OrderingTerm.desc(t.addedDate),
          ]);
        case BookSort.ageGroupAsc:
          // age_group is a TEXT token; order by its sortRank, nulls last.
          q.orderBy([
            (t) => OrderingTerm.asc(t.ageGroup),
            (t) => OrderingTerm.desc(t.addedDate),
          ]);
      }
      final rows = await q.get();
      var books = rows.map((r) => r.toDomain()).toList();
      if (sort == BookSort.ageGroupAsc) {
        // Token alpha-order != band order; re-sort by AgeGroup.sortRank in Dart
        // (nulls last) to match Kotlin's CASE-mapped ordering exactly.
        books = _byAgeRank(books);
      }
      return right(books);
    } on Object catch (e) {
      return left(StorageFailure('query: $e'));
    }
  }

  /// Stable sort by age-band rank (nulls last), preserving the SQL tiebreak
  /// (newest-added) within each band.
  List<Book> _byAgeRank(List<Book> books) {
    final indexed = books.asMap().entries.toList()
      ..sort((a, b) {
        final ra = a.value.ageGroup?.sortRank ?? 1 << 30;
        final rb = b.value.ageGroup?.sortRank ?? 1 << 30;
        if (ra != rb) return ra.compareTo(rb);
        return a.key.compareTo(b.key); // stable: keep query order in a band
      });
    return indexed.map((e) => e.value).toList();
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
  Future<Either<Failure, List<Book>>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return right(const []);
    try {
      // Match against the FTS5 index, join back to books for full rows.
      final rows = await _db
          .customSelect(
            'SELECT b.* FROM books_fts f '
            'JOIN books b ON b.id = f.rowid '
            'WHERE books_fts MATCH ?1 '
            'ORDER BY b.added_date DESC',
            variables: [Variable<String>(_ftsQuery(trimmed))],
            readsFrom: {_db.books},
          )
          .get();
      final books = rows.map((r) => _db.books.map(r.data).toDomain()).toList();
      return right(books);
    } on Object catch (e) {
      return left(StorageFailure('search: $e'));
    }
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
