/// UI-facing merge controller (application layer, AGENTS.md §4).
///
/// Owns one merge attempt's lifecycle ABOVE the page (review finding N11:
/// long-running actions used to outlive their widgets with no safe
/// completion handling):
/// a merge WRITES the catalogue, so once started it must finish even if the
/// user navigates away, and the library-list refresh must not depend on the
/// page still being there. The page only renders the MergeUiState and
/// forwards intents (choose a file → mergeFile, decision →
/// applyJoin/applyOverwrite, review row → resolve).
///
/// THE CHOSEN FILE (decision D24): [MergeController.mergeFile] lets the user
/// choose it through the app's own picker, as a private copy that is never
/// larger than the text cap, and owns everything that happens to it (see
/// `picked_text_file.dart`). The page never sees the file or its bytes.
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

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/application/merge_ui_state.dart';
import 'package:pitaka/features/import_export/application/picked_text_file.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

// The states this controller shows live in a file of their own; exported
// so that a page that imports the controller gets them with it.
export 'package:pitaka/features/import_export/application/merge_ui_state.dart';

part 'merge_controller.g.dart';

/// Runs merges for the Merge screen; idle until [mergeFile] is called.
@riverpod
class MergeController extends _$MergeController {
  /// True while a merge runs, from the tap on "choose a file" until its
  /// result is there. A second one is refused (N11).
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

  /// True while a Join or a Replace is being written. A new merge is
  /// refused meanwhile, for the same reason as [_resolving]: two writes to
  /// the catalogue at once, and the one that ends last would set the state
  /// over the other's result.
  bool get _applying => switch (state) {
    MergeNeedsDecision(:final applying) => applying,
    _ => false,
  };

  /// Whether a new merge may start now. One getter for both ways in, so
  /// that neither can forget a reason.
  bool get _mayStart => !(_running || _resolving || _applying || _disposed);

  /// Parses and merges [text]: same library ID → applied immediately
  /// ([MergeDone]); different ID → [MergeNeedsDecision] for the page.
  Future<void> mergeText(String text) => _run(() async => text);

  /// Lets the user choose a library file and merges it, as [mergeText] does
  /// with a text.
  ///
  /// Answers null when there is nothing to tell the user: the file was
  /// handed to the merge (its result is this controller's state), the
  /// picker was closed without a choice, or a merge, a choice or a review
  /// row is being worked on. Otherwise it answers WHY no file was taken,
  /// and the page says so. In both of the "nothing merged" cases the state
  /// goes back to what it was before the tap, so a pending choice and the
  /// review rows of an earlier merge stay on the page.
  ///
  /// The state is [MergeRunning] from the tap on, also while the picker is
  /// open and while a file kept online is fetched. While it is, a Join, a
  /// Replace and a review row all refuse to start, so nothing else can
  /// write the state that is put back.
  Future<PickedFileProblem?> mergeFile() async {
    PickedFileProblem? problem;
    await _run(() async {
      // Both are fetched BEFORE the picker opens. With them in hand the
      // copy of the file can be read and removed even when this controller
      // is torn down while the user is still choosing.
      final DocumentPicker picker;
      final PickedDocumentReader reader;
      try {
        picker = await ref.read(documentPickerProvider.future);
        reader = ref.read(pickedDocumentReaderProvider);
      } on Object {
        // The picker could not be set up (its folder could not be found,
        // for one). For the user that is a pick that failed.
        problem = PickedFileProblem.failed;
        return null;
      }
      final picked = await pickAndReadText(
        picker: picker,
        reader: reader,
        // The cap the parser has for a text: UTF-8 never has more
        // characters than bytes, so a byte cap is a sound early reject.
        maxBytes: ImportLimits.defaults.maxTextChars,
        // Merge hands every file to its parser, which says what is wrong
        // with it in Merge's own words.
        refuseZip: false,
      );
      switch (picked) {
        case PickedTextNothing():
          return null;
        case PickedTextProblem(problem: final found):
          problem = found;
          return null;
        case PickedTextRead(:final bytes):
          // Malformed UTF-8 is decoded leniently (as Import does), so that
          // the PARSER rejects it with a sentence instead of a throw here.
          return utf8.decode(bytes, allowMalformed: true);
      }
    });
    return problem;
  }

  /// Runs one merge. [source] answers the text to merge, or null for "there
  /// is no text and nothing went wrong" (a picker that was closed, a file
  /// that was not taken): the state then goes back to what it was.
  Future<void> _run(Future<String?> Function() source) async {
    if (!_mayStart) return;
    _running = true;
    // keepAlive for the duration of the run: without it, popping the page
    // mid-merge lets autoDispose destroy this element while the use case is
    // still writing — the terminal state would be swallowed and a rebuilt
    // page could start a SECOND concurrent merge.
    final link = ref.keepAlive();
    // What the page showed before this run, to put back when nothing is
    // merged. Nothing else can change the state meanwhile: see [mergeFile].
    final before = state;
    state = const MergeRunning();
    try {
      final text = await source();
      if (text == null) {
        if (!_disposed) state = before;
        return;
      }
      // When this controller was torn down while the picker was open, this
      // read throws (a disposed `ref` cannot be used), the catch below
      // takes it, and nothing is merged.
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
        ref.read(catalogueChangesProvider.notifier).changed();
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
  /// left [MergeDone] meanwhile (a new merge is refused while resolving), so
  /// the type check only guards a disposed-and-rebuilt element.
  void _publishRowStatus(int index, MergeReviewStatus status) {
    if (_disposed) return;
    final current = state;
    if (current is! MergeDone) return;
    state = current.withItemStatus(index, status);
  }

  /// Terminal state for a successful apply: the catalogue changed, so
  /// say so from HERE (N11; ADR 0031) — a popped Merge page cannot leave
  /// the lists underneath stale.
  MergeUiState _merged(MergeResult result) {
    ref.read(catalogueChangesProvider.notifier).changed();
    return MergeDone(result);
  }
}
