# PLAN.md — Session 26 — N10: large-library work on the UI isolate (sub-item breakdown + first slice)

Roadmap: `fix-schedule.md` §1 (NEXT). Finding: `astra-review.md` N10
("Large-library operations run unbounded work on the UI isolate"). This is the
LAST open review item and is explicitly multi-session: this plan breaks it
into sub-items (N10-a … N10-e), proposes an order, and scopes the FIRST slice.

## Understanding

The review names five sites where a 100,000-row catalogue (the accepted import
cap, `import_limits.dart:48`) would make the UI isolate do unbounded work:

1. **Whole-catalogue reads.** `LibraryController._load` → `repo.query(...)` /
   `repo.search(...)` return every row; `LibraryPage` renders them with
   `GridView.builder`/`ListView.separated` (lazy WIDGETS, but the full
   `List<Book>` is materialised and mapped from Drift rows on every rebuild).
2. **Fuzzy re-tokenisation.** `planMerge` → `_bestFuzzyMatch` calls
   `tokenSet(c)` for every local no-ISBN candidate, for every incoming no-ISBN
   book: O(I·L) regex+lowercase+split. Tokens for the local pool never change
   within one plan.
3. **Image work.** `ImageDownscaler.downscaleJpeg` decodes, resizes and
   JPEG-encodes synchronously on the calling isolate (5 call sites). The
   `maxSourceDimension` guard bounds ONE frame; `image` 4.8.0
   `GifDecoder.decode` (and the PNG/WebP animated paths) decode EVERY frame
   when `frame == null` — a 8000×8000 GIF with 500 frames passes the guard.
4. **Backup ZIP.** `BackupArchiveWriter.build` is fully synchronous:
   `readAsBytesSync` for both DBs, the vault DB and every cover, then
   `ZipEncoder().encode` — all on the UI isolate, every cover buffered.
5. **PDF pre-rasterisation.** `PdfLibraryRenderer.render` awaits
   `textRasterizer.raster` for every distinct text run and holds every tile in
   `tileCache` for the whole render. The awaits yield, but the rasteriser is
   Flutter-engine-bound (cannot leave the UI isolate) and the cache is
   unbounded.

Plus the review's closing asks: cancellation/progress, and low-memory-device
benchmarks.

## Privacy & threat notes

- **Secrets never enter an isolate** (global `AGENTS.md`, schedule §3 note).
  None of the five sites touches the vault key, passphrase or token. The
  backup writer copies `borrowers.db` + `backup_blob` as OPAQUE ciphertext —
  moving the ZIP to a worker isolate sends ciphertext bytes, not keys. Still:
  the isolate must receive file PATHS + the already-read manifest fields, and
  must never be handed a `SecretBytes`.
- **Catalogue rows are not secret** (M06b WONTFIX) but they are user data;
  sending a `List<Book>` to an isolate copies it in memory — bounded by the
  same 100k cap, and freed when the isolate exits. Acceptable.
- **Decoder-bomb surface widens if we only move image work off-isolate**: an
  OOM in a worker still kills the process on Android (one heap). The frame /
  total-pixel bound is therefore a correctness fix, not just a UX one.
- No new network, no new permission, no new storage location.

## Investigation notes (verified this session, file:line current at `d058966`)

- `lib/features/library/infrastructure/drift_book_repository.dart:27-35`
  `getAll` — no LIMIT; `:38-88` `query` — no LIMIT, plus an in-Dart re-sort for
  `ageGroupAsc` (`_byAgeRank`, `:92-102`); `:310-330` `search` — no LIMIT.
- `lib/features/library/application/library_controller.dart:41-63` `build()`
  → `_load` → whole list into `AsyncValue<List<Book>>`; `:139-160` the search
  path filters + sorts in Dart (`BookSorter.sort`).
- `lib/features/library/presentation/pages/library_page.dart:216-241`
  `GridView.builder` / `ListView.separated` over `books.length`.
- `lib/features/library/domain/merge/library_merge_engine.dart:312-333`
  `_bestFuzzyMatch` — `tokenSet(c)` inside the candidate loop; `:604-618`
  `tokenSet` (regex `_nonToken` unicode class + split). Caller:
  `merge_library_use_case.dart:512` `planMerge(local, incoming)` after
  `getAll()` — the engine is pure Dart (domain, N14 gate) and `Book` is a plain
  immutable class (`book.dart:116`) → isolate-sendable.
- `lib/core/images/image_downscaler.dart:43-101` — synchronous; header
  pre-decode bounds width/height only. `image-4.8.0/lib/src/formats/gif_decoder.dart:172-197`:
  `decode(frame: null)` loops `numFrames`. `Decoder.numFrames()` exists
  (`decoder.dart:42`) → we can refuse/limit BEFORE decoding. Call sites:
  `providers.dart:436, :950`, `library_logo_controller.dart:32`,
  `book_cover_controller.dart:41`, `local_cover_reader.dart:34`. Inputs are
  pre-bounded by `image_picker` (`maxWidth: 1600` camera, `1024` gallery
  logo) EXCEPT the publish cover read-back and the M09 remote cover fetch
  (64 MiB cap, arbitrary format).
- `lib/features/backup/infrastructure/backup_archive_writer.dart:86-139`
  `build()` sync; `create_backup_use_case.dart:54` calls it from an `async`
  method but nothing yields inside. `BackupArchiveBuilder` port
  (`backup_archive_builder.dart:15`) returns `Uint8List` synchronously.
- `lib/features/import_export/infrastructure/pdf_library_renderer.dart:95-128`
  `tileCache` + `cacheTile`; `:304-329` pre-rasterise loop over every book ×
  column × wrapped line. Caller `export_library_use_case.dart:164`.
- `grep -rn "Isolate\.\|compute(" lib` → **zero** hits: nothing in the app
  runs off the UI isolate today.
- Baseline gates (start of S26): analyze **0**; format **404 / 0**; Flutter
  **1576 passed / 0 failed** (`/tmp/pitak-s26-flutter-baseline.txt`, EXIT=0);
  cargo **32 passed**, 2 expected ignored.

## Proposed approach — sub-items

Ordered by (risk removed ÷ effort) and by "regression-testable in pure Dart".

| ID | Sub-item | Fix shape | Test shape | Est. |
|---|---|---|---|---|
| **N10-a** | Bounded image work | `downscaleJpeg` refuses > `maxSourceFrames` (1 for covers — a cover is a still image; animated input → decode frame 0 only via `decoder.decodeFrame(0)`) and > `maxSourcePixels` (w×h, tighter than the per-dimension cap); the WHOLE decode+resize+encode moves into `Isolate.run` behind an `Future<Uint8List?> downscaleJpegAsync` — the 5 call sites are all already `async`. Keep the sync function for tests/pure callers, mark it `@visibleForTesting`-ish or make the async wrapper the only public API. | Unit: a crafted 2-frame GIF is decoded as frame 0 (not all frames); `numFrames` probe rejects > cap without allocating; behaviour test that the async path returns identical bytes to the sync path; existing 5 call sites' tests unchanged. | 1 session |
| **N10-b** | Fuzzy-token cache | `planMerge` pre-computes `tokenSet` for the local no-ISBN pool once (`List<(Book, Set<String>)>`), `_bestFuzzyMatch` compares against the cached sets. Optional: inverted index token → candidate ids so incoming rows only score candidates sharing ≥1 token (turns O(I·L) into O(I·k)). Pure domain, no API change. | Engine test: instrument via an injectable `tokenSet` counter (or a `planMerge` overload taking a `Tokenizer`) proving each local candidate is tokenised exactly once; results identical to HEAD on the existing fixtures; a 5k×5k synthetic plan finishes under a generous wall-clock budget. | ½–1 session (can share with N10-a) |
| **N10-c** | Off-UI-isolate merge planning + ZIP build | `planMerge` runs via `Isolate.run` in the use case (`Book` is sendable; result `MergePlan` is plain). `BackupArchiveWriter.build` becomes async: paths + rows are sent to `Isolate.run`, which reads files and zips, returning `Uint8List`; the `BackupArchiveBuilder` port becomes `Future<Uint8List>`. Cover bytes stream into the encoder one at a time (`archive` 3.x `ZipEncoder` supports `OutputStream`-driven encoding — verify in pub-cache). | Use-case tests keep passing (ports async-ified); a test proving the UI isolate is not blocked (a `Timer` fires during the build); ZIP round-trip through the existing reader unchanged. | 1 session |
| **N10-d** | Pagination of the library list | Repository gains `queryPage(sort, language, {offset, limit})` / `searchPage(...)`; `LibraryController` state becomes a windowed list (`PagedBooks{items, total, hasMore}`), `LibraryPage` requests the next page near the end; `ageGroupAsc` re-sort moves into SQL (`CASE` on the token → rank) so paging is correct; `bookById`/derived providers unaffected (they already go by id). Every mutation path already invalidates the controller (N03/N04). | Repo tests: page boundaries, stable ordering across pages, ageGroup rank in SQL matches `AgeGroup.sortRank`; controller tests: append/replace semantics, revision guard (N05) still drops stale pages; widget test: scrolling to the end requests page 2. | 2 sessions |
| **N10-e** | PDF render bound + progress/cancel | Cap `tileCache` (LRU or per-page flush: rasterise page-by-page instead of all-up-front), add a `CancellationToken`/progress callback to `render`, surface progress in the export page. Rasteriser is engine-bound so it stays on the UI isolate; the fix is bounding + yielding. | Renderer tests: tile cache size never exceeds cap on a 2k-row fixture; cancellation stops before page 2; progress monotonic. | 1 session |

Not scheduled (flag for the user): "low-memory-device benchmarks" — a
benchmark needs a device/emulator run and a memory profiler; the debug
sandbox `dev.khoj.pitaka.fdroid` on the Pixel 8a could host a manual pass
after N10-c/N10-d, but it is not a CI gate.

**OSS references (to verify in pub-cache before implementing, not from
memory):** `Isolate.run` (SDK 2.19+, `dart:isolate`) — the blessed one-shot
worker; `image` 4.8.0 `Decoder.numFrames()`/`decodeFrame()` for N10-a;
`archive` 3.6 `ZipEncoder.startEncode/addFile/endEncode` streaming API for
N10-c; Drift `limit(count, offset:)` for N10-d; Flutter's own
`compute` docs for the "don't send closures/BuildContext" rules.

## N10-a design (verified against `image-4.8.0` source + a probe test, not memory)

**Facts the design rests on:**
- `Decoder.decode(bytes, frame: null)` in GIF (`gif_decoder.dart:172-197`), APNG
  (`png_decoder.dart:486-508`) and WebP (`webp_decoder.dart:117-131`) loops
  `numFrames` and decodes EVERY frame. `copyResize` then resizes every frame
  (`copy_resize.dart:95-97`) and `encodeJpg` writes frame 0 only — so today
  N−1 frames of work are decoded, resized and thrown away.
- `Decoder.startDecode` is header-only (GIF uses `_skipImage()`, no pixel
  buffer); `numFrames()` is valid right after it; `decodeFrame(0)` decodes one
  frame. Probe: 3-frame GIF → `numFrames()==3`, `decodeFrame(0).numFrames==1`,
  `decodeImage(gif).numFrames==3`.
- `Isolate.run` (dart:isolate) accepts a `Uint8List` and returns one under
  `flutter_tester`; under `testWidgets` it needs `tester.runAsync`. No existing
  test drives the real downscaler through a `testWidgets` body (checked all 11
  files that reach it: the widget tests stub the cover pipeline).

**Shape:**
1. `ImageDownscaler.downscaleJpeg` (sync, pure) — KEEP as the single
   implementation; add the two bounds:
   - `maxSourcePixels = 40_000_000` — checked from the header alongside the
     existing per-dimension cap (D3-a);
   - animated input → `decoder.decodeFrame(0)` instead of `decodeImage`
     (D2-a). `numFrames()` is read but NOT capped: frame 0 is all we ever
     decode, so a 10,000-frame file costs one frame. (A cap on the frame
     COUNT would be theatre — the header scan is already linear in file size
     and the file is already byte-capped upstream.)
2. `ImageDownscaler.downscaleJpegAsync(bytes, {maxW, maxH, quality})` —
   `Isolate.run(() => downscaleJpeg(...))`. The closure captures only
   `Uint8List` + ints (sendable). The five call sites switch to the async
   variant; four are already inside `async` functions, `FileEventsRepository`
   takes its `DownscaleFn` — the typedef becomes `Future<Uint8List?>
   Function(List<int>)` and `savePosterImage` awaits it.
3. No new dependency, no new provider, no `@riverpod` class edited — only
   method BODIES inside `BookCoverController`/`LibraryLogoController` change
   (→ `.g.dart` hashes WILL move; run `build_runner` LAST, hook enforces).

**Regression tests (red on HEAD):**
- `test/core/image_downscaler_test.dart`:
  (a) a 3-frame GIF is downscaled to a single-frame JPEG WITHOUT decoding
  frames 1..2 — provable red: build the GIF so frames 1..2 are byte-truncated
  garbage that makes `decodeFrame(i>0)` return null → HEAD's `decodeImage`
  returns null (GIF `decode` returns null on any failed frame, `:186-188`) →
  HEAD output `null`, new output non-null. (b) a 6400×6400 PNG (41 Mpx, both
  dimensions ≤ 8192) is refused — HEAD decodes it (red = HEAD returns
  non-null; costly on HEAD ~160 MiB, so the fixture is written with a
  tiny compressed body: `encodePng` of a blank image compresses to ~KB).
  (c) `downscaleJpegAsync` returns byte-identical output to the sync path —
  compile-red. (d) the UI isolate is not blocked: a `Timer(1 ms)` fires while
  a large downscale is in flight — compile-red (uses the async API).
- `test/features/events/file_events_repository_test.dart`: `fakeDownscale`
  becomes async — compile-red (typedef change).

## Decision points

- **D1 — Order.** Proposed: N10-a → N10-b → N10-c → N10-d → N10-e.
  (a) accept this order; (b) start with N10-d (the review's first word is
  "paginate", it is the biggest UX win for large libraries, but also the
  biggest surface — 2 sessions); (c) other. **→ (a) chosen. This session = N10-a.**
- **D2 — Animated covers (N10-a).** (a) decode frame 0 and drop the rest (a
  cover is a still image; the stored JPEG is a still anyway); (b) refuse
  animated input outright (`null` → "no usable cover"). (a) is friendlier;
  (b) is simpler and stricter. Proposed: (a). **→ (a).**
- **D3 — Total-pixel cap (N10-a).** `maxSourceDimension = 8192` allows
  8192² = 67 Mpx (256 MiB). Proposed `maxSourcePixels = 40_000_000` (~40 Mpx,
  160 MiB transient — above any phone camera still, below the worst case).
  (a) 40 Mpx; (b) keep dimension-only; (c) other number. **→ (a).**
- **D4 — Execution mode.** (a) end-to-end for the chosen first slice;
  (b) pause at each decision point. **→ (a).** No pause trigger fired.

## Steps (first slice — filled in once D1 is answered)

- [x] 0. Session bookkeeping: S25 addendum reconstructed in `fix-schedule.md`;
  repo state verified (`d058966` = `origin/main`, clean).
- [x] 1. Baseline gates recorded (above).
- [x] 2. Re-read N10 + all five cited files (line numbers stale → re-cited above).
- [x] 3. Sub-item breakdown written (this file).
- [x] 4. D1–D4 answered (a, a, a, a).
- [x] 5. Regression tests, proved red on HEAD (see Result).
- [x] 6. Implementation (N10-a).
- [x] 7. Gates green; `build_runner` run LAST (3 hash-only `.g.dart` diffs).
- [ ] 8. `PLAN.md` Result + `fix-schedule.md` S26 log entry; commit approval.

## Out-of-scope observations

- `_byAgeRank` (`drift_book_repository.dart:92-102`) re-sorts in Dart after
  SQL — harmless today, but it BLOCKS correct pagination (N10-d must move it
  into SQL).
- `LibraryController._load`'s search path filters by language and sorts in
  Dart (`:139-160`) — same paging blocker for the FTS path.
- `image_picker` bounds camera/gallery input, but the M09 remote-cover fetch
  and the publish cover read-back feed `downscaleJpeg` with arbitrary bytes
  up to the 64 MiB cap — the N10-a frame/pixel bound matters most there.
- `create_backup_use_case.dart:54` wraps a sync call in `try` inside an
  `async` method — after N10-c the `await` must stay inside the `try`
  (S25 `return await` lesson).
- `localCoverReader` had NO test before this session (the port was extracted
  in N14 without one); five tests added here. Its `on Exception` branch
  (`local_cover_reader.dart:37`) stays uncovered — it needs `readAsBytes` to
  throw on an existing path (e.g. a directory named `x.jpg`); not worth a
  contrived fixture.
- `image_picker` is called with `maxWidth: 1600` (camera) / `1024` (gallery
  logo) but the events poster picker (`events_page.dart:68`) was not checked
  for a bound this session — N10-a's pixel cap covers it regardless.
- `Isolate.run` spawns a fresh isolate per call (~ms). Publish re-encodes
  every cover in a loop, so a 1,000-cover library spawns 1,000 short-lived
  isolates. Fine today (each is cheap and the loop is already sequential);
  a pooled worker would be the N10-c-era refinement if profiling shows it.

## Result

**N10-a DONE (uncommitted; commit approval pending).**

- **Red evidence.** Graft copy of the new test file with the new symbols
  replaced by literals (`40000000`, `8192`) and the async group removed, run
  against HEAD's `image_downscaler.dart`: "an animated GIF is downscaled from
  frame 0 only" **FAILED** (`Expected: not null / Actual: <null>` — HEAD's
  `decodeImage` walked all frames and gave up on the broken second one);
  "rejects a source over maxSourcePixels before decoding" **FAILED**
  (`Expected: null / Actual: […]` — HEAD decoded the 41 Mpx PNG, measured
  ~850 ms). The `downscaleJpegAsync` group (4) and the `maxSourcePixels`
  references were compile-red. `file_events_repository_test.dart`'s
  `fakeDownscale` was compile-red after the typedef change. Graft removed.
- **Fixture technique** (for future sessions): a 3-frame GIF whose SECOND
  frame's descriptor puts it outside the canvas — located via the decoder's
  own `InternalGifImageDesc.inputPosition` (walk back over the local colour
  map + 9-byte descriptor to the `0x2C` separator). `decodeFrame(0)` is fine,
  `decodeFrame(1)` is null, `decodeImage` is null. A naive scan for `0x2C`
  bytes hits LZW payload — the first two probe attempts failed that way.
- **Changes.**
  - `lib/core/images/image_downscaler.dart`: `maxSourcePixels = 40_000_000`
    checked from the header next to the dimension cap; `decoder.decodeFrame(0)`
    replaces `decodeImage` (frame 0 only, D2-a); new `downscaleJpegAsync`
    = `Isolate.run` over the sync function (captures `Uint8List` + 3 ints
    only; `debugName: 'pitaka-image-downscale'`). Library doc explains the
    two entry points and why for a beginner. EXIF-strip path unchanged.
  - `lib/features/events/infrastructure/file_events_repository.dart`:
    `DownscaleFn` → `Future<Uint8List?> Function(List<int>)`;
    `savePosterImage` awaits it.
  - `lib/core/di/providers.dart`: `boundedCoverDownload` and
    `eventsRepository` use the async variant (`.g.dart` hashes only).
  - `lib/features/library/application/book_cover_controller.dart`,
    `lib/features/settings/application/library_logo_controller.dart`: `await
    downscaleJpegAsync` (`.g.dart` hashes only).
  - `lib/features/publish/infrastructure/local_cover_reader.dart`: `return
    await downscaleJpegAsync(…)` INSIDE the `try` (S25 lesson).
  - Tests: `test/core/image_downscaler_test.dart` +8 (2 groups: bounded
    decode work × 4, async × 4 incl. the "timer fires mid-work" UI-isolate
    proof); `test/features/publish/local_cover_reader_test.dart` NEW (5);
    `test/features/events/file_events_repository_test.dart` fake made async.
- **Gates.** analyze **0**; format **404 / 0 changed**; Flutter `--coverage`
  **1589 passed / 0 failed** (`/tmp/pitak-s26-flutter-final.txt`, EXIT=0, 0
  `[E]`); cargo **32 passed** (2 expected ignored; Rust untouched);
  `git diff --check` clean; `build_runner` run LAST → 3 hash-only `.g.dart`
  diffs, `.fvmrc`/`.gitignore` untouched. Coverage **72.65%** (+0.05);
  `image_downscaler.dart` 20/20, `local_cover_reader.dart` 6/7,
  `file_events_repository.dart` 29/32. Lib-diff privacy scan: no
  print/log/http/Uri/Platform added; the isolate receives image bytes + ints
  only — no secret, no `ref`, no `BuildContext`.
- **Not verified on a device.** The finding is a static scalability risk and
  every branch is deterministic in tests; the UI-isolate proof is the timer
  test, not a frame-timing capture. A device pass (capture a cover on the
  `dev.khoj.pitaka.fdroid` sandbox and watch for jank) is optional.
- **Behaviour change to tell users:** none visible. An animated GIF picked as
  a cover used to be decoded in full and stored as its first frame; it is now
  decoded as its first frame and stored the same way. A source over 40 Mpx
  (previously accepted up to 8192×8192) is now "no usable cover" — no phone
  camera produces such a still.

### Commit paths (explicit, never `-A`)

```
lib/core/images/image_downscaler.dart
lib/core/di/providers.dart
lib/core/di/providers.g.dart
lib/features/events/infrastructure/file_events_repository.dart
lib/features/library/application/book_cover_controller.dart
lib/features/library/application/book_cover_controller.g.dart
lib/features/publish/infrastructure/local_cover_reader.dart
lib/features/settings/application/library_logo_controller.dart
lib/features/settings/application/library_logo_controller.g.dart
test/core/image_downscaler_test.dart
test/features/events/file_events_repository_test.dart
test/features/publish/local_cover_reader_test.dart
PLAN.md
```
