/// Domain-side repository interface for periodicals and their issues
/// (AGENTS.md §3.3; ADR 0013 D2, D6, D8).
///
/// Declared in `domain`, implemented in `infrastructure`. Returns
/// `Either<Failure, T>` for expected failures; never throws across the
/// layer. Issues are ordinary `CatalogueItem` rows (the base row is the
/// lendable unit, F2); this interface only adds the series-side reads the
/// periodicals screens and use cases need — the paged issue list of a series
/// page goes through `CatalogueItemRepository.page` with
/// `LibraryQuery.periodicalUid` set (one paged read per list).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// One row of the Magazines page: the periodical plus what the list shows
/// about its issues, computed in one query (no per-row round trips).
final class PeriodicalSummary {
  /// Creates a summary.
  const PeriodicalSummary({
    required this.periodical,
    required this.issueCount,
    this.latestIssueDate,
  });

  /// The series.
  final Periodical periodical;

  /// Number of catalogue rows whose `IssueOf.periodicalUid` is this series
  /// (soft-removed issues included — they still exist).
  final int issueCount;

  /// The newest `issueDate` among those issues (epoch millis), or null when
  /// no issue has a date.
  final int? latestIssueDate;

  @override
  String toString() =>
      'PeriodicalSummary(${periodical.title}, issues: $issueCount, '
      'latest: $latestIssueDate)';
}

/// Read/write access to the periodicals store and the series-side issue
/// reads.
abstract interface class PeriodicalRepository {
  /// Every periodical (soft-removed included) with its issue summary,
  /// ordered by title (code-unit order, matching SQLite's default collation)
  /// then id.
  Future<Either<Failure, List<PeriodicalSummary>>> listAll();

  /// Finds a periodical by its per-device [id], or null when none exists.
  Future<Either<Failure, Periodical?>> getById(int id);

  /// Finds a periodical by its stable cross-device [periodicalUid], or null
  /// when none / [periodicalUid] blank.
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid);

  /// Finds a periodical by canonical [issn] (`Issn.normalize` form), or
  /// null when none / [issn] blank. Used by the magazine-barcode route
  /// (D11) and ISSN dedup (D7).
  Future<Either<Failure, Periodical?>> findByIssn(String issn);

  /// Inserts a new periodical, returning it with its assigned id (and
  /// minted uid). An ISSN already held by another row yields
  /// [DuplicateIssnFailure] (the UNIQUE index is the last line of defence
  /// behind the use case's pre-check).
  Future<Either<Failure, Periodical>> insert(Periodical periodical);

  /// Updates an existing periodical in place (matched by [Periodical.id]);
  /// id and uid are preserved. A row that no longer exists yields
  /// [NotFoundFailure]; an ISSN collision yields [DuplicateIssnFailure].
  /// Re-projecting the series' issues is the use case's job, not the
  /// repository's.
  Future<Either<Failure, Periodical>> update(Periodical periodical);

  /// Soft-deletes a periodical: `removed = true`, `removed_at = [at]`. Its
  /// issues are untouched (D8).
  Future<Either<Failure, Unit>> markRemoved(int id, int at);

  /// Clears the soft-delete flag.
  Future<Either<Failure, Unit>> restoreRemoved(int id);

  /// Permanently deletes the periodical row. Fails closed with
  /// [PeriodicalHasIssuesFailure] while any issue still references it (D8):
  /// the uid is a soft link, so the database cannot cascade or refuse on
  /// its own. Idempotent for a missing id.
  Future<Either<Failure, Unit>> delete(int id);

  /// Number of catalogue rows that are issues of [periodicalUid].
  Future<Either<Failure, int>> countIssues(String periodicalUid);

  /// The numbered issue (`periodicalUid`, `volume ?? 0`, `issueNumber`)
  /// already catalogued, or null (D6 identity key; bound volumes excluded).
  Future<Either<Failure, CatalogueItem?>> findIssue({
    required String periodicalUid,
    required int? volume,
    required int issueNumber,
  });

  /// The bound volume (`periodicalUid`, `issueDate`, `boundUntil`) already
  /// catalogued, or null (D6 identity key).
  Future<Either<Failure, CatalogueItem?>> findBoundVolume({
    required String periodicalUid,
    required int issueDate,
    required int boundUntil,
  });

  /// Every issue of [periodicalUid] (soft-removed included) in
  /// `IssueSorter` order. Bounded by the series itself — used by the
  /// re-projection after a series edit and by merge, never by a screen
  /// (screens page through `CatalogueItemRepository.page`).
  Future<Either<Failure, List<CatalogueItem>>> issuesOf(String periodicalUid);

  /// Bulk insert used by restore/import. Returns the inserted rows (with
  /// ids and minted uids). Atomic: either every row lands or none does.
  Future<Either<Failure, List<Periodical>>> insertAll(
    List<Periodical> periodicals,
  );

  /// Atomically replaces EVERY periodical with [periodicals] (delete all +
  /// insert all in one transaction). Used by merge OVERWRITE and restore.
  /// Rows keep their incoming `periodicalUid`; a null uid is minted fresh.
  Future<Either<Failure, int>> replaceAll(List<Periodical> periodicals);
}
