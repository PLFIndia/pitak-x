/// The result/outcome types of the multi-maintainer merge (application
/// layer, AGENTS.md §3.1) — split from `merge_library_use_case.dart` in plan
/// S19 so both stay under the 500-line cap; the use case file `export`s this
/// one, so existing callers keep a single import.
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// What happened to this device's library identity during an apply (N07).
enum MergeNamespaceOutcome {
  /// The IDs already matched — nothing to adopt.
  unchanged,

  /// The incoming ID (and name, when present) was adopted.
  adopted,

  /// The books landed but the identity write failed. This device still has
  /// its OLD ID: the next merge from the same library will ask to Join again
  /// (every row will then be identical, so only the identity is adopted).
  adoptionFailed,
}

/// Result of an applied merge: the engine union (IDs matched or Join), or a
/// full replacement (Overwrite). Carries every omission the user should know
/// about — skipped rows, adjustments, review items, identity outcome — so the
/// page never describes a partial merge as simply "complete" (N07).
class MergeResult {
  /// Creates a merge result.
  const MergeResult({
    required this.added,
    required this.identical,
    required this.conflicts,
    required this.possibleDuplicates,
    this.replaced = false,
    this.skippedRows = const [],
    this.adjustments = const [],
    this.namespace = MergeNamespaceOutcome.unchanged,
    this.periodicalsAdded = 0,
    this.periodicalsIdentical = 0,
    this.periodicalConflicts = const [],
  });

  /// Books added automatically (add-only union), or — for a replacement — the
  /// number of books now on this device.
  final int added;

  /// Matched + field-equal; no action taken.
  final int identical;

  /// Matched but differing — await user resolution.
  final List<MergeConflict> conflicts;

  /// No-ISBN fuzzy near-misses and in-file key collisions — await user
  /// confirmation.
  final List<PossibleDuplicate> possibleDuplicates;

  /// True when the local catalogue was REPLACED (Overwrite) rather than
  /// unioned. The page must not present this as "books added".
  final bool replaced;

  /// Rows in the file the parser REJECTED (M15) — they are not on this device.
  /// M15's own messages: row number, a short title so the user can find the
  /// row, and the field names at fault — never the invalid values themselves.
  final List<String> skippedRows;

  /// Non-fatal changes the parser made to kept rows (M15: shortened text,
  /// dropped cover links).
  final List<String> adjustments;

  /// What happened to the library identity.
  final MergeNamespaceOutcome namespace;

  /// Magazine titles added automatically (schema v4, ADR 0014 W1) — for a
  /// replacement, the number of titles now on this device.
  final int periodicalsAdded;

  /// Magazine titles matched + field-equal; no action taken.
  final int periodicalsIdentical;

  /// Magazine titles matched but differing — the local row was kept (merge
  /// is add-only for series; a removal is never applied silently). The page
  /// reports the count; there is no per-row resolution for series.
  final List<PeriodicalMergeConflict> periodicalConflicts;

  /// True when there is anything for the user to review.
  bool get hasReviewItems =>
      conflicts.isNotEmpty || possibleDuplicates.isNotEmpty;

  /// True when the summary must explain something beyond the counts.
  bool get hasOmissions =>
      skippedRows.isNotEmpty ||
      adjustments.isNotEmpty ||
      namespace == MergeNamespaceOutcome.adoptionFailed;

  /// The same result with the identity outcome set.
  MergeResult withNamespace(MergeNamespaceOutcome outcome) => MergeResult(
    added: added,
    identical: identical,
    conflicts: conflicts,
    possibleDuplicates: possibleDuplicates,
    replaced: replaced,
    skippedRows: skippedRows,
    adjustments: adjustments,
    namespace: outcome,
    periodicalsAdded: periodicalsAdded,
    periodicalsIdentical: periodicalsIdentical,
    periodicalConflicts: periodicalConflicts,
  );
}

/// Top-level outcome of `MergeLibraryUseCase.call`.
sealed class MergeOutcome {
  const MergeOutcome();
}

/// Library IDs matched (or both empty-and-equal): engine merge already applied.
final class MergeMerged extends MergeOutcome {
  /// Creates a merged outcome.
  const MergeMerged(this.result);

  /// The applied merge result.
  final MergeResult result;
}

/// Library IDs DIFFER (D40). Nothing applied yet — the user must choose JOIN or
/// OVERWRITE. Carries the data needed to apply either, plus the names for a
/// legible warning.
final class MergeDiffersDecision extends MergeOutcome {
  /// Creates a differ-decision outcome.
  const MergeDiffersDecision({
    required this.incomingBooks,
    required this.incomingLibraryId,
    required this.incomingLibraryName,
    required this.localLibraryName,
    required this.localIsEmpty,
    this.incomingPeriodicals = const [],
    this.skippedRows = const [],
    this.adjustments = const [],
  });

  /// The parsed incoming books (not yet applied).
  final List<CatalogueItem> incomingBooks;

  /// The parsed incoming magazine titles (schema v4; not yet applied). Join
  /// merges them like the books; Overwrite replaces the local titles with
  /// them.
  final List<Periodical> incomingPeriodicals;

  /// Rows the parser rejected — forwarded into the apply's [MergeResult] so
  /// a Join/Overwrite still tells the user what the file lost (N07).
  final List<String> skippedRows;

  /// Parser adjustments to kept rows — forwarded like [skippedRows].
  final List<String> adjustments;

  /// The incoming file's validated library ID (blank when absent/malformed).
  final String incomingLibraryId;

  /// The incoming file's library name (for the warning).
  final String incomingLibraryName;

  /// This app's library name (for the warning).
  final String localLibraryName;

  /// True when the local library has no books AND no magazine titles —
  /// overwrite is then safe.
  final bool localIsEmpty;
}

/// How the user chose to resolve one surfaced conflict / possible-duplicate.
enum MergeResolution {
  /// No-op: keep the local book unchanged.
  keepMine,

  /// Overwrite the local row in place (preserve id + uid; take their fields).
  takeTheirs,

  /// Insert the incoming book as a NEW separate row (fresh identity).
  keepBoth,
}
