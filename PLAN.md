# PLAN.md — current task

Roadmap: `fix-schedule.md`. Session 6, **M04 COMPLETE, uncommitted**.
User approved end-to-end execution (option a). Commit approval is separate.

## Understanding
- Prevent a bundle import from overwriting existing covers, including when
  JSON is invalid, a book is skipped, or a later database operation fails.
- Start/current HEAD: `cb5d74d`; tracked tree clean at session start.
  `astra-review.md` and `fix-schedule.md` stay untracked and must not be staged.
- Scope: bundle reader, import orchestration, narrow file-ownership ports/DI,
  relevant tests and generated code. Do not implement other scheduled findings.

## Privacy & threat notes
- A user-selected archive is untrusted. Its filenames must never authorize
  writes to existing files or access to another local image via a forged ref.
- Parse/check first; keep only image bytes referenced by accepted rows. Never
  fetch remote images during import or expose paths/catalogue data in errors.
- Store any temporary files in app-private storage; track ownership explicitly.
  Rollback may delete only files created by that particular import operation.
- No new telemetry, network, credentials, permissions, dependencies or schema.
  Existing plaintext-cover/catalogue storage policy remains M06, not changed.
- SQLite cannot roll back filesystem writes. Complete new files before their
  database references commit; remove owned files on rollback. Do not claim
  power-loss atomicity from rename or a SQL transaction alone.

## Investigation notes
- Before changes, M04 matched library_bundle_reader.dart:60–89: writeAsBytesSync used
  incoming leaf names before JSON parsing; cover write failures are skipped.
- import_controller.dart:46–64 reads/writes the bundle before applyPayload.
  No file rollback is tied to the resulting database transaction.
- import_library_use_case.dart:117–204 deduplicates within runInTransaction:
  stable UID updates, ISBN-only books skip, wishlist ISBN matches replace.
  Preserve these rules and book IDs; skipped rows must not install covers.
- Both repositories share AppDatabase via DI. DriftBookRepository:287–301
  rolls back Left results/throws; current import fakes are pass-through, so
  add real in-memory Drift integration tests, not fake-only atomicity claims.
- Read tables.dart/app_database.dart: books and wishlist both have cover_url;
  no schema change is needed. Vault/FFI are not involved in additive import.
- ImportPayload mixes file/row parse errors; PitakaJsonImporter currently keeps
  local refs for bundles. Comprehensive field validation remains M15.
- CoverFiles.saveJpeg is JPEG-specific, while bundle bytes need not be JPEG.
  Do not rename arbitrary bytes to JPEG or expand capture behavior casually.
- CoverFileJanitor:80–94 can sweep fresh UUID JPEGs before DB commit. Pending
  import files need explicit protection; do not rely on today's janitor for
  rollback (its wishlist ownership omission remains M11).
- Pinned Flutter 3.44.2 baseline: analyzer 0 issues; format 338 files / 0 changed;
  full Flutter 965 passed / 0 failed; Rust 30 passed / 2 expected ignored.
  Flutter log: `/tmp/pitak-m04-flutter-baseline.e30L4Q`.

## Implemented approach (with OSS references)
- First add the permanent invalid-JSON/existing-cover regression and demonstrate
  failure on old code. Add duplicate-ISBN and DB-failure reproductions too.
- Separate side-effect-free bundle decoding/validation from file installation.
  Use a narrow domain contract for application orchestration; keep file IO in
  infrastructure and provider wiring in core DI, with typed Either failures.
- Recommended bundle policy: reject parse errors, unsafe/missing local image
  references and unreferenced cover entries before persistence. Accept valid
  empty bundles. Leave ordinary text JSON/CSV import semantics unchanged.
- Resolve accepted rows using existing transaction/dedup rules; stage only their
  referenced images, sharing one new reference per incoming image where needed.
  Rewrite book AND wishlist refs to fresh app-owned names, never incoming names.
- Coordinate pending-file ownership with cleanup; detect destination collisions
  without overwriting. Preserve existing covers even on rollback/cleanup error.
  Test repeated imports, overlapping operations and sweeps at await boundaries.
- Tie installation and rollback to the OUTERMOST transaction result, including
  commit failure. Keep completed files after successful commit; do not report
  an already-committed import as rolled back because housekeeping failed.
- OSS foundations verified locally: Drift 2.28.2 source, runtime/api/
  connection_user.dart:431–524 (zone-scoped transaction, commit/rollback cleanup);
  pinned Dart SDK io/file.dart:223–311 (exclusive create and destructive rename
  semantics), io/directory.dart:223–240 (unique temporary directories). Adapt
  these existing primitives; no home-grown transaction or crypto library.
- Add reader/storage unit tests, ProviderContainer controller tests, real Drift
  rollback tests and UI error/retry coverage. Regenerate annotated providers;
  run full tests/coverage, analyzer, format, Rust and diff checks before done.

## Decision points
- End-to-end M04 execution and proposed bundle rejection policy: APPROVED.
- Use one DI-owned FIFO around import and janitor decisions so cleanup cannot
  observe uncommitted cover references. Wishlist ownership rules remain M11.
- Pause if file/sweep coordination requires broader M11 work or if compatibility
  evidence contradicts the proposed rejection policy. Commit approval separate.

## Steps
- [x] Verify handoff, source/callers/tests/schema and OSS primitives.
- [x] Run baseline gates and record this plan/checkpoint.
- [x] Obtain execution-mode approval.
- [x] Add permanent failing regressions before implementation.
- [x] Implement/review validation, staging, reference rewriting and owned-file rollback.
- [x] Verify failure, dedup, wishlist, lifecycle and cleanup interleavings.
- [x] Run final gates/coverage; update Result and schedule; request commit.

## Out-of-scope observations
- Archive decompression remains unbounded before some checks (M05).
- Numeric/domain validation (M15), wishlist janitor ownership (M11), broad UI
  lifecycle hardening (N11), and cross-dataset restore recovery (M02) remain open.
- Plain-JSON wishlist parsing retains local refs unlike book parsing; record for
  input-validation follow-up, do not silently broaden M04 into all import paths.

## Result
- M04 complete after user approved resumption. Three permanent real-Drift
  regressions FAILED before fixing: invalid JSON, duplicate ISBN, DB rollback
  each overwrote an old cover. All now pass; 84 net new Flutter tests overall.
- Pure BundleReader validates catalogue/refs before IO; ImportBundle owns
  immutable copies. Only accepted rows stage covers under exclusive fresh names.
  Both tables share rewritten refs; later replacements discard superseded new
  files. UID identity and ISBN/wishlist dedup rules are preserved.
- ImportLibraryUseCase:122 coordinates the top-level transaction result with
  file ownership. Failure removes only owned new files; failed cleanup returns
  a typed failure. Existing covers are never overwritten/deleted by this path.
- Shared DI-owned FIFO serializes import and janitor reference-check/delete;
  controller pins operation lifetime and blocks overlapping submissions.
  No broad M11 ownership or N11 widget-lifecycle refactor was performed.
- Tests cover immutable/unsafe input; file/directory/link collisions; partial
  writes; cleanup failures; database reads/writes; outer transaction rejection
  after its body succeeds; wishlist/shared/final refs; repeated imports; queue
  failure/release; disposal before/after staging; real-page error and retry.
- Final full Flutter --no-pub --coverage: **1049 passed / 0 failed** (baseline 965).
  Rust: **30 passed / 0 failed**, 2 expected ignored real-archive tests.
  Analyzer: **0 issues**. Format: **352 files / 0 changed**. Diff check clean.
  Flutter log: `/tmp/pitak-m04-flutter-full.KjFP1P`.
- Line coverage: import controller 31/31 (100%); import use case 119/123 (96.75%);
  image mapper 19/20 (95%); validated bundle 31/31 (100%); file store 37/37 (100%);
  reader 29/30 (96.67%); coordinator 7/7 (100%); janitor 26/26 (100%).
- Generation rerun wrote 0 outputs; expected two generated files unchanged.
  Existing SDK/analyzer language-version warning appeared on the earlier build.
  Two missed test constructor arguments and style diagnostics were corrected;
  the analyzer rerun is clean. Nominal-port lint exceptions are justified like
  the existing Importer contract, not blanket lint disabling.
- OSS: adapted synchronized 3.4.0+1 BasicLock; verified MIT license/copyright
  retained in source (initial BSD comment corrected). Drift insert.dart:205–210
  confirms upsert's last-insert-ID caveat; known matched wishlist ID is used.
- Privacy/diff review: no new network/logging/secrets/permissions/dependencies or
  schema changes. Tests use synthetic temporary files and in-memory databases.
  Narrow touched-file logging/network scan is not a full dependency/secret audit.
- Limits: no physical-device/picker/power-loss test. Outer commit rejection is
  fault-injected through the real Drift transaction wrapper, not simulated
  hardware failure. Abrupt death/failed cleanup can leave unreferenced NEW files;
  this is not a claim of cross-file power-loss atomicity. M02/M05/M11 stay open.
- All 28 code/test/generated/PLAN.md paths are uncommitted; no staging or commit
  performed. Ask separately before committing. Next finding after commit: M03.

## Proposed commit (awaiting approval)
Only these 28 paths; never stage the local review or schedule files:
```sh
git add -- \
  PLAN.md \
  lib/core/di/providers.dart \
  lib/core/di/providers.g.dart \
  lib/features/import_export/application/bundle_import_images.dart \
  lib/features/import_export/application/import_controller.dart \
  lib/features/import_export/application/import_controller.g.dart \
  lib/features/import_export/application/import_library_use_case.dart \
  lib/features/import_export/domain/bundle_cover_files.dart \
  lib/features/import_export/domain/import_bundle.dart \
  lib/features/import_export/domain/pitaka_json_importer.dart \
  lib/features/import_export/infrastructure/file_bundle_cover_store.dart \
  lib/features/import_export/infrastructure/library_bundle_reader.dart \
  lib/features/library/application/cover_file_janitor.dart \
  lib/features/library/domain/cover_file_coordinator.dart \
  test/features/import_export/bundle_import_fault_test.dart \
  test/features/import_export/bundle_import_lifecycle_test.dart \
  test/features/import_export/bundle_import_safety_test.dart \
  test/features/import_export/bundle_import_transaction_test.dart \
  test/features/import_export/bundle_test_fixture.dart \
  test/features/import_export/controlled_bundle_files.dart \
  test/features/import_export/file_bundle_cover_store_test.dart \
  test/features/import_export/import_bundle_test.dart \
  test/features/import_export/import_controller_test.dart \
  test/features/import_export/library_bundle_reader_test.dart \
  test/features/library/book_cover_controller_test.dart \
  test/features/library/cover_file_coordinator_test.dart \
  test/features/library/cover_file_janitor_test.dart \
  test/features/settings/library_logo_controller_test.dart
git commit -m "fix(import): preserve covers during bundle imports (M04)"
```
