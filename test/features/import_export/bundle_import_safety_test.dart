import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

import 'bundle_test_fixture.dart';

/// Review finding M04: an import that brings cover pictures must never
/// write over a cover that is already on the device.
///
/// The rows are built here, as the restore from the user's own published
/// site hands them to `importBundle`. (Until BR7 they came out of a bundle
/// file; reading such a file was removed, decision D29. A third scenario,
/// "invalid JSON", was a test of that reader and went with it.)
void main() {
  for (final scenario in ['duplicate ISBN', 'database rollback']) {
    test('M04: $scenario leaves existing covers untouched', () async {
      final fixture = BundleTestFixture();
      addTearDown(fixture.dispose);
      final cover = File('${fixture.directory.path}/existing.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await fixture.books.insert(
        const CatalogueItem(
          title: 'Keep',
          itemUid: 'old',
          isbn: '111',
          coverUrl: 'covers/existing.jpg',
        ),
      );
      await fixture.books.insert(
        const CatalogueItem(title: 'Other', isbn: '999'),
      );

      // The incoming rows name a cover with the SAME leaf as the one on
      // disk, and bring other bytes for it.
      final result = await fixture.apply(
        ImportPayload(
          items: [
            CatalogueItem(
              title: 'Incoming',
              isbn: scenario == 'duplicate ISBN' ? '111' : '222',
              coverUrl: 'covers/existing.jpg',
            ),
            // Same identity as 'Keep', but the ISBN of 'Other': updating
            // the row breaks a UNIQUE rule, and the transaction rolls back.
            if (scenario == 'database rollback')
              const CatalogueItem(
                title: 'Collision',
                itemUid: 'old',
                isbn: '999',
              ),
          ],
        ),
        images: {
          'existing.jpg': Uint8List.fromList([9, 9, 9]),
        },
      );

      // The old implementation wrote [9, 9, 9] before either outcome.
      expect(cover.readAsBytesSync(), [1, 2, 3]);
      expect(fixture.images, hasLength(1));
      final rows = (await fixture.books.getAll()).toNullable()!;
      expect(rows, hasLength(2));
      expect(rows.singleWhere((b) => b.itemUid == 'old').title, 'Keep');
      if (scenario == 'duplicate ISBN') {
        expect(result.toNullable()!.booksSkipped, 1);
      } else {
        expect(result.isLeft(), isTrue);
      }
    });
  }
}
