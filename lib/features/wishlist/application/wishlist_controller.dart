/// UI-facing wishlist list controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the WishlistPage drives: on build it loads all
/// entries (newest first). `delete` and `markPurchased` run their use cases and
/// then refresh the list. The repository/use cases return `Either<Failure, _>`;
/// a left becomes `AsyncError(Failure)` for a safe UI message.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'wishlist_controller.g.dart';

/// Loads and mutates the wishlist for the presentation layer.
@riverpod
class WishlistController extends _$WishlistController {
  @override
  FutureOr<List<WishlistBook>> build() => _load();

  Future<List<WishlistBook>> _load() async {
    final repo = await ref.read(wishlistRepositoryProvider.future);
    final result = await repo.getAll();
    return result.fold(
      // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
      (failure) => throw failure,
      (books) => books,
    );
  }

  /// Reloads the list.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Deletes the entry [id] then refreshes.
  ///
  /// Fail closed (§5): a use-case Left becomes `AsyncError(Failure)` — a
  /// failed delete must never refresh the list as if it succeeded.
  Future<void> delete(int id) async {
    final useCase = await ref.read(deleteWishlistBookUseCaseProvider.future);
    final result = await useCase(id);
    await result.fold(
      (failure) async => state = AsyncError(failure, StackTrace.current),
      (_) => refresh(),
    );
  }

  /// Marks the entry [id] purchased (optionally moving it to the library), then
  /// refreshes the wishlist. Returns the use-case outcome so the UI can react
  /// to the D2 "already in library" / M13 "already purchased" cases and stay
  /// on screen with a message on a `Left`.
  ///
  /// The wishlist is re-read whatever the outcome (a rolled-back write leaves
  /// the row unchanged, but the list may have been stale anyway); the library
  /// list is invalidated only when a book was actually inserted, so a failed or
  /// no-op purchase does not trigger a needless reload.
  Future<Either<Failure, MarkPurchasedOutcome>> markPurchased(
    int id, {
    bool moveToLibrary = false,
  }) async {
    final useCase = await ref.read(markWishlistPurchasedUseCaseProvider.future);
    final result = await useCase(id, moveToLibrary: moveToLibrary);
    await refresh();
    final insertedBook =
        moveToLibrary &&
        result.fold((_) => false, (o) => o is MarkPurchasedSuccess);
    if (insertedBook) ref.invalidate(libraryControllerProvider);
    return result;
  }
}
