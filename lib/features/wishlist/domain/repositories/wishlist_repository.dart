/// Domain-side repository interface for wishlist books (AGENTS.md §3.3).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Read/write access to the wishlist store.
abstract interface class WishlistRepository {
  /// All wishlist entries, newest first.
  Future<Either<Failure, List<WishlistBook>>> getAll();

  /// Finds an entry by its per-device [id], or null when none exists.
  Future<Either<Failure, WishlistBook?>> getById(int id);

  /// Inserts a new entry, returning it with its assigned id.
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book);

  /// Updates an existing entry in place (matched by [WishlistBook.id]).
  /// A row that no longer exists yields [NotFoundFailure].
  Future<Either<Failure, WishlistBook>> update(WishlistBook book);

  /// Deletes the entry with [id]. Idempotent: deleting a missing row is a
  /// no-op success (the desired end state — gone — already holds).
  Future<Either<Failure, Unit>> delete(int id);

  /// Inserts or, when the entry already has a persisted id, replaces the row
  /// with that id (latest-wins). Used by import dedup on a matching ISBN.
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book);

  /// Bulk insert used by restore/import. Returns the number inserted.
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books);

  /// Finds an entry by exact ISBN, or null when none / [isbn] blank. Used by
  /// import dedup (existing ISBN → replace, latest-wins).
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn);
}
