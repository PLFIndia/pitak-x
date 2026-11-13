/// UI-facing import controller. The run belongs to this controller, not to
/// the widget: leaving the page must not abandon an import half-way.
///
/// Import reads text: Pitak JSON and Goodreads CSV. A ZIP file is refused
/// here with a sentence and is never unpacked (backup rework BR7, decision
/// D29). This is where that RULE lives; the Import page only applies it
/// earlier, before it loads a picked file.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart'
    show hasZipLocalFileHeader;
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

  /// Imports the bytes of a file. Judged by content, not by the file's
  /// unreliable name or MIME type.
  ///
  /// Bytes that start like a ZIP are not read: the run ends as "Import
  /// failed" with [kImportZipRefusedMessage], the way a text of unknown
  /// format does. Nothing is unpacked, no cover store is asked for and
  /// nothing is written. Everything else is decoded as text.
  Future<void> importBytes(Uint8List bytes) {
    if (hasZipLocalFileHeader(bytes)) {
      return _run(
        () async => right(
          const ImportSummary(
            format: null,
            parseErrors: [kImportZipRefusedMessage],
          ),
        ),
      );
    }
    return importText(utf8.decode(bytes, allowMalformed: true));
  }

  Future<void> _run(
    Future<Either<Failure, ImportSummary>> Function() action,
  ) async {
    if (_running || _disposed) return;
    _running = true;
    // As in PublishController, keep the operation and its rollback alive during
    // navigation, then release it on completion.
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final result = await action();
      if (!_disposed) {
        state = result.match(
          (failure) => AsyncError(failure, StackTrace.current),
          (summary) {
            // N11: the import ADDS rows to both lists — refresh them from
            // HERE so a popped Import page cannot leave the lists underneath
            // stale (this used to be the page's job, lost with its `ref`).
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
