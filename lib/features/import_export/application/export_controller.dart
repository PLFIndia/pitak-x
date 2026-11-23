/// Export controller (application layer, AGENTS.md §4/§7).
///
/// Owns everything the Export screen used to do inline: resolving the PDF
/// inputs (library name, footer icon, library logo, shaped-text rasterizer),
/// minting the library ID for JSON, invoking the use case, and sending the
/// finished file where the user said: to a place chosen in the system's
/// save window, or to the share sheet. The page only collects the user's
/// scope/format/column choices and renders the typed `ExportUiState`.
///
/// ONE FILE FOR BOTH WAYS (review finding P4-M6, decisions D167 and D172):
/// the use case makes an export as bytes. Before they go anywhere they are
/// put into a private file of this run (`ExportWorkArea`), under the name
/// the user should see. The saver copies that file; the share sheet is
/// handed the same file by its path. A `finally` gives the file back on
/// every way out. Sharing BYTES is not done any more: it made the share
/// plugin write a second plain copy that nobody removed.
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
/// the export's file, the saver, the share sheet) arrive via DI ports so
/// this stays testable with overrides.
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/export_source_filter.dart';
import 'package:pitaka/features/import_export/domain/pdf_column.dart';
import 'package:pitaka/features/import_export/domain/pdf_render_progress.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'export_controller.g.dart';

/// Where a finished export goes (review finding P4-M6, decision D166).
enum ExportDestination {
  /// It is copied to a place the user chooses in the system's save window.
  save,

  /// It is handed to the system's share sheet.
  share,
}

/// Terminal result of one export run, mapped to safe UI copy by the page.
enum ExportOutcome {
  /// The file was copied to the place the user chose, and the place said
  /// that it is stored.
  saved,

  /// The user left the save window without choosing a place (not an
  /// error; nothing was written).
  saveCancelled,

  /// The place could not take the file; the unfinished file was removed.
  notSaved,

  /// The place could not take the file, and an unfinished file may still
  /// lie there.
  saveLeftBehind,

  /// The user chose a file that already holds something. The app never
  /// replaces a file: it was left as it is (decision D176).
  saveNotEmpty,

  /// The place cannot tell whether a file is stored there, so nothing
  /// counts as saved and the file was taken back (decision D183).
  saveUnconfirmed,

  /// This device has no save window, or the app's Android side is missing.
  saveUnavailable,

  /// The file was built and handed to the share sheet successfully.
  shared,

  /// The user left the share sheet without choosing an app (not an error).
  dismissed,

  /// The platform cannot share files.
  shareUnavailable,

  /// Building the export failed (read/render error).
  failed,

  /// The user cancelled the run before it finished; no file was produced.
  cancelled,
}

/// The outcome plus the file name for the success message.
///
/// FOR SHOWING ONLY: after a save, [fileName] is what the PLACE calls the
/// file, which is foreign text (cleaned by the saver) and can be empty.
class ExportRunResult {
  /// Creates a run result.
  const ExportRunResult(this.outcome, {this.fileName = ''});

  /// What happened.
  final ExportOutcome outcome;

  /// The file's name: the suggested one when [outcome] is
  /// [ExportOutcome.shared], the one the place gave when it is
  /// [ExportOutcome.saved]. Empty for every other outcome.
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
  const ExportRunning({
    required this.destination,
    this.progress,
    this.fileMade = false,
  });

  /// Where this run sends its file: the button that was tapped.
  final ExportDestination destination;

  /// True once the export's file is made and is being saved or handed to
  /// the share sheet. Nothing can be cancelled any more then, so the page
  /// shows no Cancel and no numbers. A flag of the running state, not a
  /// state of its own (decision D167: no "a file is ready" state).
  final bool fileMade;

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

  /// Where the in-flight run sends its file, and the renderer's latest
  /// report that was published: both are needed to publish the next state.
  ExportDestination _destination = ExportDestination.share;
  PdfRenderProgress? _lastProgress;

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

  /// Builds an export for [scope]/[format] (+[pdfColumns] for PDF,
  /// [sourceFilter] for CSV/PDF) and sends it to [destination]: the
  /// system's save window, or the share sheet. [sharePositionOrigin]
  /// anchors the iPad popover of the share sheet.
  ///
  /// While a run is in flight, another call returns that run's future
  /// (D4-a). All failures collapse to [ExportOutcome.failed] — no raw error
  /// text leaves this method (§5).
  Future<ExportRunResult> export({
    required ExportDestination destination,
    required ExportScope scope,
    required ExportFormat format,
    ExportSourceFilter sourceFilter = const ExportSourceFilter.all(),
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
    _destination = destination;
    _lastProgress = null;
    state = ExportRunning(destination: destination);

    final run =
        _run(
              destination: destination,
              scope: scope,
              format: format,
              sourceFilter: sourceFilter,
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
    required ExportDestination destination,
    required ExportScope scope,
    required ExportFormat format,
    required ExportSourceFilter sourceFilter,
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
        sourceFilter: sourceFilter,
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

      // The bytes become ONE private file of this run, under the name the
      // user should see (see the library doc).
      final workArea = await ref.read(exportWorkAreaProvider.future);
      final put = await workArea.put(
        fileName: export.suggestedFileName,
        bytes: export.bytes,
      );
      final path = put.toNullable();
      if (path == null) return const ExportRunResult(ExportOutcome.failed);

      // From here on this run owns a plain copy of the library on disk.
      // `finally` gives it back on EVERY way out of this block.
      try {
        if (!_disposed) {
          state = ExportRunning(
            destination: destination,
            progress: _lastProgress,
            fileMade: true,
          );
        }
        return switch (destination) {
          ExportDestination.save => await _save(path),
          ExportDestination.share => await _share(
            path: path,
            fileName: export.suggestedFileName,
            mimeType: export.mimeType,
            sharePositionOrigin: sharePositionOrigin,
          ),
        };
      } finally {
        // The saver has copied the file by now (or has given up), and the
        // share plugin works on its own copy.
        await workArea.discard(path);
      }
    } on PdfRenderCancelled {
      // The user's own request (D3-a): not a failure, no file.
      return const ExportRunResult(ExportOutcome.cancelled);
    } on Object {
      // Fail closed with a typed outcome; never raw error text (§5).
      return const ExportRunResult(ExportOutcome.failed);
    }
  }

  /// Copies the export's file to a place the user chooses. "Saved" is said
  /// only for [DocumentSaved], which the saver gives only when every byte
  /// was written and the place said that the bytes are stored. A file that
  /// is gone, or a mistake in code, is a failed run.
  Future<ExportRunResult> _save(String path) async {
    final answer = await ref.read(documentSaverProvider).saveCopy(path: path);
    return switch (answer) {
      DocumentSaved(:final document) => ExportRunResult(
        ExportOutcome.saved,
        fileName: document.displayName,
      ),
      DocumentSaveCancelled() => const ExportRunResult(
        ExportOutcome.saveCancelled,
      ),
      DocumentSaveNotSaved() => const ExportRunResult(ExportOutcome.notSaved),
      DocumentSaveLeftBehind() => const ExportRunResult(
        ExportOutcome.saveLeftBehind,
      ),
      DocumentSaveNotEmpty() => const ExportRunResult(
        ExportOutcome.saveNotEmpty,
      ),
      DocumentSaveUnavailable() => const ExportRunResult(
        ExportOutcome.saveUnavailable,
      ),
      DocumentSaveUnconfirmed() => const ExportRunResult(
        ExportOutcome.saveUnconfirmed,
      ),
      DocumentSaveSourceGone() ||
      DocumentSaveFailed() => const ExportRunResult(ExportOutcome.failed),
    };
  }

  /// Hands the export's file to the share sheet, by its path.
  Future<ExportRunResult> _share({
    required String path,
    required String fileName,
    required String mimeType,
    required Rect? sharePositionOrigin,
  }) async {
    final outcome = await ref
        .read(fileShareServiceProvider)
        .shareFile(
          path: path,
          mimeType: mimeType,
          sharePositionOrigin: sharePositionOrigin,
        );
    return switch (outcome) {
      ShareOutcome.success => ExportRunResult(
        ExportOutcome.shared,
        fileName: fileName,
      ),
      ShareOutcome.dismissed => const ExportRunResult(ExportOutcome.dismissed),
      ShareOutcome.unavailable => const ExportRunResult(
        ExportOutcome.shareUnavailable,
      ),
    };
  }

  /// Publishes the renderer's progress into [state], throttled by row count
  /// so the screen rebuilds a few times a second, not once per row.
  void _publishProgress(PdfRenderProgress p) {
    if (_disposed) return;
    final isLast = p.rowsDone >= p.rowsTotal;
    if (p.rowsDone % _publishEveryRows != 0 && !isLast) return;
    _lastProgress = p;
    state = ExportRunning(destination: _destination, progress: p);
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
