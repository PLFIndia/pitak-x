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
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Validates and inserts a new wishlist entry.
class AddWishlistBookUseCase {
  /// Creates the use case over [_repository].
  const AddWishlistBookUseCase(this._repository);

  final WishlistRepository _repository;

  /// Inserts [book] after checking the title is present.
  Future<Either<Failure, WishlistBook>> call(WishlistBook book) {
    if (book.title.trim().isEmpty) {
      return Future.value(
        left(const ValidationFailure('A title is required.')),
      );
    }
    return _repository.insert(book);
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

  /// Updates [book]; rejects a blank title, a missing row, or an `addedDate`
  /// change. Returns the updated entry or a typed [Failure].
  Future<Either<Failure, WishlistBook>> call(WishlistBook book) async {
    if (book.title.trim().isEmpty) {
      return left(const ValidationFailure('A title is required.'));
    }
    if (book.id == WishlistBook.emptyId) {
      return left(const NotFoundFailure());
    }
    final existing = await _repository.getById(book.id);
    // Propagate a storage error from the lookup unchanged.
    if (existing.isLeft()) {
      return left((existing as Left<Failure, WishlistBook?>).value);
    }
    final found = existing.toNullable();
    if (found == null) return left(const NotFoundFailure());
    if (found.addedDate != book.addedDate) {
      return left(const ValidationFailure('The date added cannot be changed.'));
    }
    return _repository.update(book);
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

/// Marks a wishlist entry purchased, optionally promoting it into the Library.
///
/// Mirrors Kotlin `MarkWishlistPurchasedUseCase`: always flips `purchased` +
/// stamps `purchasedDate`; when `moveToLibrary` is true and the ISBN is not
/// already in the library, inserts a fresh library book (new `addedDate`,
/// `copyCount = 1`). If the ISBN already exists, returns
/// [MarkPurchasedAlreadyInLibrary] (the D2 dialog hook) without duplicating.
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
  }) async {
    final found = await _repository.getById(id);
    if (found.isLeft()) {
      return left((found as Left<Failure, WishlistBook?>).value);
    }
    final book = found.toNullable();
    if (book == null) return left(const NotFoundFailure());

    final stamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final updatedResult = await _repository.update(
      book.copyWith(purchased: true, purchasedDate: stamp),
    );
    if (updatedResult.isLeft()) {
      return left((updatedResult as Left<Failure, WishlistBook>).value);
    }
    final updated = (updatedResult as Right<Failure, WishlistBook>).value;

    if (!moveToLibrary || _books == null) {
      return right(MarkPurchasedSuccess(updated));
    }

    // D2: if the ISBN already exists in the library, don't duplicate.
    final isbn = book.isbn?.trim();
    if (isbn != null && isbn.isNotEmpty) {
      final existing = await _books.findByIsbn(isbn);
      final hit = existing.toNullable();
      if (existing.isRight() && hit != null) {
        return right(MarkPurchasedAlreadyInLibrary(hit.id));
      }
    }

    final inserted = await _books.insert(_toLibraryBook(book, stamp));
    return inserted.fold(left, (_) => right(MarkPurchasedSuccess(updated)));
  }

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
