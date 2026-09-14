# PLAN.md — Session 31 — N10-e: PDF export tile bound + progress + cancel

Roadmap: `fix-schedule.md` §1 (NEXT = N10-e, the LAST N10 sub-item). Finding:
`astra-review.md` N10 ("Large-library operations run unbounded work on the UI
isolate" — "PDF pre-rasterizes and retains every text run", evidence
`pdf_library_renderer.dart:308-329` at review time). After this slice N10
closes and Phase 5 is done.

## Understanding

Verified this session against the CURRENT code (the file moved to
`infrastructure/` in N14; review line numbers stale, pattern live):

- `lib/features/import_export/infrastructure/pdf_library_renderer.dart:110-131`
  — `tileCache = <String, RasterizedText?>{}` keyed by `weight|size|colour|text`.
  `:302-323` — BEFORE the first page is laid out, a loop over EVERY book × EVERY
  column × EVERY wrapped line calls `cacheTile` → `textRasterizer.raster(...)`
  (a `dart:ui` paragraph layout + `PictureRecorder` + `toImage` + PNG encode,
  each `await`ed on the UI isolate). Every PNG tile is retained in
  `tileCache` for the whole render. Then `:329-330` `tileImages = <String,
  PdfImage?>{}` decodes each PNG into a `PdfImage` XObject the first time it
  is drawn — decoded RGB + a separate alpha SMask object — and those live on
  `PdfDocument.objects` until `save()`.
- Probe (this session, deleted): six typical cells at 12 pt → PNG 15.7 KB
  total, decoded XObject payload **343 KB** (≈22× the PNG; 823×48 px for a
  49-char title = 158 KB alone). A 10,000-row export with the default 5
  columns is ~60,000 tiles: roughly **1.4 GB** of decoded image data retained
  in `PdfDocument.objects` on the UI isolate before `save()` even starts, plus
  the PNG cache. That is the "retains every text run" the review means.
- Dedup only helps when cells repeat (years, quantities); titles/authors/ISBNs
  are unique per row, so the cache is O(rows × columns) in practice.
- The pre-pass has NO yield to the UI beyond each `await raster()`, no
  progress, no cancel. `ExportController.export` (`export_controller.dart:64`)
  awaits the whole thing; `export_page.dart:36-62` shows a spinner on the
  button and nothing else. There is no way to stop an export once started
  except killing the app.
- `pdf` 3.12.0 `PdfDocument.save()` (`document.dart:279-289`) runs in
  `Isolate.run` in production and inline under `FLUTTER_TEST` — the final
  serialisation is already off the UI isolate; the retention problem is
  upstream of it. `PdfImage.file` (`obj/image.dart:181-199`) decodes PNGs via
  `image.decodeImage`; `PdfImage()` (`:53-98`) builds the RGB buffer + an
  `_alpha` SMask object — two `PdfObjectStream`s per tile, both retained in
  `objects` until save. There is no API to drop an XObject after use, and
  every page's content stream references its images by object number, so the
  DECODED image bound is inherent to embedding raster text with this package
  — what we CAN bound is the PNG cache and the per-row engine work, and we can
  make the user's wait honest and interruptible.
- Rasteriser must stay on the UI isolate (S26 decision, confirmed:
  `UiPdfTextRasterizer` uses `dart:ui` `ParagraphBuilder`/`PictureRecorder`
  which need the engine).
- Callers of `LibraryPdfRenderer.render`: ONE production
  (`export_library_use_case.dart:177`); tests: `pdf_library_renderer_test.dart`
  (5), `pdf_text_rasterizer_test.dart` (1), `export_roundtrip_test.dart` (via
  the use case). `ExportController` is the only `render`-transitive controller;
  `export_page.dart` is its only watcher-by-`.notifier` (no `ref.watch` of its
  state anywhere — S20 obs. 2: the state writes are effectively dead today).

## Privacy & threat notes

- No new data leaves the device; no new logging. Progress values are counts
  (rows done / total, pages) — never cell text.
- Cancel must not leave a half-written file in the share sheet: the bytes are
  only handed to `FileShareService` after a COMPLETE render (unchanged), so a
  cancelled render produces no file at all (D1 below asks the user to confirm
  this is the wanted semantics vs "share what rendered so far").
- Cancel token and progress callback are plain domain types (no `dart:ui`,
  no Riverpod) so the N14 purity gate stays green; the controller (application)
  owns the token; the page only calls `cancel()`.
- Fail-closed: a cancelled or failed render → typed terminal outcome; the
  catch-all in `ExportController._run` stays.

## Investigation notes (from source, not memory)

- `pdf` 3.12.0 pub-cache: `PdfDocument.save({enableEventLoopBalancing})`
  `document.dart:279`; `pdfCompute` `io/vm.dart:27` = `Isolate.run` unless
  `FLUTTER_TEST`; `PdfImage.file` `obj/image.dart:181`; `PdfObjectStream.buf`
  `obj/object_stream.dart:37` (raw retained payload, `PdfStream` grows in
  64 KiB steps `format/stream.dart:20-34`); `PdfDictStream.output`
  `format/dict_stream.dart:52-85` deflates at SAVE time (so retained memory
  before save is the UNCOMPRESSED RGB/alpha).
- `UiPdfTextRasterizer.raster` `pdf_text_rasterizer.dart:117-165`: one
  paragraph layout + `toImage` + PNG encode per call; `scale = 3.0` (so a 12 pt
  run is 48 px tall — matches the probe).
- Existing patterns to reuse: `ImportController` `_running`/`_disposed`/
  `keepAlive` (`import_controller.dart:23-93`, N11); `MergeController` sealed
  `MergeUiState` (`merge_controller.dart:35-238`) as the model for a sealed
  export state; `ExportOutcome` enum + `ExportRunResult` already typed.
- No `CancellationToken` type exists in `lib/` (grep: only `Timer.cancel` /
  `StreamSubscription.cancel`). `package:async` is only a transitive dep
  (`pubspec.lock:44`) — NOT adding it (AGENTS.md §9); a 15-line domain token
  is the whole need.
- N14 gate: domain may import only `dart:async/collection/convert/core/
  developer/math/typed_data` + `fpdart/crypto/archive`
  (`domain_purity_test.dart:41-63`); application may not import
  `dart:isolate`/`dart:io`/`path`/`http`/`drift` (S28). A domain
  `RenderCancelToken` with `dart:async` only is fine.

## Proposed approach

Three layers, smallest diff that fixes the foundation rather than trimming
the symptom:

### 1. Renderer: rasterise per ROW, bounded cache, yield, progress, cancel

`PdfLibraryRenderer.render` gains three optional parameters on the port
(`LibraryPdfRenderer.render`):

- `PdfRenderProgress? onProgress` — `void Function(PdfRenderProgress p)`
  where `PdfRenderProgress{rowsDone, rowsTotal, pagesDone}` (domain VO).
  Called once before the loop, once per row (cheap; the page throttles
  rebuilds), once at the end. Monotonic by construction.
- `RenderCancelToken? cancelToken` — checked once per row; when
  `isCancelled`, the renderer throws `PdfRenderCancelled` (domain exception
  type) BEFORE touching the next row. The use case maps it to
  `Left(ExportCancelledFailure)`? — NO: adding a `Failure` subtype forces
  every exhaustive `switch (failure)` in 6 presentation files to change
  (grep'd: all six have a `_` arm, so it would compile, but the wording would
  be wrong for them). Instead the use case returns a typed
  `Either<Failure, ExportResult>` as today and the CONTROLLER catches
  `PdfRenderCancelled` (it already owns the token) → `ExportOutcome.cancelled`.
  See D3.
- `int maxTileCacheEntries = 256` (named constant `PdfLibraryRenderer.
  defaultTileCacheEntries`) — the PNG tile cache becomes a small LRU
  (`LinkedHashMap` re-insertion, no new dependency). WHY an LRU and not a
  per-page flush: the header/footer/column-header tiles repeat on every page
  and short cells (years, quantities) repeat across rows — an LRU keeps the
  hot ones and evicts the one-off titles. WHY 256: default 5 columns × ~1.5
  lines × ~30 rows/page ≈ 225 tiles per page, so one page's working set fits
  and a 10k-row export holds ≤ 256 PNGs instead of 60k.
- The all-up-front pre-pass (`:302-323`) is DELETED. Each row's tiles are
  rasterised right before that row is drawn (the pagination loop is already
  the natural place — it computes `cellLines` per row). `drawText` becomes
  async-free: the tiles a row needs are awaited into the cache first, then
  the synchronous draw calls run.
- One `await Future<void>.delayed(Duration.zero)` per row is NOT added — each
  row already awaits ≥ 1 rasteriser call, which yields to the event loop.
  The regression test proves it (a 1 ms `Timer` fires mid-render).
- `PdfImage` XObjects: we cannot drop them (see Understanding). The
  `tileImages` map is replaced by an LRU of the SAME size so we at least stop
  holding the Dart-side `PdfImage` handles for one-off tiles (the
  `PdfDocument.objects` set still holds them — documented in the class doc as
  the residual bound and in §Out-of-scope as the reason a raster-text PDF of
  100k rows is not a supported target; the pre-existing page count is the
  real limiter there).

### 2. Use case: pass-through

`ExportLibraryUseCase.call` gains `onProgress` + `cancelToken` and forwards
them to `render`. Nothing else changes (JSON/CSV ignore them).

### 3. Controller + page: typed state, cancel, progress

`ExportController` (application):
- New sealed `ExportUiState`: `ExportIdle`, `ExportRunning{progress}`,
  `ExportFinished{ExportRunResult}` — replaces `FutureOr<ExportRunResult?>`
  so the page can `ref.watch` progress. `build()` → `ExportIdle`.
- `export(...)` keeps its return value (the page's existing `await` still
  works) and ADDITIONALLY publishes `ExportRunning` updates from
  `onProgress` (throttled to ≤ 10 Hz by row count, so a 10k-row render does
  not schedule 10k rebuilds).
- `cancel()` — sets the token; only meaningful while running.
- `_running`/`_disposed` + `ref.keepAlive()` link during the run (N11
  pattern) so leaving the page does not lose the terminal state or allow a
  second concurrent export; a second `export()` while running is refused
  with the CURRENT state (no-op return `ExportRunResult(ExportOutcome.busy)`?
  — no new enum value needed: refused calls return `failed`? — see D4).
- `ExportOutcome.cancelled` added. `ExportRunResult` unchanged otherwise.

`ExportPage` (presentation):
- Watches `exportControllerProvider`; while `ExportRunning`, shows a
  `LinearProgressIndicator(value: rowsDone / rowsTotal)` (indeterminate when
  `rowsTotal == 0`), a "Rendering page P · R of N books" line, and a
  **Cancel** `OutlinedButton` that calls `cancel()`. The export button stays
  disabled while running.
- `ExportOutcome.cancelled` → status "Export cancelled." (safe copy).
- Progress UI is PDF-only in practice (JSON/CSV never report progress; the
  indicator is indeterminate for them, as today's spinner is).

### OSS references (verified in pub-cache / SDK, not memory)

- `pdf` 3.12.0 `PdfDocument.save` already uses `Isolate.run` — no change.
- LRU via `LinkedHashMap` remove-and-reinsert: the standard Dart idiom
  (also what `package:quiver`'s `LruMap` does internally — not adding quiver).
- Cancel token: modelled on `package:async`'s `CancelableOperation` idea in
  its minimal form (`isCancelled` flag + `cancel()`), no dependency.
- Controller lifecycle: in-repo `ImportController` (N11).

## Decision points (ask ONE at a time, before coding)

- **D1 — Cancel semantics.** (a) Cancel discards everything: no file is
  produced, status "Export cancelled." (simplest, no half-catalogue PDF in
  the wild). (b) Cancel keeps the pages rendered so far and shares a
  partial PDF marked "(partial)". Proposed: **(a)** — a partial catalogue
  can be mistaken for a complete one; the user can narrow columns and retry.
- **D2 — Where progress surfaces.** (a) Export page only (button disabled +
  progress bar + Cancel + row/page counter). (b) Also a persistent
  notification / drawer badge. Proposed: **(a)** — the export is user-driven
  and the page is where they wait.
- **D3 — How "cancelled" travels.** (a) The renderer throws a domain
  `PdfRenderCancelled`; the use case lets it propagate (it is NOT an expected
  Failure of the export contract — it is the caller's own request); the
  controller that owns the token catches it → `ExportOutcome.cancelled`.
  (b) New `Failure` subtype `CancelledFailure` in `core/error/`. Proposed:
  **(a)** — keeps the sealed `Failure` hierarchy stable (six presentation
  switches untouched) and the cancellation stays with its owner.
- **D4 — Second `export()` while one is running.** (a) Refused: returns the
  in-flight run's future (callers await the same result). (b) Refused with
  `ExportOutcome.failed`. Proposed: **(a)** — matches `ImportController`
  (silent refusal) but still gives the page a result to await.
- **D5 — Tile cache bound.** Proposed **256 PNG tiles** (≈ one page's working
  set + headers). Alternative: 512. Not a user-visible knob.
- **D6 — Execution mode.** End-to-end, or pause at each decision point?

## Steps

- [x] 0. Baseline gates: analyzer 0, format 412/0, Flutter **1634 passed**
      EXIT=0, cargo 32 passed / 2 ignored. Note: S30 recorded 1628 from a
      pre-final-edit run; CI run `34770918770` on `e19528f` reports **1634** —
      the repo's `test/`+`lib/` are byte-identical to `e19528f`, so 1634 IS the
      true S30-end count. Recorded in the schedule.
- [x] 1. D1–D6 asked one at a time → **a, a, a, a, b (512), a (end-to-end)**.
- [x] 2. Domain `pdf_render_progress.dart` (`PdfRenderProgress` VO with
      `cachedTiles` as the bound's test seam, `RenderCancelToken`,
      `PdfRenderCancelled`); port gains `onProgress`/`cancelToken`/
      `maxCachedTiles`.
- [x] 3. Regression tests RED first (renderer group, 8 tests) against a
      HEAD-shaped graft (HEAD renderer + the new params + HEAD-shaped progress
      reporting, in `test/_tmp_red/`, removed): **bound** `Expected ≤ 64 /
      Actual 8030` (peak cache 8030); **per-row order** `Expected ≥ 611 /
      Actual 610` (the last row's ISBN was rasterised BEFORE row 1 was
      reported); **cancel boundary** `Expected: not contains
      '9780000000011' / Actual: [...]` (HEAD had already rasterised every row).
      Compile-red on HEAD proper: every new param. Controller (6) and page (3)
      tests compile-red (`ExportUiState`, `cancel()`, `isRunning`,
      `ExportOutcome.cancelled`, `export-cancel` key).
- [x] 4. Renderer rewrite: pre-pass deleted; `_TileSource` (pinned chrome +
      LRU row cache, PNG bytes dropped after embed, `_Tile` holds the
      `PdfImage` handle + metrics); per-row rasterise → draw; `report()` per
      row; `throwIfCancelled()` at entry + every row; explicit yield every 20
      rows in all modes.
- [x] 5. Use case pass-through; `ExportController` sealed `ExportUiState`
      (`ExportIdle`/`ExportRunning{progress}`/`ExportFinished{result}`),
      `cancel()`, `isRunning`, `_inFlight` de-dup (D4-a), keep-alive link,
      `_disposed` guard, throttled `_publishProgress` (every 25 rows + last),
      `on PdfRenderCancelled` → `ExportOutcome.cancelled`; `ExportPage`
      watches the state (`_ExportProgress`: determinate `LinearProgressIndicator`
      keyed `export-progress`, counter label, `OutlinedButton` keyed
      `export-cancel`), `_export` is fire-and-forget (no post-await `setState`).
- [x] 6. `build_runner` LAST → `export_controller.g.dart` hash +
      `AutoDisposeNotifierProvider<ExportController, ExportUiState>`; re-run
      after `dart format` → no further diff; `.fvmrc`/`.gitignore` untouched.
- [x] 7. Gates: analyze **0**; format **413 / 0 changed**; Flutter
      `--coverage` **1651 passed / 0 failed** (EXIT=0, 0 `[E]`,
      `/tmp/pitak-s31-flutter-final.txt`); cargo **32 passed** (Rust untouched,
      baseline stands); `git diff --check` clean. Coverage **73.37%** (+0.47);
      `pdf_library_renderer.dart` 153/159, `export_controller.dart` 65/67,
      `export_page.dart` 86/92, `pdf_render_progress.dart` 8/13 (`toString`
      + `fraction` null branch uncovered), `export_library_use_case.dart` 64/80
      (pre-existing misses). Lib-diff privacy scan: no print/log/http/Uri/
      Platform/io/isolate added; progress values are counts only.
- [x] 8. `fix-schedule.md` §1/§1.1/§1.2/§3/§5 updated; commit approved ("go
      ahead") → **`13511b6`** perf(import_export) N10-e, 11 paths staged
      explicitly (forbidden-list, `--check`, secret scan clean; pre-commit
      hook: "generated code is current"); push `5223a79..13511b6 main ->
      main` on `PLFIndia/pitak-x`, no force; HEAD = `origin/main` verified
      after `git fetch`. Housekeeping: README test count 1634 → 1651;
      `appDetails.md` §3 export map, §5 count, §9 D1–D5 decision, §10 two
      gotchas, §11 N10 CLOSED + two unscheduled leftovers.

## Result

**N10-e committed `13511b6` + pushed; N10 CLOSED; Phase 5 done.** CI result in `fix-schedule.md` S31 addendum.

What changed, in plain English: exporting a PDF used to rasterise every text
run of every book before drawing anything, keep all of them in memory until
the end, and give the user a spinner with no way out. Now each row is
rasterised right before it is drawn, only the page chrome and up to 512 row
tiles are held at once, the Export screen shows a real progress bar
("Rendering page P · R of N books") with a Cancel button, and Cancel stops
at the next row and produces no file. Leaving the screen mid-run no longer
loses the run (controller keep-alive); a second tap joins the run in flight.

Residual bound (documented in the renderer's library doc + §Out-of-scope):
the `pdf` package keeps every embedded image XObject on `PdfDocument.objects`
until `save()`, so decoded bitmaps still scale with pages × tiles-per-page for
a shaped-text PDF. Our cache bounds the PNG side and the Dart handles; the
XObject side is inherent to raster text with `pdf` 3.x.

Red evidence (HEAD-shaped graft): peak cache **8030** vs bound 64; last row
rasterised before row 1 reported; cancel after row 10 had already touched
row 500. Fixed: peak ≤ bound on 2000 unique rows; per-row order; cancel
stops ≤ 1 row past the request; 1 ms timer fires well before a 300-row render
ends; progress monotonic 0 → N; Latin-only mode reports progress with 0
tiles.

Tests: +17 (renderer 8, controller 6, page 3). Full suite 1651 / 0.

### Commit paths (10 + PLAN.md)

- `lib/features/import_export/domain/pdf_render_progress.dart` (new)
- `lib/features/import_export/domain/pdf_render_port.dart`
- `lib/features/import_export/infrastructure/pdf_library_renderer.dart`
- `lib/features/import_export/application/export_library_use_case.dart`
- `lib/features/import_export/application/export_controller.dart`
- `lib/features/import_export/application/export_controller.g.dart`
- `lib/features/import_export/presentation/pages/export_page.dart`
- `test/features/import_export/pdf_library_renderer_test.dart`
- `test/features/import_export/export_controller_test.dart`
- `test/features/import_export/export_page_share_test.dart`
- `PLAN.md`

## Out-of-scope observations (recorded, not fixed)

- `PdfDocument.objects` retains every decoded tile XObject until `save()`
  regardless of our cache — inherent to raster-text PDFs with `pdf` 3.x. The
  honest bound for a shaped-text PDF is therefore pages × tiles-per-page of
  DECODED bitmaps; a JPEG tile (`PdfImage.jpeg` stores the compressed bytes
  verbatim, `obj/image.dart:100-141`) would cut retention ~20× but loses the
  alpha channel (text on white → acceptable?) — a follow-up decision, not
  N10-e.
- `ExportController` state was never watched (S20 obs. 2) — this session
  makes it load-bearing.
- `export_page.dart` had one widget test (CSV share) — the PDF path is now
  covered at the page level (3 tests), but the column-picker path still only
  by the default selection.
- `PdfRenderProgress.toString` and the `fraction == null` branch are
  uncovered (5 lines) — trivial, left.
- The `ExportRunning` state for JSON/CSV never carries progress (those
  formats do not report) — the bar is indeterminate, matching the old
  spinner; a row-count for CSV would be a small follow-up.
- Widget tests of the Export page need a phone-tall viewport
  (`tester.view.physicalSize = 1080×2400`) because the PDF column picker
  pushes the button below the default 800×600 test window, where a
  `ListView` never mounts it — recorded as a gotcha for `appDetails.md`.
- Pre-existing: `export_library_use_case.dart` 64/80 (CSV quoting branches).
