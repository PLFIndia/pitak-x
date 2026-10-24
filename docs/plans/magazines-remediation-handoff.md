# Magazines remediation — handoff after S6

- **Date:** 2026-10-24
- **Branch:** `magazines`
- **Status:** S6 complete. S7 has **not** started.
- **Remediation HEAD:** `ea3ccf3` (this handoff is a documentation-only follow-up)
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

The working tree was clean immediately after `ea3ccf3`. The database remains at **schema v7** (S6 adds no schema change). No release version bump, tag, or publish step has been performed.

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

Linux golden regeneration, CI-at-final-SHA checks, and Android device journeys are **not claimed here**; they remain S11 work. No macOS golden images were generated or committed.

## 4. Resume with S7 only

Start with `magazineIssues.md` **S7 — Correct cover ownership, form races, and async prefill** (H7, M7, M8, M11, L2). Its S4 dependency is complete.

1. Confirm `git switch magazines && git status --short` is empty and HEAD is `ea3ccf3` (or the docs commit that follows it).
2. Read S7 and the locked cover decision: downloads and persistence target the actual owner, an inherited series cover never becomes issue-owned, and diagnostic paths do not log cover URLs.
3. Run the S7 baseline, including `full`, before editing; stop on any pre-existing failure.
4. Add the gated form/materialization, structural-owner dedup, issue-detail fallback, and A→B/ABA prefill regressions first. Cover issue, other-item, and periodical forms independently.
5. Introduce the pure-Dart structural `CoverOwner` record and thread it through `ItemCover`, scheduling, materialization, refusal reporting, provider wiring, and diagnostics without adding a parallel identity pattern.
6. Materialize remote series covers on the periodical, invalidate both library and periodical signals on success, and leave coverless issues coverless. Preserve own-cover-wins behavior everywhere.
7. Make all three edit forms race-safe with explicit cover dirty/pending state, current-row observation, Save gating (or awaiting the exact operation), and `mounted` checks after async gaps.
8. Resolve issue-detail fallback through `IssueCover.resolve` with the inherited periodical owner, and guard every Add Issue prefill await with both its generation and selected UID. Track copies dirtiness separately.
9. Preserve typed failures, the S1–S6 identity/interchange/date/transaction/backup contracts, and the existing blessed Riverpod patterns. Do not start S8 or R1.

## 5. Handoff notes

- `magazineIssues.md` Part D is the authoritative session log; this document is the human-readable restart summary. It supersedes the earlier "after S5" text.
- S0–S6 are Done. S7–S11 remain Pending.
- The original 26-finding release hold is unchanged. Completing S6 does not make the branch release-ready.
- Two conventions worth reusing: (a) when a file hits the 500-line guideline, extract a cohesive collaborator instead of adding a ratchet entry (S4/S5 both did this); (b) a file-level refusal belongs in `ImportPayload.fatalErrors` / `BackupEntryOverflow`, never in a silently skipped row.
- `BackupEntryOverflow` is the writer's mirror of the reader's bounds. If `ItemDetailsArchiveCodec.maxBytes`/`maxRows` ever change, the writer picks the new number up automatically — but the boundary tests in `backup_extras_bounds_test.dart` still pin "equal is readable, one byte more is not".
- For identity-fallback changes, pin both the distinctness rule and the fallback controls, then verify final relationships in real Drift rather than trusting result counts alone. S6's two-series/four-issue fixture is the pattern.
