/// UI-facing import controller. File ownership belongs to the use case, not
/// the widget: leaving the page must not abandon a partially written bundle.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart'
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

  /// Routes by content, not the file's unreliable name/MIME type.
  Future<void> importBytes(Uint8List bytes) {
    if (!hasZipLocalFileHeader(bytes)) {
      return importText(utf8.decode(bytes, allowMalformed: true));
    }
    return _run(() async {
      final reader = await ref.read(libraryBundleReaderProvider.future);
      final decoded = await reader.read(bytes);
      return decoded.match(
        (failure) async => left<Failure, ImportSummary>(failure),
        (bundle) async {
          final useCase = await ref.read(importLibraryUseCaseProvider.future);
          final covers = await ref.read(bundleCoverFilesProvider.future);
          final coordinator = ref.read(coverFileCoordinatorProvider);
          return useCase.importBundle(
            bundle,
            coverFiles: covers,
            coordinator: coordinator,
          );
        },
      );
    });
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
