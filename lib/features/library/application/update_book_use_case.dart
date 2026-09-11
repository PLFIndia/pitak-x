/// Update an existing library book (application layer, AGENTS.md §3/§4).
///
/// Mirrors Kotlin `UpdateBookUseCase`: title-required, the row must already
/// exist (else [NotFoundFailure]), and the id is immutable (the repository
/// matches on it). `addedDate` is intentionally user-editable (Kotlin D30, as
/// amended) — the form may back-date a book — so it is NOT forced here.
///
/// The ISBN-change confirmation dialog (Kotlin D30) is a UI concern and is not
/// part of this use case.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';

/// Validates and updates an existing [Book].
class UpdateBookUseCase {
  /// Creates the use case over [_repository].
  const UpdateBookUseCase(this._repository);

  final BookRepository _repository;

  /// Updates [book] after validating it against the shared catalogue rules
  /// (M15: `Book.validate` is the single gate) and checking the id is set.
  /// Returns the updated book or a typed [Failure].
  Future<Either<Failure, Book>> call(Book book) {
    return Book.validate(book).match(
      (errors) {
        return Future.value(left(ValidationFailure(errors.first.userMessage)));
      },
      (valid) {
        if (valid.id == Book.emptyId) {
          return Future.value(left(const NotFoundFailure()));
        }
        return _repository.update(valid);
      },
    );
  }
}
