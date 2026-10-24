# Magazines remediation — handoff after S1

- **Date:** 2026-10-24
- **Branch:** `magazines`
- **Status:** Paused by maintainer after S1. S2 has **not** started.
- **Remediation HEAD:** `c72b0cc` (this handoff is a documentation-only follow-up)
- **Release state:** R1 remains blocked until `magazineIssues.md` S1–S11 are Done.

## 1. Commits and current state

| Item | Commit | Result |
|---|---|---|
| Reviewed baseline | `e2dd250` | Exact review starting point; only `magazineIssues.md` was untracked. |
| S0 — baseline, fixtures, release hold | `68d4d0d` | Baseline recorded, shared fixtures added, R1 explicitly gated on remediation. |
| S1 — canonical identity and kind integrity | `c72b0cc` | M4, H6, and M6 fixed with schema v6 and regression coverage. |

The working tree was clean immediately after `c72b0cc`. The database is now at **schema v6**. No v7 work, release version bump, tag, or publish step has been performed.

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

Linux golden regeneration, CI-at-final-SHA checks, and Android device journeys are **not claimed here**; they remain S11 work. No macOS golden images were generated or committed.

## 4. Resume with S2 only

Start with `magazineIssues.md` **S2 — Calendar-day semantics for issue and subscription dates** (M10, M12). Its S1 dependency is complete.

1. Confirm `git switch magazines && git status --short` is empty.
2. Read S2 and the locked decisions in `magazineIssues.md`, especially UTC-midnight calendar days and the legacy conversion limitation.
3. Run the S2 baseline before editing; stop on any pre-existing failure.
4. Add regression tests first for timezone/DST stability, subscription end-date behavior, migration rollback, and immediate post-restore projection consistency.
5. Introduce the pure-Dart `CalendarDate` under `features/library/domain/value_objects/` and migrate schema **v6 → v7** with new Drift snapshots/helpers and migration-matrix rows.
6. Normalize at every required boundary, use shared `IssueReprojection` after `.pitabak` restore and merge OVERWRITE, and run focused suites under both `TZ=Asia/Calcutta` and `TZ=America/New_York`.
7. Keep `addedDate`, `removedAt`, loan dates, and `exportedAt` as instants; do not convert them.
8. Do not add packages, alter Rust/FRB/vault schemas, or start R1.

## 5. Handoff notes

- `magazineIssues.md` Part D is the authoritative session log; this document is the human-readable restart summary.
- S0 and S1 are Done. S2–S11 remain Pending.
- The original 26-finding release hold is unchanged. Completing S1 does not make the branch release-ready.
