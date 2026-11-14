/// UI-facing import controller. The run belongs to this controller, not to
/// the widget: leaving the page must not abandon an import half-way.
///
/// Import reads text: Pitak JSON and Goodreads CSV. Two ways in:
///  - [ImportController.importText], for text the user pasted;
///  - [ImportController.importFile], which lets the user choose a file. The
///    file comes through the app's own picker, as a private copy that is
///    never larger than the text cap, and this controller owns everything
///    that happens to it (decision D24, see `picked_text_file.dart`). The
///    page never sees the file or its bytes.
///
/// A ZIP file is refused with a sentence and is never unpacked or loaded
/// (backup rework BR7, decision D29): [ImportController.importFile] asks
/// for that when it picks.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/platform/picked_document_reader.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/picked_text_file.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'import_controller.g.dart';

/// Drives one import at a time and surfaces its safe terminal result.
@riverpod
class ImportController extends _$ImportController {
  bool _running = false;
  bool _disposed = false;

  @override
  FutureOr<ImportSummary?> build() {
    ref.onDispose(() => _disposed = true);
    return null;
  }

  /// Sniffs and imports text. Its existing partial-row semantics are unchanged.
  Future<void> importText(String text) => _run(() async {
    final useCase = await ref.read(importLibraryUseCaseProvider.future);
    return useCase.importText(text);
  });

  /// Lets the user choose a file and imports it. Judged by content, not by
  /// the file's unreliable name or MIME type.
  ///
  /// Answers null when there is nothing to tell the user: the file was
  /// imported (its result is this controller's state), the picker was
  /// closed without a choice, or another import is running. Otherwise it
  /// answers WHY no file was taken, and the page says so. In both of the
  /// "nothing imported" cases the state goes back to what it was before
  /// the tap, so an earlier summary stays on the page.
  ///
  /// The state is "loading" from the tap on, also while the picker is open
  /// and while a file kept online is fetched: nothing else can be started
  /// meanwhile.
  Future<PickedFileProblem?> importFile() async {
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
        // One cap, the text cap: UTF-8 never has more characters than
        // bytes, so a byte cap is a sound early reject, and the parser
        // checks the decoded length again.
        maxBytes: ImportLimits.defaults.maxTextChars,
        // D29: Import reads no ZIP.
        refuseZip: true,
      );
      switch (picked) {
        case PickedTextNothing():
          return null;
        case PickedTextProblem(problem: final found):
          problem = found;
          return null;
        case PickedTextRead(:final bytes):
          // When this controller was torn down while the picker was open,
          // this read throws (a disposed `ref` cannot be used), `_run`
          // catches it, and nothing is imported: nobody is left to show a
          // result to. The copy is gone already.
          final useCase = await ref.read(importLibraryUseCaseProvider.future);
          return useCase.importText(utf8.decode(bytes, allowMalformed: true));
      }
    });
    return problem;
  }

  /// Runs [action] as the one import of this controller.
  ///
  /// [action] answers the import's result, or null for "nothing was
  /// imported and nothing went wrong" (a picker that was closed, a file
  /// that was not taken): the state then goes back to what it was.
  Future<void> _run(
    Future<Either<Failure, ImportSummary>?> Function() action,
  ) async {
    if (_running || _disposed) return;
    _running = true;
    // As in PublishController, keep the operation and its rollback alive during
    // navigation, then release it on completion.
    final link = ref.keepAlive();
    // What the page showed before this run, to put back when nothing is
    // imported. Nothing else can change the state meanwhile: `_running`
    // refuses every other run.
    final before = state;
    state = const AsyncLoading();
    try {
      final result = await action();
      if (!_disposed) {
        state = result == null
            ? before
            : result.match(
                (failure) => AsyncError(failure, StackTrace.current),
                (summary) {
                  // N11: the import ADDS rows to both lists — refresh them
                  // from HERE so a popped Import page cannot leave the
                  // lists underneath stale (this used to be the page's job,
                  // lost with its `ref`).
                  ref
                    ..invalidate(libraryControllerProvider)
                    ..invalidate(wishlistControllerProvider);
                  return AsyncData(summary);
                },
              );
      }
    } on Object catch (_, stack) {
      if (!_disposed) {
        state = AsyncError(const UnexpectedFailure('Import failed.'), stack);
      }
    } finally {
      _running = false;
      link.close();
    }
  }
}
