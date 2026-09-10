# PLAN.md — Session 14: M16 — settings controller mutation race

## Understanding

`fix-schedule.md` §1 NEXT = **M16** (astra-review.md, Major): every
`SettingsController` setter takes a snapshot of the whole `AppSettings`,
awaits the repository write, then **replaces the entire state with that
snapshot + its one change**. Two setters in flight at once each captured the
same "before" snapshot; whichever repository write finishes *last* wins and
silently undoes the other one's field in memory.

Security-relevant instance (reviewer's): `setAppLockBiometric(true)` completes
first → state shows the lock ON; a slower `setThemeMode` that started earlier
completes second and publishes its snapshot with `appLockBiometric: false`.
Disk says ON (both prefs keys are written correctly — the repository writes
one key per setter), memory says OFF. `AppLockController._gateEnabled` reads
memory → the gate does not fire on the next background/resume until restart.

Fix the foundation: setters must not be able to overwrite each other's fields.

## Privacy & threat notes

- **Data touched:** non-secret app settings only (`AppSettings` carries no
  secrets by design; see `app_settings.dart` header). No new data collected,
  nothing leaves the device, no new permissions.
- **Who is affected by the bug:** the device user, unknowingly. The failure is
  fail-*open* (lock appears enabled, is not) — the wrong direction for this
  codebase (repo AGENTS.md §2.7 "fail closed").
- **What stops it after the fix:** state can only be published by one setter
  at a time, and each publishes a patch on the *then-current* state.
- **Threat model:** no attacker needed — an ordinary fast double-tap or a
  Settings page that fires two writes on one gesture triggers it. Not remotely
  exploitable; local misconfiguration only.

## Investigation notes (verified this session, HEAD `4bc4fb5`)

- `lib/features/settings/application/settings_controller.dart` — read in
  full. Review's `:31–41, 45–60, 164–170` are stale line numbers but the
  pattern is unchanged: every setter does
  `current = state.valueOrNull ?? defaults` → `_update(persist, current.copyWith(...))`
  → `_update` awaits persist → `state = AsyncData(next)` (whole snapshot).
  Ten mutating entry points: `setThemeMode`, `setLibraryName`,
  `getOrCreateLibraryId`, `setLibraryId`, `regenerateLibraryId`,
  `setMaintainerName`, `setLibrarySort`, `setLoadRemoteCovers`,
  `setPublishContact`, `setLibraryLogo`, `setAppLockBiometric`.
  `getOrCreateLibraryId` / `regenerateLibraryId` bypass `_update` and assign
  `state` directly from a captured snapshot — same race.
- `lib/features/settings/domain/settings_repository.dart` — every write is
  `Either<Failure, Unit>` (M17, Session 7). One prefs key per setter, so the
  **on-disk** state is never clobbered — the race is purely in-memory. That
  narrows the fix to the controller; the repository is correct.
- `lib/core/app_lock/app_lock_controller.dart:139–141` — `_gateEnabled` reads
  `settingsControllerProvider.valueOrNull?.appLockBiometric ?? true`. Reads
  memory, not disk → confirms the reviewer's impact chain is live.
- `lib/core/widgets/book_cover.dart:129` — listens to the `loadRemoteCovers`
  bit via `select` (Session 13, D-2). A reverted bit would also silently drop a
  consent the user just granted. Same class of impact, non-security.
- Existing FIFO in the repo: `lib/features/library/domain/cover_file_coordinator.dart`
  (BasicLock from `synchronized`, MIT, credited), reused verbatim in
  `remote_cover_materializer.dart:44–75`. Same shape will be used here —
  "one blessed way" (repo AGENTS.md §0).
- Existing tests: `test/features/settings/settings_test.dart` (450 lines)
  covers each setter happy path, the throw path, and M17 false-write path
  with `_FailingSettingsRepo` / `_FalseWriteStore`. **No test has two setters
  in flight.** There is no fake repo with *controllable completion* — one must
  be added (a `Completer`-driven repo).
- Baseline gates: analyzer 0 issues; format 388 / 0 changed; Rust 32 passed
  (2 expected ignored); Flutter full suite — see Result (run in background).

## Proposed approach

**Serialise all mutations through one FIFO AND patch on current state.**
Two layers, each cheap, together closing every path:

1. **FIFO (`_tail` BasicLock, same code as `CoverFileCoordinator`).** Every
   mutating method runs inside `_serialised(() async {...})`. Overlapping
   calls queue; the second one starts only after the first has published its
   state. This alone fixes the reviewer's scenario.
2. **Patch-on-current, not snapshot-replace.** `_update` takes a
   `AppSettings Function(AppSettings current)` patch instead of a pre-built
   `next`, and applies it to `state.valueOrNull ?? defaults` *after* the
   awaited persist. Defence in depth: even if a future caller bypasses the
   FIFO, a setter can only touch its own field.

Why both, in beginner terms: the queue makes writes take turns; the patch
makes each write change only what it owns. Either alone would fix today's
bug; both together mean the next person editing this file can't reintroduce
it by forgetting one of them.

`getOrCreateLibraryId` and `regenerateLibraryId` (return `Either<Failure,
String>`) join the same queue and patch the same way — they are mutations.

**Not changing:** the repository, `AppSettings`, any caller, any UI, error
semantics (`AsyncError` on left/throw, last-known-good preserved — M17).

OSS reference: `synchronized` 3.4.0+1 `BasicLock` (Tekartik, MIT) — already
credited in `cover_file_coordinator.dart`; this session adapts the same
7 lines, no new dependency.

## Decision points (one at a time)

- **D1 — Design:** (a) FIFO + patch-on-current (recommended, above); (b) FIFO
  only; (c) patch-on-current only. Trade-off: (b)/(c) are each ~half the
  diff, but each leaves one way to reintroduce the bug. (a) is ~30 lines.
- **D2 — Execution mode:** (a) end-to-end, or (b) pause at each step.

## Steps

- [x] 1. Baseline gates recorded: analyzer 0, format 388/0, Rust 32, Flutter **1309 passed**.
- [x] 2. D1 = (a), D2 = (a).
- [x] 3. Regression tests in `test/features/settings/settings_test.dart`:
      a `_GatedSettingsRepo` whose writes complete via `Completer`s the test
      controls. Test A (reviewer's): start `setThemeMode(light)`, start
      `setAppLockBiometric(true)`, complete the lock write, complete the theme
      write → state must have BOTH `light` and `appLockBiometric == true`.
      Test B: same with `getOrCreateLibraryId` + `setLibraryName`. Test C:
      a failing write in the queue does not block or revert a later write.
      **Prove red on HEAD** (run before touching the controller). → A and B red
      on HEAD (`Expected: true / Actual: <false>`; `Expected: 'aaa…' / Actual: ''`);
      C passes on HEAD by design (it guards the queue against deadlock/revert
      after a left, a property the new code must keep).
- [x] 4. Implement in `settings_controller.dart`: `_tail` FIFO, `_update`
      becomes patch-based, all 11 mutators go through it. Update the class
      doc to explain both layers in plain language.
- [x] 5. build_runner: only the `_$settingsControllerHash` line changed.
- [x] 6. Gates green; `settings_controller.dart` 62/62 lines.
- [x] 7. `fix-schedule.md` updated.
- [ ] 8. Commit — awaiting approval.

## Out-of-scope observations

- `_GatedSettingsRepo` in `settings_test.dart` is the first controllable-
  completion settings fake; `test/core/app_lock/app_lock_controller_test.dart`
  has a `_ScriptedSettingsRepo` that could adopt it for a lock-toggle race
  test at the `AppLockController` level. Not needed for M16 (the controller
  is the single write path); noted for N11.
- The test-repo `started` counter is unused by the three tests (kept as a
  seam for a future "second write does not START until the first published"
  assertion). Harmless; remove if it bothers the linter later.
- 12 test files each hand-roll a `SettingsRepository` fake (see grep in
  fix-schedule archive S14 notes). A shared `test/support/` fake would cut
  ~300 lines. Hygiene, not a finding; not done.

## Result

- **M16 fixed.** `SettingsController` mutations now (1) run one at a time
  through a `_tail` FIFO (BasicLock shape, credited: synchronized 3.4.0+1,
  Tekartik, MIT, via `CoverFileCoordinator`) and (2) publish a `copyWith`
  patch on the state *after* the write rather than a snapshot captured before
  it. Both `Either<Failure, String>` minting methods go through the same
  queue via `_mintLibraryId`. Error semantics unchanged (M17: left/throw →
  `AsyncError`, last-known-good preserved).
- Diff: `settings_controller.dart` rewritten (196 lines, each setter now a
  2-lambda one-liner; class doc explains both layers in plain language);
  `.g.dart` hash only; `settings_test.dart` +170 (gated fake + 3 tests).
  No repository, domain, UI or caller change. No new dependency.
- Evidence: tests A + B **red on HEAD, green after**; full suite **1312
  passed / 0 failed** (`/tmp/pitak-s14-flutter-final.txt`, 0 `[E]`); Rust 32;
  analyzer 0; format 388/0; `git diff --check` clean; coverage
  `settings_controller.dart` 62/62, project 68.56%.
- Honest limits: the race was never reproduced on a device (reviewer's
  finding was static; the test reproduces it deterministically with a gated
  fake). No device pass this session. `_serialised` is not reentrant — a
  mutator calling another mutator would deadlock; none does today, and the
  field doc says so.
- Privacy: no new data, permission, network or log path. Narrow diff scan:
  no `print`/`log`/`http`/`Uri`/`Platform` added.
