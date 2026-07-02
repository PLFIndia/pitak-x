/// Export controller (application layer, AGENTS.md §4/§7).
///
/// Owns everything the Export screen used to do inline: resolving the PDF
/// inputs (library name, footer icon, library logo, shaped-text rasterizer),
/// minting the library ID for JSON, invoking the use case, and handing the
/// bytes to the share sheet. The page only collects the user's scope/format/
/// column choices and renders the typed [ExportOutcome].
///
/// Side-effecting collaborators (asset loads, logo file read, rasterizer,
/// share sheet) arrive via DI ports so this stays testable with overrides.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'export_controller.g.dart';

/// Terminal result of one export run, mapped to safe UI copy by the page.
enum ExportOutcome {
  /// The file was built and handed to the share sheet successfully.
  shared,

  /// The user dismissed the share sheet (not an error; show nothing).
  dismissed,

  /// The platform cannot share files.
  shareUnavailable,

  /// Building the export failed (read/render error).
  failed,
}

/// The outcome plus the file name for the success message.
class ExportRunResult {
  /// Creates a run result.
  const ExportRunResult(this.outcome, {this.fileName = ''});

  /// What happened.
  final ExportOutcome outcome;

  /// The suggested file name (set when [outcome] is [ExportOutcome.shared]).
  final String fileName;
}

/// Runs exports for the Export screen; idle until [export] is called.
@riverpod
class ExportController extends _$ExportController {
  @override
  FutureOr<ExportRunResult?> build() => null;

  /// Builds an export for [scope]/[format] (+[pdfColumns] for PDF) and hands
  /// it to the share sheet. [sharePositionOrigin] anchors the iPad popover.
  ///
  /// All failures collapse to [ExportOutcome.failed] — no raw error text
  /// leaves this method (§5).
  Future<ExportRunResult> export({
    required ExportScope scope,
    required ExportFormat format,
    List<PdfColumn>? pdfColumns,
    Rect? sharePositionOrigin,
  }) async {
    state = const AsyncLoading();
    final result = await _run(
      scope: scope,
      format: format,
      pdfColumns: pdfColumns,
      sharePositionOrigin: sharePositionOrigin,
    );
    state = AsyncData(result);
    return result;
  }

  Future<ExportRunResult> _run({
    required ExportScope scope,
    required ExportFormat format,
    required List<PdfColumn>? pdfColumns,
    required Rect? sharePositionOrigin,
  }) async {
    try {
      final useCase = await ref.read(exportLibraryUseCaseProvider.future);
      // CSV is library-only; PDF is always the library list.
      final effectiveScope = format == ExportFormat.csv
          ? ExportScope.libraryOnly
          : scope;
      final isPdf = format == ExportFormat.pdf;
      final isJson = format == ExportFormat.json;

      // The library name rides the PDF header AND the JSON merge envelope.
      final libraryName = (isPdf || isJson)
          ? ref
                .read(settingsControllerProvider)
                .maybeWhen(data: (s) => s.libraryName, orElse: () => '')
          : '';
      // Mint/read this app's library ID so every JSON export carries one
      // (PLAN-merge.md D40).
      final libraryId = isJson
          ? await ref
                .read(settingsControllerProvider.notifier)
                .getOrCreateLibraryId()
          : '';
      final footerIcon = isPdf
          ? await ref.read(pdfFooterIconLoaderProvider)()
          : null;
      final logoBytes = isPdf ? await _loadLibraryLogo() : null;
      // Shaped-image PDF text: Flutter's engine shapes complex scripts right
      // (Devanagari half-letters / matra reordering) where `drawString`
      // cannot. Provided via DI (infrastructure needs a live engine).
      final rasterizer = isPdf ? ref.read(pdfTextRasterizerProvider) : null;

      final result = await useCase(
        scope: effectiveScope,
        format: format,
        pdfColumns: pdfColumns,
        libraryName: libraryName,
        libraryId: libraryId,
        footerIconBytes: footerIcon,
        logoBytes: logoBytes,
        textRasterizer: rasterizer,
      );

      final export = result.toNullable();
      if (result.isLeft() || export == null) {
        return const ExportRunResult(ExportOutcome.failed);
      }

      final share = ref.read(fileShareServiceProvider);
      final outcome = await share.shareBytes(
        bytes: export.bytes,
        fileName: export.suggestedFileName,
        mimeType: export.mimeType,
        sharePositionOrigin: sharePositionOrigin,
      );
      return switch (outcome) {
        ShareOutcome.success => ExportRunResult(
          ExportOutcome.shared,
          fileName: export.suggestedFileName,
        ),
        ShareOutcome.dismissed => const ExportRunResult(
          ExportOutcome.dismissed,
        ),
        ShareOutcome.unavailable => const ExportRunResult(
          ExportOutcome.shareUnavailable,
        ),
      };
    } on Object {
      // Fail closed with a typed outcome; never raw error text (§5).
      return const ExportRunResult(ExportOutcome.failed);
    }
  }

  /// Resolves the user's library logo to bytes for the PDF header, or null
  /// when none is set / the file is missing. Reuses [CoverPaths] + the covers
  /// dir exactly like the `LibraryLogo` widget (single source of truth). A
  /// missing/unreadable logo never blocks the export.
  Future<Uint8List?> _loadLibraryLogo() async {
    try {
      final logoRef = ref
          .read(settingsControllerProvider)
          .maybeWhen(data: (s) => s.libraryLogo, orElse: () => '');
      final leaf = CoverPaths.leafOf(logoRef);
      if (leaf == null) return null;
      final coversDir = await ref.read(coversDirProvider.future);
      final file = File(p.join(coversDir, leaf));
      if (!file.existsSync()) return null;
      return file.readAsBytes();
    } on Object {
      return null;
    }
  }
}
