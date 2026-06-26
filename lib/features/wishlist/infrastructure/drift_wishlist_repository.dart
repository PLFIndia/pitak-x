/// Drift-backed implementation of [WishlistRepository] (AGENTS.md §3.3).
///
/// Side effects at the edge; expected failures returned as typed [Failure]s
/// (fail-closed). Wishlist has no UUID/merge key (it is purely local intent).
library;

import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';
import 'package:pitaka/features/wishlist/infrastructure/wishlist_mapper.dart';

/// Persists wishlist books in the Drift [AppDatabase].
class DriftWishlistRepository implements WishlistRepository {
  /// Creates the repository over [_db].
  DriftWishlistRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async {
    try {
      final query = _db.select(_db.wishlistBooks)
        ..orderBy([(t) => OrderingTerm.desc(t.addedDate)]);
      final rows = await query.get();
      return right(rows.map((r) => r.toDomain()).toList());
    } on Object catch (e) {
      return left(StorageFailure('getAll: $e'));
    }
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async {
    try {
      final row =
          await (_db.select(_db.wishlistBooks)
                ..where((t) => t.id.equals(id))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('getById: $e'));
    }
  }

  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async {
    try {
      final id = await _db.into(_db.wishlistBooks).insert(book.toCompanion());
      return right(book.copyWith(id: id));
    } on Object catch (e) {
      return left(StorageFailure('insert: $e'));
    }
  }

  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async {
    try {
      // insertOnConflictUpdate replaces the row when its primary key (id)
      // already exists; otherwise it inserts and assigns a fresh id.
      final id = await _db
          .into(_db.wishlistBooks)
          .insertOnConflictUpdate(book.toCompanion());
      return right(book.copyWith(id: id));
    } on Object catch (e) {
      return left(StorageFailure('upsert: $e'));
    }
  }

  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async {
    if (book.id == WishlistBook.emptyId) {
      return left(const NotFoundFailure());
    }
    try {
      final existing =
          await (_db.select(_db.wishlistBooks)
                ..where((t) => t.id.equals(book.id))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) return left(const NotFoundFailure());
      await _db.update(_db.wishlistBooks).replace(book.toCompanion());
      return right(book);
    } on Object catch (e) {
      return left(StorageFailure('update: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    try {
      await (_db.delete(_db.wishlistBooks)..where((t) => t.id.equals(id))).go();
      return right(unit);
    } on Object catch (e) {
      return left(StorageFailure('delete: $e'));
    }
  }

  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async {
    if (isbn.trim().isEmpty) return right(null);
    try {
      final row =
          await (_db.select(_db.wishlistBooks)
                ..where((t) => t.isbn.equals(isbn))
                ..limit(1))
              .getSingleOrNull();
      return right(row?.toDomain());
    } on Object catch (e) {
      return left(StorageFailure('findByIsbn: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books) async {
    try {
      var count = 0;
      await _db.batch((b) {
        for (final book in books) {
          b.insert(_db.wishlistBooks, book.toCompanion());
          count++;
        }
      });
      return right(count);
    } on Object catch (e) {
      return left(StorageFailure('insertAll: $e'));
    }
  }
}
