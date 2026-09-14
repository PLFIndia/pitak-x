/// Export controller (application layer, AGENTS.md §4/§7).
///
/// Owns everything the Export screen used to do inline: resolving the PDF
/// inputs (library name, footer icon, library logo, shaped-text rasterizer),
/// minting the library ID for JSON, invoking the use case, and handing the
/// bytes to the share sheet. The page only collects the user's scope/format/
/// column choices and renders the typed `ExportUiState`.
///
/// N10-e — a long PDF render is now an honest, interruptible wait:
///  - the state is a sealed [ExportUiState] the page WATCHES: idle, running
///    (with the renderer's latest `PdfRenderProgress`) or finished (with the
///    typed `ExportRunResult`);
///  - `cancel()` flips the run's `RenderCancelToken`; the renderer stops at the
///    next row and the run ends as `ExportOutcome.cancelled` with no file
///    (decision D1-a — a partial catalogue is never produced);
///  - the run is pinned with `ref.keepAlive()` (N11 pattern, as in
///    `ImportController`) so leaving the page mid-render neither loses the
///    terminal state nor lets a second export start underneath;
///  - a second `export()` call while one is running returns the SAME future
///    (decision D4-a) — one render, one result, nothing silently dropped.
///
/// Side-effecting collaborators (asset loads, logo file read, rasterizer,
/// share sheet) arrive via DI ports so this stays testable with overrides.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
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

  /// The user cancelled the run before it finished; no file was produced.
  cancelled,
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

/// What the Export screen shows. Sealed so the page's `switch` is exhaustive
/// (a new state cannot be forgotten in the UI).
sealed class ExportUiState {
  const ExportUiState();
}

/// Nothing running; nothing to report yet.
final class ExportIdle extends ExportUiState {
  /// Creates the idle state.
  const ExportIdle();
}

/// An export is in flight. [progress] is the renderer's latest report, or
/// null before the first one (and for JSON/CSV, which do not report).
final class ExportRunning extends ExportUiState {
  /// Creates the running state.
  const ExportRunning({this.progress});

  /// Latest renderer progress; null = indeterminate.
  final PdfRenderProgress? progress;
}

/// The last run finished with [result].
final class ExportFinished extends ExportUiState {
  /// Creates the finished state.
  const ExportFinished(this.result);

  /// The typed outcome of the run.
  final ExportRunResult result;
}

/// Runs exports for the Export screen; idle until [export] is called.
@riverpod
class ExportController extends _$ExportController {
  /// The in-flight run (D4-a: a second call joins it) and its cancel token.
  Future<ExportRunResult>? _inFlight;
  RenderCancelToken? _token;
  bool _disposed = false;

  /// Rows between published progress states — a 10k-row render must not
  /// schedule 10k rebuilds. The last report is always published.
  static const int _publishEveryRows = 25;

  @override
  ExportUiState build() {
    ref.onDispose(() => _disposed = true);
    return const ExportIdle();
  }

  /// True while a run is in flight.
  bool get isRunning => _inFlight != null;

  /// Builds an export for [scope]/[format] (+[pdfColumns] for PDF) and hands
  /// it to the share sheet. [sharePositionOrigin] anchors the iPad popover.
  ///
  /// While a run is in flight, another call returns that run's future
  /// (D4-a). All failures collapse to [ExportOutcome.failed] — no raw error
  /// text leaves this method (§5).
  Future<ExportRunResult> export({
    required ExportScope scope,
    required ExportFormat format,
    List<PdfColumn>? pdfColumns,
    Rect? sharePositionOrigin,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    if (_disposed) {
      return Future.value(const ExportRunResult(ExportOutcome.failed));
    }

    final token = RenderCancelToken();
    _token = token;
    // keepAlive for the duration of the run: without it, popping the page
    // disposes this autoDispose provider mid-render and the terminal state
    // (and the cancel token) would be lost.
    final link = ref.keepAlive();
    state = const ExportRunning();

    final run =
        _run(
              scope: scope,
              format: format,
              pdfColumns: pdfColumns,
              sharePositionOrigin: sharePositionOrigin,
              token: token,
            )
            .then((result) {
              if (!_disposed) state = ExportFinished(result);
              return result;
            })
            .whenComplete(() {
              _inFlight = null;
              _token = null;
              link.close();
            });
    _inFlight = run;
    return run;
  }

  /// Asks the in-flight render to stop at the next row. No-op when idle.
  void cancel() => _token?.cancel();

  Future<ExportRunResult> _run({
    required ExportScope scope,
    required ExportFormat format,
    required List<PdfColumn>? pdfColumns,
    required Rect? sharePositionOrigin,
    required RenderCancelToken token,
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
      // (PLAN-merge.md D40). M17: a failed mint/persist aborts a JSON export
      // rather than shipping a file under a phantom identity.
      var libraryId = '';
      if (isJson) {
        final minted = await ref
            .read(settingsControllerProvider.notifier)
            .getOrCreateLibraryId();
        if (minted.isLeft()) {
          return const ExportRunResult(ExportOutcome.failed);
        }
        libraryId = minted.getOrElse((_) => '');
      }
      final footerIcon = isPdf
          ? await ref.read(pdfFooterIconLoaderProvider)()
          : null;
      final logoBytes = isPdf ? await _loadLibraryLogo() : null;
      // Shaped-image PDF text: Flutter's engine shapes complex scripts right
      // (Devanagari half-letters / matra reordering) where `drawString`
      // cannot. Provided via DI (infrastructure needs a live engine).
      final rasterizer = isPdf ? ref.read(pdfTextRasterizerProvider) : null;

      // The user may have cancelled while the inputs above were loading.
      token.throwIfCancelled();

      final result = await useCase(
        scope: effectiveScope,
        format: format,
        pdfColumns: pdfColumns,
        libraryName: libraryName,
        libraryId: libraryId,
        footerIconBytes: footerIcon,
        logoBytes: logoBytes,
        textRasterizer: rasterizer,
        onProgress: _publishProgress,
        cancelToken: token,
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
    } on PdfRenderCancelled {
      // The user's own request (D3-a): not a failure, no file.
      return const ExportRunResult(ExportOutcome.cancelled);
    } on Object {
      // Fail closed with a typed outcome; never raw error text (§5).
      return const ExportRunResult(ExportOutcome.failed);
    }
  }

  /// Publishes the renderer's progress into [state], throttled by row count
  /// so the screen rebuilds a few times a second, not once per row.
  void _publishProgress(PdfRenderProgress p) {
    if (_disposed) return;
    final isLast = p.rowsDone >= p.rowsTotal;
    if (p.rowsDone % _publishEveryRows != 0 && !isLast) return;
    state = ExportRunning(progress: p);
  }

  /// Resolves the user's library logo to bytes for the PDF header, or null
  /// when none is set / the file is missing. Reuses [CoverPaths] + the covers
  /// dir exactly like the `LibraryLogo` widget (single source of truth). A
  /// missing/unreadable logo never blocks the export.
  Future<Uint8List?> _loadLibraryLogo() async {
    // N14: the actual file read is infrastructure, injected as a port.
    final logoRef = ref
        .read(settingsControllerProvider)
        .maybeWhen(data: (s) => s.libraryLogo, orElse: () => '');
    final readLogo = await ref.read(exportLogoReaderProvider.future);
    return readLogo(logoRef);
  }
}
