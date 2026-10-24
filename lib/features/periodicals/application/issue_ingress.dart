/// The steps every magazine-issue write shares (periodicals application
/// layer, AGENTS.md §3/§4; ADR 0013 D1, D3, D6).
///
/// `AddIssueUseCase` and `UpdateIssueUseCase` both have to: find the series
/// the issue belongs to, project the series' fields onto the issue's base
/// row (D3), run that row through `CatalogueItem.validate` (the ingress
/// gate, ADR 0004) and make sure no OTHER row already holds the issue's
/// identity key (D6). Keeping those steps in one place means "a valid issue"
/// has one definition, not one per use case.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

/// Prepares an issue row for persistence and pre-checks its identity.
class IssueIngress {
  /// Creates the ingress over [_periodicals].
  const IssueIngress(this._periodicals);

  final PeriodicalRepository _periodicals;

  /// Looks up the series named by `item.issue.periodicalUid`, projects it
  /// onto [item] and validates the result. Returns the row that may be
  /// written, or a typed failure: [ValidationFailure] when the series no
  /// longer exists or a field is invalid, [UnexpectedFailure] when [item]
  /// is not an issue at all (a caller bug — the generic catalogue use cases
  /// handle books and others), or the repository's read failure.
  Future<Either<Failure, CatalogueItem>> prepare(CatalogueItem item) async {
    final issue = item.issue;
    if (issue == null) {
      return left(
        const UnexpectedFailure('IssueIngress: the item is not an issue'),
      );
    }
    final series = await _periodicals.findByUid(issue.periodicalUid);
    return series.fold(left, (periodical) {
      if (periodical == null) {
        // The link points at nothing: the input is invalid at this boundary,
        // worded through the shared field labels so the form reads naturally.
        return left(
          ValidationFailure(
            const FieldError(
              'issue.periodicalUid',
              'no longer exists',
            ).userMessage,
          ),
        );
      }
      // Normalize the issue's own fields BEFORE projection. Otherwise a
      // legacy local-midnight date could compose the previous UTC month/year,
      // then a later gate would normalize only the details and leave the base
      // title stale. Do not validate the base row yet: add-mode deliberately
      // has a blank title until the series projection supplies it below.
      final normalized = item.copyWith(details: issue.normalized());
      final projected = IssueProjection.apply(normalized, periodical);
      return CatalogueItem.validate(projected).fold(
        (errors) => left(ValidationFailure(errors.first.userMessage)),
        right,
      );
    });
  }

  /// The D6 identity pre-check for a [valid] (already prepared) issue: a
  /// numbered issue must not repeat (`periodicalUid`, `volume ?? 0`,
  /// `issueNumber`), a bound volume must not repeat (`periodicalUid`,
  /// `issueDate`, `boundUntil`). A date-only single issue has no identity
  /// key — like a book without an ISBN — and always passes. [excludeId] is
  /// the row being updated, which cannot collide with itself.
  ///
  /// Same reasoning as the ISBN pre-check (S34): the two partial UNIQUE
  /// indexes are the last line of defence and the repository maps their
  /// violation to the same [DuplicateIssueFailure]; this check turns the
  /// common case into a failure that names the existing row. A failed read
  /// aborts the write (fail closed).
  Future<Either<Failure, Unit>> ensureIdentityIsFree(
    CatalogueItem valid, {
    int? excludeId,
  }) async {
    final issue = valid.issue;
    if (issue == null) {
      return left(
        const UnexpectedFailure('IssueIngress: the item is not an issue'),
      );
    }
    final from = issue.issueDate;
    final until = issue.boundUntil;
    final number = issue.issueNumber;
    final Either<Failure, CatalogueItem?> lookup;
    if (until != null && from != null) {
      lookup = await _periodicals.findBoundVolume(
        periodicalUid: issue.periodicalUid,
        issueDate: from,
        boundUntil: until,
      );
    } else if (until == null && number != null) {
      lookup = await _periodicals.findIssue(
        periodicalUid: issue.periodicalUid,
        volume: issue.volume,
        issueNumber: number,
      );
    } else {
      return right(unit);
    }
    return lookup.fold(left, (found) {
      if (found == null || found.id == excludeId) return right(unit);
      return left(
        DuplicateIssueFailure(
          existingTitle: found.title,
          existingItemId: found.id,
        ),
      );
    });
  }
}
