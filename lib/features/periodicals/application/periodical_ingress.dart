/// The steps every periodical write shares (periodicals application layer,
/// AGENTS.md §3/§4; ADR 0013 D2, D7).
///
/// `AddPeriodicalUseCase` and `UpdatePeriodicalUseCase` both run the row
/// through `Periodical.validate` (the ingress gate, AGENTS §3.3) and then
/// check that its ISSN is not already held by ANOTHER magazine title (D7).
/// Keeping both steps here means "a periodical that may be saved" has one
/// definition, not one per use case.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Validates a periodical and pre-checks its ISSN against the store.
class PeriodicalIngress {
  /// Creates the ingress over [_periodicals].
  const PeriodicalIngress(this._periodicals);

  final PeriodicalRepository _periodicals;

  /// Returns the validated, normalised [periodical] (title trimmed, ISSN in
  /// its canonical `NNNN-NNNC` form) when it may be saved, or a typed
  /// failure: [ValidationFailure] for a field error, [DuplicateIssnFailure]
  /// when another row already carries the ISSN. [excludeId] is the row being
  /// updated — keeping your own ISSN is no collision.
  ///
  /// Why a pre-check when the UNIQUE index already refuses the write (the
  /// same S34 reasoning as the ISBN check in `AddCatalogueItemUseCase`): the
  /// index rejection arrives as a raw SQLite exception, which the repository
  /// can only report as "a storage error". Checking first turns the common
  /// case into an honest failure naming the existing title. The repository
  /// maps the race (a concurrent add between this check and the write) to
  /// the SAME failure, so callers see one behaviour. A FAILED read is
  /// propagated, never skipped: if the store cannot be read we do not
  /// blind-write (fail closed).
  Future<Either<Failure, Periodical>> prepare(
    Periodical periodical, {
    int? excludeId,
  }) async {
    return Periodical.validate(periodical).fold(
      (errors) => left(ValidationFailure(errors.first.userMessage)),
      (valid) => _issnIsFree(valid, excludeId: excludeId),
    );
  }

  Future<Either<Failure, Periodical>> _issnIsFree(
    Periodical valid, {
    required int? excludeId,
  }) async {
    final issn = valid.issn;
    // `Periodical.validate` turns a blank ISSN into null: no ISSN, no check.
    if (issn == null) return right(valid);
    final existing = await _periodicals.findByIssn(issn);
    return existing.fold(left, (found) {
      if (found == null || found.id == excludeId) return right(valid);
      return left(
        DuplicateIssnFailure(
          existingTitle: found.title,
          existingPeriodicalId: found.id,
        ),
      );
    });
  }
}
