/// Edit an existing magazine issue (periodicals application layer,
/// AGENTS.md §3/§4; ADR 0013 D3, D6, D8).
///
/// Same shape as `UpdateCatalogueItemUseCase` with two issue-specific rules:
///  - the stored row must already BE an issue — a row's kind cannot change
///    after creation (D8), so this use case never turns a book or an "other"
///    item into an issue;
///  - the inherited fields are re-projected from the series the edited row
///    names (moving an issue to another series is an ordinary edit: it is
///    projected from, and deduplicated within, the new series).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/application/issue_ingress.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Projects, validates and updates an existing issue row.
class UpdateIssueUseCase {
  /// Creates the use case over the periodicals store (series lookup and
  /// identity pre-check) and the item store (the stored row and the write).
  UpdateIssueUseCase({
    required PeriodicalRepository periodicals,
    required CatalogueItemRepository items,
  }) : _items = items,
       _ingress = IssueIngress(periodicals);

  final CatalogueItemRepository _items;
  final IssueIngress _ingress;

  /// Updates [item] in place (matched by id; the stored uid is preserved by
  /// the repository). Returns the stored row or a typed failure:
  /// [NotFoundFailure] for an unpersisted or vanished row,
  /// [ValidationFailure] when the stored row is not an issue (D8), the
  /// series no longer exists or a field is invalid, [DuplicateIssueFailure]
  /// when ANOTHER row holds the identity key, or the repository's failure.
  Future<Either<Failure, CatalogueItem>> call(CatalogueItem item) async {
    if (item.id == CatalogueItem.emptyId) {
      return left(const NotFoundFailure());
    }
    final stored = await _items.getById(item.id);
    return stored.fold(left, (existing) async {
      if (existing == null) return left(const NotFoundFailure());
      if (existing.kind != ItemKind.magazineIssue) {
        return left(
          const ValidationFailure(
            'This item is not a magazine issue. An item cannot change its '
            'kind after it is added.',
          ),
        );
      }
      final prepared = await _ingress.prepare(item);
      return prepared.fold(left, (valid) async {
        final free = await _ingress.ensureIdentityIsFree(
          valid,
          excludeId: valid.id,
        );
        return free.fold(left, (_) => _items.update(valid));
      });
    });
  }
}
