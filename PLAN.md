# PLAN.md — current task

Roadmap: `fix-schedule.md`. Session 3, M07 complete; uncommitted.

## Understanding
- Fix M07: asynchronous vault work must never undo a later lock or provider
  invalidation. Serialize session operations so concurrent work cannot reuse
  a disposed secret or publish snapshots out of order.
- Start HEAD: `e266aca`. Working tree matched the handoff: only the intentionally
  untracked `astra-review.md` and `fix-schedule.md` existed before planning.
- Scope: vault session lifecycle and its regression tests. No auto-lock timeout,
  new dependencies, cryptography, schema changes, or unrelated review fixes.

## Privacy & threat notes
- A late unlock/read can expose borrower PII after the user explicitly locks;
  a late unlock can also retain its passphrase again.
- Lock must immediately forget visible data and invalidate earlier work, without
  waiting behind slow crypto, biometric prompts, or writes.
- Secrets stay in existing wipeable buffers; cleanup must include incoming,
  queued, and late-returned secrets, not only the currently held passphrase.
- Native calls already dispatched have their own scoped copies. Rejecting a
  completion does not cancel or roll back its native write. Do not claim it does.
- No new collection, logging, network, permissions, or persistent data fields.

## Investigation notes (before implementation)
- Review evidence matched `vault_session_controller.dart:364–371` and
  `:505–570`: lock has no invalidation; unlock and refresh publish unconditionally.
- `_mutate` captures the held secret before awaiting the store, then reuses it
  after a write. `purgeLoansForBook` also reuses it across multiple awaited deletes.
- `enable`, passphrase change, and biometric enrollment/unlock have additional
  await boundaries before retaining secrets or changing artifacts.
- Existing `test/features/vault/vault_session_controller_test.dart` exercises
  ordinary success/failure, but not delayed completions or concurrent calls.
- Read the repository contract, FFI implementation, `SecretBytes`, artifact-store
  contract/implementation, state types, DI providers, vault page callers, restore
  controller/tests, and Rust unlock/create/rewrap/biometric entry points.
- `SecretBytes.useAsync` defensively copies and wipes in finally; FFI uses it.
  Rust retains the vault key internally and wipes owned passphrase buffers.
- Successful restore invalidates the session (`restore_controller.dart:54`).
  Its disposal hook must invalidate pending work even if Riverpod rebuilds the
  same notifier. Failed restore deliberately does not invalidate today (M02).
- Baseline on pinned Flutter 3.44.2: analyzer 0 issues; format 335 files,
  0 changed; full Flutter suite 819 passed, 0 failed; Rust 30 passed, 0 failed,
  2 expected ignored real-archive tests. No fallback test run was needed.

## Proposed approach (with OSS references)
- Give every submitted session operation a generation identity. Lock and
  `ref.onDispose` invalidate prior generations. Check validity after each await
  before using held secrets, starting another side effect, or publishing state.
- Serialize session-changing operations through one private FIFO mechanism.
  Capture identity at submission, not when dequeued, so old queued requests do
  not run in a newly unlocked session. Lock must bypass this queue.
- Centralize secret ownership/cleanup and stale-operation failure handling using
  the existing `Either<Failure, T>` contract; no raw exceptions or PII in UI errors.
- Preserve artifact integrity when canceling creation/enrollment: simply throwing
  away a created DB's only wrapped-key blob is not a safe cancellation strategy.
  Check these boundaries explicitly; pause if they require a broader storage fix.
- Verified OSS models: Riverpod 2.6.1 `lib/src/async_notifier/base.dart:350–364`
  ignores canceled future completions; `synchronized` 3.4.0+1
  `lib/src/basic_lock.dart` chains operations with a completer released in finally.
  Adapt these lifecycle/serialization patterns without adding a package or
  implementing cryptography. Both sources were read from the local package cache.

## Decision points
- User approved end-to-end execution. Pause only for unforeseen decisions,
  security trade-offs, or actions requiring exact-command approval.
- Any discovered need for storage recovery, restore coordination, dependency
  changes, or a security trade-off requires a separate pause and explanation.
- Commit only code/tests and PLAN.md, by explicit paths, after exact-command
  approval. Never stage the local review or schedule files.

## Steps
- [x] Verify handoff, rules, cited evidence, callers/callees, and baseline gates.
- [x] Write this plan and record the planning checkpoint in fix-schedule.md.
- [x] Receive execution-mode approval: end-to-end.
- [x] First add and run a failing delayed-unlock → lock → complete regression.
      Failed on old code: expected VaultLocked, actual VaultUnlocked.
- [x] Add deterministic completion-controlled tests for write/refresh, queued
      operations, multi-delete, rekey, biometric paths, disposal/invalidation,
      and lock before store resolution. Assert secret cleanup and no stale calls.
- [x] Implement generation invalidation and serialization with explicit ownership.
- [x] Generate annotated code; only the expected provider hash changed;
      a second generation run made no further tracked changes.
- [x] Focused tests 83 passed; full Flutter tests 880 passed; analyzer 0 issues;
      format 336 files / 0 changed; Rust 30 passed, 2 expected ignored.
- [x] Scoped security/diff review: no new logging, remote calls, plaintext
      secret storage, dependencies, permissions, or FFI/schema changes.
- [x] Update Result and schedule. No staging or commit performed.

## Out-of-scope observations
- M02 still owns crash-safe restore and failed-restore cache clearing. A session
  token does not coordinate an already-running native write with file replacement.
- Existing biometric hardware-gating claims and non-Android capture protection
  remain M08/M18. No promise of stronger hardware protection in this task.
- build_runner warns SDK language 3.12.0 is newer than its analyzer's 3.9.0;
  generation and analysis succeed. Dependency upgrades belong to N15; none made.

## Result
M07 implemented and verified. Lock/disposal invalidate submitted operations and
wipe held/pending input secrets immediately. A shared FIFO prevents overlapping
session writes, refreshes, rekey, and biometric operations; checks after awaits
prevent stale secret reuse and publishing. Late biometric secrets are wiped;
rollback failures are returned, and cleanup keeps its queue slot until finished.

Creation detail: after a lock, an already-created empty encrypted DB still gets
its wrapped-key blob, but no secret or rows are retained. After disposal/restore
invalidation, an old creation cannot write a blob into the replacement lifetime;
an abandoned empty creation uses the existing orphan-recovery path. Native calls
already dispatched are not cancellable. Cross-file restore coordination is M02.

Changes: vault_session_controller.dart (+ generated hash), the original failing
regression in vault_session_controller_test.dart, and 60 additional tests in
vault_session_race_test.dart (real Dart FFI adapter, synthetic native completions).
Total: 61 new tests; full suite 819 → 880. Controller line coverage **269/298
(90.27%)**, measured with `flutter test --no-pub --coverage`. Rust: 27 unit +
3 fixture tests passed; 2 real-archive tests remain intentionally ignored.
No device biometric prompt or physical-device lifecycle run was performed.

PLAN.md and fix-schedule.md updated; all edits re-read, diff check clean.
No changes committed. Next task: M01; obtain commit approval separately.
