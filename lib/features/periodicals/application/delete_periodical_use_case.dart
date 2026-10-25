/// Hard-delete a magazine title (periodicals application layer, AGENTS.md
/// §4; ADR 0013 D8).
///
/// Fail closed: a title whose issues still reference it cannot be deleted
/// ([PeriodicalHasIssuesFailure] — the UI offers "mark as removed" instead,
/// or the user removes the issues first). The pre-check here gives the
/// honest refusal up front; the repository repeats it INSIDE its own delete
/// transaction, so an issue added between the two cannot be orphaned.
///
/// No vault interaction, unlike `DeleteCatalogueItemUseCase`: the lendable
/// unit is the base row (ADR 0013 F2), so loans reference issues, never the
/// series — and a series that still has issues is never deleted here.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
// The same hook type the item delete uses; the janitor is the one
// implementation of both (`CoverFileJanitor.releaseReference`).
import 'package:pitaka/features/library/application/delete_catalogue_item_use_case.dart'
    show ReleaseCoverFile;
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Permanently deletes a periodical that no issue references any more.
class DeletePeriodicalUseCase {
  /// Creates the use case. [releaseCover] is called with the deleted series'
  /// cover reference AFTER the row is gone (decision Q12: no orphan files);
  /// it defaults to a no-op.
  const DeletePeriodicalUseCase({
    required this.periodicals,
    this.releaseCover = _noRelease,
  });

  static Future<void> _noRelease(String? _) async {}

  /// Periodicals repository (owns the hard `delete`).
  final PeriodicalRepository periodicals;

  /// Cover-file housekeeping hook.
  final ReleaseCoverFile releaseCover;

  /// Deletes the periodical with [id]. Idempotent for a missing id (nothing
  /// to delete, nothing to release). Refuses with
  /// [PeriodicalHasIssuesFailure] while issues still link to the series; a
  /// read failure aborts before anything is deleted (fail closed).
  Future<Either<Failure, Unit>> call(int id) async {
    final lookup = await periodicals.getById(id);
    return lookup.fold(left, (periodical) async {
      if (periodical == null) return right(unit);
      final issueCount = await _countIssues(periodical);
      return issueCount.fold(left, (count) async {
        if (count > 0) return left(PeriodicalHasIssuesFailure(count));
        final deleted = await periodicals.delete(id);
        if (deleted.isRight()) {
          // Row gone → its cover file is unreferenced unless an item or
          // another row still shares it (the janitor double-checks).
          // Best-effort; never fails the delete.
          await releaseCover(periodical.coverUrl);
        }
        return deleted;
      });
    });
  }

  Future<Either<Failure, int>> _countIssues(Periodical periodical) {
    final uid = periodical.periodicalUid;
    // A persisted row always has a uid (the mapper fails closed without
    // one); the guard only keeps the type honest. The repository re-checks
    // on the STORED uid inside its transaction regardless.
    if (uid == null) return Future.value(right(0));
    return periodicals.countIssues(uid);
  }
}
