/// What the Merge screen can show: the states of one merge attempt and the
/// review rows of a finished one (application layer, AGENTS.md §7).
///
/// These types were part of `merge_controller.dart` until that file came
/// to the 500-line ceiling (2026-11, decision D24: the controller gained
/// the way of a chosen file). They moved here unchanged. The controller's
/// file exports this one, so whoever imports the controller still gets
/// them.
///
/// Only the merge controller makes and changes these states; a page reads
/// them.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_result.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';

/// Lifecycle of one merge attempt, owned by the merge controller (N11).
sealed class MergeUiState {
  const MergeUiState();
}

/// Nothing picked yet.
final class MergeIdle extends MergeUiState {
  /// Creates the idle state.
  const MergeIdle();
}

/// A merge (or an apply) is running.
final class MergeRunning extends MergeUiState {
  /// Creates the running state.
  const MergeRunning();
}

/// The incoming file belongs to a DIFFERENT library: the user must choose
/// Join or Overwrite. Preserved across a failed apply (with [applyFailure]
/// set) so the user can retry or pick the other option — a failed apply must
/// not drop them off the decision.
final class MergeNeedsDecision extends MergeUiState {
  /// Creates the decision state for [decision].
  const MergeNeedsDecision(
    this.decision, {
    this.applyFailure,
    this.applying = false,
  });

  /// The pending join/overwrite decision.
  final MergeDiffersDecision decision;

  /// Why the last apply attempt failed, or null when not attempted/failed.
  final Failure? applyFailure;

  /// True while an apply (join/overwrite) is in flight — buttons disable.
  final bool applying;
}

/// The merge was applied. [result] carries the counts AND every omission the
/// user must hear about — skipped rows, adjustments, a replaced catalogue, an
/// identity that could not be adopted (N07) — so the page can be honest.
/// [review] is the per-row review list built from the result's conflicts and
/// possible duplicates (conflicts first, engine order), each with its own
/// status.
final class MergeDone extends MergeUiState {
  /// Creates the done state with [result]; the review list is derived.
  MergeDone(this.result) : review = _reviewItemsOf(result);

  const MergeDone._(this.result, this.review);

  /// The applied merge (or replacement) result.
  final MergeResult result;

  /// One item per conflict / possible duplicate, in display order.
  final List<MergeReviewItem> review;

  /// Items the user has not resolved yet (pending or failed).
  int get openCount => review.where((i) => i.isOpen).length;

  /// True while one row's write is in flight.
  bool get isResolving => review.any((i) => i.status is ReviewApplying);

  /// The same state with the [index]th item's status replaced.
  MergeDone withItemStatus(int index, MergeReviewStatus status) {
    final next = List<MergeReviewItem>.of(review);
    next[index] = next[index]._withStatus(status);
    return MergeDone._(result, List.unmodifiable(next));
  }

  static List<MergeReviewItem> _reviewItemsOf(MergeResult result) {
    final items = <MergeReviewItem>[
      for (final c in result.conflicts)
        MergeReviewItem._(
          kind: MergeReviewKind.conflict,
          local: c.local,
          incoming: c.incoming,
          similarity: 1,
          matchedBy: c.matchedBy,
        ),
      for (final d in result.possibleDuplicates)
        MergeReviewItem._(
          kind: switch (d.reason) {
            DuplicateReason.similarTitle => MergeReviewKind.similarTitle,
            // The key holder is a persisted local row (a claimed one) OR an
            // earlier row from the same file (never persisted under that
            // object). Only the latter has nothing to overwrite.
            DuplicateReason.identityKey =>
              d.local.id == CatalogueItem.emptyId
                  ? MergeReviewKind.inFileCollision
                  : MergeReviewKind.identityKey,
          },
          local: d.local,
          incoming: d.incoming,
          similarity: d.similarity,
          matchedBy: null,
        ),
    ];
    return List.unmodifiable(items);
  }
}

/// Why a row needs the user's attention (N07). Drives the card's headline
/// and which actions make sense.
enum MergeReviewKind {
  /// Same book (uid/ISBN match), differing catalogue fields.
  conflict,

  /// No-ISBN incoming row resembling a local no-ISBN book (fuzzy).
  similarTitle,

  /// The incoming row's uid/ISBN is held by a book on this device that
  /// another row of the file already claimed.
  identityKey,

  /// The incoming row's uid/ISBN is held by an EARLIER row of the same file.
  /// "Take theirs" is impossible: there is no local book to replace.
  inFileCollision,
}

/// Lifecycle of one review row.
sealed class MergeReviewStatus {
  const MergeReviewStatus();
}

/// Awaiting the user's choice.
final class ReviewPending extends MergeReviewStatus {
  /// Creates the pending status.
  const ReviewPending();
}

/// The chosen resolution is being written.
final class ReviewApplying extends MergeReviewStatus {
  /// Creates the applying status.
  const ReviewApplying();
}

/// The resolution was applied.
final class ReviewResolved extends MergeReviewStatus {
  /// Creates the resolved status for [resolution].
  const ReviewResolved(this.resolution);

  /// What the user chose.
  final MergeResolution resolution;
}

/// The last attempt failed; the row stays open for a retry.
final class ReviewFailed extends MergeReviewStatus {
  /// Creates the failed status with [failure].
  const ReviewFailed(this.failure);

  /// The typed failure (never raw exception text, §5).
  final Failure failure;
}

/// One conflict / possible duplicate awaiting (or past) the user's decision.
final class MergeReviewItem {
  const MergeReviewItem._({
    required this.kind,
    required this.local,
    required this.incoming,
    required this.similarity,
    required this.matchedBy,
    this.status = const ReviewPending(),
  });

  /// Why this row is here.
  final MergeReviewKind kind;

  /// The book already on the winning side (a local row — or, for
  /// [MergeReviewKind.inFileCollision], the earlier incoming row).
  final CatalogueItem local;

  /// The incoming book.
  final CatalogueItem incoming;

  /// Jaccard similarity for [MergeReviewKind.similarTitle]; 1.0 otherwise.
  final double similarity;

  /// What established a [MergeReviewKind.conflict] match; null otherwise.
  final MatchKind? matchedBy;

  /// Where this row is in its lifecycle.
  final MergeReviewStatus status;

  /// True when the user can still act on this row.
  bool get isOpen => status is ReviewPending || status is ReviewFailed;

  /// False for an in-file collision: [local] was never persisted, so there
  /// is no row on this device to overwrite. Also false when the two sides
  /// are different KINDS (ADR 0013 D6/D8: an item cannot change its kind
  /// after creation — overwriting in place would flip it). The page hides
  /// the button; the use case refuses the call regardless.
  bool get canTakeTheirs =>
      kind != MergeReviewKind.inFileCollision && local.kind == incoming.kind;

  MergeReviewItem _withStatus(MergeReviewStatus next) => MergeReviewItem._(
    kind: kind,
    local: local,
    incoming: incoming,
    similarity: similarity,
    matchedBy: matchedBy,
    status: next,
  );
}

/// The merge itself failed (parse, storage, unexpected) — safe copy only.
final class MergeFailed extends MergeUiState {
  /// Creates the failed state with [failure].
  const MergeFailed(this.failure);

  /// The typed failure (never raw exception text, §5).
  final Failure failure;
}
