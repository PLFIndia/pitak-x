import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/infrastructure/drift_wishlist_repository.dart';

import 'bundle_test_fixture.dart';
import 'controlled_bundle_files.dart';

const _failure = StorageFailure('synthetic repository failure');

void main() {
  for (final fault in ['stage', 'retain', 'throw', 'rollback']) {
    for (final row in [
      'new book',
      'existing book',
      'new wish',
      'existing wish',
    ]) {
      test('$fault failure for $row preserves live data', () async {
        final fixture = BundleTestFixture();
        addTearDown(fixture.dispose);
        fixture.cover('covers/old.jpg').writeAsBytesSync([9]);
        await fixture.books.insert(
          const Book(title: 'Old', bookUid: 'u', coverUrl: 'covers/old.jpg'),
        );
        await fixture.wishlist.insert(
          const WishlistBook(
            title: 'Old wish',
            isbn: 'w',
            coverUrl: 'covers/old.jpg',
          ),
        );
        final files = ControlledBundleFiles(fixture.files)..failures.add(fault);
        if (fault == 'rollback') files.failures.add('retain');
        final payload = ImportPayload(
          books: row.endsWith('book')
              ? [
                  Book(
                    title: 'New',
                    bookUid: row == 'existing book' ? 'u' : null,
                    coverUrl: 'covers/a.jpg',
                  ),
                ]
              : [],
          wishlist: row.endsWith('wish')
              ? [
                  WishlistBook(
                    title: 'New wish',
                    isbn: row == 'existing wish' ? 'w' : null,
                    coverUrl: 'covers/a.jpg',
                  ),
                ]
              : [],
        );
        final result = await fixture.apply(
          payload,
          images: {
            'a.jpg': Uint8List.fromList([1]),
          },
          coverFiles: files,
        );
        expect(result.isLeft(), isTrue);
        expect(files.committed, isFalse);
        expect(files.rolledBack, isTrue);
        expect(
          (await fixture.books.getAll()).toNullable()!.single.title,
          'Old',
        );
        expect(
          (await fixture.wishlist.getAll()).toNullable()!.single.title,
          'Old wish',
        );
        expect(fixture.cover('covers/old.jpg').readAsBytesSync(), [9]);
        if (fault == 'rollback') {
          expect(
            fixture.images,
            hasLength(2),
            reason: 'failed cleanup leaves only an unreferenced new file',
          );
          files.failures.clear();
          await files.batch.rollback();
        }
        expect(fixture.images, hasLength(1));
      });
    }
  }
  for (final fault in [
    'uid',
    'isbn',
    'insert',
    'update',
    'wishLookup',
    'wishInsert',
    'wishUpsert',
    'commit',
    'throw',
  ]) {
    test('$fault failure rolls back both tables and all new covers', () async {
      final fixture = BundleTestFixture();
      addTearDown(fixture.dispose);
      fixture.cover('covers/old.jpg').writeAsBytesSync([9]);
      await fixture.books.insert(
        const Book(
          title: 'Old',
          bookUid: 'old',
          isbn: 'seed',
          coverUrl: 'covers/old.jpg',
        ),
      );
      await fixture.wishlist.insert(
        const WishlistBook(
          title: 'Old wish',
          isbn: 'w',
          coverUrl: 'covers/old.jpg',
        ),
      );
      final books = _BookFaults(fixture, fault);
      final result = await fixture.apply(
        const ImportPayload(
          books: [
            Book(
              title: 'New',
              bookUid: 'new',
              isbn: 'new',
              coverUrl: 'covers/a.jpg',
            ),
            Book(
              title: 'Updated',
              bookUid: 'old',
              isbn: 'seed',
              coverUrl: 'covers/b.jpg',
            ),
          ],
          wishlist: [
            WishlistBook(
              title: 'New wish',
              isbn: 'new-w',
              coverUrl: 'covers/a.jpg',
            ),
            WishlistBook(
              title: 'Updated wish',
              isbn: 'w',
              coverUrl: 'covers/b.jpg',
            ),
          ],
        ),
        images: {
          'a.jpg': Uint8List.fromList([1]),
          'b.jpg': Uint8List.fromList([2]),
        },
        bookRepository: books,
        wishlistRepository: _WishFaults(fixture, fault),
      );
      expect(result.isLeft(), isTrue);
      if (fault == 'commit') expect(books.bodySucceeded, isTrue);
      expect((await fixture.books.getAll()).toNullable()!.single.title, 'Old');
      expect(
        (await fixture.wishlist.getAll()).toNullable()!.single.title,
        'Old wish',
      );
      expect(fixture.images, hasLength(1));
      expect(fixture.cover('covers/old.jpg').readAsBytesSync(), [9]);
    });
  }
}

class _BookFaults extends DriftBookRepository {
  _BookFaults(BundleTestFixture fixture, this.fault) : super(fixture.database);
  final String fault;
  bool bodySucceeded = false;
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async =>
      fault == 'uid' ? left(_failure) : super.findByUid(bookUid);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async =>
      fault == 'isbn' ? left(_failure) : super.findByIsbn(isbn);
  @override
  Future<Either<Failure, Book>> insert(Book book) async =>
      fault == 'insert' ? left(_failure) : super.insert(book);
  @override
  Future<Either<Failure, Book>> update(Book book) async =>
      fault == 'update' ? left(_failure) : super.update(book);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) {
    if (fault == 'throw') throw StateError('synthetic unexpected failure');
    return super.runInTransaction(() async {
      final result = await action();
      bodySucceeded = result.isRight();
      // Simulate rejection at the outer boundary AFTER the body succeeds.
      // The real Drift wrapper performs the rollback, not an in-memory fake.
      return fault == 'commit' ? left(_failure) : result;
    });
  }
}

class _WishFaults extends DriftWishlistRepository {
  _WishFaults(BundleTestFixture fixture, this.fault) : super(fixture.database);
  final String fault;
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      fault == 'wishLookup' ? left(_failure) : super.findByIsbn(isbn);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async =>
      fault == 'wishInsert' ? left(_failure) : super.insert(book);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      fault == 'wishUpsert' ? left(_failure) : super.upsert(book);
}
