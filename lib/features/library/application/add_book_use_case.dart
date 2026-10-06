/// Add a book to the library (application layer, AGENTS.md §3/§4).
///
/// Mirrors Kotlin `AddBookUseCase`: enforces the non-blank-title invariant (the
/// UI also validates, but the use case is the single source of truth) and
/// persists via the repository, which mints the `book_uid` at first insert.
///
/// S34: the duplicate-ISBN routing the Kotlin app deferred is now here — a
/// non-blank ISBN is checked against the library BEFORE the insert, so a
/// re-scan of a catalogued book returns a typed [DuplicateIsbnFailure] the
/// form renders as "already in your library" instead of a generic save error.
///
/// NOT ported (deferred, see PLAN Step 13): the `addedBy` maintainer-name stamp
/// (needs a Settings/preferences layer that doesn't exist yet).
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

  /// Inserts [book] after validating it against the shared catalogue rules
  /// (M15: `Book.validate` is the single gate every ingress passes through —
  /// the form pre-checks the title, but the use case is the source of truth).
  /// A non-blank ISBN that the library already holds is refused with a
  /// [DuplicateIsbnFailure] naming the existing book. Returns the persisted
  /// book (with its assigned id + minted uid) or a typed [Failure].
  Future<Either<Failure, Book>> call(Book book) {
    return Book.validate(book).match(
      (errors) =>
          Future.value(left(ValidationFailure(errors.first.userMessage))),
      _insertIfIsbnIsNew,
    );
  }

  /// The duplicate-ISBN gate (S34), then the insert.
  ///
  /// Why a pre-check when the UNIQUE index already refuses the write: the
  /// index rejection arrives as a raw SQLite exception, which the repository
  /// can only report as "a storage error". Checking first turns the common
  /// case into an honest, titled [DuplicateIsbnFailure]. The index stays the
  /// final gate — a concurrent add that slips past this check is mapped to
  /// the SAME failure inside the repository, so callers see one behaviour.
  ///
  /// The lookup uses the ISBN exactly as it would be stored: the UNIQUE index
  /// compares raw strings, so the pre-check must too (trimming here could
  /// miss the collision the index is about to report). A FAILED read is
  /// propagated, not skipped: if we cannot read the library we do not
  /// blind-insert (fail closed).
  Future<Either<Failure, Book>> _insertIfIsbnIsNew(Book book) async {
    final isbn = book.isbn;
    if (isbn != null && isbn.trim().isNotEmpty) {
      final existing = await _repository.findByIsbn(isbn);
      return existing.fold(
        left,
        (found) => found == null
            ? _repository.insert(book)
            : left(
                DuplicateIsbnFailure(
                  existingTitle: found.title,
                  existingBookId: found.id,
                  existingIsRemoved: found.removed,
                ),
              ),
      );
    }
    return _repository.insert(book);
  }
}
