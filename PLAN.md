# PLAN.md — Session 23: N07 (part 1 of 2) — merge: honest summary, preserved warnings, namespace adoption coordinated with data + settings

## Understanding

`astra-review.md` N07: "Merge cannot resolve conflicts and can partially change
namespace state." Re-read this session; the review's line numbers are stale,
every cited pattern is live in current code:

1. **Conflicts are counts only.** `merge_page.dart:245-279` `_ResultView`
   prints "`N book(s)` appear on both devices but differ … reviewing each one
   … is coming in a later update." `MergeLibraryUseCase.applyResolution`
   (`merge_library_use_case.dart:275-316`, keep-mine / take-theirs / keep-both)
   is implemented and unit-tested but has **no caller in `lib/`** (grep).
   `MergeConflict` / `PossibleDuplicate` (`library_merge_engine.dart:56-115`)
   already carry both `Book`s + `matchedBy` / `similarity` — enough for a
   review row. → **Session 24** (UI + controller `resolve`).
2. **Join adopts the namespace BEFORE the data lands.**
   `merge_library_use_case.dart:200-218` `applyJoin`: `setLibraryId` →
   `setLibraryName` → `_applyEngineMerge`. If `insertAll` fails the device now
   carries the OTHER library's ID with none of its books; the next merge of the
   same file passes the ID gate and auto-applies the union with no Join
   decision — exactly the "failed Join can still change future merge identity"
   the reviewer describes. `applyOverwrite` (`:230-277`) already does data
   first, ID second.
3. **Settings state goes stale.** The use case writes through
   `SettingsRepository` directly (`_settings.setLibraryId/…Name`), bypassing
   `SettingsController` — the keep-alive in-memory `AppSettings` (M16's single
   serialised writer). `MergeController._merged` (`merge_controller.dart:185`)
   invalidates only `libraryControllerProvider`. After a Join/Overwrite the
   drawer header (`app_drawer.dart:35`), the library AppBar
   (`library_page.dart:58`), the Settings name field (`settings_page.dart:108`),
   the PDF/JSON export envelope name (`export_controller.dart:97-100`) and the
   publish site title (`publish_controller.dart:92`) all keep showing the OLD
   library name until restart. (The ID self-heals on the next export/QR because
   those call the controller's `getOrCreateLibraryId`, which re-reads prefs.)
4. **Parse warnings are discarded.** `merge_library_use_case.dart:152-155`
   surfaces `payload.parseErrors` ONLY when zero books parsed; a file with 99
   good rows and 1 invalid row (M15 rejects, not coerces) silently drops the
   row. `payload.warnings` (M15 truncations / dropped covers) is never read.
   `MergeResult` and `MergeDiffersDecision` have no field for either, so
   nothing can be shown after Join/Overwrite.
5. **Overwrite is reported as a zeroed merge.** `merge_controller.dart:135-147`
   maps a successful Overwrite to `MergeResult(added: 0, identical: 0, …)`;
   the page then says "Merge complete / Books added: 0 / Already matched: 0"
   for a catalogue that was just REPLACED. Reviewer: "Do not describe a partial
   merge as complete without explaining omissions."
6. **S12/S13 N07 note — `_mergeCover`** (`library_merge_engine.dart:351`).
   After M09 a device with remote covers ON materialises `https://…` into
   `covers/<uuid>.jpg`; a device with it OFF keeps the URL. Merging the two:
   `remoteUrlOf(local photo)` = null vs `remoteUrlOf(url)` = the URL → a
   conflict. Under M09's precedence (`resolveIncomingCover`), take-theirs
   keeps the local photo anyway, so this conflict is unresolvable-to-anything
   and pure noise. `library_merge_engine_test.dart:300` currently LOCKS the
   opposite ("local cover vs remote cover is a real conflict"). → D2.

Scope split (the schedule allots 2 sessions):
- **Session 23 (this):** items 2–6 — application-layer foundation + honest
  result surface. Everything a review UI will need must be true first.
- **Session 24:** item 1 — per-row conflict / possible-duplicate review
  (controller `resolve`, `applyResolution` guard for in-file collisions whose
  `local` is a not-yet-persisted row, widget tests).

## Privacy & threat notes

- No new data collected, no network, no new permissions. Merge stays local.
- Who can influence this path: whoever hands the user a `.json` file. Threat is
  **namespace poisoning** (item 2): a crafted file that makes `insertAll` fail
  (e.g. a UNIQUE collision the planner misses) after the ID was adopted leaves
  the device silently re-identified. Fix: data first, ID only after success.
- Surfaced text: `parseErrors` / `warnings` are our OWN messages built by
  `_RowReader` (M15) — row number, a ≤40-char title so the user can find the
  row (`pitaka_json_importer.dart:333-338`, verified in step 4 when a test
  assumption said "no title"), and the field names at fault. The INVALID
  VALUES are never echoed. `MergeResult` copy must stay that way (step 9).
- Settings writes stay behind the M16 FIFO (D1-b) — no second writer race.
- `debugPrint`/logging: none added.

## Investigation notes

- `MergeController` (S20, N11): keep-alive, `_running`, sealed `MergeUiState`
  (`Idle/Running/NeedsDecision{applyFailure, applying}/Done/Failed`).
  `_apply` KEEPS the decision on a failed apply so the user can retry or pick
  the other option — that contract assumes NOTHING landed. Once the union has
  landed, offering "Replace my library" again would replace an already-merged
  catalogue → a post-data adoption failure must go to `MergeDone` with an
  explicit omission, not back to the decision (D3).
- `SettingsController` (M16): `_serialised` FIFO + `_update(persist, patch)`
  patch-on-current; `setLibraryId`/`setLibraryName` are `Future<void>` and fold
  failures into `AsyncError` — no `Either` for a caller to branch on.
  `_mintLibraryId` returns `Either<Failure, String>` and patches state.
  Precedent for a controller implementing a domain port consumed by a use
  case: `VaultSessionController implements CatalogueReplacementGuard`
  (`vault_session_controller.dart:53-54`), wired in `providers.dart:884`
  via `ref.read(vaultSessionControllerProvider.notifier)`.
- Riverpod 2.6.1 (pub-cache, not memory): `when/maybeWhen` default
  `skipLoadingOnRefresh = true` (`common.dart:674`) — an `invalidate` of a
  keep-alive AsyncNotifier keeps the previous value visible in `maybeWhen(data:)`
  consumers; `AsyncNotifierProviderElement.create` caches the notifier
  (`_notifierNotifier.result ??=`, `base.dart:534`) so the FIFO survives a
  rebuild. (Relevant only if D1-a is chosen.)
- `ImportPayload.warnings` (M15) exists and is populated by
  `PitakaJsonImporter`; `ImportSummary` + `import_page.dart:215-229` already
  render "Issues" + "Adjustments" — the merge summary should mirror that copy.
- The JSON importer never sets `Book.id` → incoming rows have `id == emptyId`.
  `PossibleDuplicate.local` for an in-file collision is such a row
  (`library_merge_engine.dart:236-240`) → `takeTheirs` would `update()` id 0
  (NotFound). Session-24 guard; recorded here so it is not forgotten.
- Existing tests: `merge_library_use_case_test.dart` (646 lines,
  `_FakeBooks`/`_FakeSettings implements SettingsRepository`),
  `merge_controller_test.dart` (361, own fakes, `makeContainer` with live
  listener), `merge_page_test.dart` (269, `ReplacementSettings` from
  `test/features/library/replacement_harness.dart`), engine test (405).
  `merge_controller_test.dart:241` "a failed applyJoin keeps the decision" does
  NOT assert settings unchanged — the hole item 2 lives in.

## Proposed approach

### A. `applyJoin`: data first, namespace second, honest result
- Run `_applyEngineMerge` FIRST. Only on `Right` adopt the incoming ID + name.
- Adoption failure after data success → `Right(MergeResult(…, namespace:
  MergeNamespaceOutcome.adoptionFailed))` — the books are there, the page says
  so and explains the omission ("… but this device could not adopt the
  library's identity; the next merge from this library will ask you to Join
  again"). Self-healing: the next Join finds every row identical and only
  adopts. (D3.)
- `applyOverwrite` → returns `Either<Failure, MergeResult>` with
  `replaced: true, added: incoming.length` and the same namespace outcome.
  The controller's zeroed mapping goes away.

### B. Settings written through the single writer (D1)
- (b, recommended) new domain port `LibraryNamespace` in
  `lib/features/settings/domain/library_namespace.dart`:
  `Future<Either<Failure, LibraryIdentity>> current()` (id via
  get-or-create + current name) and
  `Future<Either<Failure, Unit>> adopt({required String id, required String
  name})`. `SettingsController implements LibraryNamespace`: `current()` awaits
  its own `future` then `_mintLibraryId`; `adopt()` runs BOTH prefs writes in
  ONE `_serialised` turn and patches state once. `MergeLibraryUseCase` drops
  its `SettingsRepository` dependency for the port; `providers.dart` wires
  `ref.read(settingsControllerProvider.notifier)` (the replacement-guard
  precedent). Result: no code path writes library identity behind M16's FIFO,
  and every watcher (drawer, AppBar, export, publish) sees the new name at
  once.
- (a, alternative) keep the repo writes; `MergeController._merged` also
  `ref.invalidate(settingsControllerProvider)` when a namespace was adopted.
  Smaller diff; leaves the second writer in place.

### C. Warnings and skipped rows preserved
- `MergeResult` gains `skippedRows: List<String>` (= `parseErrors`, rows NOT
  imported) and `adjustments: List<String>` (= `warnings`). `MergeDiffersDecision`
  carries both so Join/Overwrite forward them. `call()` keeps the existing
  "zero books + errors → Left" rule.
- `_ResultView` renders them with the Import page's wording ("Issues" /
  "Adjustments"), plus: a "Library replaced — N books now on this device" head
  for `replaced`, the namespace omission line, and — until Session 24 — the
  review count with copy that no longer promises "a later update" but says the
  rows were left unchanged and can be reviewed below (S24 adds the rows).

### D. Engine cover rule (D2)
- (a, recommended) `mergeEquals` treats a LOCAL cover on one side vs a REMOTE
  https cover on the other as equal (M09 precedence makes take-theirs a
  no-op for that field; after materialisation both devices show the same
  picture). Flip `library_merge_engine_test.dart:300` with the M09 rationale;
  keep "remote vs remote differ" and "remote vs null" as conflicts.
- (b) leave as is; note remains open on the N07 row.

### E. Tests (regression first, red on HEAD)
- `merge_library_use_case_test.dart`: failed `insertAll` on Join → settings
  UNCHANGED (behaviour-red); adoption fails after data → `Right` with
  `adoptionFailed` + books present (behaviour-red: HEAD returns Left);
  1 good + 1 invalid row → `skippedRows` (compile-red); truncated field →
  `adjustments`; decision path carries both; overwrite returns `replaced`
  result (compile-red).
- `merge_controller_test.dart`: after `applyJoin` the `settingsControllerProvider`
  state shows the new id + name (behaviour-red); overwrite → `MergeDone`
  with `replaced` (compile-red).
- `settings_test.dart` (D1-b): `adopt` is one FIFO turn — a slow theme write
  in flight cannot revert id/name (M16 gated fake).
- `library_merge_engine_test.dart` (D2-a): flipped case + a new "remote vs
  remote still conflicts" guard already exists (`:278`).
- `merge_page_test.dart`: summary shows Issues/Adjustments; overwrite shows
  the replaced head; namespace omission line.

OSS reference: none new — the `Either`-typed port + controller-implements-port
shape is this repo's own `CatalogueReplacementGuard`; result-with-omissions is
the same idea as `ImportSummary.warnings` (M15).

## Decision points

- **D1 — settings coordination:** (a) invalidate `settingsControllerProvider`
  after adoption · (b) `LibraryNamespace` port implemented by
  `SettingsController`, use case stops touching `SettingsRepository`.
  → **(b)** (user, 2026-09-12)
- **D2 — cover rule:** (a) local photo vs remote https = equal · (b) keep the
  conflict. → **(a)** (user)
- **D3 — adoption fails AFTER data landed:** proposed **`MergeDone` with
  `adoptionFailed` omission** (staying on the decision would re-offer
  "Replace my library" against an already-merged catalogue).
  → **confirmed** (no objection).
- **D4 — execution mode:** end-to-end, or pause at each decision point?
  → **end-to-end** (user)

## Steps

- [x] 1. Protocol start: repo matches S22 handoff (`98f1d5b` = origin/main;
  only the recorded 2-line PLAN.md tick-off dirty). Baseline gates recorded.
- [x] 2. Re-read N07 + all cited files; evidence re-verified (above).
- [x] 3. Ask D1, D2 (one at a time), confirm D3, ask D4 — b / a / confirmed / end-to-end.
- [x] 4. Regression tests written and proved red on HEAD (E).
- [x] 5. Domain: `LibraryNamespace` port (D1-b) / engine cover rule (D2-a).
- [x] 6. `SettingsController implements LibraryNamespace` (+ `.g.dart`).
- [x] 7. `MergeLibraryUseCase`: result types, data-first Join, typed overwrite
  result, warnings forwarded; `providers.dart` wiring.
- [x] 8. `MergeController`: drop the zeroed mapping; `MergePage._ResultView`
  honest summary.
- [x] 9. Privacy pass on the lib diff (no values from the file in copy, no
  logs). Gates: analyze, format, `build_runner` LAST, full suite detached,
  cargo.
- [ ] 10. fix-schedule.md §1/§3/§5; commit approval with explicit paths.

## Out-of-scope observations

- (S24) per-row review UI; `applyResolution` must refuse `takeTheirs` when
  `local.id == Book.emptyId` (in-file collision).
- `_mergeIntoExisting`-style hand-built books in `applyResolution.takeTheirs`
  bypass `Book.validate` (S17 obs. 2) — S24 candidate when the rows get a UI.
- `ReplacementSettings` / `_FakeSettings` ×2 hand-roll `SettingsRepository`
  (17 files now) — a shared `test/support/` fake keeps growing in value.

## Result

**N07 part 1 implemented end-to-end; uncommitted, pending commit approval.**

- Gates: analyzer **0**; format **404 / 0 changed**; Flutter `--coverage`
  **1487 passed / 0 failed** (`/tmp/pitak-s23-flutter-final2.txt`, 0 `[E]`;
  a final3 confirmation run after the last non-annotated edit is recorded in
  fix-schedule.md §5); cargo **32 passed**, 2 ignored; `build_runner` re-run
  LAST → only the 3 expected `.g.dart` diffs (`providers`, `merge_controller`,
  `settings_controller`), `.fvmrc`/`.gitignore` untouched; `git diff --check`
  clean; domain-purity gate green (`library_namespace.dart` imports only
  fpdart + `core/error`).
- Coverage: project **71.42%** (+0.29 vs S22); `merge_library_use_case.dart`
  137/141, `merge_controller.dart` 44/47, `merge_page.dart` 111/121,
  `library_merge_engine.dart` 114/117, `settings_controller.dart` 75/84 (the
  misses are the pre-existing `setPublishContact`/`setLibraryLogo` lines).
- Regression evidence (red on HEAD behaviour): **12 tests red** against a
  HEAD-shaped graft of the use case (identity adopted before the union,
  adoption failure → Left, warnings dropped) + HEAD's engine file; 1 engine
  test red on HEAD directly (`Expected: true / Actual: <false>`); 2 new tests
  green by design (no-ID file, zero-rows-still-Left). Widget summary tests
  and `settings_test.dart` `adopt`/`current` tests are compile-red on HEAD
  (new API).
- What changed, plain English:
  1. **Join no longer changes who you are before it has your books.** The
     union is inserted first; only then is the other library's ID + name
     adopted. A failed insert leaves the device's identity untouched
     (`merge_library_use_case_test.dart` "a failed Join insert leaves the
     local identity untouched": `adoptCalls == 0`).
  2. **One owner for the library identity.** New domain port
     `LibraryNamespace` (`settings/domain/library_namespace.dart`);
     `SettingsController implements` it: `current()` (mint/read via the M16
     FIFO + loaded name) and `adopt(id, name)` (both prefs writes in ONE
     queued turn, one state patch). The use case depends on the port; the
     `settingsRepositoryProvider` dependency is gone from
     `mergeLibraryUseCaseProvider`. Every screen watching settings sees the
     new name at once (`merge_controller_test.dart` "after applyJoin the
     settings controller shows the new id + name").
  3. **Honest result.** `MergeResult` gained `replaced`, `skippedRows`,
     `adjustments`, `namespace` (`MergeNamespaceOutcome`), `hasOmissions`,
     `withNamespace`; `MergeDiffersDecision` carries `skippedRows`/
     `adjustments` so Join/Overwrite forward them. `applyOverwrite` returns a
     `MergeResult` (`replaced: true`, `added` = the repository's real insert
     count). The controller's zeroed Overwrite mapping is deleted.
  4. **D3:** books landed + identity write failed → `Right` with
     `adoptionFailed`; the page says the next merge will ask to Join again.
     `catalogue_replacement_failure_test.dart` "settings ID failure" flipped
     from expecting a Left to expecting the omission — the old expectation
     WAS the reviewer's "partial namespace state" bug.
  5. **Page** (`merge_page.dart` `_ResultView`): "Library replaced / Books
     now on this device: N" vs "Merge complete / Books added / Already
     matched"; "Not imported" (M15 row messages) and "Adjustments" (Import
     page wording); the identity-omission line; review copy no longer
     promises "a later update".
  6. **Engine (D2-a):** `_coversEqual` — a local file on either side is never
     a cover conflict against a remote URL (M09 precedence makes take-theirs
     a no-op there); remote-vs-different-remote and remote-vs-nothing stay
     conflicts. `CoverPaths.remoteUrlOf` remains the single classifier.
- Test fixtures: `merge_library_use_case_test.dart` `_FakeSettings` →
  `_FakeNamespace implements LibraryNamespace` (+ `insertAllFailure` on
  `_FakeBooks`; the M03 case now builds through the real provider over
  `ReplacementSettings`); `merge_controller_test.dart` builds the use case
  over the container's REAL `SettingsController` (production wiring);
  `merge_page_test.dart` likewise + `_DoneController` for summary rendering;
  `replacement_harness.dart` exposes `namespace` and `overwrite()` returns
  `Either<Failure, MergeResult>`.
- Privacy pass: lib diff adds no print/log/http/Uri/Platform; the one new
  `StorageFailure` reason carries `e.runtimeType` only; summary text is
  M15's own row/field messages (short title + row number + field names, the
  invalid values never echoed — verified against `_RowReader.label`).
- Not done (Session 24): per-row conflict / possible-duplicate review UI
  (`applyResolution` + controller `resolve`; guard `takeTheirs` when
  `local.id == Book.emptyId`); no device verification (static finding,
  reproduced deterministically in tests).

### Commit paths (17, explicit)

`lib/core/di/providers.dart`, `lib/core/di/providers.g.dart`,
`lib/features/import_export/application/merge_controller.dart`,
`lib/features/import_export/application/merge_controller.g.dart`,
`lib/features/import_export/application/merge_library_use_case.dart`,
`lib/features/import_export/presentation/pages/merge_page.dart`,
`lib/features/library/domain/merge/library_merge_engine.dart`,
`lib/features/settings/application/settings_controller.dart`,
`lib/features/settings/application/settings_controller.g.dart`,
`lib/features/settings/domain/library_namespace.dart` (new),
`test/features/import_export/merge_controller_test.dart`,
`test/features/import_export/merge_library_use_case_test.dart`,
`test/features/import_export/merge_page_test.dart`,
`test/features/library/catalogue_replacement_failure_test.dart`,
`test/features/library/library_merge_engine_test.dart`,
`test/features/library/replacement_harness.dart`,
`test/features/settings/settings_test.dart`, `PLAN.md`.
