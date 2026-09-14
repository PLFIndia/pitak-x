/// Progress + cancellation contract for the paginated PDF renderer (domain,
/// AGENTS.md §3.3; N10-e in `astra-review.md`).
///
/// WHY THIS EXISTS: rendering a large catalogue to a shaped-text PDF is the
/// longest single piece of UI-isolate work in the app (every text run is
/// laid out by the platform text engine, which cannot leave the UI isolate).
/// Before N10-e the export offered a spinner and no way out. These three
/// types give the caller an honest picture of the wait and a way to stop it,
/// without the renderer knowing anything about Riverpod or widgets.
///
/// All three are pure Dart so the domain-purity gate (N14) stays green and
/// any layer — use case, controller, test — can use them.
library;

/// A snapshot of how far a render has got. Values only ever grow within one
/// render (the renderer's tests pin this), so a progress bar never jumps
/// backwards.
class PdfRenderProgress {
  /// Creates a progress snapshot.
  const PdfRenderProgress({
    required this.rowsDone,
    required this.rowsTotal,
    required this.pagesDone,
    required this.cachedTiles,
  });

  /// Book rows fully drawn so far (0 before the first row).
  final int rowsDone;

  /// Total book rows in this render (fixed for the whole run).
  final int rowsTotal;

  /// Pages started so far (1 as soon as the first page exists).
  final int pagesDone;

  /// Rasterized text tiles currently held in the renderer's cache. Exposed
  /// so a test can prove the cache is BOUNDED (N10-e); the UI ignores it.
  final int cachedTiles;

  /// 0.0–1.0 fraction of rows done, or null when there are no rows to
  /// measure against (an empty library, or a non-PDF export).
  double? get fraction => rowsTotal <= 0 ? null : rowsDone / rowsTotal;

  @override
  String toString() =>
      'PdfRenderProgress(rows $rowsDone/$rowsTotal, pages $pagesDone, '
      'tiles $cachedTiles)';
}

/// Called by the renderer as it makes progress. Keep the callback cheap: it
/// runs once per row on the UI isolate.
typedef PdfRenderProgressListener = void Function(PdfRenderProgress progress);

/// A one-way switch the caller flips to stop a render. Shared by reference:
/// the owner keeps the token and calls [cancel]; the renderer only READS
/// [isCancelled] (once per row) and stops at the next row boundary by
/// throwing [PdfRenderCancelled].
///
/// Deliberately minimal (no `package:async` dependency, AGENTS.md §9): a flag
/// is all the contract needs, and a flag cannot be mis-awaited.
class RenderCancelToken {
  /// Creates an un-cancelled token.
  RenderCancelToken();

  bool _cancelled = false;

  /// True once [cancel] has been called. Never goes back to false.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;

  /// Throws [PdfRenderCancelled] if cancellation has been requested. The
  /// renderer calls this at each row boundary.
  void throwIfCancelled() {
    if (_cancelled) throw const PdfRenderCancelled();
  }
}

/// Thrown by the renderer when its [RenderCancelToken] is cancelled.
///
/// This is NOT a `Failure`: nothing went wrong — the caller asked to stop.
/// It travels as an exception so the sealed `Failure` hierarchy (and the six
/// presentation switches over it) stays untouched (N10-e decision D3-a); the
/// controller that owns the token is the one place that catches it.
class PdfRenderCancelled implements Exception {
  /// Creates the cancellation signal.
  const PdfRenderCancelled();

  @override
  String toString() => 'PdfRenderCancelled';
}
