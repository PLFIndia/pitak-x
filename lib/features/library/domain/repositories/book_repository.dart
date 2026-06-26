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

  /// Bulk insert used by restore/import. Returns the number inserted.
  Future<Either<Failure, int>> insertAll(List<Book> books);
}
