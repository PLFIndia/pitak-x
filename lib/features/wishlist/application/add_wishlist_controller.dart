/// UI-facing add/edit-wishlist controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the AddWishlistPage drives: idle until `save`
/// or `saveEdit` is called. The use cases return `Either<Failure, _>`; a left
/// becomes `AsyncError(Failure)` so the form can show a safe message.
///
/// **Edits save on top of the CURRENT row (N03).** The form was opened with a
/// snapshot; the row may have moved on by the time the user taps Save (a cover
/// materialised, the entry marked purchased from another screen). `saveEdit`
/// re-reads the row, hands it to the form as the base for every field the
/// form does not own, and only then updates. Same shape as
/// `AddBookController.saveEdit` in the library feature.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_wishlist_controller.g.dart';

/// Drives a one-shot add or edit and surfaces the saved entry.
@riverpod
class AddWishlistController extends _$AddWishlistController {
  @override
  FutureOr<WishlistBook?> build() => null; // idle until save() is called

  /// Inserts a NEW [book] (`id == WishlistBook.emptyId`). A persisted id is
  /// refused: an edit must go through [saveEdit] so it applies to the current
  /// row, not a snapshot.
  Future<void> save(WishlistBook book) async {
    state = const AsyncLoading();
    if (book.id != WishlistBook.emptyId) {
      state = AsyncError(
        const ValidationFailure('Use saveEdit to change an existing entry.'),
        StackTrace.current,
      );
      return;
    }
    final useCase = await ref.read(addWishlistBookUseCaseProvider.future);
    _publish(await useCase(book));
  }

  /// Updates the entry with [id]: re-reads its CURRENT row, lets [applyEdits]
  /// build the new value on top of it, then updates. Missing row →
  /// [NotFoundFailure]; a repository read error is propagated unchanged.
  Future<void> saveEdit(
    int id,
    WishlistBook Function(WishlistBook current) applyEdits,
  ) async {
    state = const AsyncLoading();
    final repo = await ref.read(wishlistRepositoryProvider.future);
    final current = await repo.getById(id);
    final result = await current.fold(
      (failure) async => left<Failure, WishlistBook>(failure),
      (book) async {
        if (book == null) {
          return left<Failure, WishlistBook>(const NotFoundFailure());
        }
        final useCase = await ref.read(
          updateWishlistBookUseCaseProvider.future,
        );
        return useCase(applyEdits(book));
      },
    );
    _publish(result);
  }

  void _publish(Either<Failure, WishlistBook> result) {
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }
}
