import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

import 'bundle_test_fixture.dart';

void main() {
  late BundleTestFixture fixture;
  setUp(() {
    fixture = BundleTestFixture();
    addTearDown(fixture.dispose);
  });
  final a = Uint8List.fromList([1, 2]);
  final b = Uint8List.fromList([3, 4]);

  test('UID update preserves identity and old shared files', () async {
    final old = (await fixture.books.insert(
      const Book(title: 'Old', bookUid: 'u', coverUrl: 'covers/old.jpg'),
    )).toNullable()!;
    fixture.cover('covers/old.jpg').writeAsBytesSync([9]);
    final result = await fixture.apply(
      const ImportPayload(
        books: [Book(title: 'New', bookUid: 'u', coverUrl: 'covers/a.jpg')],
      ),
      images: {'a.jpg': a},
    );
    expect(result.toNullable()!.booksUpdated, 1);
    final saved = (await fixture.books.getAll()).toNullable()!.single;
    expect(saved.id, old.id);
    expect(saved.bookUid, old.bookUid);
    expect(fixture.cover(saved.coverUrl!).readAsBytesSync(), a);
    expect(fixture.cover('covers/old.jpg').readAsBytesSync(), [9]);
  });
  test(
    'repeated UID rows retain only the final cover, including null fallback',
    () async {
      final result = await fixture.apply(
        const ImportPayload(
          books: [
            Book(title: 'First', bookUid: 'u', coverUrl: 'covers/a.jpg'),
            Book(title: 'Second', bookUid: 'u', coverUrl: 'covers/b.jpg'),
            Book(title: 'Final', bookUid: 'u'),
          ],
        ),
        images: {'a.jpg': a, 'b.jpg': b},
      );
      expect(result.toNullable()!.booksUpdated, 2);
      final saved = (await fixture.books.getAll()).toNullable()!.single;
      expect(saved.title, 'Final');
      expect(fixture.images, hasLength(1));
      expect(fixture.cover(saved.coverUrl!).readAsBytesSync(), b);
    },
  );
  test(
    'wishlist replacements retain only final refs, not last-insert IDs',
    () async {
      final result = await fixture.apply(
        const ImportPayload(
          wishlist: [
            WishlistBook(title: 'First', isbn: '111', coverUrl: 'covers/a.jpg'),
            WishlistBook(title: 'Other', isbn: '222'),
            WishlistBook(title: 'Final', isbn: '111', coverUrl: 'covers/b.jpg'),
          ],
        ),
        images: {'a.jpg': a, 'b.jpg': b},
      );
      expect(result.toNullable()!.wishlistReplaced, 1);
      final saved = (await fixture.wishlist.findByIsbn('111')).toNullable()!;
      expect(saved.title, 'Final');
      expect(fixture.images, hasLength(1));
      expect(fixture.cover(saved.coverUrl!).readAsBytesSync(), b);
    },
  );

  test('same numeric ID in different tables keeps both covers', () async {
    final result = await fixture.apply(
      const ImportPayload(
        books: [Book(title: 'A', coverUrl: 'covers/a.jpg')],
        wishlist: [WishlistBook(title: 'B', coverUrl: 'covers/b.jpg')],
      ),
      images: {'a.jpg': a, 'b.jpg': b},
    );
    expect(result.isRight(), isTrue);
    expect(fixture.images, hasLength(2));
    final book = (await fixture.books.getAll()).toNullable()!.single;
    final wish = (await fixture.wishlist.getAll()).toNullable()!.single;
    expect(book.id, wish.id);
    expect(fixture.cover(book.coverUrl!).readAsBytesSync(), a);
    expect(fixture.cover(wish.coverUrl!).readAsBytesSync(), b);
  });
  test(
    'reimport by ISBN skips images; shared wishlist still receives one',
    () async {
      const payload = ImportPayload(
        books: [Book(title: 'A', isbn: '111', coverUrl: 'covers/a.jpg')],
      );
      await fixture.apply(payload, images: {'a.jpg': a});
      final repeated = await fixture.apply(payload, images: {'a.jpg': b});
      expect(repeated.toNullable()!.booksSkipped, 1);
      expect(fixture.images, hasLength(1));
      expect(fixture.images.single.readAsBytesSync(), a);
      final shared = await fixture.apply(
        const ImportPayload(
          books: [Book(title: 'A', isbn: '111', coverUrl: 'covers/a.jpg')],
          wishlist: [WishlistBook(title: 'Wish', coverUrl: 'covers/a.jpg')],
        ),
        images: {'a.jpg': b},
      );
      expect(shared.toNullable()!.booksSkipped, 1);
      expect(fixture.images, hasLength(2));
      final wish = (await fixture.wishlist.getAll()).toNullable()!.single;
      expect(fixture.cover(wish.coverUrl!).readAsBytesSync(), b);
    },
  );
  test('empty bundle does not create files', () async {
    expect((await fixture.apply(const ImportPayload())).isRight(), isTrue);
    expect(fixture.images, isEmpty);
  });

  test('one shared file for library, wishlist and legacy references', () async {
    final result = await fixture.apply(
      const ImportPayload(
        books: [Book(title: 'A', coverUrl: 'covers/a.png')],
        wishlist: [
          WishlistBook(title: 'B', coverUrl: 'file:///old/device/a.png'),
        ],
      ),
      images: {'a.png': a},
    );
    expect(result.isRight(), isTrue);
    final book = (await fixture.books.getAll()).toNullable()!.single;
    final wish = (await fixture.wishlist.getAll()).toNullable()!.single;
    expect(book.coverUrl, wish.coverUrl);
    expect(book.coverUrl, isNot('covers/a.png'));
    expect(fixture.cover(book.coverUrl!).readAsBytesSync(), a);
    expect(fixture.images, hasLength(1));
  });
}
