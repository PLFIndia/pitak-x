/// Domain-side repository interface for library books (AGENTS.md §3.3).
///
/// Declared in `domain`, implemented in `infrastructure`. Returns
/// `Either<Failure, T>` for expected failures; never throws across the layer.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/book_page.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/library_query.dart';

/// Read/write access to the library books store.
abstract interface class BookRepository {
  /// All books (including soft-removed), newest first.
  Future<Either<Failure, List<Book>>> getAll();

  /// ONE window of the library list for [query] (N10-d, astra-review.md N10).
  ///
  /// This is the only list read the Library screen uses. A blank
  /// `query.text` lists every book; non-blank text is a full-text search over
  /// the FTS5 index. Either way the rows are narrowed to `query.language`
  /// (exact match on the stored string; null = all) and ordered by
  /// `query.sort` with the domain's `BookSorter` rules. The order is FINAL
  /// and TOTAL (ties broken newest-first, then by id), and the window is cut
  /// by SQLite on the SAME statement that orders — so `offset` rows in, the
  /// next `limit` rows out, are exactly the rows the user should see there.
  ///
  /// [limit] is clamped to `1..maxLibraryPageSize` and [offset] to `>= 0` by
  /// the implementation: a caller can never turn a page back into a whole-
  /// catalogue read. `hasMore` on the result is true when at least one row
  /// follows the window.
  ///
  /// OFFSET semantics (user decision S30, D1-a): if a row that sorts BEFORE
  /// the window is inserted or removed between two reads, the next window
  /// shifts by one (a repeated or skipped row at the seam). Every write path
  /// in the app refreshes the list controller, which reloads from offset 0,
  /// so the UI never pages across its own write; the limitation is pinned by
  /// a test in `drift_book_repository_test.dart` so it stays visible.
  Future<Either<Failure, BookPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
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
