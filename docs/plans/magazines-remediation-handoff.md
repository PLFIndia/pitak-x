# Magazines remediation — handoff after S4

- **Date:** 2026-10-24
- **Branch:** `magazines`
- **Status:** S4 complete. S5 has **not** started.
- **Remediation HEAD:** `df774d5` (this handoff is a documentation-only follow-up)
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

The working tree was clean immediately after `df774d5`. The database remains at **schema v7** (S4 adds no schema change). No release version bump, tag, or publish step has been performed.

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
| S4 commit checks | Pre-commit generated-code check passed; `git diff --check` clean; working tree clean at `df774d5`. |

Linux golden regeneration, CI-at-final-SHA checks, and Android device journeys are **not claimed here**; they remain S11 work. No macOS golden images were generated or committed.

## 4. Resume with S5 only

Start with `magazineIssues.md` **S5 — Complete v4 bundle and bounded backup round-trips** (H4, M2, L5). Its S4 dependency is complete.

1. Confirm `git switch magazines && git status --short` is empty and HEAD is `df774d5` (or the docs commit that follows it).
2. Read S5 plus the locked import/bundle decisions, especially the writer/reader size parity rule and the distinct `issueEntriesDropped` versus `issuesDetached` units.
3. Run the S5 baseline, including `full`, before editing; stop on any pre-existing failure.
4. Add the real-ZIP, series-only, unsafe-cover, rollback, writer-boundary, and restore-counter regressions first.
5. Make `ImportBundle.validate` lossless for v4 and teach `LibraryBundleReader` that `periodicals` is a third valid collection with a validated shape.
6. Give series covers the full `BundleImportImages` lifecycle, sharing one staged file across series/items/wishlist references and including series leaves in `retainFinalReferences`.
7. Change `BackupArchiveBuilder.build` to return `Either<Failure, Uint8List>`, enforce the exact reader limits for `item_kinds.json` and `periodicals.json`, and propagate the typed failure through the writer and `CreateBackupUseCase`.
8. Split `issueEntriesDropped` from `issuesDetached` through `RestoredItemDetails`, `RestoreSummary`, `withAdoptionResults`, notices, and the restore page copy.
9. Keep typed `Either` rollback, the S1 interchange reads, S2 calendar-day semantics, and the S3/S4 import guards. Do not start S6 or R1.

## 5. Handoff notes

- `magazineIssues.md` Part D is the authoritative session log; this document is the human-readable restart summary. It supersedes the earlier "handoff after S3" text.
- S0, S1, S2, S3 and S4 are Done. S5–S11 remain Pending.
- The original 26-finding release hold is unchanged. Completing S4 does not make the branch release-ready.
- The repo enforces the 500-line guideline (`test/architecture/layer_boundaries_test.dart`). S4's extraction is the pattern to follow: move a cohesive responsibility into its own application collaborator rather than raising a ratchet record.
- `ImportPayload.fatalErrors` is now the channel for "this whole file must be refused". Any new reader must populate it for file-level ambiguity rather than reporting a row skip.
