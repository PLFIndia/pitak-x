/// Wishlist-feature DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the wishlist use cases and the by-id read model. The
/// wishlist REPOSITORY binding lives in the database module (see its header
/// for the cycle-breaking reason); the `WishlistController` notifier keeps
/// its own `@riverpod` file in the feature's application layer.
library;

import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_use_cases.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'wishlist_providers.g.dart';

/// Adds a new wishlist entry (title-required validation + persist).
@riverpod
Future<AddWishlistBookUseCase> addWishlistBookUseCase(
  AddWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return AddWishlistBookUseCase(repo);
}

/// Updates a wishlist entry (title-required; id + addedDate immutable).
@riverpod
Future<UpdateWishlistBookUseCase> updateWishlistBookUseCase(
  UpdateWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return UpdateWishlistBookUseCase(repo);
}

/// Deletes a wishlist entry by id.
@riverpod
Future<DeleteWishlistBookUseCase> deleteWishlistBookUseCase(
  DeleteWishlistBookUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  return DeleteWishlistBookUseCase(repo);
}

/// Marks a wishlist entry purchased, with optional move-to-library (D2 check).
@riverpod
Future<MarkWishlistPurchasedUseCase> markWishlistPurchasedUseCase(
  MarkWishlistPurchasedUseCaseRef ref,
) async {
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  final books = await ref.watch(bookRepositoryProvider.future);
  return MarkWishlistPurchasedUseCase(repo, books: books);
}

/// One wishlist entry, observed by id, for its detail screen (N03).
/// Same shape and rationale as [bookById]; the freshness signal is
/// [wishlistControllerProvider], which every wishlist mutation refreshes.
@riverpod
Future<WishlistBook?> wishlistBookById(
  WishlistBookByIdRef ref,
  int bookId,
) async {
  ref.watch(wishlistControllerProvider);
  final repo = await ref.watch(wishlistRepositoryProvider.future);
  final result = await repo.getById(bookId);
  return result.fold(
    // ignore: only_throw_errors, Riverpod surfaces typed errors via throw
    (failure) => throw failure,
    (book) => book,
  );
}
