/// Edit a magazine title and keep its issues in step (periodicals
/// application layer, AGENTS.md §3/§4; ADR 0013 D3, D7).
///
/// D3 (beginner note): an issue's title, transliteration, publisher,
/// language, publication year and age group are PROJECTED from its series
/// onto the issue's own base row, so every existing consumer — list, search,
/// publish, backup, merge — reads plain columns. The price is paid here:
/// after the series row is updated, every issue of the series is
/// re-projected, in ONE transaction. A failure on issue N rolls back the
/// series edit and issues 1..N-1 alike, so the catalogue can never show a
/// renamed series with half of its issues still carrying the old name.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/issue_reprojection.dart';
import 'package:pitaka/features/periodicals/application/periodical_ingress.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Validates and updates an existing [Periodical], re-projecting its issues.
class UpdatePeriodicalUseCase {
  /// Creates the use case over the periodicals store and the item store the
  /// issues live in.
  UpdatePeriodicalUseCase({
    required PeriodicalRepository periodicals,
    required CatalogueItemRepository items,
  }) : _periodicals = periodicals,
       _items = items,
       _ingress = PeriodicalIngress(periodicals),
       _reprojection = IssueReprojection(
         periodicals: periodicals,
         items: items,
       );

  final PeriodicalRepository _periodicals;
  final CatalogueItemRepository _items;
  final PeriodicalIngress _ingress;

  /// The shared re-projection loop (one blessed way, AGENTS §0): the merge
  /// use case repairs stale series projections through the same code.
  final IssueReprojection _reprojection;

  /// Updates [periodical] (matched by id; the stored uid is preserved by the
  /// repository) and rewrites the projected fields of every issue of the
  /// series. Returns the stored row, or a typed failure: [NotFoundFailure]
  /// for an unpersisted or vanished row, [ValidationFailure],
  /// [DuplicateIssnFailure], or the repository's failure. On ANY failure
  /// nothing is changed.
  Future<Either<Failure, Periodical>> call(Periodical periodical) async {
    // The id is not touched by validation, so the cheapest check goes first.
    if (periodical.id == Periodical.emptyId) {
      return left(const NotFoundFailure());
    }
    final prepared = await _ingress.prepare(
      periodical,
      excludeId: periodical.id,
    );
    return prepared.fold(
      left,
      // Drift transactions are zone-scoped: the periodical repository's
      // update and every item update below join this ONE transaction, and a
      // `Left` from the callback rolls all of them back. Only the item
      // repository exposes the transaction — the two stores share the
      // database, so it covers both.
      (valid) => _items.runInTransaction(() => _updateAndReproject(valid)),
    );
  }

  Future<Either<Failure, Periodical>> _updateAndReproject(
    Periodical valid,
  ) async {
    final updated = await _periodicals.update(valid);
    return updated.fold(
      left,
      (stored) async => (await _reprojection.call(stored)).map((_) => stored),
    );
  }
}
