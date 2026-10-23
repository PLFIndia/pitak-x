/// Re-project the issues of a stored series (periodicals application layer,
/// AGENTS.md §3/§4; ADR 0013 D3) — the single shared loop behind a series
/// edit and the merge.
///
/// D3 (beginner note): an issue's title, transliteration, publisher,
/// language, publication year and age group are PROJECTED from its series
/// onto the issue's own base row, so every existing consumer — list, search,
/// publish, backup, merge — reads plain columns. The price: whenever the
/// series' stored row and its issues could disagree, every issue is
/// rewritten from the series. Two callers need that (AGENTS §0 "one blessed
/// way", so it lives here exactly once):
///  - `UpdatePeriodicalUseCase` — the series was just edited;
///  - `MergeLibraryUseCase` — a merged series' stored issues may be stale
///    (import updates the series row without re-projecting, S18) and the
///    merge is the seam that repairs them.
///
/// Call INSIDE a transaction (the item repository's `runInTransaction`
/// covers both stores — they share the database): a `Left` here must roll
/// back the surrounding writes, so a catalogue can never show a renamed
/// series with half of its issues still carrying the old name.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Rewrites the projected fields of every issue of one stored series.
class IssueReprojection {
  /// Creates the helper over the periodicals store (for the issue reads) and
  /// the item store (for the writes).
  IssueReprojection({
    required PeriodicalRepository periodicals,
    required CatalogueItemRepository items,
  }) : _periodicals = periodicals,
       _items = items;

  final PeriodicalRepository _periodicals;
  final CatalogueItemRepository _items;

  /// Rewrites every issue of [stored] whose projected fields differ from
  /// what the series now says. Unchanged rows are skipped: editing a private
  /// field such as the subscription window must not rewrite (and re-index)
  /// every issue for nothing. Any `Left` — the issue read, an item write, or
  /// a projected row failing the validation gate — is propagated so the
  /// caller's transaction rolls back.
  Future<Either<Failure, Unit>> call(Periodical stored) async {
    final uid = stored.periodicalUid;
    if (uid == null || uid.trim().isEmpty) {
      // Cannot happen — a persisted row always has a uid and the repository
      // keeps the stored one — but without it the issues cannot be found,
      // and committing a change that leaves them behind is exactly the drift
      // D3 forbids. Fail closed: the `Left` rolls the caller's writes back.
      return left(
        const UnexpectedFailure(
          'IssueReprojection: the stored periodical has no uid',
        ),
      );
    }
    final issues = await _periodicals.issuesOf(uid);
    return issues.fold(left, (rows) async {
      for (final row in rows) {
        final projected = IssueProjection.apply(row, stored);
        if (_alreadyProjected(row, projected)) continue;
        // The projected row passes the same gate as any other write
        // (ADR 0004): a series title at the length cap could compose an
        // issue title over it, and that must refuse the write, not store it.
        final written = await CatalogueItem.validate(projected).fold(
          (errors) async => left<Failure, CatalogueItem>(
            ValidationFailure(errors.first.userMessage),
          ),
          _items.update,
        );
        if (written.isLeft()) return written.map((_) => unit);
      }
      return right(unit);
    });
  }

  /// True when [row] already carries exactly what [projected] would write.
  /// These six fields are the only ones `IssueProjection.apply` changes.
  static bool _alreadyProjected(CatalogueItem row, CatalogueItem projected) =>
      row.title == projected.title &&
      row.titleTransliteration == projected.titleTransliteration &&
      row.publisher == projected.publisher &&
      row.language == projected.language &&
      row.publishedYear == projected.publishedYear &&
      row.ageGroup == projected.ageGroup;
}
