/// "Which items show this cover picture?" (backup domain, pure Dart).
///
/// WHY THIS FILE EXISTS (beginner note): a cover picture that is too large
/// is left out of a backup when it is written (decision D10) and skipped
/// when a backup is restored (decisions D18 and D23). Both times the user
/// is told WHICH items lost their picture, by title. The rule that turns
/// "these picture files" into "these titles" must be the same on both
/// sides, so it lives here once.
library;

import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// The titles of the items whose cover reference names one of the picture
/// files in [coverLeaves] (file names, without a folder).
///
/// The order is fixed: [books] first, then [wishlist] entries, then magazine
/// titles ([periodicals]), each in the order it was given. An item appears
/// once per list it is in; two items with the same title give two entries.
///
/// A picture file that no item refers to adds nothing: there is nothing to
/// name. A remote or unsafe cover reference names no file at all
/// (`CoverPaths.leafOf` is the app's one rule for that).
List<String> titlesOfItemsWithCover({
  required Set<String> coverLeaves,
  required List<CatalogueItem> books,
  required List<WishlistBook> wishlist,
  required List<Periodical> periodicals,
}) {
  if (coverLeaves.isEmpty) return const [];

  bool namesOne(String? coverUrl) {
    final leaf = CoverPaths.leafOf(coverUrl);
    return leaf != null && coverLeaves.contains(leaf);
  }

  return [
    for (final book in books)
      if (namesOne(book.coverUrl)) book.title,
    for (final wish in wishlist)
      if (namesOne(wish.coverUrl)) wish.title,
    for (final periodical in periodicals)
      if (namesOne(periodical.coverUrl)) periodical.title,
  ];
}
