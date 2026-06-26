/// Add a book to the library (application layer, AGENTS.md §3/§4).
///
/// Mirrors Kotlin `AddBookUseCase`: enforces the non-blank-title invariant (the
/// UI also validates, but the use case is the single source of truth) and
/// persists via the repository, which mints the `book_uid` at first insert.
///
/// NOT ported (deferred, see PLAN Step 13): the `addedBy` maintainer-name stamp
/// (needs a Settings/preferences layer that doesn't exist yet) and the
/// duplicate-ISBN routing (a UI concern that calls `findByIsbn` first).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// Validates and inserts a new [Book].
class AddBookUseCase {
  /// Creates the use case over [_repository].
  const AddBookUseCase(this._repository);

  final BookRepository _repository;

  /// Inserts [book] after checking the title is present. Returns the persisted
  /// book (with its assigned id + minted uid) or a typed [Failure].
  Future<Either<Failure, Book>> call(Book book) {
    if (book.title.trim().isEmpty) {
      return Future.value(
        left(const ValidationFailure('A title is required.')),
      );
    }
    return _repository.insert(book);
  }
}
