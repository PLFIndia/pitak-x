/// Add a magazine issue — or a bound volume of issues — to the library
/// (periodicals application layer, AGENTS.md §3/§4; ADR 0013 D1, D3, D4,
/// D6).
///
/// The form hands in a catalogue item whose `details` is an `IssueOf`
/// (the series link, numbers and dates) plus the issue's own fields (cover,
/// copies, pages, location, notes…). Everything the issue inherits from its
/// series — title, transliteration, publisher, language, year, age group —
/// is projected here, never typed; the row then passes the shared gate and
/// the identity pre-check before the item repository stores it (base row +
/// detail row in one transaction).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/issue_ingress.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Projects, validates and inserts a new issue row.
class AddIssueUseCase {
  /// Creates the use case over the periodicals store (series lookup and
  /// identity pre-check) and the item store (the write).
  AddIssueUseCase({
    required PeriodicalRepository periodicals,
    required CatalogueItemRepository items,
  }) : _items = items,
       _ingress = IssueIngress(periodicals);

  final CatalogueItemRepository _items;
  final IssueIngress _ingress;

  /// Inserts [item] as an issue of the series its `issue.periodicalUid`
  /// names. Returns the persisted row (projected title, assigned id, minted
  /// uid) or a typed failure: [ValidationFailure] (unknown series, invalid
  /// field), [DuplicateIssueFailure] naming the row that already holds the
  /// identity key, or the repository's failure.
  Future<Either<Failure, CatalogueItem>> call(CatalogueItem item) async {
    final prepared = await _ingress.prepare(item);
    return prepared.fold(left, (valid) async {
      final free = await _ingress.ensureIdentityIsFree(valid);
      return free.fold(left, (_) => _items.insert(valid));
    });
  }
}
