/// UI-facing merge controller (application layer, AGENTS.md §4).
///
/// Owns one merge attempt's lifecycle ABOVE the page (N11, astra-review.md):
/// a merge WRITES the catalogue, so once started it must finish even if the
/// user navigates away, and the library-list refresh must not depend on the
/// page still being there. The page only renders the MergeUiState and
/// forwards intents (pick → mergeText, decision → applyJoin/applyOverwrite,
/// review row → resolve).
///
/// Lifecycle pattern modelled on `ImportController`/`PublishController`:
/// `ref.keepAlive()` pins this autoDispose element for the run, `_running`
/// refuses a concurrent second merge, and every path ends in a typed state —
/// an unexpected throw becomes `MergeFailed(UnexpectedFailure)` instead of
/// escaping into the page's unawaited future.
///
/// N07 (part 2): after a merge, the conflicts and possible duplicates the
/// engine surfaced become [MergeReviewItem]s inside [MergeDone]. The user
/// resolves them one at a time through [MergeController.resolve]; each row
/// keeps its own [MergeReviewStatus] so a failure on one row never hides the
/// others, and a completed write refreshes the library list from here.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'merge_controller.g.dart';

/// Lifecycle of one merge attempt, owned by [MergeController] (N11).
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
              d.local.id == Book.emptyId
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
  final Book local;

  /// The incoming book.
  final Book incoming;

  /// Jaccard similarity for [MergeReviewKind.similarTitle]; 1.0 otherwise.
  final double similarity;

  /// What established a [MergeReviewKind.conflict] match; null otherwise.
  final MatchKind? matchedBy;

  /// Where this row is in its lifecycle.
  final MergeReviewStatus status;

  /// True when the user can still act on this row.
  bool get isOpen => status is ReviewPending || status is ReviewFailed;

  /// False for an in-file collision: [local] was never persisted, so there
  /// is no row on this device to overwrite. The page hides the button; the
  /// use case refuses the call regardless.
  bool get canTakeTheirs => kind != MergeReviewKind.inFileCollision;

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

/// Runs merges for the Merge screen; idle until [mergeText] is called.
@riverpod
class MergeController extends _$MergeController {
  /// True while [mergeText] runs — a second pick is refused (N11).
  bool _running = false;

  /// True after this element was disposed (container teardown mid-run).
  bool _disposed = false;

  @override
  MergeUiState build() {
    ref.onDispose(() => _disposed = true);
    return const MergeIdle();
  }

  /// True while a review row's write is in flight (N07). A new file pick is
  /// refused meanwhile: the catalogue is mid-write and the new merge would
  /// plan against a moving target. This is also what keeps the state in
  /// [MergeDone] until the row's completion lands.
  bool get _resolving => switch (state) {
    MergeDone(:final isResolving) => isResolving,
    _ => false,
  };

  /// Parses and merges [text]: same library ID → applied immediately
  /// ([MergeDone]); different ID → [MergeNeedsDecision] for the page.
  Future<void> mergeText(String text) async {
    if (_running || _resolving || _disposed) return;
    _running = true;
    // keepAlive for the duration of the run: without it, popping the page
    // mid-merge lets autoDispose destroy this element while the use case is
    // still writing — the terminal state would be swallowed and a rebuilt
    // page could start a SECOND concurrent merge.
    final link = ref.keepAlive();
    state = const MergeRunning();
    try {
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final result = await useCase.call(text);
      if (!_disposed) {
        state = result.match(
          MergeFailed.new,
          (outcome) => switch (outcome) {
            MergeMerged(:final result) => _merged(result),
            MergeDiffersDecision() => MergeNeedsDecision(outcome),
          },
        );
      }
    } on Object {
      if (!_disposed) {
        state = const MergeFailed(UnexpectedFailure('Merge failed.'));
      }
    } finally {
      _running = false;
      link.close();
    }
  }

  /// JOIN (non-destructive union + adopt the incoming namespace).
  Future<void> applyJoin() =>
      _apply((useCase, decision) => useCase.applyJoin(decision));

  /// OVERWRITE (replace the local catalogue; the page confirms first). The
  /// use case reports it as a replacement (`replaced: true`), not as a
  /// zero-count merge (N07).
  Future<void> applyOverwrite() =>
      _apply((useCase, decision) => useCase.applyOverwrite(decision));

  Future<void> _apply(
    Future<Either<Failure, MergeResult>> Function(
      MergeLibraryUseCase useCase,
      MergeDiffersDecision decision,
    )
    action,
  ) async {
    final current = state;
    if (current is! MergeNeedsDecision || current.applying || _disposed) {
      return;
    }
    final link = ref.keepAlive();
    state = MergeNeedsDecision(current.decision, applying: true);
    try {
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final result = await action(useCase, current.decision);
      if (!_disposed) {
        state = result.match(
          (failure) =>
              MergeNeedsDecision(current.decision, applyFailure: failure),
          _merged,
        );
      }
    } on Object {
      if (!_disposed) {
        state = MergeNeedsDecision(
          current.decision,
          applyFailure: const UnexpectedFailure('Merge failed.'),
        );
      }
    } finally {
      link.close();
    }
  }

  /// Applies [resolution] to the [index]th review row of the current
  /// [MergeDone] (N07). Refused — silently, the page never offers it — when
  /// there is no done state, the index is out of range, the row is not open,
  /// or another row is already applying (one write at a time, fail closed).
  ///
  /// The row moves to [ReviewApplying], then to [ReviewResolved] or
  /// [ReviewFailed] (typed; an unexpected throw becomes `UnexpectedFailure`).
  /// A write that changed the catalogue (take-theirs / keep-both) refreshes
  /// the library list from here; keep-mine touches nothing.
  Future<void> resolve(int index, MergeResolution resolution) async {
    final current = state;
    if (current is! MergeDone ||
        _disposed ||
        current.isResolving ||
        index < 0 ||
        index >= current.review.length ||
        !current.review[index].isOpen) {
      return;
    }
    final item = current.review[index];
    // Same reason as `_apply`: the write must finish even if the page goes.
    final link = ref.keepAlive();
    state = current.withItemStatus(index, const ReviewApplying());
    try {
      final useCase = await ref.read(mergeLibraryUseCaseProvider.future);
      final result = await useCase.applyResolution(
        local: item.local,
        incoming: item.incoming,
        resolution: resolution,
      );
      _publishRowStatus(
        index,
        result.match(ReviewFailed.new, (_) => ReviewResolved(resolution)),
      );
      if (result.isRight() && resolution != MergeResolution.keepMine) {
        ref.invalidate(libraryControllerProvider);
      }
    } on Object {
      _publishRowStatus(
        index,
        const ReviewFailed(UnexpectedFailure('Merge failed.')),
      );
    } finally {
      link.close();
    }
  }

  /// Writes a row status into the current [MergeDone]. The state cannot have
  /// left [MergeDone] meanwhile (`mergeText` is refused while resolving), so
  /// the type check only guards a disposed-and-rebuilt element.
  void _publishRowStatus(int index, MergeReviewStatus status) {
    if (_disposed) return;
    final current = state;
    if (current is! MergeDone) return;
    state = current.withItemStatus(index, status);
  }

  /// Terminal state for a successful apply: the catalogue changed, so
  /// refresh the library list from HERE (N11) — a popped Merge page cannot
  /// leave the list underneath stale.
  MergeUiState _merged(MergeResult result) {
    ref.invalidate(libraryControllerProvider);
    return MergeDone(result);
  }
}
