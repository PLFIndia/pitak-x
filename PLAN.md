# Task: Quick-win (logo→PDF header) + Library Merge port + Pitak launcher icon

## Understanding (user's words, restated)
Track B from the handoff:
1. **Quick win** — wire `settings.libraryLogo` into the PDF header (renderer
   already accepts `logoBytes`; only the export page needs to resolve + pass it).
2. **Merge** — port Kotlin's multi-maintainer "same library catalogue" merge
   (`LibraryMergeEngine` + `MergeLibraryUseCase`, PLAN-merge.md). Suggest a better
   architecture if warranted.
3. **Icon** — replace the Flutter placeholder launcher icon with Pitak's, taken
   from the fdroid app's adaptive-icon source.

## Investigation notes (verified)
- ALREADY PORTED: Drift `books` has `book_uid`, `removed`, `removed_at`,
  `added_by` (tables.dart). Repo has `markRemoved`/`restoreRemoved`/`findByIsbn`/
  `getAll`/`insert`/`insertAll`/`update`/`delete`. Soft-delete UI lives in
  `book_row.dart` (badge+dim) + `book_detail_page.dart` (Remove/Restore). Publish
  strips removed. Exporter emits per-book `addedBy`; schemaVersion = 3.
- MISSING for merge (vs Kotlin):
  - `LibraryId` pure validator (16–64 lowercase hex) — Kotlin
    `domain/model/LibraryId.kt`.
  - `libraryId` pref (auto-gen 32-hex, getOrCreate) — Flutter settings only has
    `libraryName`+`maintainerName`.
  - Envelope `libraryId`/`libraryName` in exporter + importer (currently absent).
  - Pure `LibraryMergeEngine.plan` (domain) — Kotlin `domain/merge/`.
  - `MergeLibraryUseCase` (application) — Kotlin `domain/usecase/`.
  - A Merge screen + Settings "Community library" entry.
- QUICK WIN: `ExportLibraryUseCase.call` forwards to `_pdf.render(logoBytes:)`
  which already draws a header logo. Export page resolves the cover the same way
  `LibraryLogo` does (CoverPaths.leafOf + coversDir).
- ICON: `assets/branding/app_icon.png`, `assets/pdf/app_icon.png`, and every
  `android/app/src/main/res/mipmap-*/ic_launcher.png` are **byte-identical to the
  Flutter default placeholder** (md5 57838d52…). Source art:
  fdroid `res/drawable/ic_launcher_foreground.xml` (book mark, viewport 108) on
  `pitaka_saffron_400 = #E25822`. ImageMagick available to rasterize.

## Privacy & threat notes (§2a)
- Merge transport is MANUAL FILE EXCHANGE only (the existing JSON export). NO new
  network surface, no server, no P2P — §1.1-clean. Vault/wishlist NOT merged.
- `libraryId` is a random opaque namespace token, not PII. `addedBy` is
  self-asserted (coordination, not security) and is already stripped at publish.
- Library-ID adoption (Join/Overwrite) funnels through `LibraryId.normalizeOrNull`
  so a hand-crafted/corrupt export can never inject a malformed ID. Overwrite is
  destructive → guarded behind explicit confirm; Join is the non-destructive
  default (D39: never make "lose all books" a one-tap mistake).
- Logo bytes for the PDF stay on-device (read from app docs covers/).

## Proposed approach (rooted in Kotlin design + our conventions)
- **Engine stays pure** (domain, no Flutter/IO) — faithful port of
  `LibraryMergeEngine`: identity = bookUid → ISBN → no-ISBN fuzzy (Jaccard token
  set, `\p{L}\p{M}\p{Nd}` to keep Indic matras); add-only union; conflicts +
  possibleDuplicates surfaced, never silently overwritten.
- **Architecture improvement over a literal port (idiomatic adaptation):** the
  use case returns `Either<Failure, MergeOutcome>` (repo convention §5) instead of
  throwing; `MergeOutcome` is a sealed class (`Merged` / `DiffersDecision` /
  `Failed`) mirroring Kotlin's sealed `Outcome`. Engine remains a pure free
  function. This matches both AGENTS files (fpdart Either, sealed failures).
- **Library ID** as a settings field with a `getOrCreateLibraryId()` that lazily
  mints 32-char hex via `Random.secure()` (CSPRNG, §6.4) and persists it.
- **UI v1 matches Kotlin's own shipped scope:** Merge-from-file screen + a
  Join/Overwrite decision when IDs differ + surfaced COUNTS for conflicts /
  possible-duplicates. Per-row conflict-review UI and QR pairing were DEFERRED in
  Kotlin too — see Decision points.

## Decision points (RESOLVED by user)
- [x] D1 (QR pairing): BUILD IT. Done — full show/scan pairing (S9 below).
- [x] D2 (conflict-review grain): DEFER (no significant value yet). Counts-only
      stays; `applyResolution` remains implemented + unit-tested for a future
      per-row screen. Recorded in Out-of-scope.
- [x] D3 (icon spine colour): SWITCH TO GRAY. Done — spine is now #808080 on
      saffron #E25822, regenerated across all densities + branding/pdf icons.

## Steps
- [x] S0 Quick win: export page resolves libraryLogo→bytes; use case `call` gains
      `logoBytes`; forward to renderer. + test.
- [x] S1 Icon: rasterized Pitak art (saffron #E25822 + open-book mark, paths from
      the fdroid vector) to all 5 mipmap densities + branding/pdf app_icon.png
      (the latter two were byte-identical to the Flutter placeholder, so this also
      fixes splash/drawer/PDF branding). Verified corner pixel = #E25822 each.
- [x] S2 LibraryId pure validator + tests (port).
- [x] S3 settings: libraryId field + getOrCreateLibraryId (Random.secure, 32-hex)
      + setLibraryId, repo/controller wiring + tests.
- [x] S4 envelope: exporter emits libraryId/libraryName (blank omitted); importer
      `parseEnvelope` reads them tolerantly. Round-trip + omit tests.
- [x] S5 pure LibraryMergeEngine (planMerge) + 17-case test port (all green).
- [x] S6 MergeLibraryUseCase (Either<Failure,MergeOutcome>, sealed outcomes) +
      9 tests. Caught + fixed two real bugs: copyWith-can't-null identity
      collision in keepBoth (now builds a fresh-identity copy), and a
      concurrent-modification in applyOverwrite (now snapshots ids first).
- [x] S7 UI: MergePage (pick file → ID gate → counts, or Join/Overwrite decision
      with Overwrite behind a confirm) + Settings → Data → "Merge from a file".
      Provider `mergeLibraryUseCaseProvider` wired. + widget smoke test.
- [x] S8 analyze 0 · format clean.
- [x] S9 QR pairing (D1): pure `LibraryQrPayload` (`pitaka-lib:<id>` — CROSS-APP
      contract kept identical to Kotlin so Flutter↔Kotlin pairing works) + tests;
      `QrView` CustomPainter widget over the `qr` pkg (promoted transitive→direct,
      version unchanged 3.0.2, no new download); `ScanLibraryQrPage` (reuses
      mobile_scanner, QR format, validates via LibraryQrPayload.parse, no new dep
      or permission — CAMERA already declared); settings repo/controller gain
      `regenerateLibraryId`; Settings → Data "Community library" section: Show
      library QR / Scan a library QR (adopt) / Start a new library (guarded).
- [x] S8' final gate: analyze 0 · format clean · 396 tests (was 346).

## Out-of-scope observations
- Wishlist merge (same machinery, ISBN-keyed) — Kotlin parked it; we keep books-only.
- Automatic transport (shared repo / P2P) — future; the engine is transport-agnostic.
- Per-row conflict-review UI (D2) — deferred (counts-only ships; applyResolution
  is built + unit-tested, just no per-row screen). Kotlin deferred it too.
- QR pairing — DONE this round (D1 = build it).

## Bugfix (on-device: export "nothing happens")
ROOT CAUSE: `file_selector` has NO save dialog on Android (open-only) — its
`getSaveLocation` throws `UnimplementedError`, swallowed by a catch-less
`try/finally`, so every Export (JSON/CSV/PDF) AND Create Backup silently did
nothing on the phone. FIX: added `share_plus` (matches the Kotlin app's
ACTION_SEND export + the merge "pass a file" workflow; Android share sheet
includes "Save to Files"). New `core/platform/file_share.dart` seam
(FileShareService + SharePlusFileShareService) wired via DI
(`fileShareServiceProvider`), used by both the export page and the backup page;
both now surface failures instead of swallowing them. Tests: a fake
FileShareService proves the export page hands bytes to the sheet (the exact
regression). 397 tests, analyze 0, format clean. Rebuilt + reinstalled on device.

## Bugfix 2 (on-device: Devanagari half-letters render as full letter + halant)
ROOT CAUSE: dart_pdf's `PdfGraphics.drawString` maps codepoints to glyphs 1:1
with NO complex-script shaping (it ships shaping for Arabic only). Indic scripts
need GSUB shaping (conjuncts / half-forms / matra reorder) — e.g. बच्चे. The
Kotlin app sidesteps this by drawing on an Android `Canvas`, which shapes via the
OS HarfBuzz. CONFIRMED by reading Kotlin `PdfLibraryRenderer.kt` (uses
`android.graphics.pdf.PdfDocument` + `Canvas.drawText`, plain `Paint`, NO bundled
fonts — the OS shapes).
DECISION (user = option A): let Flutter's engine (HarfBuzz) shape the text, then
embed the result as images in the existing PDF. Tradeoff accepted: PDF text is
raster, not selectable. Per-cell tiles (user = B), supersampled 3× for print.
IMPLEMENTATION:
 - NEW `infrastructure/pdf_text_rasterizer.dart`: `UiPdfTextRasterizer` registers
   the bundled Noto TTFs at runtime via `FontLoader` (one fallback family per
   weight) and shapes each run with `dart:ui` `ParagraphBuilder` →
   `Picture.toImage` → PNG + logical width/height/baseline.
 - `PdfLibraryRenderer.render` gained an optional `textRasterizer`. When present,
   a pre-pass rasterizes every run into a tile cache (keyed by text+size+bold+
   colour); `drawText` embeds the tile aligned to the baseline via `drawImage`
   (reusing the existing image path). When null, the original `drawString` path
   is kept (Latin-only callers / pure tests). Pagination/columns/weights/wrap all
   unchanged.
 - Export use case + page pass a `UiPdfTextRasterizer` built from the existing
   `_kRegularFonts`/`_kBoldFonts` asset lists; the old per-string TTF byte
   bundles are no longer sent on the PDF path (the rasterizer owns fonts now).
 - NOTE: the "Helvetica has no Unicode support" log line still appears (twice) —
   it's dart_pdf boilerplate emitted on page/graphics creation regardless of our
   text (verified: fires even for an all-Latin shaped render). Harmless; all
   visible text is now shaped images.
TESTS: pdf_text_rasterizer_test (Devanagari conjunct → PNG tile; empty → null;
full Hindi render → valid %PDF). Existing renderer/export tests still green
(drawString fallback intact). 400 tests, analyze 0, format clean. APK built
(101.8MB); install pending phone reconnect.

## Result
DONE (host-tested; on-device pending). Track B shipped:
1. **Quick win** — the user's library logo now renders in the PDF export header
   (export page resolves covers/<uuid>.jpg → bytes via CoverPaths, passes to the
   renderer which already supported logoBytes).
2. **Merge** — full multi-maintainer catalogue merge ported faithfully from
   Kotlin: pure `LibraryMergeEngine` (uid→ISBN→fuzzy identity, add-only union,
   conflict/dup surfacing), `LibraryId` validator, `libraryId` pref (CSPRNG
   auto-mint), JSON envelope libraryId/libraryName, `MergeLibraryUseCase` (ID
   gate → Merged / DiffersDecision → Join / Overwrite / applyResolution), and a
   Merge screen reachable from Settings → Data. Architecture improvement over the
   literal port: Either<Failure,MergeOutcome> instead of throwing (AGENTS §5).
3. **Icon** — Flutter placeholder replaced with the Pitak brand mark everywhere
   (launcher mipmaps + in-app branding/pdf icons).
All schema/soft-delete/publish-strip/addedBy groundwork was ALREADY in place from
prior sessions — only the merge top half (ID + engine + use case + UI) was new.

NOT yet user-confirmed on-device: launcher icon appearance, logo-in-PDF render,
and an end-to-end merge with two real exported files. See HANDOFF §6.
