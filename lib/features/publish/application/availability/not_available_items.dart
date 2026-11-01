/// The "not available" set, from the catalogue and the loan counts (publish
/// application layer; ADR 0019 Decisions 1 and 2, plan C.3, A.6 #17/#18).
///
/// Why this lives in application and not in the publish domain (beginner
/// note): the ONE rule for "every copy is lent out" is the vault's
/// `isBookUnavailable`. Application code may depend on another feature's
/// domain; the publish domain may not, and must not keep its own copy of the
/// rule. The catalogue builder's inline tag calls the same function, so
/// `availability.json` and the inline `books.json` tag can never disagree
/// when they are built from the same counts.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/vault/domain/availability.dart';

/// The internal ids of the items that are NOT available: live (not removed),
/// not of kind Other, and with every copy lent out according to
/// [activeCounts] (item id → active loans).
///
/// [activeCounts] must be KNOWN counts. A locked vault has no counts at all,
/// and the caller must then publish nothing, never an empty set (AV5).
///
/// Kind Other is skipped (product decision, A.6 #17): no reader shows a tag
/// for it, so there is nothing to publish, and lending one changes nothing.
Set<int> notAvailableItemIds({
  required Iterable<CatalogueItem> items,
  required Map<int, int> activeCounts,
}) => {
  for (final item in items)
    if (!item.removed &&
        item.kind != ItemKind.other &&
        isBookUnavailable(
          bookId: item.id,
          copyCount: item.copyCount,
          activeCounts: activeCounts,
        ))
      item.id,
};
