# Magazines remediation — handoff after S9

> **Historical snapshot, superseded as active handoff on 2026-10-25:** S10 is
> complete. Resume with `magazineIssues.md` **S11**; current status lives in
> that file's Part D and in `magazines-progress.md`. This document preserves
> the after-S9 evidence and the original S10 restart instructions.

- **Date:** 2026-10-25
- **Branch:** `magazines`
- **Status at this snapshot:** S9 complete; S10 had **not** started.
- **Remediation HEAD:** `518960c` (this handoff is a documentation-only follow-up)
- **Release state:** R1 remains blocked until `magazineIssues.md` S1–S11 are Done.

## 1. Commits and current state

| Item | Commit | Result |
|---|---|---|
| Reviewed baseline | `e2dd250` | Exact review starting point; only `magazineIssues.md` was untracked. |
| S0 — baseline, fixtures, release hold | `68d4d0d` | Baseline recorded, shared fixtures added, R1 explicitly gated on remediation. |
| S1 — canonical identity and kind integrity | `c72b0cc` | M4, H6, and M6 fixed with schema v6 and regression coverage. |
| S2 — calendar-day semantics | `62e79cb` | M10 and M12 fixed with schema v7, dual-timezone regression coverage, and immediate restore/overwrite reprojection. |
| S3 — atomic writes and removed-series guard | `d8b1bab` | M1 and M9 fixed with one outer issue-write transaction, exact real-Drift race coverage, and removed-series add/scan refusal. |
| S4 — plain JSON reconciliation | `df774d5` | H1, H2, H3, and M3 fixed with one series-resolution map, cross-kind refusal, D6 skip claims, and a file-level trim-collision refusal. |
| S5 — v4 bundles, bounded backups, split counters | `29e412d` | H4, M2, and L5 fixed with a lossless bundle, series-cover lifecycle, reader-bound enforcement at creation, and separate entry/row restore counters. |
| S6 — distinct-ISSN merge identity | `ea3ccf3` | H5 fixed by suppressing exact-title fallback only for different valid ISSNs, with planner/review controls and real-Drift issue-link coverage. |
| S7 — cover ownership and async forms | `1aecff0` | H7, M7, M8, M11, and L2 fixed with structural owner/URL dedup, fresh-owner materialization, race-safe forms, detail fallback, and generation-guarded prefill. |
| S8 — publish redaction and total hashing | `8d4aa1f` | M5 and M13 fixed with exact Other redaction, UTF-8 cover keys, canonical link refusal, and real viewer runtime coverage. |
| S9 — shared refresh and kind-neutral UI | `518960c` | L1, L3, and L4 fixed with live magazine refresh, recoverable filtered-empty states, neutral generic item wording, and synchronized guide/mockup/native copy. |

The working tree was clean immediately after `518960c`. The database remains at **schema v7** (S9 adds no schema change). No release version bump, tag, or publish step has been performed.

## 2. Completed work

### S0

- Confirmed 2,884 non-golden Flutter tests passed on the reviewed baseline.
- Confirmed generated code, scoped analysis, and formatting were clean.
- Rust format, clippy, dependency checks, and release tests passed: 35 passed, 2 environment-gated ignored.
- Added shared raw-row, periodical/issue, and controllable-async fixtures.
- Changed the bundle fixture to use `DriftPeriodicalRepository` on the same real in-memory Drift database as items and wishlist; 77 focused tests passed.
- Added the R1 dependency on all remediation sessions in `docs/plans/otherDetails.md`.
- The maintainer confirmed Pitaka-JSON v4, `.pitabak` W2, and published W3 artifacts have stayed only on test devices/this unreleased branch. No extra format versioning is needed for S2 on that account.

### S1 — M4, H6, M6

- Added one shared `canonicalPeriodicalUid` rule: trim surrounding whitespace only and preserve non-ASCII identities.
- Applied it through `Periodical.validate`, `CatalogueItem.validate`, JSON/archive ingress, D6 lookups, repository minting, and persistence companions.
- Added typed canonical-UID collision refusal before periodical writes; bulk replacement validates incoming identities before deleting old rows.
- Added schema v6 with an atomic repair migration. It validates every final periodical UID and numbered/bound D6 key before its first write and aborts safely on ambiguity.
- Generated `drift_schema_v6.json`, `schema_v6.dart`, and the updated schema registry.
- Added `getAllForInterchange()` using the existing joined SQL and ordering. Unknown kinds and detail-less issues fail there, while display reads remain fail-soft.
- Export, backup, publish, and merge now use the strict interchange read. Vault and cover-janitor display reads intentionally remain on `getAll()`.
- Detail-less issue write-back now fails before mutation and preserves the raw kind, title, and cover.

### S2 — M10, M12

- Added pure-Dart `CalendarDate`: issue/subscription dates remain integer wire/column values but now mean calendar days at 00:00 UTC, with one idempotent legacy conversion.
- Applied the rule through domain gates, Pitaka JSON, `.pitabak`, merge/direct OVERWRITE, forms, D6 lookups, repositories and companions. `addedDate`, `removedAt`, loan dates and `exportedAt` remain instants.
- Made title/year projection, cadence and subscription status timezone/DST-stable. The entire subscription end date remains `expiringSoon`; the next local day is `lapsed`.
- Added schema v7 with precomputed conversions and D6 collision refusal before writes. Same-device projections and FTS are preserved; generated v7 snapshots/helpers and migration rows are included.
- `.pitabak` restore and merge OVERWRITE reproject every stored series before commit. Direct overwrite also revalidates both incoming collections.

### S3 — M1, M9

- Wrapped the whole add/update issue operation in `_items.runInTransaction`: stored-row lookup, series lookup and projection, domain validation, D6 pre-check and the final write. Typed `Either` rollback is preserved.
- Extended `IssueIngress.prepare` with `allowRemovedSeries`: false for add, true for update. New issues under a removed series fail before any write; historical issue edits remain allowed.
- Added the `OpenPeriodical` scan destination. A removed ISSN match now opens its existing series detail/restore flow instead of the add-issue form.
- Added controlled real-Drift delete/rename relays. The final harness proves exactly one outer transaction across stored-row, series, D6 and write stages, and checks the committed series and complete issue projection afterward.

### S4 — H1, H2, H3, M3

- Added `ImportSeriesReconciler` (`lib/features/import_export/application/import_reconciliation.dart`). Inside the existing import transaction it validates every incoming series, builds one `incoming canonical UID → stored winning series` map, and reports add/update/skip counts plus the stored series that must be reprojected.
- Resolution order per row: already resolved by an earlier row of this file → skip; same UID → merge in place; same canonical ISSN under another UID → keep the local series and map the incoming UID onto it; otherwise insert and remember the RETURNED row, including a repository-minted UID.
- `mergeImportedPeriodical` is the periodical twin of the item merge: stored `id`/`periodicalUid` survive, covers follow `resolveIncomingCover`, and `addedDate`/`addedBy` are preserved when the file omits them.
- Issues are validated, re-anchored through the shared `reattachIncomingIssue`, and validated again before the write. A same-UID cross-kind update returns a typed `ValidationFailure` naming both kinds; the v3 book-versus-stored-issue case is covered.
- D6 duplicates are skipped and counted after re-anchoring, including keys claimed by earlier writes in the same file; `ImportIssueClaims` releases an item's previous claim when a repeated UID updates it. Date-only issues keep their additive behaviour.
- Every updated stored series is reprojected LAST through the shared `IssueReprojection`, so issues absent from the file follow a rename; a failure rolls back series, items, wishlist and staged covers together.
- Trim-created UID collisions are now fatal in the parser (`ImportPayload.fatalErrors`) and re-checked for hand-built payloads by `ImportPayloadGuard`, which the merge use case also honours before any namespace read or repository IO. `ImportBundle.validate` refuses a payload carrying fatal errors.
- Structure: the reconciliation moved out of the import use case, the file-level refusal to `import_payload_guard.dart` + `domain/periodical_uid_ambiguity.dart`, and the merge's per-row apply to `merge_resolution_applier.dart`. The three grown files are 482/497/416 lines and the `merge_library_use_case` file-size allow-list entry was deleted; `merge_resolution_applier.dart` joins the ingress-gate census.

### S5 — H4, M2, L5

- `ImportBundle.validate` is lossless: `items`, `periodicals`, `wishlist` and `warnings` all survive (unmodifiable), while `parseErrors`/`fatalErrors` still refuse the bundle. Series cover references are validated and count as referenced leaves, so the unreferenced-cover check accepts the bundle's own series art.
- `LibraryBundleReader` treats `periodicals` as a third valid top-level collection: shape-checked before parsing, on the same footing as books/wishlist. A titles-only v4 document is valid; a malformed or null collection is refused instead of silently becoming an empty series list, and v3 documents behave exactly as before.
- `BundleImportImages` gained `preparePeriodical`/`recordPeriodical`, and series final references joined `retainFinalReferences`. Staging is keyed by source leaf, so a series, an issue and a wishlist row naming the same leaf share one staged file. A same-UID merge that keeps this device's cover now passes that already-on-device reference through — before, it looked for a bundle leaf that never existed and failed the import (a latent bug for items too).
- `BackupArchiveBuilder.build` now returns `Either<Failure, Uint8List>`. The worker isolate returns plain data — bytes or a `BackupEntryOverflow` code — and the calling isolate maps it to the new `BackupTooLargeFailure`; no `Failure` object crosses the boundary. The create-backup page shows "This catalogue is too large for this backup format. Nothing was exported."
- Both W2 entries are encoded and bound-checked BEFORE any file work, against the restore reader's own `maxBytes`/`maxRows`. An oversized catalogue is therefore refused before a scratch directory, a SQLite file, or any bytes exist.
- `RestoredItemDetails` and `RestoreSummary` report `issueEntriesDropped` (raw `issues[]` entries that produced no link) separately from `issuesDetached` (unique catalogue rows restored as books, deduplicated by `bookUid`). Parse-time drops no longer seed the row counter, `withAdoptionResults` and `hasAdjustments` carry both, and the restore page prints two distinct sentences — the units are never summed.
- Structure: the bound policy and row counting moved to `backup_entry_bounds.dart`; the writer is 471 lines, so no ratchet entry was needed.

### S6 — H5

- `planPeriodicalMerge` preserves UID-first and canonical-ISSN identity, but an exact-title candidate is ignored when both sides normalize to valid, different ISSNs. The incoming series is therefore added under its own UID instead of becoming a same-series conflict.
- Title fallback remains when either side lacks a valid ISSN. Same-ISSN/different-UID reconciliation, same-UID/changed-ISSN conflicts, first-claim behavior, and separate in-file same-title adds are unchanged.
- The existing `winners` mapping and `reattachIncomingIssue` now keep the distinct incoming issues under the incoming series; no reattachment rewrite was needed. The composed plan and applied `MergeResult` have no periodical conflict, item conflict, possible duplicate, or review item for this expected add.
- A real shared-Drift regression starts with two local issues and merges two incoming issues with the same numbers under a same-title/different-ISSN series. It verifies two stored series and all four issues with their correct series links after apply.
- The change is confined to the pure-Domain fallback decision, its contract comments, and regression tests. Schema v7 and all S1–S5 persistence/interchange guards are unchanged.

### S7 — H7, M7, M8, M11, L2

- Added pure-Dart structural `CoverOwner` identity (`catalogueItem` or `periodical`) and replaced `ItemCover.bookId` with an optional owner. Scheduler dedup is the structural `(owner, coverUrl)` pair, so independently rebuilt owners share one fetch while another owner kind, id, or URL gets its own entry. Post-frame requests also re-check the current owner/URL.
- `MaterializeRemoteCoverUseCase` now reads either repository fresh before downloading and again after storing the JPEG. A changed/missing/local cover or read failure deletes the new file without touching the newer row; a successful update builds on the latest entity and releases only the reference validated by that read. Mid-download cover replacements and unrelated field edits therefore survive.
- Series materialization updates the periodical, never an issue displaying its cover, and invalidates both library and periodical signals. List/grid/detail and series rows/heroes pass the actual owner; issue detail resolves through `IssueCover.resolve`, own cover wins, and Replace cover remains attached to the issue. Refusal diagnostics carry the typed owner and reason, never a URL.
- All three forms track `_coverDirty` and `_coverPending`. Untouched forms observe the current row and preserve its cover at Save; deliberate capture/removal wins instead. `FormCoverField.onBusyChanged` disables Save through picker, crop, downscale and storage, and every async plugin/store boundary is `mounted`-guarded, including route disposal.
- Add Issue prefill checks both generation and selected UID after every await, avoids duplicate initial scheduling, and tracks copies dirtiness separately so an explicit `1` is not mistaken for the untouched default. A→B, ABA, and user-input-during-read regressions pin the behavior.
- Structure: issue number/date/copy/title-preview rows moved to `add_issue_form_sections.dart`, keeping the page at 475 lines with no ratchet entry. Schema v7 and the S1–S6 persistence/interchange/date/transaction/backup contracts are unchanged.

### S8 — M5, M13

- `redactForPublish` now switches exhaustively on item details. An Other emits exactly `title`, `kind: other`, resolved `coverUrl`, `language`, and `ageGroup`; availability, issue data, transliteration, and every book-specific/private field stay out. Book, issue, and periodical public-field behavior is unchanged.
- `PublishCoverIds.shortHashHexForKey` hashes `salt || UTF-8(key)`. Independently calculated fixtures pin the old ASCII digests and a deterministic Telugu/Devanagari digest, and a real `PublishLibraryUseCase` publish proves a non-ASCII covered series commits with canonical grouping and one shared fallback cover.
- Pure-Dart `PublishPeriodicalLinks` creates the single series lookup used by publish. Missing, blank, noncanonical, or duplicate series UIDs and noncanonical/unresolved live-issue links return a safe `PublishFailure` before cover IO, viewer construction, JSON encoding, manifest save, or commit. Removed series remain in the lookup for D8 cover fallback but publish no top-level entry.
- The real inline viewer runs under a dependency-free Node DOM harness in table, card, and grid modes. Checks cover sparse Other fields without null/undefined placeholders, book behavior, series grouping/order, and hostile text/attribute escaping. Node 22 is documented in the README and provisioned in CI through a SHA-pinned `actions/setup-node`; no npm or app dependency was added.
- Structure: `PublishResult` moved to `publish_result.dart` and is re-exported for existing callers, keeping the use case at 466 lines with no ratchet entry. Schema v7 and all S1–S7 contracts are unchanged.

### S9 — L1, L3, L4

- `PeriodicalsController.build` watches `libraryControllerProvider` as well as `nowTickProvider`. Import, merge, restore and the real issue hard-delete action therefore refresh a kept-alive Magazines list's title, count and latest date without a minute tick or route recreation; the tick remains only for time-derived subscription badges.
- `LibraryPage` is a `ConsumerStatefulWidget` with a page-owned, disposed search controller. Query-only, facet-only and combined empty results say "No items match these filters." Clear search empties the visible field and preserves facets; Clear filters resets only kind/language and preserves query text. Add/Import appears only for a genuinely empty unfiltered library.
- Generic detail, scan, remove/delete, lending, missing-row and error copy uses Item/item, including `Item #id`. Borrower-deletion pre-checks and the authoritative native fallback share the same "items out" sentence with no persisted-name or Rust/FRB API change. Book-specific add/ISBN/lookup screens and wishlist wording are unchanged.
- The vault guide and all three mockups mirror the neutral wording. The unfiltered empty hint is now "Items you add will appear here." Its Linux golden still needs the planned S11 regeneration; no macOS golden was produced.
- Structure: generated output changed only the expected `periodicals_controller.g.dart` hash. `LibraryPage` is 447 lines and `EmptyLibraryState` 124, so no ratchet entry was needed. Schema v7 and the S1–S8 persistence/interchange/date/transaction/backup/publish contracts are unchanged.

## 3. Verification evidence

| Gate | Result |
|---|---|
| Red-first identity/corruption regressions | 9 failed on unfixed code for the intended reasons, then passed. |
| Red-first v6 migration regressions | 4 failed on unfixed v5 code, then passed. |
| `fvm dart run build_runner build --delete-conflicting-outputs` | Completed; pre-commit generated-code check passed. |
| `fvm flutter analyze lib test integration_test` | No issues found. |
| `fvm dart format --set-exit-if-changed --output=none lib test integration_test` | Clean. |
| `fvm flutter test test/architecture test/core/database/migration_test.dart` | Passed, including v1→v6, v5→v6, raw-object health, and collision rollback cases. |
| `fvm flutter test --exclude-tags golden` | **2,901 tests passed.** |
| `git diff --check` | Clean before both remediation commits. |
| S2 generation, analysis, formatting, architecture and migration gates | Clean; v7 snapshot/helpers included and v1→v7 paths passed. |
| S2 focused suites under `TZ=Asia/Calcutta` and `TZ=America/New_York` | **218 tests passed in each timezone**, including forms, migration, merge and restore. |
| S2 `fvm flutter test --exclude-tags golden` | **2,926 tests passed.** |
| S3 red-first removed-series/scan regressions | **3 failed on unfixed code** for the intended reasons, then passed; the historical-issue edit control remained green. |
| S3 red-first real-Drift interleavings | **4 failed on clean unfixed HEAD**, then passed. The final suite also rejects partial or multiple transaction boundaries. |
| S3 focused and DI suites | **50 focused tests passed**; the **5 DI provider tests** also passed after recording the new transaction call. |
| S3 analysis, formatting, architecture and migration gates | Clean; **30 architecture/migration tests passed**. |
| S3 `fvm flutter test --exclude-tags golden` | **2,934 tests passed.** |
| S4 real-Drift reconciliation regressions | **20 new tests** in `import_library_reconciliation_test.dart` (link/cover/metadata, cross-kind matrix, D6, in-file duplicates, rollback), plus a merge-side regression proving the same file-level refusal happens before any repository IO. |
| S4 `fvm flutter test test/features/import_export` | **408 tests passed.** |
| S4 transformation/architecture gates | Generation wrote no committed diffs; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed** with the `merge_library_use_case` ratchet entry removed. |
| S4 suites under `TZ=America/New_York` | **60 tests passed** in the reconciliation and merge suites. |
| S4 `fvm flutter test --exclude-tags golden` | **2,955 tests passed.** |
| S5 new regressions | **24 new tests** across the bundle, reader, writer, restore-counter and page suites. The real-bundle block is **5 real-ZIP/real-Drift tests** in `bundle_periodical_roundtrip_test.dart` (shared cover staged once, titles-only bundle, unsafe/missing/unreferenced series covers, cross-kind rollback deleting only new series covers, orphan issue → book). |
| S5 bundle/reader regressions | Lossless payload preservation and series-cover validation in `import_bundle_test.dart`; `periodicals` as a third collection, malformed-collection refusal and v3 parity in `library_bundle_reader_test.dart`. |
| S5 writer/backup regressions | Byte-cap and row-cap refusals with no scratch directory created, a fitting v4 archive that still round-trips, the exact-`maxBytes` reader boundary for both entries (`backup_extras_bounds_test.dart`), use-case propagation of `BackupTooLargeFailure`, and the create-page sentence. |
| S5 restore-counter regressions | Entry-versus-row matrix in `restore_item_details_test.dart` (one malformed entry + one declared row = 1 + 1, never 2 detachments), the real-archive case in `restore_backup_test.dart`, and two separate restore-page sentences. |
| S5 `fvm flutter test test/features/import_export test/features/backup` | **622 tests passed.** |
| S5 sufficiency gates | Generation wrote no committed diffs; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed**, writer 471 lines with no new ratchet entry. |
| S5 suites under `TZ=America/New_York` | **19 tests passed** in the round-trip, restore-details and boundary suites. |
| S5 `fvm flutter test --exclude-tags golden` | **2,979 tests passed.** |
| S5 commit checks | Pre-commit generated-code check passed; `git diff --check` clean. |
| S6 pre-edit baseline | Clean `47a4e26`; analysis/formatting clean, **421 import/export tests**, **30 architecture/migration tests**, and **2,979 non-golden tests** passed before editing. |
| S6 red-first regressions | The direct planner, composed plan/review, and real-Drift cases **failed on unfixed code** for the intended reasons, then passed. **34 focused tests** passed after the fix, including missing-ISSN fallback and in-file same-title controls. |
| S6 feature suites | `fvm flutter test test/features/library test/features/import_export`: **932 tests passed.** |
| S6 sufficiency gates | Generation left no committed diffs; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed**; no schema or ratchet change. |
| S6 `fvm flutter test --exclude-tags golden` | **2,984 tests passed.** |
| S6 commit checks | Pre-commit generated-code check passed; `git diff --check` clean; working tree clean at `ea3ccf3`. |
| S7 pre-edit baseline | Clean `9ea0710`; analysis/formatting clean and **2,984 non-golden tests** passed before editing. |
| S7 red-first regressions | **15 behavioral checks failed on unfixed code** across the initial implementation and the independent-review race regression, then passed. The structural-owner test also started red because the type/API did not exist; dirty-cover and own-cover controls stayed green. |
| S7 focused suites | **145 tests passed**, including all three forms' picker/crop/store gates and disposal, structural dedup, item/periodical mid-download interleavings, issue detail/list/grid/series ownership, and A→B/ABA/copies prefill cases. |
| S7 independent review | Review found the first-read mid-download race; the second-fresh-read fix and gated item/periodical regressions resolved it. Re-review reported no remaining concrete finding. |
| S7 sufficiency gates | Generation updated only the two expected providers; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed**; no schema or ratchet change. |
| S7 `fvm flutter test --exclude-tags golden` | **3,017 tests passed.** |
| S7 commit checks | Pre-commit generated-code check passed; `git diff --check` clean; working tree clean at `1aecff0`. |
| S8 pre-edit baseline | Clean `4d0eda4`; analysis/formatting clean and **3,017 non-golden tests** passed before editing. |
| S8 red-first regressions | **9 behavioral checks failed on unfixed code** for the intended reasons: Other's exact key set, helper and end-to-end Unicode hashing, five malformed-link cases, and viewer rendering of the leaked fields. ASCII compatibility and viewer syntax controls stayed green; all then passed. |
| S8 focused and feature suites | **49 focused tests passed** across redaction, cover IDs, publish use case, and real viewer runtime; the complete publish suite passed **413 tests** on the remediation commit. |
| S8 independent review | Review found missing removed-series fallback coverage and a noncanonical-series fixture that did not isolate periodical-side validation. Both tests were corrected; re-review reported no concrete finding. The residual Node prerequisite concern was resolved in CI and the README. |
| S8 sufficiency gates | Generation left no committed diffs; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed**; use case 466 lines with no schema or ratchet change. |
| S8 `fvm flutter test --exclude-tags golden` | **3,027 tests passed.** |
| S8 commit checks | Pre-commit generated-code check passed; `git diff --check` clean; working tree clean at `8d4aa1f`. |
| S9 pre-edit baseline | Clean `c391f96`; analysis/formatting clean and **3,027 non-golden tests** passed before editing. |
| S9 red-first regressions | Shared title/count/latest refresh plus real import, merge, restore and hard-delete producer paths failed on unfixed code, then passed. Filtered-empty/recovery, Issue/Other wording, `Item #id`, guide and borrower-deletion/native-copy checks also failed for the intended reasons before the fixes. |
| S9 focused and independent review | **199 focused tests passed**, including accessibility checks and the real delete button. Review found the remaining borrower-deletion wording gap; Dart/Rust neutral copy and Issue/Other regressions resolved it, and re-review reported no concrete finding. |
| S9 sufficiency gates | Generation changed only the expected provider hash; `dart analyze` clean; `dart format --set-exit-if-changed` clean; **30 architecture/migration tests passed**; no schema or ratchet change. |
| S9 full and Rust gates | `fvm flutter test --exclude-tags golden`: **3,046 tests passed.** Rust fmt, clippy and `cargo deny check` passed; **35 release tests passed, 2 environment-gated ignored.** |
| S9 commit checks | Pre-commit generated-code and Rust-format checks passed; `git diff --check` clean; working tree clean at `518960c`. |

Linux golden regeneration, CI-at-final-SHA checks, and Android device journeys are **not claimed here**; they remain S11 work. No macOS golden images were generated or committed. S11 must include the changed unfiltered empty-library image.

## 4. Historical restart instruction — S10 (completed)

Do not rerun this session. The following was the restart instruction at the
after-S9 snapshot:

Start with `magazineIssues.md` **S10 — Reconcile contracts, changelog, and release instructions** (L6 and documentation for S1–S9). Its S1–S9 dependency is complete.

1. Confirm `git switch magazines && git status --short` is empty and HEAD is `518960c` (or the docs commit that follows it).
2. Read S10 and the final behavior in ADR 0013/0014, `docs/ARCHITECTURE.md`, the changelog, `magazines-progress.md`, and `docs/plans/otherDetails.md`; this is a reconciliation session, not an opportunity to redesign completed contracts.
3. Run the S10 baseline, including `full`, before editing; stop on any pre-existing failure.
4. Amend the ADRs and architecture documentation for the implemented identity, interchange, transaction, calendar-day, D6, backup, cover and publish decisions, preserving the rationale for already shipped behavior.
5. Reconcile `[Unreleased]`, progress notes and release instructions through current HEAD. Include the Tokio security update, N1 and S1–S9 user-visible changes; leave only genuinely outstanding S11/R1 work.
6. Replace the Fastlane byte check with the specified UTF-8 character-count check (maximum 500, not an exact count), run it, and mark plan sessions Done only with their actual commit/test evidence.
7. Preserve every S1–S9 contract. Do not start S11 or R1.

## 5. Handoff notes

- `magazineIssues.md` Part D is the authoritative session log; this document is the human-readable restart summary. It supersedes the earlier "after S8" text.
- Snapshot state: S0–S9 were Done and S10–S11 were Pending. See the banner
  above and `magazineIssues.md` Part D for current status.
- The original 26-finding release hold is unchanged. Completing S9 does not make the branch release-ready.
- Two conventions worth reusing: (a) when a file hits the 500-line guideline, extract a cohesive collaborator instead of adding a ratchet entry (S4/S5/S7/S8 did this); (b) a file-level refusal belongs in `ImportPayload.fatalErrors` / `BackupEntryOverflow`, never in a silently skipped row.
- Publish linkage uses one validating resolver before any cover or artifact work. Do not replace it with an unchecked map: a missing/ambiguous link must fail closed, while a removed series stays available for its live issues' cover fallback.
- The viewer syntax/runtime tests require Node 22 or newer on PATH, with no npm install. CI provisions it explicitly; do not skip these tests when Node is missing.
- For slow background materialization, a fresh read at operation start is not enough: re-read and revalidate immediately before the write, build on that latest row, and clean up the new file on mismatch. S7's gated mid-download item and periodical fixtures are the pattern.
- `BackupEntryOverflow` is the writer's mirror of the reader's bounds. If `ItemDetailsArchiveCodec.maxBytes`/`maxRows` ever change, the writer picks the new number up automatically — but the boundary tests in `backup_extras_bounds_test.dart` still pin "equal is readable, one byte more is not".
- For identity-fallback changes, pin both the distinctness rule and the fallback controls, then verify final relationships in real Drift rather than trusting result counts alone. S6's two-series/four-issue fixture is the pattern.
