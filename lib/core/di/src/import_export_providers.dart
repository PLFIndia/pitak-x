/// Import/export/merge DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the imported-cover store, the import/export use cases,
/// the PDF renderer seams, and the multi-maintainer merge use case. Concrete
/// codecs/renderers are infrastructure, wired here at the composition root
/// (N14).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pitaka/core/di/src/availability_providers.dart';
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';
import 'package:pitaka/features/import_export/domain/export_work_area.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_port.dart';
import 'package:pitaka/features/import_export/domain/pdf_text_raster.dart';
import 'package:pitaka/features/import_export/infrastructure/background_merge_planner.dart';
import 'package:pitaka/features/import_export/infrastructure/file_bundle_cover_store.dart';
import 'package:pitaka/features/import_export/infrastructure/file_export_work_area.dart';
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

/// Operation-owned imported covers under the existing app-private covers dir.
@riverpod
Future<BundleCoverFiles> bundleCoverFiles(BundleCoverFilesRef ref) async =>
    FileBundleCoverStore(coversDir: await ref.watch(coversDirProvider.future));

/// One-shot library/wishlist import use case.
@riverpod
Future<ImportLibraryUseCase> importLibraryUseCase(
  ImportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(catalogueItemRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  final periodicalRepo = await ref.watch(periodicalRepositoryProvider.future);
  return ImportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    // ADR 0014 W1: schema v4 payloads carry periodicals.
    periodicalRepo: periodicalRepo,
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

/// Where the file of ONE export lies while it is saved or shared (review
/// finding P4-M6): a private folder per export under the app's temporary
/// directory, and the one place that removes it again.
///
/// keepAlive (justified): this object remembers which folders are IN USE by
/// an export of this app session, so that a sweep never deletes a file that
/// is being saved or shared. An auto-disposed instance would forget that
/// between two reads (the same reason as `backupWorkArea`).
@Riverpod(keepAlive: true)
Future<ExportWorkArea> exportWorkArea(ExportWorkAreaRef ref) async {
  final temp = await ref.watch(appTempDirProvider.future);
  return FileExportWorkArea(tempRoot: temp.path);
}

/// One-time clean-up per app start: removes what an export left behind when
/// the app was killed while its file was being saved or shared (a plain
/// copy of the library). Triggered next to the backup's sweep, by the
/// Library screen's first build.
///
/// keepAlive (justified): "once per app session" is the whole point, as for
/// `staleBackupWorkSweep`. The result is not shown anywhere: when something
/// could not be removed, the next start (and the next export) tries again.
@Riverpod(keepAlive: true)
Future<void> staleExportWorkSweep(StaleExportWorkSweepRef ref) async {
  final workArea = await ref.watch(exportWorkAreaProvider.future);
  await workArea.sweep();
}

/// One-shot library/wishlist export use case.
@riverpod
Future<ExportLibraryUseCase> exportLibraryUseCase(
  ExportLibraryUseCaseRef ref,
) async {
  final bookRepo = await ref.watch(catalogueItemRepositoryProvider.future);
  final wishlistRepo = await ref.watch(wishlistRepositoryProvider.future);
  final periodicalRepo = await ref.watch(periodicalRepositoryProvider.future);
  return ExportLibraryUseCase(
    bookRepo: bookRepo,
    wishlistRepo: wishlistRepo,
    // ADR 0014 W1: JSON writes periodicals top-level; CSV resolves series.
    periodicalRepo: periodicalRepo,
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

/// Loads the two fonts the PDF export writes REAL text with (ADR 0033): the
/// bundled Latin face, regular and bold. Each is the first entry of its
/// list, which is ordered base-first.
///
/// Only the Latin face is handed over, on purpose. The `pdf` package places
/// glyph after glyph and cannot shape, so a font of an Indian script would
/// make the renderer believe it can write that text, and it would come out
/// wrong. Such text is drawn by the rasterizer below instead.
///
/// Behind a provider because `rootBundle` is a side effect the application
/// layer must not own (as for the footer icon above). A font that cannot be
/// loaded is NOT skipped: the error ends the export, which says "failed".
@riverpod
Future<PdfTextFonts> Function() pdfTextFontsLoader(PdfTextFontsLoaderRef ref) =>
    () async => (
      regular: [await rootBundle.load(pdfRegularFontAssets.first)],
      bold: [await rootBundle.load(pdfBoldFontAssets.first)],
    );

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
  final bookRepo = await ref.watch(catalogueItemRepositoryProvider.future);
  final periodicalRepo = await ref.watch(periodicalRepositoryProvider.future);
  // Plan J9: an overwrite renumbers every book, so the published keys are
  // marked unusable first (CatalogueKeysReset). Resolved only when an
  // overwrite really runs, never while building.
  Future<T> beforeIdsChange<T>(Future<T> Function() change) async =>
      (await ref.read(
        catalogueKeysResetProvider.future,
      )).beforeIdsChange(change);
  return MergeLibraryUseCase(
    bookRepo: bookRepo,
    periodicalRepo: periodicalRepo,
    namespace: ref.read(settingsControllerProvider.notifier),
    jsonParser: const PitakaJsonImporter(),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
    // N10-c: the plan is computed on a worker isolate.
    planner: planMergeInBackground,
    idsChangeGuard: beforeIdsChange,
  );
}
