/// UI-facing import controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the presentation layer drives: idle until
/// `importText` is called, then exposes loading / data(ImportSummary) / error.
/// Failures map to `AsyncError(Failure)` so the UI can show a safe message.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart'
    show hasZipLocalFileHeader;
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'import_controller.g.dart';

/// Drives a one-shot import and surfaces its [ImportSummary].
@riverpod
class ImportController extends _$ImportController {
  @override
  FutureOr<ImportSummary?> build() => null; // idle until an import is run

  /// Sniffs + imports [text], updating state to the resulting summary or an
  /// error. The use case returns `Either<Failure, _>`; a left becomes
  /// `AsyncError(failure)` for the UI to render safely.
  Future<void> importText(String text) async {
    state = const AsyncLoading();
    final useCase = await ref.read(importLibraryUseCaseProvider.future);
    final result = await useCase.importText(text);
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }

  /// Imports raw file [bytes], routing by CONTENT (not filename), mirroring
  /// Kotlin `ExportImportViewModel.importFrom`: a ZIP local-file-header magic
  /// (`PK\x03\x04`) means a Pitaka bundle → read it and apply the payload;
  /// anything else is decoded as UTF-8 text and sniffed (JSON/CSV). Content-
  /// routing is deliberate because a shared file's reported MIME is unreliable.
  Future<void> importBytes(Uint8List bytes) async {
    state = const AsyncLoading();
    final useCase = await ref.read(importLibraryUseCaseProvider.future);
    if (hasZipLocalFileHeader(bytes)) {
      final reader = await ref.read(libraryBundleReaderProvider.future);
      final payload = await reader.read(bytes);
      // Both read() and applyPayload() fail with the same `Failure` type, so a
      // monadic flatMap threads the success payload into the writer and
      // short-circuits on the first failure.
      final result = await payload.match(
        (failure) async => left<Failure, ImportSummary>(failure),
        (parsed) => useCase.applyPayload(parsed, ImportFormat.pitakaBundle),
      );
      state = result.match(
        (failure) => AsyncError(failure, StackTrace.current),
        AsyncData.new,
      );
      return;
    }
    // Treat as UTF-8 text (lenient: malformed bytes won't throw).
    final text = utf8.decode(bytes, allowMalformed: true);
    await importText(text);
  }
}
