import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
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
  // S5 (H4): validate() used to rebuild the payload with items + wishlist
  // only, so a v4 bundle silently lost every magazine title and its issues
  // restored as books.
  test('preserves magazine titles and warnings losslessly (S5)', () {
    final result = ImportBundle.validate(
      const ImportPayload(
        items: [CatalogueItem(title: 'A')],
        periodicals: [Periodical(title: 'Frontline', periodicalUid: 'p1')],
        wishlist: [WishlistBook(title: 'W')],
        warnings: ['Something was shortened.'],
      ),
      {},
    );
    final payload = result.toNullable()!.payload;
    expect(payload.periodicals.single.periodicalUid, 'p1');
    expect(payload.items.single.title, 'A');
    expect(payload.wishlist.single.title, 'W');
    expect(payload.warnings, ['Something was shortened.']);
    // The bundle is immutable all the way down (the pre-existing contract).
    expect(payload.periodicals.clear, throwsUnsupportedError);
    expect(payload.warnings.clear, throwsUnsupportedError);
  });

  test('a series cover is validated and counts as a referenced leaf (S5)', () {
    const seriesRow = Periodical(
      title: 'Frontline',
      periodicalUid: 'p1',
      coverUrl: 'covers/series.jpg',
    );
    // Present in the archive: accepted, and the leaf is referenced.
    expect(
      ImportBundle.validate(const ImportPayload(periodicals: [seriesRow]), {
        'series.jpg': Uint8List.fromList([1]),
      }).isRight(),
      isTrue,
    );
    // Absent from the archive: refused before any write.
    expect(
      ImportBundle.validate(
        const ImportPayload(periodicals: [seriesRow]),
        {},
      ).isLeft(),
      isTrue,
    );
    // Unsafe reference: refused, exactly like an item's.
    expect(
      ImportBundle.validate(
        const ImportPayload(
          periodicals: [
            Periodical(
              title: 'Frontline',
              periodicalUid: 'p1',
              coverUrl: 'covers/../series.jpg',
            ),
          ],
        ),
        {
          'series.jpg': Uint8List.fromList([1]),
        },
      ).isLeft(),
      isTrue,
    );
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
