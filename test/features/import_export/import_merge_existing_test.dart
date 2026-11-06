import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_merge_existing.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

void main() {
  test('same-kind merge preserves identity, attribution and local cover', () {
    const existing = CatalogueItem(
      id: 7,
      itemUid: 'uid-7',
      title: 'Old title',
      coverUrl: 'covers/local.jpg',
      addedDate: 11,
      addedBy: 'me',
    );
    const incoming = CatalogueItem(
      title: 'New title',
      coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
    );

    final result = mergeImportedCatalogueItem(
      existing: existing,
      incoming: incoming,
    );

    expect(result.isRight(), isTrue);
    final merged = result.toNullable()!;
    expect(merged.id, 7);
    expect(merged.itemUid, 'uid-7');
    expect(merged.title, 'New title');
    expect(merged.addedDate, 11);
    expect(merged.addedBy, 'me');
    expect(merged.coverUrl, 'covers/local.jpg');
  });

  test('a merged row that fails validation returns a typed failure', () {
    const existing = CatalogueItem(id: 7, itemUid: 'uid-7', title: 'Old title');
    const incoming = CatalogueItem(title: '');

    final result = mergeImportedCatalogueItem(
      existing: existing,
      incoming: incoming,
    );

    expect(result.isLeft(), isTrue);
    expect(result.swap().toNullable(), isA<ValidationFailure>());
  });
}
