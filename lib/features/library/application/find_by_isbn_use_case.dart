/// Find a library book by its exact ISBN (application layer, AGENTS.md §3/§4).
///
/// Why this exists (beginner note): presentation code must not talk to a
/// repository directly (layer rule §3.1). The quick-add scan flow needs to
/// ask "is this ISBN already catalogued?" so it can route the user to the
/// EXISTING book instead of the add form — this thin use case is that
/// question, wrapped in the shared `Either<Failure, Book?>` contract.
///
/// The match is exact, mirroring the UNIQUE `books.isbn` index the database
/// enforces: normalisation (hyphens, ISBN-10 → 13) happens at the scanner
/// boundary (`IsbnFormat.normalize`), not here.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// Returns the book holding the given ISBN, or null when none does.
class FindByIsbnUseCase {
  /// Creates the use case over [_repository].
  const FindByIsbnUseCase(this._repository);

  final BookRepository _repository;

  /// Looks [isbn] up; a blank ISBN is never stored, so it yields null.
  Future<Either<Failure, Book?>> call(String isbn) =>
      _repository.findByIsbn(isbn);
}
