import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

void main() {
  test('owns immutable copies of rows, mapping and bytes', () {
    final books = [const CatalogueItem(title: 'A', coverUrl: 'covers/a.png')];
    final bytes = Uint8List.fromList([1, 2]);
    final covers = {'a.png': bytes};
    final bundle = ImportBundle.validate(
      ImportPayload(items: books),
      covers,
    ).toNullable()!;
    books.clear();
    covers.clear();
    bytes[0] = 9;
    expect(bundle.payload.items, hasLength(1));
    expect(bundle.covers['a.png'], [1, 2]);
    expect(bundle.payload.items.clear, throwsUnsupportedError);
    expect(bundle.covers.clear, throwsUnsupportedError);
    expect(() => bundle.covers['a.png']![0] = 3, throwsUnsupportedError);
  });
  for (final reference in [
    'covers/../a.jpg',
    r'covers/a\b.jpg',
    'covers/a\u0000.jpg',
    'file:///old/',
    'covers/missing.jpg',
  ]) {
    for (final wishlist in [false, true]) {
      test('rejects unsafe/missing local ref ($wishlist): $reference', () {
        final payload = ImportPayload(
          items: wishlist
              ? []
              : [CatalogueItem(title: 'A', coverUrl: reference)],
          wishlist: wishlist
              ? [WishlistBook(title: 'A', coverUrl: reference)]
              : [],
        );
        expect(ImportBundle.validate(payload, {}).isLeft(), isTrue);
      });
    }
  }
  test('library and wishlist may share a legacy source leaf', () {
    final result = ImportBundle.validate(
      const ImportPayload(
        items: [
          CatalogueItem(title: 'A', coverUrl: 'file:///another/device/a.jpg'),
        ],
        wishlist: [WishlistBook(title: 'B', coverUrl: 'covers/a.jpg')],
      ),
      {
        'a.jpg': Uint8List.fromList([1]),
      },
    );
    expect(result.toNullable()!.covers, hasLength(1));
  });
  test('remote and absent refs need no images and make no requests', () {
    final result = ImportBundle.validate(
      const ImportPayload(
        items: [
          CatalogueItem(title: 'A'),
          CatalogueItem(
            title: 'B',
            coverUrl: 'https://covers.openlibrary.org/x',
          ),
        ],
      ),
      {},
    );
    expect(result.isRight(), isTrue);
  });
  test('rejects parser omissions and unreferenced images', () {
    expect(
      ImportBundle.validate(
        const ImportPayload(parseErrors: ['omitted']),
        {},
      ).isLeft(),
      isTrue,
    );
    expect(
      ImportBundle.validate(const ImportPayload(), {
        'a.jpg': Uint8List(1),
      }).isLeft(),
      isTrue,
    );
    expect(
      ImportBundle.validate(const ImportPayload(), {
        r'a\b.jpg': Uint8List(1),
      }).isLeft(),
      isTrue,
    );
  });
}
