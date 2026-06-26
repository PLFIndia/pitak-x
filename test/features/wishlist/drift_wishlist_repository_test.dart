import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

T ok<T>(Either<Failure, T> either) =>
    either.getOrElse((f) => fail('unexpected failure: $f'));

void main() {
  late AppDatabase db;
  late DriftWishlistRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftWishlistRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('round-trips every field incl. price, priority, source token', () async {
    const book = WishlistBook(
      title: 'पापा जब बच्चे थे',
      author: 'Alexander Raskin',
      priceEstimate: 199.5,
      priority: WishlistBook.priorityHigh,
      source: WishlistSource.scanned,
      addedDate: 100,
      purchased: true,
      purchasedDate: 200,
    );

    final inserted = ok<WishlistBook>(await repo.insert(book));
    expect(inserted.id, greaterThan(0));

    final got = ok<List<WishlistBook>>(await repo.getAll()).single;
    expect(got.title, 'पापा जब बच्चे थे');
    expect(got.priceEstimate, 199.5);
    expect(got.priority, WishlistBook.priorityHigh);
    expect(got.source, WishlistSource.scanned);
    expect(got.purchased, isTrue);
    expect(got.purchasedDate, 200);
  });

  test('defaults: priority med, source manual, not purchased', () async {
    await repo.insert(const WishlistBook(title: 'X', addedDate: 1));
    final got = ok<List<WishlistBook>>(await repo.getAll()).single;
    expect(got.priority, WishlistBook.priorityMed);
    expect(got.source, WishlistSource.manual);
    expect(got.purchased, isFalse);
  });

  test('insertAll counts and persists', () async {
    final res = await repo.insertAll(const [
      WishlistBook(title: 'A', addedDate: 1),
      WishlistBook(title: 'B', addedDate: 2),
    ]);
    expect(ok<int>(res), 2);
    expect(ok<List<WishlistBook>>(await repo.getAll()).length, 2);
  });
}
