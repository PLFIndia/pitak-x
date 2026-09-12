/// UI-facing merge controller (application layer, AGENTS.md §4).
///
/// Owns one merge attempt's lifecycle ABOVE the page (N11, astra-review.md):
/// a merge WRITES the catalogue, so once started it must finish even if the
/// user navigates away, and the library-list refresh must not depend on the
/// page still being there. The page only renders the MergeUiState and
/// forwards intents (pick → mergeText, decision → applyJoin/applyOverwrite).
///
/// Lifecycle pattern modelled on `ImportController`/`PublishController`:
/// `ref.keepAlive()` pins this autoDispose element for the run, `_running`
/// refuses a concurrent second merge, and every path ends in a typed state —
/// an unexpected throw becomes `MergeFailed(UnexpectedFailure)` instead of
/// escaping into the page's unawaited future.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
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
final class MergeDone extends MergeUiState {
  /// Creates the done state with [result].
  const MergeDone(this.result);

  /// The applied merge (or replacement) result.
  final MergeResult result;
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

  /// Parses and merges [text]: same library ID → applied immediately
  /// ([MergeDone]); different ID → [MergeNeedsDecision] for the page.
  Future<void> mergeText(String text) async {
    if (_running || _disposed) return;
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

  /// Terminal state for a successful apply: the catalogue changed, so
  /// refresh the library list from HERE (N11) — a popped Merge page cannot
  /// leave the list underneath stale.
  MergeUiState _merged(MergeResult result) {
    ref.invalidate(libraryControllerProvider);
    return MergeDone(result);
  }
}
