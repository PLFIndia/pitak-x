# PLAN.md — Session 20: N11 — long-running UI actions: lifecycle ownership, mounted/ref guards, typed terminal results

## Understanding

`astra-review.md` N11: several long-running UI actions outlive their widgets
without safe completion handling. Re-verified against current code (review line
numbers stale; patterns confirmed live):

**Verified Riverpod 2.6.1 semantics (pub-cache source, not memory):**
- A widget's `ref.read/watch/invalidate` after unmount **throws**
  `StateError('Cannot use "ref" after the widget was disposed.')`
  (`flutter_riverpod-2.6.1/lib/src/consumer.dart:549` `_assertNotDisposed`,
  called by `read` at `:620`).
- A notifier's `state =` after provider dispose is silently accepted (no
  listeners notified) — `riverpod-2.6.1/lib/src/framework/element.dart:128`
  `setState` has no mounted check. So a disposed autoDispose controller loses
  its terminal state AND a re-entered page builds a fresh idle element while
  the old operation still runs → a second concurrent operation becomes
  possible.

**Live instances (current code):**
1. `restore_page.dart` `_runRestore` (`:138-147`): after
   `await ...restore()` it calls `ref.read(restoreControllerProvider)` and
   `ref.read(libraryControllerProvider.notifier).refresh()` +
   `wishlistControllerProvider.notifier).refresh()` with **no `mounted`
   guard** → StateError if the page was popped mid-restore; the refresh is
   lost exactly when it matters (page gone, underlying list stale).
2. `RestoreController` (`restore_controller.dart`): no `keepAlive` link, no
   `_disposed`/`_running` guard, no catch-all. Mid-flight dispose loses the
   terminal state and permits a second concurrent restore on re-entry; an
   unexpected throw from the restorer propagates to the page's unawaited
   future. `ImportController` (same repo) already has the fix pattern.
3. `import_page.dart` `_importText`/`_importFile` (`:50-87`): post-await
   `ref.read(importControllerProvider).hasValue` + `_refreshLists()` with no
   `mounted` guard; `openFile`/`_hasZipMagic`/`readPickedFileBounded` plugin
   throws are uncaught.
4. `merge_page.dart`: (a) still length-then-`readAsString` (`:64-70`) instead
   of the shared `readPickedFileBounded` (S10 note — a lying `length()` buys
   a full unbounded buffer); (b) `setState` in the `res.match` callbacks is
   unguarded — a pop mid-merge throws inside `try`, and the `on Object`
   handler then throws AGAIN calling `setState` on the dead widget;
   (c) `_join`/`_overwrite` have no catch — a use-case throw escapes as an
   unhandled async error; (d) `_refreshLibrary()` fire-and-forget from
   callbacks reads `ref` after possible unmount.
5. `create_backup_page.dart` `_createAndSave` (`:34-81`): mounted checks are
   present, but there is **no try/catch** — a throwing share plugin or
   use-case-provider build failure leaves `_busy = true` forever (stuck
   spinner) and an unhandled async error.
6. `RemoteCoverMaterializer._materialize` (`remote_cover_materializer.dart:96-105`):
   a refused/failed download's `Left` is silently swallowed — no diagnostic
   surface anywhere (S13 note: a future archive.org naming change would
   silently re-break covers).

**In-repo fix patterns to reuse (AGENTS.md: borrow, don't invent):**
- `ImportController._run`: `_running` + `_disposed` flags, `ref.keepAlive()`
  link closed in `finally`, catch-all → `AsyncError(UnexpectedFailure)`.
- `PublishController.publish`: keepAlive link with the rationale comment.
- `ExportController` + `ExportPage`: typed terminal result returned to the
  page; page does `if (!mounted) return;` before `setState`.
- `RestoreController` already invalidates `vaultSessionControllerProvider`
  on success — the precedent for controller-side post-success invalidation.

## Privacy & threat notes

No new data leaves the device; no new storage; no secrets touched. The
cover-download diagnostic is `debugPrint` (debug/profile builds only, local
stderr) carrying a book id + failure type — no URLs, no PII, no telemetry
(AGENTS.md §3.4/§6.2). Restore remains an authoritative overwrite; the
keepAlive change only guarantees an in-flight restore finishes and its
terminal state is not lost — it does not make restore cancellable (M02 made
the switchover atomic; abandoning mid-way is not possible anyway).

## Investigation notes

- `restore_page.dart`, `import_page.dart`, `merge_page.dart`,
  `create_backup_page.dart` read in full (current HEAD `1e1eeae`).
- `restore_controller.dart`, `import_controller.dart`,
  `publish_controller.dart`, `export_controller.dart`,
  `remote_cover_materializer.dart`, `bounded_file_read.dart` read in full.
- Riverpod 2.6.1 disposal semantics verified in pub-cache source (above).
- Picker test seam: `FileSelectorPlatform.instance` fake returning
  `XFile.fromData` (existing pattern in `restore_page_test.dart:62`,
  `import_page_test.dart:104`, `merge_page_test.dart:24`).
- `restore_controller_test.dart` harness: real M02 storage chain over a temp
  docs dir, fake vault — reusable for the mid-flight-dispose test.
- `merge_library_use_case.dart` API: `call(text) → Either<Failure,
  MergeOutcome>` (`MergeMerged(MergeResult)` / `MergeDiffersDecision`),
  `applyJoin(decision) → Either<Failure, MergeResult>`,
  `applyOverwrite(decision) → Either<Failure, Unit>`.
- Both list controllers are autoDispose AsyncNotifiers → controller-side
  `ref.invalidate` is safe with or without listeners.
- No `create_backup_page_test.dart` exists yet; `fileShareServiceProvider`
  is the share seam (override-able, see `export_page_share_test.dart`).

## Proposed approach

1. **RestoreController** — adopt the ImportController pattern: `_running` +
   `_disposed` guards, `ref.keepAlive()` for the duration of `restore()`,
   catch-all `on Object` → `AsyncError(UnexpectedFailure('Restore failed.'))`.
   On success, invalidate `libraryControllerProvider` +
   `wishlistControllerProvider` **in the controller** (next to the existing
   vault-session invalidation) so the lists refresh even when the page is
   gone. `inspectArchive` stays stateless/thin.
2. **restore_page.dart** — `_runRestore` drops all post-await `ref` reads
   (the controller now owns the refresh); wrap `_pickArchive` in try/catch →
   `_inspectError` with the existing safe copy.
3. **ImportController** — on success, invalidate both list controllers in
   `_run` (same ownership move); page drops `_refreshLists` and the post-await
   `ref.read(...).hasValue` checks.
4. **import_page.dart** — try/catch around the pick/read path → `_fileError`
   safe copy; no post-await `ref` use left.
5. **merge_page.dart + new `MergeController`** — a `@riverpod` AsyncNotifier
   (keepAlive during runs, `_running` guard) owning the merge state machine:
   idle → running → `MergeOutcome` (merged / needs-decision) → applying →
   done/failed, with safe-copy failures only. It invalidates
   `libraryControllerProvider` on every successful apply. The page becomes a
   renderer of the controller state (decision card + result counts unchanged
   visually) and reads the picked file via `readPickedFileBounded` +
   `utf8.decode(allowMalformed: true)` (same as import page).
6. **create_backup_page.dart** — try/catch/finally around the whole
   `_createAndSave` body: unexpected throw → `_busy = false` + existing
   generic error copy (guarded by `mounted`). No controller: the operation
   must NOT survive navigation (the share sheet needs the user present), so
   page scope is the correct ownership — only the failure paths were missing.
7. **RemoteCoverMaterializer** — on a `Left` from the use case, `debugPrint`
   the book id + failure runtime type (debug builds only; no URL/PII). The
   M09 user-facing decision ("a missing thumbnail is not an error they can
   act on") stands; this is a developer diagnostic only.

## Regression tests (prove red on HEAD first)

- `restore_controller_test.dart` +N11 group: (a) mid-flight dispose — start
  a gated restore, drop all listeners, complete → re-listen shows the
  terminal summary and the vault-session invalidation still ran (red on HEAD:
  element disposed → fresh idle state); (b) a second `restore()` while one is
  in flight is refused (red on HEAD: both run); (c) a throwing restorer →
  `AsyncError(UnexpectedFailure)`, passphrase still wiped (red on HEAD:
  throw propagates); (d) success invalidates library+wishlist controllers
  controller-side (moves the N04 page-level test to the right owner).
- `restore_page_test.dart` +navigate-away widget test: start a gated restore,
  pop the page, complete → no exception, no crash (red on HEAD: StateError
  from `ref.read` after unmount).
- `import_page_test.dart` +navigate-away widget test (same shape; red on
  HEAD at the post-await `ref.read`).
- `merge_page_test.dart` reworked onto `MergeController` + new cases:
  navigate-away mid-merge (red on HEAD: setState-after-dispose), throwing
  use case → safe error copy (red: unhandled), lying-length pick rejected via
  the bounded read (red: `readAsString` loads it), decision survives… (state
  now lives in a keepAlive-linked controller).
- `create_backup_page_test.dart` (new): throwing share plugin → error copy +
  busy reset (red on HEAD: unhandled + stuck spinner); unavailable →
  existing copy; success → "Backup saved.".
- `remote_cover_materializer_test.dart` +1: a `Left` from the use case is
  reported through `debugPrint` (intercepted) with the book id (red on HEAD:
  nothing printed).

## Decision points

- **D1 — post-success list refresh ownership (restore + import):**
  (a) move the invalidation INTO the controllers (restore already invalidates
  the vault session there — same pattern); refresh happens even when the page
  was popped mid-operation. (b) keep page-level refresh + `mounted` guards
  (popped page → underlying list stale until re-entry). Recommend (a).
- **D2 — merge ownership:** (a) new `MergeController` owning the state
  machine + library invalidation (mirrors ImportController; page becomes a
  renderer; merge_page_test reworked). (b) page-driven flow kept; only
  guards + catch + bounded read. Recommend (a) — the write must be owned
  above the page, and the decision state surviving navigation is a real UX
  win. (b) leaves "result lost + stale list on pop" by design.
- **D3 — create-backup scope:** (a) minimal page fix (try/catch/finally +
  mounted) — the operation should NOT survive navigation because the share
  sheet needs the user; (b) new CreateBackupController mirroring
  ExportController. Recommend (a).
- **D4 — cover-refusal diagnostic:** (a) debug-only `debugPrint` (book id +
  failure type) in the materializer now; typed refusal reasons stay with N08.
  (b) defer all of it to N08. Recommend (a).
- **D5 — execution:** end-to-end, or pause at each decision point?

## Steps

- [ ] 1. Baseline gates recorded (analyze 0; format 397/0; flutter suite
  detached; cargo 32).
- [ ] 2. Write the red regression tests (controller + page level).
- [ ] 3. Prove them red on HEAD (stash/swap technique as in S14–S19).
- [ ] 4. RestoreController: keepAlive + guards + catch-all + controller-side
  list invalidation.
- [ ] 5. restore_page.dart: slim `_runRestore`, try/catch `_pickArchive`.
- [ ] 6. ImportController: controller-side list invalidation on success.
- [ ] 7. import_page.dart: drop post-await ref reads; try/catch pick path.
- [ ] 8. MergeController + merge_page.dart rework + bounded read.
- [ ] 9. create_backup_page.dart: try/catch/finally.
- [ ] 10. RemoteCoverMaterializer debugPrint diagnostic.
- [ ] 11. build_runner (annotated controllers added/changed) → check only
  expected `.g.dart` diffs; revert `.fvmrc`/`.gitignore` if touched.
- [ ] 12. Gates: analyze / format / full flutter suite (detached) / cargo.
- [ ] 13. Update fix-schedule.md (state block, N11 row, §5 log); ask commit
  approval with explicit path list.

## Result

**Decisions:** D1 (a) controller-owned refresh · D2 (a) MergeController ·
D3 (a) minimal create-backup page fix · D4 (b) cover-refusal diagnostic
deferred to N08 · D5 end-to-end.

**Red-proof:** 11 behaviour-red on HEAD (restore_controller ×4, restore_page
×1, import_page ×1, merge_page ×3, create_backup_page ×2) + merge_controller
compile-red. Two red-proof iterations needed: (1) the navigate-away widget
tests were timing-flaky — the pop ANIMATION must settle (widget fully
disposed) before the gate opens, otherwise the continuation races disposal;
(2) `XFile.fromData.readAsString` never throws (maps bytes to code points),
so the malformed-UTF8 merge test needed a `_StrictXFile` that strictly
decodes like the real path-backed picker file. All pre-existing tests in the
touched files stayed green throughout.

**Changes:**
- `restore_controller.dart`: `_running`/`_disposed` guards, keepAlive link,
  catch-all → `AsyncError(UnexpectedFailure)`, controller-side invalidation
  of vault session + library + wishlist on success; a refused call still
  wipes the handed-over passphrase.
- `restore_page.dart`: `_runRestore` no longer touches `ref` after the
  await; `_pickArchive` wrapped in try/catch → safe copy.
- `import_controller.dart`: success invalidates both list controllers.
- `import_page.dart`: `_refreshLists` and post-await `ref.read` gone; pick
  path wrapped in try/catch.
- `merge_controller.dart` (new): MergeUiState sealed hierarchy
  (Idle/Running/NeedsDecision/Done/Failed), keepAlive, `_running` guard,
  typed terminal states on every path, library invalidation on every
  successful apply; a failed apply keeps the decision with `applyFailure`.
- `merge_page.dart`: renders MergeUiState; bounded read via
  `readPickedFileBounded` + lenient decode (replaces length-then-
  `readAsString`); confirm dialog copy unchanged (dynamic localIsEmpty).
- `create_backup_page.dart`: try/catch around the whole run → safe copy +
  busy reset; operation deliberately stays page-scoped (share sheet needs
  the user).
- Tests: restore_controller_test +N11 group (4), restore_page_test
  +navigate-away (the N04 page-level refresh test moved to controller
  level — its `_SuccessController` fake bypassed the new ownership),
  import_page_test +1, merge_page_test +3, merge_controller_test (new, 6),
  create_backup_page_test (new, 4).

**Gates:** analyze 0 · format 401/0 · flutter **1441 passed / 0 failed**
(/tmp/pitak-s20-flutter-final.txt) · cargo 32 (2 expected ignored) ·
coverage **70.91%** (+0.61). Touched files: restore_controller 34/34,
import_controller 36/36, merge_controller 44/48, merge_page 83/104,
create_backup_page 53/59, restore_page 140/158, import_page 77/88.
Lib-diff scan: no print/log/http/Uri/Platform added; `git diff --check`
clean.

**Found while implementing (out of scope, recorded):** cold `build_runner`
runs on HEAD already drift two committed hashes (`providers.g.dart`
pendingSnapshot, `restore_controller.g.dart`) — pre-existing codegen drift,
not caused by this change; the cold-build-correct hashes are included in
this commit. `XFile.fromData.readAsString` never throws (byte→code-point
map) — picker-seam tests needing strict UTF-8 failure must bring their own
XFile. `ExportController` has the typed-result pattern but no keepAlive
link — same mid-flight-dispose class as N11, not cited by the review;
candidate follow-up.
