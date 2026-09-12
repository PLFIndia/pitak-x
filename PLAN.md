# PLAN.md — Session 24 — N07 part 2 of 2: per-row conflict review UI

Roadmap: `fix-schedule.md` §1 (NEXT). Finding: `astra-review.md` N07
("conflicts/possible duplicates are counts only, with no way to inspect or
apply the implemented resolutions"). Part 1 (S23, `418d17a`, unpushed by
user decision — rides with this session's commit) fixed the namespace order,
the honest summary, warnings, and the cover rule. This session wires the
already-implemented `MergeLibraryUseCase.applyResolution` to a per-row UI.

## Understanding

After a merge, `MergeResult.conflicts` (`MergeConflict{local, incoming,
matchedBy}`) and `MergeResult.possibleDuplicates` (`PossibleDuplicate{local,
incoming, similarity}`) reach the page inside `MergeDone`, but `_ResultView`
(`merge_page.dart:250-320`) renders only a count line. The user cannot see
what differs or act on it. `applyResolution` (use case `:365-395`) exists,
is unit-tested (5 cases), and has NO caller in `lib/` (grep, this session).

What "done" means here: every review item is shown as a card with what
differs (or why it looks like a duplicate), with actions keep-mine /
take-theirs / keep-both that call `applyResolution` through the controller,
per-item progress + typed failure + retry, library refresh after every
write, and honest labels for the in-file-collision case where "take theirs"
is impossible.

## Privacy & threat notes

- Data shown: this device's catalogue fields and the fields of a file the
  user picked themselves. Displayed on-device only; nothing logged
  (`kDebugMode` or otherwise), nothing leaves the device. FLAG_SECURE is
  app-wide (`MainActivity.kt:13`), so the review cards are screenshot-safe
  like every other page. Notes/location (private, stripped at publish) may
  appear in a diff — that is the user's own data on their own screen.
- Threat: a crafted file plants values that crash the review card. Incoming
  rows already passed M15 (`PitakaJsonImporter` → `Book.validate`), and this
  session adds `Book.validate` as the LAST gate before `update`/`insert`
  inside `applyResolution` (defence in depth, S17 obs. 2). Display uses
  `maxLines` + ellipsis so an 8000-char note cannot blow up the layout.
- Failure copy: `_messageFor` shows `ValidationFailure.message` (our own
  text) and a generic line for every other type — no raw exception text.
- Fail closed: one resolution in flight at a time; a new file pick is refused
  while a row write is running; a resolution completion is dropped if the
  controller has moved on (generation check).

## Investigation notes (verified this session, file:line current)

- `merge_library_use_case.dart:365-395` `applyResolution`: `takeTheirs` →
  `_bookRepo.update(incoming.copyWith(id: local.id, bookUid: local.bookUid,
  coverUrl: resolveIncomingCover(...)))`; `keepBoth` → `insert(_freshCopyOf
  (incoming))`. No `Book.validate`. No `emptyId` guard.
- `drift_book_repository.dart:148-150`: `update` with `id == emptyId` →
  `left(NotFoundFailure())` — the in-file collision would surface as a
  misleading "not found" instead of a clear refusal.
- `library_merge_engine.dart:236-240`: for a key collision the engine stores
  the KEY HOLDER as `PossibleDuplicate.local`; for an in-file collision that
  is the earlier incoming row — `id == emptyId`, never persisted under that
  object. `PossibleDuplicate` has no `reason`; `similarity == 1.0` is also a
  legitimate fuzzy score (identical title+author tokens), so kind cannot be
  inferred from the score.
- `mergeEquals` (`:291-311`) is a hand-written `&&` chain over 18 fields; no
  per-field diff exists anywhere. Cover equality is `_coversEqual` (S23).
- `merge_controller.dart`: `MergeDone(result)` is terminal; `_apply` uses a
  keep-alive link + `applying` flag; `mergeText` guards only `_running`.
  Nothing stops `mergeText` during a future row write, and a stale
  completion would write into whatever `MergeDone` is current.
- `merge_page.dart:250-320` `_ResultView`: one `bodySmall` line for the
  review count. Page `busy` = `MergeRunning` only.
- Tests: `merge_controller_test.dart` (`makeContainer` over the REAL
  `SettingsController`, `_FakeBooks` with `update` returning `right(book)`
  WITHOUT storing — must store for these tests); `merge_page_test.dart`
  (`_DoneController` pins `MergeDone`; `_Books` fake has only `getAll`);
  `merge_library_use_case_test.dart` `applyResolution` group (5) with
  `_FakeBooks.update` → NotFound on a missing id; engine test (427 lines).
- Precedents: `import_page.dart:185-233` `_Summary` (list-in-column copy
  style); `UpdateBookUseCase` (`update_book_use_case.dart:28-30`) is the
  in-repo model for `Book.validate(...).match(errors → ValidationFailure
  (errors.first.userMessage), ok → repo.update(ok))`.

## Proposed approach

1. **Domain (engine)** — additive:
   - `enum DuplicateReason { similarTitle, identityKey }` +
     `PossibleDuplicate.reason` (default `similarTitle` so existing
     constructors compile; the engine sets `identityKey` at `:236-240`).
   - `enum MergeField` (the 18 compared fields) + `MergeFieldDifference
     {field, local, incoming}` + `List<MergeFieldDifference>
     mergeDifferences(Book a, Book b)`. `mergeEquals` iterates the SAME
     private field-spec list with early return — one source of truth, no
     allocation on the hot path, engine tests pin equivalence.
2. **Use case** — `applyResolution.takeTheirs` refuses `local.id ==
   Book.emptyId` with a `ValidationFailure` naming the situation (no repo
   call); both writing branches pass the built book through
   `Book.validate` (model: `UpdateBookUseCase`).
3. **Controller** — review state lives INSIDE `MergeDone` (one owner, same
   keep-alive lifecycle): `MergeReviewItem{index, kind, local, incoming,
   similarity, status}` with sealed `MergeReviewStatus` = `ReviewPending |
   ReviewApplying | ReviewResolved(resolution) | ReviewFailed(failure)`;
   `MergeDone.review` built from the result; `MergeDone.openCount` /
   `isResolving`. New `resolve(int index, MergeResolution)`: refuses unless
   `MergeDone`, item open, nothing else applying, not disposed; keep-alive
   link for the write; generation counter so a completion after a new
   `mergeText` is dropped; `mergeText` refuses while resolving; library
   invalidated after a successful `takeTheirs`/`keepBoth` (not `keepMine`);
   catch-all → `ReviewFailed(UnexpectedFailure)`.
4. **Page** — `_ResultView` gains a "Needs your review" section: one
   `_ReviewCard` per item (headline by kind; differing fields as
   "Label: yours → theirs" for conflicts, both titles + similarity for
   fuzzy, plain-English explanation for a key collision); actions
   `Keep mine` / `Take theirs` / `Keep both` (for an in-file collision:
   `Skip` / `Add as a separate book`, no take-theirs); applying → disabled +
   spinner; failed → safe copy + retry; resolved → one status line. The
   file-pick button is disabled while a row write runs.
5. `build_runner` LAST (controller is `@riverpod`), gates, PLAN Result,
   schedule §1/§3/§5.

OSS reference: the card-per-item review with tri-state actions mirrors the
Kotlin origin's intent (`LibraryMergeEngine` port comments); no external
code copied.

## Decision points

- **D1 — `Book.validate` inside `applyResolution`?** (a) yes, both writing
  branches (recommended — M15 rule "every ingress passes the gate", cost is
  ~6 lines + 2 tests); (b) defer. → **(a)** (user, this session)
- **D2 — in-file collision `takeTheirs`:** refuse in the use case AND hide
  the button (fix-schedule NEXT already says "must refuse"; resolving the
  real persisted row by uid/ISBN would make "take theirs" mean overwriting
  a row the same file just added — not what the label promises). Taken as
  settled; flagged here, not re-asked.
- **D3 — concurrency:** one resolution at a time, file pick refused while a
  row write runs. Design choice (fail closed, simplest testable state);
  flagged, not asked.
- **D4 — execution mode:** end-to-end or pause at each decision point. →
  **(a) end-to-end** (user, this session); pause only if an assumption
  breaks.

## Steps

- [x] 1. Regression tests, proved red on HEAD: use case `N07 — guards` (4)
  **behaviour-red** — collision `takeTheirs` returned `NotFoundFailure` (the
  misleading path), copyCount 0 / year 0 written unvalidated, evil-host
  cover written verbatim. Engine (8), controller (11), page (6): compile-red;
  every analyzer error names a new symbol (`review`, `resolve`,
  `MergeField`, `DuplicateReason`, `reason`, `openCount`, `isResolving`,
  `MergeReviewKind`, `withItemStatus`, `Review*`, `mergeDifferences`,
  `canTakeTheirs`) — no unrelated error.
- [x] 2. Engine: `DuplicateReason`, `MergeField`, `MergeFieldDifference`,
  `mergeDifferences`, `mergeEquals` over the shared `_mergeFieldSpecs` list
  (equivalence pinned by a test over all 18 fields). Domain purity green.
- [x] 3. Use case: `emptyId` guard (typed `ValidationFailure`, no repo call)
  + `Book.validate` on both writes via `_validated` (normalised book lands).
- [x] 4. Controller: `MergeReviewItem`/`MergeReviewKind`/`MergeReviewStatus`
  inside `MergeDone` (`openCount`, `isResolving`, `withItemStatus`),
  `resolve(index, resolution)` with keep-alive + one-at-a-time + `mergeText`
  refused while resolving. The planned generation counter was DROPPED: since
  `mergeText` is refused while a row is applying, the state cannot leave
  `MergeDone` under a resolution — a counter would guard an unreachable
  path ("no magic"). `.g.dart` regenerated.
- [x] 5. Page: `_ReviewSection` + `_ReviewCard` (headline/explanation by
  kind, field diffs via `mergeDifferences` with `maxLines`, tri-state
  actions, collision → Skip / Add as a separate book, applying → spinner,
  failed → safe copy + retry), pick button disabled while resolving; header
  doc updated; count-only line removed.
- [x] 6. Privacy pass on the lib diff: no print/debugPrint/log/http/Uri/
  Platform added; the only `toString()` is `_num` on an `int` for display;
  failure → copy goes through `_failureLine`/`_messageFor` (own
  `ValidationFailure.message`, generic line otherwise); card text is the
  user's own catalogue values with `maxLines` + ellipsis.
- [x] 7. `build_runner` LAST (1 `.g.dart` hash, `.fvmrc`/`.gitignore`
  untouched); analyze 0; format 404/0; Flutter **1516 passed / 0 failed**
  (`/tmp/pitak-s24-flutter-final.txt`, EXIT=0, 0 `[E]`); cargo 32 (2
  expected ignored); `git diff --check` clean.
- [ ] 8. `fix-schedule.md` §1/§3 (N07 → DONE ledger)/§5; commit approval with
  explicit paths; push approval (carries `418d17a`).

## Out-of-scope observations

- `takeTheirs` on a FUZZY duplicate keeps the local uid and drops the
  incoming uid, so the next merge of the same file re-surfaces the pair
  (similarity 1.0). Pre-existing Kotlin-port semantics; a uid-adoption
  option is a separate design question.
- `MergeController._running` and `MergeNeedsDecision.applying` and the new
  resolve guard are three flags for "busy" — a single `_busy` state would be
  cleaner; left alone to keep the diff reviewable.
- Long review lists (100+ conflicts) render as one Column inside the page
  `ListView` — N10 territory (pagination).
- `test/features/import_export/*` fakes: `_FakeBooks` now exists in three
  files with slightly different `update` semantics — the S14–S23 shared
  `test/support/` fake note keeps growing.

## Result

**N07 part 2 implemented end-to-end; uncommitted, pending commit approval.**
With part 1 (`418d17a`) this closes N07.

- Gates: analyzer **0**; format **404 / 0 changed**; Flutter `--coverage`
  **1516 passed / 0 failed** (+29 vs S23; 0 `[E]`); cargo **32 passed**, 2
  expected ignored; `git diff --check` clean; `build_runner` run last → one
  expected `merge_controller.g.dart` hash. Coverage **71.89%** (+0.47);
  `merge_controller.dart` 110/113, `merge_library_use_case.dart` 143/147,
  `merge_page.dart` 215/235, `library_merge_engine.dart` 165/168.
- Regression evidence: use-case guards **behaviour-red on HEAD** (collision
  `takeTheirs` → `NotFoundFailure`; copyCount 0 / year 0 / evil-host cover
  written unvalidated); engine/controller/page groups compile-red with only
  new-symbol errors. All 29 new tests green after the change; the 5
  pre-existing `applyResolution` tests unchanged and green.
- Behaviour now: after a merge, every conflict / possible duplicate is a
  card. Conflicts list the differing fields "yours → theirs" (via the new
  `mergeDifferences`, which shares its field list with `mergeEquals`).
  Fuzzy duplicates show both titles + a percentage. A key collision against
  a persisted local row explains the situation and keeps all three actions.
  An in-file collision (local never persisted) offers only Skip / Add as a
  separate book — and the use case refuses `takeTheirs` for it with a typed
  message even if called. One row writes at a time; the file picker is
  disabled meanwhile and `mergeText` is refused; a failed row keeps its
  actions for a retry; a completed write refreshes the library list from
  the controller (keep-mine refreshes nothing). Both writing branches pass
  the built book through `Book.validate` (D1-a).
- Deviation from the plan, recorded in step 4: no generation counter
  (unreachable path once `mergeText` is refused while resolving).
- No device verification (static finding, reproduced deterministically in
  tests).

### Commit paths (explicit, never `-A`)

```
lib/features/import_export/application/merge_controller.dart
lib/features/import_export/application/merge_controller.g.dart
lib/features/import_export/application/merge_library_use_case.dart
lib/features/import_export/presentation/pages/merge_page.dart
lib/features/library/domain/merge/library_merge_engine.dart
test/features/import_export/merge_controller_test.dart
test/features/import_export/merge_library_use_case_test.dart
test/features/import_export/merge_page_test.dart
test/features/library/library_merge_engine_test.dart
PLAN.md
```
