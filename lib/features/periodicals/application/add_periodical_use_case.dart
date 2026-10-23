/// Add a magazine title (periodicals application layer, AGENTS.md §3/§4;
/// ADR 0013 D2, D7).
///
/// Mirrors `AddCatalogueItemUseCase`: the form pre-checks the title, but the
/// use case is the single source of truth — every row passes
/// `Periodical.validate` and the ISSN pre-check (both in
/// `PeriodicalIngress`) before the repository mints the `periodical_uid` at
/// first insert.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/periodicals/application/periodical_ingress.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Validates and inserts a new [Periodical].
class AddPeriodicalUseCase {
  /// Creates the use case over [periodicals].
  AddPeriodicalUseCase(PeriodicalRepository periodicals)
    : _periodicals = periodicals,
      _ingress = PeriodicalIngress(periodicals);

  final PeriodicalRepository _periodicals;
  final PeriodicalIngress _ingress;

  /// Inserts [periodical] after validating it and checking that its ISSN (if
  /// any) is not already catalogued. Returns the persisted row (with its
  /// assigned id and minted uid), a [ValidationFailure], a
  /// [DuplicateIssnFailure] naming the existing title, or the repository's
  /// failure.
  Future<Either<Failure, Periodical>> call(Periodical periodical) async {
    final prepared = await _ingress.prepare(periodical);
    return prepared.fold(left, _periodicals.insert);
  }
}
