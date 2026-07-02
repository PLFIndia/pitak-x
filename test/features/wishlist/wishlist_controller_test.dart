import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// In-memory wishlist repo with scriptable delete results, to assert the
/// controller fails closed (§5) instead of swallowing a failed delete.
class _FakeWishlistRepo implements WishlistRepository {
  _FakeWishlistRepo(this._all);

  final List<WishlistBook> _all;
  Failure? failDeleteWith;
  int deleteCalls = 0;

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(_all);

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    deleteCalls++;
    final f = failDeleteWith;
    if (f != null) return left(f);
    _all.removeWhere((w) => w.id == id);
    return right(unit);
  }

  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async =>
      right(_all.where((w) => w.id == id).firstOrNull);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
}

void main() {
  WishlistBook entry(int id) =>
      WishlistBook(id: id, title: 'Wanted $id', addedDate: id);

  ProviderContainer makeContainer(_FakeWishlistRepo repo) {
    final container = ProviderContainer(
      overrides: [wishlistRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('successful delete refreshes and drops the row', () async {
    final repo = _FakeWishlistRepo([entry(1), entry(2)]);
    final container = makeContainer(repo);
    await container.read(wishlistControllerProvider.future);

    await container.read(wishlistControllerProvider.notifier).delete(1);

    expect(repo.deleteCalls, 1);
    final list = container.read(wishlistControllerProvider).requireValue;
    expect(list.map((w) => w.id), [2]);
  });

  test('failed delete surfaces AsyncError(Failure) — never a silent '
      '"success" refresh (§5 fail closed)', () async {
    final repo = _FakeWishlistRepo([entry(1)])
      ..failDeleteWith = const StorageFailure('disk full');
    final container = makeContainer(repo);
    await container.read(wishlistControllerProvider.future);

    await container.read(wishlistControllerProvider.notifier).delete(1);

    final state = container.read(wishlistControllerProvider);
    expect(state, isA<AsyncError<List<WishlistBook>>>());
    expect(state.error, isA<StorageFailure>());
  });
}
