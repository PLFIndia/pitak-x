/// Wishlist use cases (application layer, AGENTS.md §3/§4).
///
/// Mirrors Kotlin `AddWishlistBookUseCase`, `UpdateWishlistBookUseCase`,
/// `DeleteWishlistBookUseCase`, and `MarkWishlistPurchasedUseCase` (incl. the
/// move-to-library path with the D2 duplicate-ISBN check).
///
/// Wishlist has no vault/loan entanglement, so delete is a plain row removal
/// (unlike library delete, which needs the vault unlocked to purge loans).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Validates and inserts a new wishlist entry.
class AddWishlistBookUseCase {
  /// Creates the use case over [_repository].
  const AddWishlistBookUseCase(this._repository);

  final WishlistRepository _repository;

  /// Inserts [book] after validating it against the shared catalogue rules
  /// (M15: `WishlistBook.validate` is the single gate every ingress passes
  /// through — it also catches a priority outside 0..2 and a non-finite
  /// price, which the form's dropdown/keyboard can't produce but a crafted
  /// call could).
  Future<Either<Failure, WishlistBook>> call(WishlistBook book) {
    return WishlistBook.validate(book).match(
      (errors) =>
          Future.value(left(ValidationFailure(errors.first.userMessage))),
      _repository.insert,
    );
  }
}

/// Validates and updates an existing wishlist entry.
///
/// Title-required; the id must be set and exist; `addedDate` is immutable
/// (Kotlin D30 mirror) — an attempt to change it is rejected so the
/// recently-added ordering can't be silently rewritten.
class UpdateWishlistBookUseCase {
  /// Creates the use case over [_repository].
  const UpdateWishlistBookUseCase(this._repository);

  final WishlistRepository _repository;

  /// Updates [book]; rejects an invalid row (M15: shared
  /// `WishlistBook.validate` gate), a missing row, or an `addedDate` change.
  /// Returns the updated entry or a typed [Failure].
  Future<Either<Failure, WishlistBook>> call(WishlistBook book) async {
    final validated = WishlistBook.validate(book);
    if (validated.isLeft()) {
      final errors = (validated as Left<List<FieldError>, WishlistBook>).value;
      return left(ValidationFailure(errors.first.userMessage));
    }
    final valid = validated.toNullable()!;
    if (valid.id == WishlistBook.emptyId) {
      return left(const NotFoundFailure());
    }
    final existing = await _repository.getById(valid.id);
    // Propagate a storage error from the lookup unchanged.
    if (existing.isLeft()) {
      return left((existing as Left<Failure, WishlistBook?>).value);
    }
    final found = existing.toNullable();
    if (found == null) return left(const NotFoundFailure());
    if (found.addedDate != valid.addedDate) {
      return left(const ValidationFailure('The date added cannot be changed.'));
    }
    return _repository.update(valid);
  }
}

/// Deletes a wishlist entry by id (idempotent; no vault interaction).
class DeleteWishlistBookUseCase {
  /// Creates the use case over [_repository].
  const DeleteWishlistBookUseCase(this._repository);

  final WishlistRepository _repository;

  /// Deletes the entry with [id].
  Future<Either<Failure, Unit>> call(int id) => _repository.delete(id);
}

/// Outcome of marking a wishlist entry purchased.
sealed class MarkPurchasedOutcome {
  const MarkPurchasedOutcome();
}

/// Marked purchased (and moved to the library if requested + no duplicate).
final class MarkPurchasedSuccess extends MarkPurchasedOutcome {
  /// Creates a success carrying the updated wishlist [entry].
  const MarkPurchasedSuccess(this.entry);

  /// The updated (now-purchased) wishlist entry.
  final WishlistBook entry;
}

/// The move-to-library step was skipped because the ISBN already exists in the
/// library (Kotlin D2). The entry is still marked purchased.
final class MarkPurchasedAlreadyInLibrary extends MarkPurchasedOutcome {
  /// Creates the already-in-library outcome with the existing library book id.
  const MarkPurchasedAlreadyInLibrary(this.existingBookId);

  /// The id of the library book that already has this ISBN.
  final int existingBookId;
}

/// The entry was already marked purchased, so nothing was written (M13, D1 =
/// a). Happens on a second concurrent tap or for a row the user earlier marked
/// "purchased only". Idempotent by construction: no duplicate library books.
final class MarkPurchasedAlreadyPurchased extends MarkPurchasedOutcome {
  /// Creates the already-purchased outcome.
  const MarkPurchasedAlreadyPurchased();
}

/// Marks a wishlist entry purchased, optionally promoting it into the Library.
///
/// Mirrors Kotlin `MarkWishlistPurchasedUseCase`: flips `purchased` + stamps
/// `purchasedDate`; when `moveToLibrary` is true and the ISBN is not already
/// in the library, inserts a fresh library book (new `addedDate`,
/// `copyCount = 1`). If the ISBN already exists, returns
/// [MarkPurchasedAlreadyInLibrary] (the D2 dialog hook) without duplicating.
///
/// **Atomicity (M13).** The move runs inside ONE database transaction via
/// [BookRepository.runInTransaction] — both repositories sit on the same
/// database, and Drift transactions are zone-scoped, so the wishlist update
/// issued inside the callback joins it. Any `Left` (lookup error, insert
/// error, row vanished) rolls everything back: the entry is left exactly as
/// it was, so the user can simply retry. This replaces the old sequence
/// "mark purchased, then insert", which could leave a purchased row with no
/// library book and no way to retry.
///
/// **Idempotency (M13, D1 = a).** The row is re-read *inside* the transaction
/// and an already-purchased row is refused with [MarkPurchasedAlreadyPurchased]
/// without writing. Drift serialises statements around an open transaction,
/// so a second concurrent tap waits, then sees the first tap's commit.
class MarkWishlistPurchasedUseCase {
  /// Creates the use case over its collaborators.
  const MarkWishlistPurchasedUseCase(this._repository, {BookRepository? books})
    : _books = books;

  final WishlistRepository _repository;
  final BookRepository? _books;

  /// Flags the entry [id] purchased at [now]; promotes to the library when
  /// [moveToLibrary] is set and a [BookRepository] was provided.
  Future<Either<Failure, MarkPurchasedOutcome>> call(
    int id, {
    bool moveToLibrary = false,
    int? now,
  }) {
    final stamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final books = _books;
    if (!moveToLibrary || books == null) {
      // Flag-only: a single row write, already atomic on its own.
      return _markOnly(id, stamp);
    }
    // Move: read + check + insert + update must commit or roll back together.
    return books.runInTransaction(() => _markAndMove(id, stamp, books));
  }

  /// Flips the purchased flag without touching the library.
  Future<Either<Failure, MarkPurchasedOutcome>> _markOnly(
    int id,
    int stamp,
  ) async {
    final found = await _loadWanted(id);
    if (found.isLeft()) {
      return left((found as Left<Failure, WishlistBook?>).value);
    }
    final book = found.toNullable();
    if (book == null) return right(const MarkPurchasedAlreadyPurchased());
    final stamped = await _stampPurchased(book, stamp);
    return stamped.map(MarkPurchasedSuccess.new);
  }

  /// Body of the transaction. Order matters: the library insert comes BEFORE
  /// the wishlist update so that, if the insert fails, the wishlist write was
  /// never even issued (rollback still covers the other order; this keeps the
  /// failure path short and obvious).
  Future<Either<Failure, MarkPurchasedOutcome>> _markAndMove(
    int id,
    int stamp,
    BookRepository books,
  ) async {
    final found = await _loadWanted(id);
    if (found.isLeft()) {
      return left((found as Left<Failure, WishlistBook?>).value);
    }
    final book = found.toNullable();
    if (book == null) return right(const MarkPurchasedAlreadyPurchased());

    // D2: if the ISBN already exists in the library, don't duplicate. A
    // storage error here is propagated (M13) — not knowing is not "no match".
    final isbn = book.isbn?.trim();
    if (isbn != null && isbn.isNotEmpty) {
      final existing = await books.findByIsbn(isbn);
      if (existing.isLeft()) {
        return left((existing as Left<Failure, Book?>).value);
      }
      final hit = existing.toNullable();
      if (hit != null) {
        final stamped = await _stampPurchased(book, stamp);
        return stamped.map((_) => MarkPurchasedAlreadyInLibrary(hit.id));
      }
    }

    // M15: the wishlist row may predate the S17 validation gate (or come
    // from a restored backup), so the built library book is validated before
    // it is inserted. A Left refuses the move INSIDE the transaction, so the
    // wishlist purchase rolls back with it. The returned entity is the
    // normalised one (e.g. a hostile cover is dropped, not copied).
    final checked = Book.validate(_toLibraryBook(book, stamp));
    final toInsert = checked.fold<Book?>((errors) => null, (valid) => valid);
    if (toInsert == null) {
      return left(
        ValidationFailure(checked.getLeft().toNullable()!.first.userMessage),
      );
    }
    final inserted = await books.insert(toInsert);
    if (inserted.isLeft()) {
      return left((inserted as Left<Failure, Book>).value);
    }
    final stamped = await _stampPurchased(book, stamp);
    return stamped.map(MarkPurchasedSuccess.new);
  }

  /// Loads the entry [id]; `Right(null)` means it exists but is ALREADY
  /// purchased (the idempotency guard); a missing row is [NotFoundFailure].
  Future<Either<Failure, WishlistBook?>> _loadWanted(int id) async {
    final found = await _repository.getById(id);
    return found.flatMap((book) {
      if (book == null) return left(const NotFoundFailure());
      return right(book.purchased ? null : book);
    });
  }

  Future<Either<Failure, WishlistBook>> _stampPurchased(
    WishlistBook book,
    int stamp,
  ) => _repository.update(book.copyWith(purchased: true, purchasedDate: stamp));

  /// Maps a purchased wishlist entry to a fresh library book (Kotlin
  /// `toLibraryBook`): new acquisition date, single copy.
  static Book _toLibraryBook(WishlistBook w, int now) => Book(
    title: w.title,
    titleTransliteration: w.titleTransliteration,
    author: w.author,
    isbn: w.isbn,
    publisher: w.publisher,
    publishedYear: w.publishedYear,
    coverUrl: w.coverUrl,
    notes: w.notes,
    addedDate: now,
    needsMetadata: w.needsMetadata,
  );
}
