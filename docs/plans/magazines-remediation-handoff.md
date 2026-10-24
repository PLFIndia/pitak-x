# Magazines remediation — handoff after S2

- **Date:** 2026-10-24
- **Branch:** `magazines`
- **Status:** S2 complete. S3 has **not** started.
- **Remediation HEAD:** `62e79cb` (this handoff is a documentation-only follow-up)
- **Release state:** R1 remains blocked until `magazineIssues.md` S1–S11 are Done.

## 1. Commits and current state

| Item | Commit | Result |
|---|---|---|
| Reviewed baseline | `e2dd250` | Exact review starting point; only `magazineIssues.md` was untracked. |
| S0 — baseline, fixtures, release hold | `68d4d0d` | Baseline recorded, shared fixtures added, R1 explicitly gated on remediation. |
| S1 — canonical identity and kind integrity | `c72b0cc` | M4, H6, and M6 fixed with schema v6 and regression coverage. |
| S2 — calendar-day semantics | `62e79cb` | M10 and M12 fixed with schema v7, dual-timezone regression coverage, and immediate restore/overwrite reprojection. |

The working tree was clean immediately after `62e79cb`. The database is now at **schema v7**. No release version bump, tag, or publish step has been performed.

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

Linux golden regeneration, CI-at-final-SHA checks, and Android device journeys are **not claimed here**; they remain S11 work. No macOS golden images were generated or committed.

## 4. Resume with S3 only

Start with `magazineIssues.md` **S3 — Atomic issue writes and removed-series guard** (M1, M9). Its S2 dependency is complete.

1. Confirm `git switch magazines && git status --short` is empty.
2. Read S3 and the locked decisions, especially the rule that editing an existing issue remains allowed while creating one under a removed series is refused.
3. Run the S3 baseline before editing; stop on any pre-existing failure.
4. Add controlled real-Drift interleaving regressions first for delete/rename races, then removed-series use-case and scan-routing tests.
5. Wrap the whole add/update issue operation in `_items.runInTransaction`: stored-row lookup, series lookup, projection, validation, D6 pre-check and write.
6. Extend `IssueIngress.prepare` with `allowRemovedSeries`: false for add, true for update. Route removed ISSN scans to the existing-series/restore flow.
7. Preserve typed `Either` rollback behavior and keep all v7 calendar-day semantics intact. Do not start S4 or R1.

## 5. Handoff notes

- `magazineIssues.md` Part D is the authoritative session log; this document is the human-readable restart summary.
- S0, S1 and S2 are Done. S3–S11 remain Pending.
- The original 26-finding release hold is unchanged. Completing S1 does not make the branch release-ready.
