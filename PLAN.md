# PLAN.md — Session 28 — N10-c: `planMerge` + `BackupArchiveWriter.build` off the UI isolate

Roadmap: `fix-schedule.md` §1 (NEXT = N10-c). Finding: `astra-review.md` N10
("Large-library operations run unbounded work on the UI isolate"), sub-item c
of the S26 breakdown (a→b→c→d→e). Two call sites, one pattern (N10-a's
`Isolate.run`).

## Understanding

Two pieces of heavy, CPU/IO-bound work still run on whichever isolate calls
them — in production that is the UI isolate, so every frame is frozen until
they return:

1. **Backup build** — `BackupArchiveWriter.build`
   (`lib/features/backup/infrastructure/backup_archive_writer.dart:87-139`):
   writes two SQLite files row by row, `readAsBytesSync` EVERY cover into an
   `Archive` object (all covers resident at once), then `ZipEncoder().encode`
   deflates the lot into a second full-size buffer. Fully synchronous; the
   `BackupArchiveBuilder` port (`domain/backup_archive_builder.dart:20`)
   returns `Uint8List`. Caller: `CreateBackupUseCase.call`
   (`application/create_backup_use_case.dart:54`) → `create_backup_page.dart:42`.
2. **Merge plan** — `planMerge(local, incoming)` at
   `merge_library_use_case.dart:512` (`_applyEngineMerge`, the only
   production caller). N10-b made it ~300× cheaper, but a 100k×100k plan is
   still hundreds of ms of pure CPU on the UI isolate.

Verified in pub-cache (`archive-3.6.1/lib/src/zip_encoder.dart`), NOT memory:
`ZipEncoder.encode` (`:81-99`) is just `startEncode` → `addFile` per file →
`endEncode`; those three are public (`:101`, `:162`, `:272`). `addFile`
deflates the entry, writes it to the output stream at once (`:263`) and drops
its compressed bytes (`:265`). So covers can be read, deflated and written
ONE AT A TIME — peak memory becomes (one cover + the growing ZIP) instead of
(all covers + all deflated copies + the ZIP). The ZIP itself must still end
as bytes: the page shares it via `XFile.fromData` (`core/platform/file_share.dart:67`).

Verified by probe tests (written + deleted this session, `test/_tmp_probe/`):
- `Book`, `WishlistBook`, `MergePlan` cross `Isolate.run` intact (plain
  fields + enums; `sourceType` round-trips).
- **`sqlite3.open` (the injected `openDatabase`) is an instance tear-off on
  the `Sqlite3` object and is NOT sendable**: `Illegal argument in isolate
  message: (object is a NativeFinalizer)`. A top-level function that calls
  `sqlite3.open` INSIDE the worker works (each isolate lazily builds its own
  `sqlite3` global; `drift`'s own `NativeDatabase.createInBackground` relies
  on the same fact).
- Every caller passes `sqlite3.open` (`providers.dart:907`,
  `backup_archive_writer_test.dart:23,202`,
  `catalogue_replacement_restore_test.dart:52`); nobody injects anything else.

Test reach check: `merge_page_test.dart` never executes `planMerge` (the
default fixture's library ID differs → `MergeDiffersDecision`; "Replace my
library" → `applyOverwrite`, no engine; N07 group uses `_DoneController`), so
no `runAsync` migration. `merge_controller_test`, `merge_library_use_case_test`,
`catalogue_replacement_failure_test`, both backup writer tests are plain
`test()` bodies — `Isolate.run` works there (S26 probe + today's).

## Privacy & threat notes

- Nothing new leaves the device; no network, no logging added.
- What crosses into the worker isolate (in-process memory copy, same OS
  process, same sandbox): catalogue rows (unencrypted by M06b decision),
  file PATHS (work dir, covers dir, vault DB path), and the wrapped-key blob
  STRING. The blob is AES-GCM ciphertext already stored as a plain file — it
  is not a secret and the writer already copies it into the archive today.
  The vault DB is copied as opaque ciphertext bytes. **The passphrase / vault
  key never appears anywhere in this path** (unchanged).
- Threat: a hostile cover file / huge library cannot do more in the worker
  than it can today on the UI isolate; the work is the same, only the isolate
  differs. Isolate failure → exception → `StorageFailure` (fail closed,
  unchanged contract).
- Isolate closures must capture ONLY plain data (typed-data, strings, ints,
  entity lists). No `ref`, no `BuildContext`, no FFI handles. The
  `NativeFinalizer` finding is exactly this rule biting: fix by construction
  (D1), not by documentation.

## Investigation notes

- `OutputStream.getBytes()` (`util/output_stream.dart:44`) returns a
  `Uint8List.view` over an over-allocated buffer → copy to exact size before
  returning (`Uint8List.fromList`), as the current code already does.
- `Isolate.run` hands the result back with `Isolate.exit` (no second copy).
- `ArchiveFile(name, size, Uint8List)` → `compress = true` (deflate) —
  identical entry shape to today; the restore reader
  (`bounded_zip_extractor.dart:275`) accepts store + deflate.
- Application layer may import `dart:isolate` (the N14 allowlist gate only
  covers `/domain/`; `dart:isolate` is explicitly OFF the domain list).
- N10-a precedent: `core/images/image_downscaler.dart:142-155` —
  `Isolate.run(() => sync(rawBytes, ints), debugName: 'pitaka-…')`; timer test
  `test/core/image_downscaler_test.dart:257-275`.

## Proposed approach (OSS reference: Dart SDK `Isolate.run` docs; `drift`'s
`NativeDatabase.createInBackground` for "open sqlite3 inside the worker")

### Backup
- `BackupArchiveBuilder.build` → `Future<Uint8List>` (port).
- `BackupArchiveWriter.build` becomes: on the CALLER isolate, resolve the
  cheap, non-sendable bits into plain data (`vaultStore.isInitialized()`,
  `vaultStore.dbPath`, `vaultStore.readBlob()` — two `existsSync` + a tiny
  read); then `Isolate.run(() => _buildInWorker(job))` where `job` is a
  private plain-data record (paths, rows, exportedAt, hasVault, blob) and
  `_buildInWorker` is a **static** function: writes the two SQLite files
  (opening via `sqlite3.open` inside the worker), `ZipEncoder.startEncode`
  on an `OutputStream`, `addFile` manifest/books/wishlist/vault/blob, then
  covers one at a time (`readAsBytesSync` → `addFile` → next), `endEncode`,
  exact-size copy back.
- D1 decides what happens to the `openDatabase` constructor parameter.
- `CreateBackupUseCase.call` awaits `writer.build` (inside the existing try).

### Merge (corrected mid-session — see D4)
- Port in application: `lib/features/import_export/application/merge_planner.dart`
  = `typedef MergePlanner = Future<MergePlan> Function(List<Book>, List<Book>)`
  ONLY (no `dart:isolate`).
- Implementation in infrastructure:
  `lib/features/import_export/infrastructure/background_merge_planner.dart`
  = `planMergeInBackground(local, incoming) => Isolate.run(() =>
  planMerge(local, incoming), debugName: 'pitaka-merge-plan')`.
- `MergeLibraryUseCase` gains **required** `MergePlanner planner`;
  `_applyEngineMerge` does `final plan = await _planner(local, incoming)`.
  `providers.dart` injects `planMergeInBackground`; the 35 test constructions
  inject a shared synchronous `planMergeInline` from
  `test/features/library/replacement_test_guard.dart`.

## Decision points

- **D1 — the `openDatabase` seam on `BackupArchiveWriter`.** Today it is
  documented as a test seam but every caller passes the same non-sendable
  `sqlite3.open`; keeping it means any future caller passing a tear-off
  fails only at RUNTIME with an opaque isolate error.
  (a) REMOVE the parameter; the worker opens SQLite itself via a private
  top-level function (`sqlite3.open`). Constructor: `vaultStore` + `coversDir`
  only. Touches `providers.dart:907` and the 3 test constructions. Fail-closed
  by construction. **Recommended.**
  (b) Keep the parameter, document "must be a top-level/static function",
  DI + tests pass a new top-level `openNativeSqlite`. Same behaviour, one
  extra footgun.
- **D2 — merge hop policy.** (a) always `Isolate.run` (spawn cost ≈ ms; N10-a
  precedent). **Recommended.** (b) hop only above a row threshold (adds a
  branch + threshold test; premature).
- **D3 — execution mode:** end-to-end, or pause at each decision point?

**Answers (2026-09-13):** D1 → **(a)** remove `openDatabase`; D2 → **(a)**
always hop; D3 → **(a)** end-to-end, pause only for commit/push or a broken
assumption.

- **D4 — broken assumption (paused, asked, answered).** The N14 gate has a
  SECOND test, `domain_purity_test.dart:138-169` "application files perform
  no platform IO", that forbids `import 'dart:isolate'` in `/application/`.
  My plan had read only the domain test. Options offered: (a) port in
  application + implementation in infrastructure + `planner` REQUIRED
  (the `jsonParser`/`PitakaJsonImporter` precedent); (b) same move with a
  synchronous default (footgun); (c) weaken the gate. **Answer: (a).**

## Steps

- [x] 1. Baseline gates recorded (done: analyzer 0, format 405/0, Flutter 1596, cargo 32).
- [x] 2. Regression tests, proved red on HEAD:
  - `test/features/backup/backup_archive_writer_test.dart`: `build` returns a
    `Future` (compile-red on HEAD); a 1 ms `Timer` fires while a large build
    is in flight (behaviour-red vs a `Future.sync` graft of HEAD's writer);
    covers/vault/manifest still round-trip through `unzip` + restore reader
    (existing tests, made `await`).
  - `test/features/import_export/merge_planner_test.dart` (new):
    `planMergeInBackground` == `planMerge` on the same fixture (ids/uids/
    counts); 1 ms `Timer` fires during a 3000×3000 plan (behaviour-red vs a
    `Future.sync(planMerge)` graft).
  - `test/features/import_export/merge_library_use_case_test.dart`: the use
    case routes through the injected `planner` (compile-red on HEAD).
- [x] 3. Port `BackupArchiveBuilder.build` → `Future<Uint8List>`.
- [x] 4. Writer: plain-data job + static worker + incremental `ZipEncoder`;
  D1 outcome applied.
- [x] 5. `CreateBackupUseCase` awaits; `providers.dart` wiring.
- [x] 6. `merge_planner.dart` (port) + `background_merge_planner.dart` (impl); `MergeLibraryUseCase(planner:)` required; `await`.
- [x] 7. Fix the 3 existing sync callers in tests (`await`) + 35 constructions gain `planner: planMergeInline`.
- [x] 8. Gates: analyzer 0, format, full Flutter suite detached, cargo;
  `build_runner` LAST if any `@riverpod` code changed (expected: none — the
  provider body changes only if D1 = a … `providers.dart:907` IS inside a
  `@riverpod` function → `.g.dart` hash changes → run `build_runner`).
- [x] 9. Lib-diff privacy scan (print/log/http/Uri added? isolate captures?).
- [ ] 10. Commit approval (explicit paths), push approval, CI check.

## Out-of-scope observations

- `poster_file_reader.dart` and `logo_file_reader.dart` show 0/7 line coverage
  in lcov (pre-existing; not touched).
- `Isolate.run` spawns one isolate per backup/merge — fine (one user action
  each); the S26 "pooled worker" note stands only for the per-cover downscale.
- `catalogue_replacement_failure_test.dart` was the one merge test file not
  importing `replacement_test_guard.dart`; it now does (for `planMergeInline`).
- The test-side `planMergeInline` duplicates the shape of a possible
  production "inline planner"; deliberately NOT added to `lib/` — production
  has exactly one planner (D2-a).

## Result

- **Backup:** `BackupArchiveBuilder.build` → `Future<Uint8List>`;
  `BackupArchiveWriter` ships a plain `_BackupJob` record to `Isolate.run`,
  where a static `_buildInWorker` opens SQLite itself (`_openSqlite`,
  top-level — the `sqlite3.open` tear-off is NOT sendable, probe-verified:
  "Illegal argument in isolate message: (object is a NativeFinalizer)"),
  writes the two Room DBs, and drives `ZipEncoder.startEncode/addFile/
  endEncode` so each cover is read → deflated → appended → dropped, one at a
  time. `openDatabase` constructor parameter REMOVED (D1-a). Use case awaits.
- **Merge:** `MergePlanner` port (application) + `planMergeInBackground`
  (infrastructure, `Isolate.run`) injected from `providers.dart`;
  `MergeLibraryUseCase.planner` is required (D4-a); `_applyEngineMerge`
  awaits it. 35 test constructions use the shared synchronous
  `planMergeInline`.
- **Red evidence** (graft copies of HEAD's writer/planner behind
  `Future.sync`, run from `test/_tmp_red/`, dir removed): writer timer test
  "fired at 876 ms, build took 876 ms" (needed < 438); planner timer test
  "fired at 59 ms, plan took 59 ms" (needed < 29); `openDatabase` required
  ×4, `planMergeInBackground` undefined ×3, `planner` undefined ×1
  compile-red on HEAD. Fixed code: both timers fire at ≈1 ms.
- **Tests:** +8 net (writer group 3, planner file 3, use-case seam 2;
  existing tests made `async`). Full suite **1604 passed / 0 failed**
  (`/tmp/pitak-s28-flutter-final.txt`, EXIT=0, 0 `[E]`); cargo **32 passed**
  (2 expected ignored, Rust untouched); analyzer **0**; format **408 / 0
  changed**; `git diff --check` clean; coverage **72.74%** (+0.06);
  `backup_archive_writer.dart` 107/107, `background_merge_planner.dart` 3/3,
  `merge_library_use_case.dart` 143/147. `build_runner` run LAST → 2
  hash-only diffs in `providers.g.dart` (`mergeLibraryUseCase`,
  `createBackupUseCase`); `.fvmrc`/`.gitignore` untouched.
- **Privacy:** lib-diff scan — no print/log/http/Uri/Platform added; the two
  isolate closures capture `job` (paths, rows, ints, ciphertext blob string)
  and two `List<Book>` respectively. The vault passphrase/key never appears.
- Commit + push: pending approval (see §Commit paths).

## Commit paths (explicit — never `git add -A`)

```
PLAN.md
lib/core/di/providers.dart
lib/core/di/providers.g.dart
lib/features/backup/application/create_backup_use_case.dart
lib/features/backup/domain/backup_archive_builder.dart
lib/features/backup/infrastructure/backup_archive_writer.dart
lib/features/import_export/application/merge_library_use_case.dart
lib/features/import_export/application/merge_planner.dart
lib/features/import_export/infrastructure/background_merge_planner.dart
test/features/backup/backup_archive_writer_test.dart
test/features/backup/catalogue_replacement_restore_test.dart
test/features/import_export/merge_controller_test.dart
test/features/import_export/merge_library_use_case_test.dart
test/features/import_export/merge_page_test.dart
test/features/import_export/merge_planner_test.dart
test/features/library/catalogue_replacement_failure_test.dart
test/features/library/replacement_test_guard.dart
```
