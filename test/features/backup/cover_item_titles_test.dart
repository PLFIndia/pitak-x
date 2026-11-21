import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/cover_item_titles.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// BR6 (decisions D10, D18 and D23): the ONE rule for "which items show
/// this cover picture". The backup writer names the items whose picture it
/// left out with it, and the restore names the items whose picture it
/// skipped. The writer's side is also covered, through `selectBackupCovers`,
/// in `backup_preflight_test.dart`.
void main() {
  const books = [
    CatalogueItem(id: 1, title: 'A book', coverUrl: 'covers/book.jpg'),
    CatalogueItem(id: 2, title: 'Shares it', coverUrl: 'covers/book.jpg'),
    CatalogueItem(id: 3, title: 'Other book', coverUrl: 'covers/other.jpg'),
    CatalogueItem(id: 4, title: 'No cover'),
    CatalogueItem(
      id: 5,
      title: 'Legacy',
      coverUrl: 'file:///data/user/0/app/files/covers/old.jpg',
    ),
    CatalogueItem(
      id: 6,
      title: 'Remote',
      coverUrl: 'https://example.org/book.jpg',
    ),
    CatalogueItem(id: 7, title: 'Traversal', coverUrl: 'covers/../book.jpg'),
  ];
  const wishlist = [
    WishlistBook(id: 1, title: 'A wish', coverUrl: 'covers/wish.jpg'),
    WishlistBook(
      id: 2,
      title: 'Wish, same picture',
      coverUrl: 'covers/book.jpg',
    ),
  ];
  const periodicals = [
    Periodical(
      title: 'A magazine',
      periodicalUid: 'p1',
      coverUrl: 'covers/series.jpg',
    ),
  ];

  List<String> titles(Set<String> leaves) => titlesOfItemsWithCover(
    coverLeaves: leaves,
    books: books,
    wishlist: wishlist,
    periodicals: periodicals,
  );

  test('books first, then wishlist entries, then magazine titles', () {
    expect(titles({'series.jpg', 'wish.jpg', 'book.jpg'}), [
      'A book',
      'Shares it',
      'A wish',
      'Wish, same picture',
      'A magazine',
    ]);
  });

  test('every item that shares the picture is named', () {
    expect(titles({'book.jpg'}), ['A book', 'Shares it', 'Wish, same picture']);
  });

  test('a legacy file:// reference names its file too', () {
    expect(titles({'old.jpg'}), ['Legacy']);
  });

  test('a picture no item refers to names nobody', () {
    expect(titles({'orphan.jpg'}), isEmpty);
  });

  test('no pictures: nobody is named', () {
    expect(titles(const {}), isEmpty);
  });

  test('a remote or an unsafe reference names no file', () {
    // "Remote" and "Traversal" both end in book.jpg; neither is this file.
    expect(titles({'book.jpg'}), isNot(contains('Remote')));
    expect(titles({'book.jpg'}), isNot(contains('Traversal')));
  });
}
