import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/publish/application/availability/not_available_items.dart';
import 'package:pitaka/features/vault/domain/availability.dart';

/// The "not available" set (ADR 0019 Decisions 1 and 2, plan C.3).
void main() {
  test('only items with EVERY copy out are listed', () {
    const items = [
      CatalogueItem(id: 1, title: 'One copy, lent'),
      CatalogueItem(id: 2, title: 'One copy, on the shelf'),
      CatalogueItem(id: 3, title: 'Three copies, two lent', copyCount: 3),
      CatalogueItem(id: 4, title: 'Three copies, all lent', copyCount: 3),
    ];
    expect(
      notAvailableItemIds(items: items, activeCounts: const {1: 1, 3: 2, 4: 3}),
      {1, 4},
    );
  });

  test('lending the second copy of a three-copy book changes nothing', () {
    const book = CatalogueItem(id: 1, title: 'T', copyCount: 3);
    expect(
      notAvailableItemIds(items: [book], activeCounts: const {1: 1}),
      isEmpty,
    );
    expect(
      notAvailableItemIds(items: [book], activeCounts: const {1: 2}),
      isEmpty,
    );
  });

  test('removed items and items of kind Other are never listed (A.6 #17)', () {
    const items = [
      CatalogueItem(id: 1, title: 'Removed', removed: true),
      CatalogueItem(id: 2, title: 'Board game', details: OtherItemOf()),
      CatalogueItem(
        id: 3,
        title: 'Issue',
        details: IssueOf(periodicalUid: 'uid-1', issueNumber: 1),
      ),
    ];
    expect(
      notAvailableItemIds(items: items, activeCounts: const {1: 1, 2: 1, 3: 1}),
      {3},
      reason: 'magazine issues are tagged like books',
    );
  });

  test('known but empty counts mean everything is on the shelf', () {
    const items = [CatalogueItem(id: 1, title: 'T')];
    expect(notAvailableItemIds(items: items, activeCounts: const {}), isEmpty);
  });

  test('agrees with the vault rule for every row, malformed ones included', () {
    // copyCount 0 never passes validation, but the clamp in the ONE rule
    // still decides, so the out-set can never disagree with the inline tag.
    const items = [
      CatalogueItem(id: 1, title: 'Zero copies', copyCount: 0),
      CatalogueItem(id: 2, title: 'Zero copies, one lent', copyCount: 0),
      CatalogueItem(id: 3, title: 'Two copies', copyCount: 2),
    ];
    const counts = {2: 1, 3: 2};
    expect(notAvailableItemIds(items: items, activeCounts: counts), {
      for (final item in items)
        if (isBookUnavailable(
          bookId: item.id,
          copyCount: item.copyCount,
          activeCounts: counts,
        ))
          item.id,
    });
    expect(notAvailableItemIds(items: items, activeCounts: counts), {2, 3});
  });
}
