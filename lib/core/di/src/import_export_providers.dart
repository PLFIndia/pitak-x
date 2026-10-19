/// Import/export/merge DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the bundle reader + imported-cover store, the
/// import/export use cases, the PDF renderer seams, and the multi-maintainer
/// merge use case. Concrete codecs/renderers are infrastructure, wired here
/// at the composition root (N14).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/import_bundle.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/background_merge_planner.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';
import 'package:pitaka/features/import_export/infrastructure/library_bundle_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/logo_file_reader.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_text_rasterizer.dart'
    hide PdfTextRasterizer, RasterizedText;
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'import_export_providers.g.dart';

/// Side-effect-free bundle decoding, exposed through its domain contract.
@riverpod
Future<BundleReader> libraryBundleReader(LibraryBundleReaderRef ref) async =>
    const LibraryBundleReader();

/// Operation-owned imported covers under the existing app-private covers dir.
@riverpod
Future<BundleCoverFiles> bundleCoverFiles(BundleCoverFilesRef ref) async =>
    FileBundleCoverStore(coversDir: await ref.watch(coversDirProvider.future));

/// One-shot library/wishlist import use case.
@riverpod
Future<ImportLibraryUseCase> importLibraryUseCase(
  ImportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ImportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    // N14: the concrete JSON codec is infrastructure, wired here at the
    // composition root.
    jsonParser: const PitakaJsonImporter(),
  );
}

/// Library-logo file reader for exports (N14): file IO injected as a port;
/// the application controller no longer touches dart:io.
@riverpod
Future<Future<Uint8List?> Function(String)> exportLogoReader(
  ExportLogoReaderRef ref,
) async {
  final coversDir = await ref.watch(coversDirProvider.future);
  return logoFileReader(coversDir);
}

/// One-shot library/wishlist export use case.
@riverpod
Future<ExportLibraryUseCase> exportLibraryUseCase(
  ExportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  return ExportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    jsonEncoder: const PitakaJsonExporter(),
    pdfRenderer: const PdfLibraryRenderer(),
  );
}

/// Loads the bundled footer icon for the PDF export, or null when the asset
/// is missing (a missing icon must never block an export). Behind a provider
/// because `rootBundle` is a side effect the application layer must not own.
@riverpod
Future<Uint8List?> Function() pdfFooterIconLoader(PdfFooterIconLoaderRef ref) =>
    () async {
      try {
        final data = await rootBundle.load('assets/pdf/app_icon.png');
        return data.buffer.asUint8List();
      } on Object {
        return null;
      }
    };

/// Shaped-text rasterizer for the PDF export (needs a live Flutter engine +
/// the bundled Noto fonts — infrastructure, injected as the domain
/// `PdfTextRasterizer` port).
@riverpod
PdfTextRasterizer pdfTextRasterizer(PdfTextRasterizerRef ref) =>
    UiPdfTextRasterizer(
      regularAssets: pdfRegularFontAssets,
      boldAssets: pdfBoldFontAssets,
    );

/// Multi-maintainer library merge use case (PLAN-merge.md): reconciles an
/// incoming Pitaka-JSON file with the local catalogue behind the library-ID
/// gate. The library identity (ID gate + Join/Overwrite adoption) goes through
/// `SettingsController` — the single serialised settings writer — via the
/// `LibraryNamespace` port, so the drawer/title/export name update the moment
/// a merge adopts a library (N07; same shape as the replacement guard below).
@riverpod
Future<MergeLibraryUseCase> mergeLibraryUseCase(
  MergeLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(bookRepositoryProvider.future);
  return MergeLibraryUseCase(
    bookRepo: bookRepo,
    namespace: ref.read(settingsControllerProvider.notifier),
    jsonParser: const PitakaJsonImporter(),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
    // N10-c: the plan is computed on a worker isolate.
    planner: planMergeInBackground,
  );
}
