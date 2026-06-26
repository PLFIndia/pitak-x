/// UI-facing add/edit-wishlist controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the AddWishlistPage drives: idle until `save` is
/// called. An entry with `id == WishlistBook.emptyId` is inserted (add); any
/// other id is updated (edit). The use cases return `Either<Failure, _>`; a
/// left becomes `AsyncError(Failure)` so the form can show a safe message.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'add_wishlist_controller.g.dart';

/// Drives a one-shot add or edit and surfaces the saved entry.
@riverpod
class AddWishlistController extends _$AddWishlistController {
  @override
  FutureOr<WishlistBook?> build() => null; // idle until save() is called

  /// Persists [book]: inserts when new, updates otherwise.
  Future<void> save(WishlistBook book) async {
    state = const AsyncLoading();
    final result = book.id == WishlistBook.emptyId
        ? await (await ref.read(addWishlistBookUseCaseProvider.future))(book)
        : await (await ref.read(updateWishlistBookUseCaseProvider.future))(
            book,
          );
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }
}
