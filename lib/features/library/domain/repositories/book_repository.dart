/// Domain-side repository interface for library books (AGENTS.md §3.3).
///
/// Declared in `domain`, implemented in `infrastructure`. Returns
/// `Either<Failure, T>` for expected failures; never throws across the layer.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Read/write access to the library books store.
abstract interface class BookRepository {
  /// All books (including soft-removed), newest first.
  Future<Either<Failure, List<Book>>> getAll();

  /// Books ordered by [sort], optionally narrowed to [language] (exact, case-
  /// insensitive; null = all). Used by the library list's sort/filter controls.
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  });

  /// Distinct non-blank languages present, A→Z — the filter-chip facet values.
  Future<Either<Failure, List<String>>> distinctLanguages();

  /// Finds a book by its per-device [id], or null when none exists.
  Future<Either<Failure, Book?>> getById(int id);

  /// Inserts a new book, returning it with its assigned id (and minted uid).
  Future<Either<Failure, Book>> insert(Book book);

  /// Updates an existing book in place (matched by [Book.id]); the id and
  /// `book_uid` are preserved. Returns the updated book. A row that no longer
  /// exists yields [NotFoundFailure].
  Future<Either<Failure, Book>> update(Book book);

  /// Soft-deletes a book: sets `removed = true` and `removed_at = [at]`. The
  /// row stays (visible-but-inert), mirroring Kotlin `markRemoved`. NOT a hard
  /// delete — hard delete must purge vault loans (a vault-write op), so it is
  /// deferred to the vault-write tier.
  Future<Either<Failure, Unit>> markRemoved(int id, int at);

  /// Clears the soft-delete flag on a book (Kotlin `restore`).
  Future<Either<Failure, Unit>> restoreRemoved(int id);

  /// Permanently deletes the book row (Kotlin `delete`). The caller is
  /// responsible for purging the book's vault loans FIRST (a vault-write op);
  /// this only removes the Drift row. Idempotent: deleting a missing id is ok.
  Future<Either<Failure, Unit>> delete(int id);

  /// Full-text search over the FTS5 index; returns matching books.
  Future<Either<Failure, List<Book>>> search(String query);

  /// Finds a book by exact ISBN, or null when none / [isbn] blank. Used by
  /// import dedup (existing ISBN → skip).
  Future<Either<Failure, Book?>> findByIsbn(String isbn);

  /// Finds a book by its stable cross-device [bookUid], or null when none /
  /// [bookUid] blank. Used by import to UPDATE a re-imported book in place
  /// instead of colliding on the UNIQUE `book_uid` index (decision Q9).
  Future<Either<Failure, Book?>> findByUid(String bookUid);

  /// Runs [action] inside ONE database transaction: every repository call
  /// made within it (books AND wishlist — they share the database) commits
  /// together or rolls back together. If [action] returns a `Left`, or
  /// throws, everything is rolled back and that `Left` (or a
  /// `StorageFailure`) is returned. Used by import so a failure on row N can
  /// never leave rows 1..N-1 behind (review 2026-09-03).
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  );

  /// Bulk insert used by restore/import. Returns the number inserted.
  /// Atomic: either every row lands or none does.
  Future<Either<Failure, int>> insertAll(List<Book> books);

  /// Atomically replaces the ENTIRE catalogue with [books] (delete all +
  /// insert all in one transaction). Used by merge OVERWRITE: a failure
  /// mid-way must roll back so the device is never left with a partial or
  /// empty catalogue reported as success/failure incorrectly
  /// (REVIEW_FINDINGS_2 S5). Rows keep their incoming `book_uid` (cross-device
  /// identity); a null uid is minted fresh, matching [insert].
  Future<Either<Failure, int>> replaceAll(List<Book> books);
}
