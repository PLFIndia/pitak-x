# PLAN.md — Session 9: M02 atomic restore (generation directories)

## Understanding

Only M02 is in scope (`fix-schedule.md` §1 NEXT). Restore currently commits
three independent stores in sequence — catalogue Drift transaction
(`restore_backup.dart:263–315`), vault rename pair (`vault_store.dart:246–267`),
covers wipe-and-rewrite (`restore_backup.dart:333–336, 428–447`). A crash or IO
error between any two leaves the device on a mix of old and new data, and no
startup code detects it. **User decision (2026-09-08): Option 1 — versioned
generation directories with an atomic active pointer.** The review's static
finding was re-verified against HEAD `db4d040`; all three boundaries still exist.
Session 8 already locks the old session after a vault-bearing restore
(`vault_session_controller.dart:700`), which is the only part of M02 done so far.

Expected size: **two sessions** (schedule). This session delivers a safe,
committable slice; the remainder is recorded explicitly in Steps.

## Privacy & threat notes

- Trust boundary unchanged: everything stays in the app-private documents dir.
  The catalogue is still plain SQLite (M06b, open); the vault stays SQLCipher.
- **Retention:** a generation switch briefly leaves the previous generation
  (plaintext catalogue + covers + encrypted vault) on disk. Data minimization
  requires deleting it promptly: obsolete generations are removed right after
  the switch and again at every startup. Android is the only shipping target
  (M18 decision d); POSIX unlink semantics make deleting a directory whose old
  SQLite handle is still closing safe (the inode outlives the name).
- No new secrets, logging of paths/PII, telemetry, network, or permissions.
  Vault key material is never read by Dart; the vault files are copied as
  opaque bytes while the session FIFO (M03 guard) guarantees no writer runs.
- Fail closed everywhere: any error while BUILDING a generation discards it and
  leaves the active generation byte-identical. Only the pointer switch commits.
- Adoption of the current flat layout on first launch must be idempotent and
  must never delete anything outside `data/gen-*`.

## Investigation notes (verified this session)

- Layout today (`providers.dart:116,127,530,719,740`): `<docs>/pitaka.db`,
  `<docs>/covers/`, `<docs>/borrowers.db`, `<docs>/vault_backup_blob`,
  `<docs>/vault_biometric_blob`. Not replaced by restore and therefore staying
  in `<docs>`: events, posters, publish manifest, bookmarks/settings (prefs),
  scratch dirs (`restore_work`, `backup_create_work`, `vault_view_work`).
- Consumers that must follow the active generation: `appDatabaseProvider`,
  `coversDirProvider` (→ coverStore, localCoverReader, bundle cover store,
  logo reader, `book_cover.dart:87`, `library_logo.dart:51`), `vaultStoreProvider`
  (→ session controller via `ref.read`, backup writer, restore), and the two
  literal `p.join(dir.path, 'covers')` in `createBackupUseCase`/`restoreBackup`.
- `pitaka.db` uses SQLite's default rollback journal (no `setup:` PRAGMA), so a
  hot `-journal` can exist after a crash: adoption must move `-journal/-wal/-shm`
  companions together with each DB. Same for `borrowers.db` (Rust, default mode).
- `VaultSessionController.build` uses `ref.read(vaultStoreProvider.future)`
  (`:92–93`) and caches the store; a switch does not re-point it. Today the
  restore controller `ref.invalidate`s the session only on success (`:69`).
- `stageRestore`/`StagedVaultInstall` (`vault_artifacts_store.dart`,
  `vault_store.dart:158–277`) become dead once the generation dir is the
  staging area; six `vault_store_test.dart` tests cover them and will be
  replaced by generation tests (no dead code, repo AGENTS.md §2.4).
- Test fixtures constructing `RestoreBackup(...)` with `coversDir`/`vaultStore`:
  `restore_backup_test.dart`, `migration_matrix_test.dart`,
  `restore_controller_test.dart`, `restore_page_test.dart`,
  `catalogue_replacement_restore_test.dart` (+ `replacement_harness.dart`).
  They assert on the in-memory live `db`; after the change the NEW generation's
  DB holds the rows, so the fixtures need an "open active catalogue" helper.
- Verified primitives: `File.rename` replaces an existing file atomically and
  fails over a directory (pinned SDK `io/file.dart:281–283`, probe confirmed);
  `dart:io` cannot fsync a directory (probe: "Is a directory") — directory-entry
  durability relies on the filesystem committing metadata in order (ext4/f2fs
  journal ordering); this limit is documented, not hidden.
- SQLite `sqlite_sequence` keeps the AUTOINCREMENT high-water mark across
  delete/copy (CLI probe: seq 500 → next id 501), so M03's no-ID-reuse property
  survives a snapshot into a new generation.

## Proposed approach (with OSS references)

Layout: `<docs>/data/CURRENT` (text: active generation name) and
`<docs>/data/gen-NNNNNN/{pitaka.db, covers/, borrowers.db, vault_backup_blob,
vault_biometric_blob, COMPLETE}`. `COMPLETE` is an empty marker written
(flushed) last, so startup can tell a finished generation from a crashed build.

1. **`lib/core/storage/data_generations.dart`** (new; dart:io, cross-cutting like
   `core/database`): `open()` = adopt flat layout into `gen-000001` if `CURRENT`
   is absent (per-file rename, idempotent, moves DB companions, never overwrites
   an existing destination), read `CURRENT`, require its `COMPLETE`, fall back
   to the highest complete generation if the pointer is dangling, delete every
   other `gen-*`; `beginNext()` = fresh builder dir; `complete()` = marker;
   `activate(name)` = write `CURRENT.tmp` flushed → rename over `CURRENT` →
   delete obsolete generations. Adapted from LevelDB `SetCurrentFile`
   (`db/filename.cc`, BSD-3, fetched 2026-09-08) and its remove-obsolete-files-
   on-recovery rule; temp-then-rename durability as in SQLite (already credited
   in `vault_store.dart`).
2. **DI:** new keepAlive `@riverpod` `ActiveDataGeneration` AsyncNotifier
   (build → `open()`; `activate(prepared)` → switch + publish new paths).
   `appDatabaseProvider`, `coversDirProvider`, `vaultStoreProvider` watch it;
   `createBackupUseCase` uses `coversDirProvider`. Everything downstream follows
   via `ref.watch`. `main.dart` unchanged (providers are lazy).
3. **Restore = build a generation, then switch** (`RestoreBackup`): snapshot
   the live catalogue with `VACUUM INTO <gen>/pitaka.db` (transactionally
   consistent copy; preserves schema, indexes, FTS shadow tables, and
   `sqlite_sequence`), open a private `AppDatabase` on it, run the existing
   M03 plan + delete/insert/rebuildFts transaction THERE, close; write covers
   into `<gen>/covers/` (fail closed now — nothing live is at risk; when the
   archive has no covers, copy the active covers dir to preserve today's
   behaviour); vault: archive-borne pair written + validated in the new dir, or
   the retained pair (+ biometric blob) copied from the active dir under the
   FIFO; write `COMPLETE`; check `scope.isCurrent`; `activate`. Any failure →
   discard the builder dir, typed `Failure`, live state untouched.
4. **Session safety:** `CatalogueReplacementGuard.protectReplacement` gains
   `endsSession` (restore always passes it: the vault's location changes even
   when its key does not); the guard locks in `finally`, deterministic inside
   the FIFO. `VaultSessionController.build` switches to `ref.watch` of the
   store so ANY generation change also rebuilds it (belt and braces).
5. Remove `stageRestore`/`StagedVaultInstall`; remove `RestoreBackup.coversDir`.
6. Copy pass (schedule doc item): restore page mentions the library logo lives
   with covers; README/PRIVACY sentence on crash-safe restore.

## Decision points

1. **Settled:** Option 1 (generation directories + atomic pointer).
2. **Settled: (a) end-to-end.** Still pause on the triggers in point 4.
3. Any `git commit`, `rm`, package add, or schema change needs separate approval
   of the exact invocation. None requested at this checkpoint. No new packages
   are expected (`path`, `drift`, `sqlite3` already present).
4. Pause triggers even under end-to-end: `createInBackground` misbehaving in
   tests; any need to touch Rust or the FRB surface; any assumption above
   failing. (`VACUUM INTO` verified through the Drift executor 2026-09-08:
   works from memory and background-isolate sources, preserves `user_version`,
   `sqlite_sequence` and FTS shadow tables; refuses to run inside a
   transaction; refuses an existing output file.)

## Steps

Slice 1 (storage foundation):
- [x] Verify handoff/HEAD, cited evidence, consumers, primitives, and tests.
- [x] Baseline gates on pinned SDK 3.44.2 (recorded in Result).
- [x] Obtain the design decision (Option 1).
- [x] Obtain execution-mode approval (a — end-to-end).
- [x] Failing tests first: adoption (all artifacts + DB companions, idempotent
      mid-way, fresh install), dangling/incomplete `CURRENT`, GC scope,
      `activate` temp+rename, incomplete builder never activates
      (`test/core/storage/data_generations_test.dart`, 18 tests;
      `active_data_generation_test.dart`, 4 tests — provider re-pointing).
- [x] Implement `DataGenerations` + `ActiveDataGeneration` provider; re-point
      `appDatabase`/`coversDir`/`vaultStore`/`createBackupUseCase`/`restoreBackup`.
- [x] build_runner; full gates; re-read every edited region.

Slice 2 (atomic restore) — completed in the same session:
- [x] Fault-injection regressions at every boundary
      (`test/features/backup/atomic_restore_test.dart`, 14 tests): wrong
      passphrase, guard refusal, FTS failure, lease lost before switch, corrupt
      legacy DB, cover write failure, pointer-switch failure, missing
      borrowers.db, crash-simulated complete-but-unswitched generation; success
      paths for vault-free, vault-bearing (old bio blob dropped), retained vault
      + bio blob carried over, covers carried when archive has none, two
      restores chained in one session.
- [x] Rebuild `RestoreBackup` around a builder generation (`VACUUM INTO`
      snapshot → replace inside a transaction on the copy → covers → vault →
      `COMPLETE` → lease check → atomic `activate`); discard on any failure.
- [x] `CatalogueReplacementGuard.protectReplacement(endsSession:)`; session
      controller locks in `finally`; `_storeFuture` now `ref.watch`es the store
      so a generation switch rebuilds the session (3 + 1 new tests).
- [x] Delete `stageRestore`/`StagedVaultInstall`; replace with
      `installRestored`/`copyFrom` on the domain port (6 store tests).
- [x] Fixtures: `generation_fixture.dart`; `ReplacementHarness(generations:)`
      runs the real chain; restore/controller/page/matrix tests updated; the
      publish fixture pins `coversDirProvider` (it used `Directory('.')`).
- [x] Copy pass: restore page (logo, re-lock, all-or-nothing), README, PRIVACY.
- [x] Gates, coverage, generation idempotency, privacy/diff review, Result.
- [ ] Commit approval for the explicit manifest below.

## Out-of-scope observations

- A library logo referenced by settings can dangle after a covers-bearing
  restore that lacks it (pre-existing; settings are not in backups). Record for
  N07/N04; only the copy is adjusted here.
- `RestoreController` is autoDispose and uses `ref` after awaits (N11).
- The Drift catalogue uses the default rollback journal; WAL is not needed for
  this fix and is not changed.
- Windows/Linux/iOS/macOS unlink-while-open semantics differ; Android-only
  shipping (M18) is assumed and documented in code.
- Startup recovery is synchronous file IO in `ActiveDataGeneration.build`
  (one listing + a handful of renames once per install). Fine today; if a
  device ever accumulates many stray `gen-*` dirs it would be noticeable.
- `restore_backup_test.dart` still contains the `_FtsFailingDb` fault helper;
  it now targets the builder catalogue (kept; still the S10 regression).
- The M02 review also mentioned "rollback uses a truncating write" — that code
  path (`StagedVaultInstall.commit`) is deleted, not patched.
- A stray `data/` directory appeared at the repo root during the session,
  created by `publish_controller_test.dart`'s `Directory('.')` docs override
  hitting the new generation chain; the fixture is fixed, the directory is
  untracked and needs a §6-approved `rm -rf data/` (contains only an empty
  `gen-000001/COMPLETE` + `CURRENT`).

## Result

Baseline (pinned SDK 3.44.2, HEAD `db4d040` = `origin/main`, tracked tree clean;
untracked only `.fvm/`, `astra-review.md`, `fix-schedule.md`): analyzer
**0 issues**; format **371 files / 0 changed**; Flutter **1152 passed / 0 failed**
(log `/tmp/pitak-m02-flutter-baseline.SGmgFb`, 0 `[E]` markers); Rust
**32 passed / 0 failed**, 2 expected ignored.

Final gates: analyzer **0 issues**; format **378 files / 0 changed**; full
Flutter `--no-pub --coverage` **1192 passed / 0 failed** (+40; log
`/tmp/pitak-m02-flutter-final.V6dzOk`, re-run after the last fixture fix
`/tmp/pitak-m02-flutter-final2.DsVOqv`, 0 `[E]` markers); Rust **32 passed /
0 failed**, 2 expected ignored; `git diff --check` clean. build_runner rerun:
the 3 affected generated files byte-identical; only DI + session hash diffs
and the new `active_data_generation.g.dart`.

Regression evidence: this finding was **static** (no reviewer reproduction);
the fault-injection suite is the "would have caught it" test set. The M03
restore regressions were re-run on the REAL storage chain (session guard +
generation switch) and additionally assert the retained vault moved with the
catalogue and the session ended. Test iterations fixed along the way: a fresh
device has no catalogue file yet (skip `VACUUM INTO`, let Drift create the
schema); Riverpod `updateOverrides` cannot add overrides (test rewritten with
a mutable store path); the harness's flat vault files were being adopted by
the real generation chain (pinned `coversDirProvider` where the flat layout is
intended).

Coverage: `data_generations.dart` **104/113 (92.04%)**;
`active_data_generation.dart` **7/7**; `restore_backup.dart` **146/156
(93.59%)** (was 106/139); `vault_store.dart` **72/72 (100%)**;
`vault_session_controller.dart` **310/339 (91.45%)**; `restore_controller.dart`
**14/14**. Project **7582/11194 (67.73%)**. Line coverage is not proof of
power-loss behaviour: crash points are simulated by throwing at boundaries and
by hand-building on-disk states for startup recovery, not by killing the
process. `dart:io` cannot fsync a directory; the pointer rename's durability
relies on filesystem metadata ordering (documented in code).

Privacy/diff review: no new logging, network, telemetry, permissions, crypto,
schema or dependency changes (grep of all added production lines: none).
Vault bytes are only ever copied as opaque files under the M03 FIFO; the
generation store never reads them. Old generations are deleted right after a
switch and on every startup, so no second plaintext copy lingers (§3.1).
OSS credit: LevelDB `db/filename.cc` `SetCurrentFile` (BSD-3-Clause) for the
`CURRENT` temp+rename pattern and its remove-obsolete-files recovery rule;
SQLite temp-then-rename durability (already credited in `vault_store.dart`);
`VACUUM INTO` verified through Drift on 2026-09-08.

## Proposed commit manifest — exactly 31 paths (awaiting approval)

Stage only these paths; never the local review, schedule, `.fvm/` or the stray
`data/` directory. One buildable M02 fix with its regression tests, docs and
working plan.

```sh
git add -- \
  PLAN.md \
  PRIVACY.md \
  README.md \
  lib/core/di/providers.dart \
  lib/core/di/providers.g.dart \
  lib/core/storage/active_data_generation.dart \
  lib/core/storage/active_data_generation.g.dart \
  lib/core/storage/data_generations.dart \
  lib/features/backup/application/restore_controller.dart \
  lib/features/backup/infrastructure/restore_backup.dart \
  lib/features/backup/presentation/pages/restore_page.dart \
  lib/features/library/domain/catalogue_replacement_guard.dart \
  lib/features/vault/application/vault_session_controller.dart \
  lib/features/vault/application/vault_session_controller.g.dart \
  lib/features/vault/domain/vault_artifacts_store.dart \
  lib/features/vault/infrastructure/vault_store.dart \
  test/core/storage/active_data_generation_test.dart \
  test/core/storage/data_generations_test.dart \
  test/features/backup/atomic_restore_test.dart \
  test/features/backup/catalogue_replacement_restore_test.dart \
  test/features/backup/generation_fixture.dart \
  test/features/backup/migration_matrix_test.dart \
  test/features/backup/restore_backup_test.dart \
  test/features/backup/restore_controller_test.dart \
  test/features/backup/restore_page_test.dart \
  test/features/library/catalogue_replacement_integration_test.dart \
  test/features/library/replacement_harness.dart \
  test/features/library/replacement_test_guard.dart \
  test/features/publish/publish_controller_test.dart \
  test/features/vault/vault_session_controller_test.dart \
  test/features/vault/vault_store_test.dart
git commit -m "fix(backup): atomic restore via data generations (M02)"
```
