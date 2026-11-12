import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';

/// BR6: the covers phase of a restore.
void main() {
  // The ONE rule for "is this archive entry a cover picture, and what is
  // its file called". The list of covers a restore writes and the covers
  // the publishing record believes in both come from it.
  group('restorableCoverLeaf', () {
    test('a cover entry gives its file name', () {
      expect(restorableCoverLeaf('cover_a.jpg'), 'a.jpg');
      expect(
        restorableCoverLeaf('cover_3f2b8c1e-0000-4000-8000-000000000000.jpg'),
        '3f2b8c1e-0000-4000-8000-000000000000.jpg',
      );
      // Only the first prefix is taken off.
      expect(restorableCoverLeaf('cover_cover_a.jpg'), 'cover_a.jpg');
      // A name in another script, and a space inside a name, are fine.
      expect(restorableCoverLeaf('cover_गोदान.jpg'), 'गोदान.jpg');
      expect(restorableCoverLeaf('cover_my cover.jpg'), 'my cover.jpg');
    });

    test('an entry that is not called cover_… is not a cover', () {
      expect(restorableCoverLeaf('books.db'), isNull);
      expect(restorableCoverLeaf('manifest.json'), isNull);
      expect(restorableCoverLeaf('Cover_a.jpg'), isNull);
      expect(restorableCoverLeaf('acover_a.jpg'), isNull);
      expect(restorableCoverLeaf('cover'), isNull);
      expect(restorableCoverLeaf(''), isNull);
    });

    test('an empty name is refused', () {
      expect(restorableCoverLeaf('cover_'), isNull);
    });

    test('a name that could leave the folder is refused', () {
      expect(restorableCoverLeaf('cover_..'), isNull);
      expect(restorableCoverLeaf('cover_../a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_a..b.jpg'), isNull);
      expect(restorableCoverLeaf('cover_sub/a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_/a.jpg'), isNull);
      expect(restorableCoverLeaf('cover_c:d.jpg'), isNull);
      expect(restorableCoverLeaf('cover_C:'), isNull);
    });

    test('a name that trimming would change is refused', () {
      expect(restorableCoverLeaf('cover_a.jpg '), isNull);
      expect(restorableCoverLeaf('cover_a.jpg\n'), isNull);
      expect(restorableCoverLeaf('cover_ '), isNull);
    });

    test('whatever it accepts, an item can refer to, and the other way '
        'round', () {
      // The rule an item's cover reference has to pass is the same one, so
      // no item can point at a file this function refuses.
      for (final leaf in ['a.jpg', 'गोदान.jpg', 'my cover.jpg', '..', 'a:b']) {
        final asEntry = restorableCoverLeaf('$coverEntryPrefix$leaf');
        final asReference = CoverPaths.leafOf('${CoverPaths.prefix}$leaf');
        expect(asEntry, asReference, reason: leaf);
      }
    });
  });
}
