# PLAN.md — Session 8: M03 catalogue replacement and existing loans

## Understanding

Only M03 is in scope, per `fix-schedule.md`. Merge-overwrite and vault-free
restore can invalidate existing loans or silently link them to different books.
**User decision: C — preserve loan links only when every required stable-identity
match is certain; refuse otherwise.** No automatic reset or discarded history.
Status: **M03 implemented and verified; user approved the 25-path commit.**
Policy C remains binding; commits and destructive actions need separate approval.
Start HEAD: `6eeb92e`; tracked tree clean, with only the three expected local
untracked paths (`.fvm/`, `astra-review.md`, `fix-schedule.md`).

## Privacy & threat notes

- A valid but unrelated catalogue can substitute book identities without a
  missing-ID error. Protect active loans AND returned-loan history.
- A locked vault's loan contents are unknown, not empty. Do not persist loan
  counts, names, contacts, or matching indexes in plaintext to bypass unlock.
- No automatic vault reset, discarded loans, remote lookup, telemetry, or new
  secret copies. A reset deletes borrowers/history and needs explicit consent.
- Reject before catalogue/settings/cover/vault mutations when safety cannot be
  established. A UI warning or a one-time stale state check is insufficient.
- Catalogue encryption remains M06b; cross-file crash recovery remains M02.

## Investigation notes (pre-fix evidence)

- Review M03 evidence re-verified before implementation at then-current lines:
  `merge_library_use_case.dart:225–230` zeroes incoming IDs before replaceAll;
  `merge_page.dart:119–123` claims the vault is not affected;
  `restore_backup.dart:245–315` commits replacement before flagging a kept vault.
  These are under `lib/features/import_export/` and `lib/features/backup/`.
- `lib/features/library/infrastructure/drift_book_repository.dart:229–247`
  atomically deletes/reinserts books, but never coordinates with the vault.
- `rust/src/vault.rs:46–76`: loans contain only numeric book_id; the sole FK
  is to borrowers. No book UUID or ISBN is stored in the loan schema.
- `lib/core/database/tables.dart:20–24` and `app_database.dart:40–47` provide
  nullable book_uid/ISBN and unique indexes. Neither is universally present.
  JSON parser carries bookUid; LegacyDbReader preserves book_uid AND local id.
- `lib/features/vault/domain/loan_integrity.dart:49–65` checks existence only;
  it cannot detect the same number referring to a different book.
- `lib/core/di/providers.dart:692–703,730–742` wires merge without a vault
  collaborator; restore has a store but no shared session-operation guard.
- `vault_session_controller.dart:80,145–212,623–680` (vault/application) has
  conservative loading-state handling and a FIFO, but creation keeps the old
  uninitialized UI state while awaiting native IO. Guarding only vaultExists
  or isInitialized once would miss operations that start/finish concurrently.
- Read merge use-case/page tests and restore use-case/controller tests.
  `test/features/backup/restore_backup_test.dart:393–421` explicitly tests the
  old keep-and-warn policy; replace this expectation only after user decision.
- VaultArtifactsStore has clear(), but no user-facing vault-reset flow was
  found in the vault/settings paths searched. Do not invent a reset action.

## Proposed approach (implemented; with OSS references)

Implemented **C**, chosen by the user on 2026-09-07:
- Use one pure, testable replacement planner for both entry points. Every book
  referenced by active OR returned loans needs a certain one-to-one stable
  identity match. Missing, conflicting or ambiguous identities fail closed;
  numeric-ID coincidence and fuzzy title similarity are never evidence.
- Incoming catalogue rows with verified matches retain the existing local IDs;
  encrypted loan rows need no rewrite. New rows use the existing SQLite
  AUTOINCREMENT path without resetting sqlite_sequence. Real-Drift tests prove
  collision safety with reversed incoming IDs and a deleted historical ID 500.
  A pre-existing dangling loan refuses; numeric coincidence cannot repair it.
- Exact nonblank UID matches are authoritative; checksum-valid ISBN fallback
  (normalized, ISBN-10 converted to ISBN-13 by existing IsbnFormat) is allowed
  only when a UID is absent, never when two UIDs disagree. Duplicate keys,
  two-to-one claims and contradictory UID/ISBN matches refuse. No fuzzy match.
- One narrow CatalogueReplacementGuard is implemented by the session's existing
  FIFO. Fresh reads expose only an immutable, ephemeral set of loan book IDs.
  Merge snapshot+replacement share one transaction; restore plans inside its
  transaction. Both check a cancellable scope before writes and before commit.
  New loan insertion rechecks the book/availability inside that same FIFO, so
  a lend action waiting behind replacement cannot write a dangling reference.
- Require unlock when existing loan contents cannot be safely verified. No-vault
  replacement stays available. Unknown/error state refuses; no plaintext index.
- Coordinate vault creation/lending and the catalogue snapshot through the full
  replacement, not only a UI preflight. Keep secrets/crypto in Rust and expected
  errors as Either. Refusal leaves catalogue, settings, covers and vault intact.
- Reuse existing narrow domain ports and the M07 FIFO pattern. Canonical OSS
  source inspected: installed Drift 2.28.2 `lib/src/runtime/api/connection_user.dart`
  lines 430–524 documents transaction rollback, including commit failure.
  A Drift transaction does NOT cover separate vault files. Preserving IDs
  proved sufficient; no new cross-store commit, schema, crypto or dependency
  changes. Architecture skill's layering guidance was used, but repository
  Riverpod/codegen and feature folders supersede its MVVM examples.

## Decision points

1. **Settled: C.** Do not re-ask the loan-policy question or fall back to A/B.
2. **Settled: A — execute M03 end-to-end.** Still pause for an unforeseen
   safety trade-off, failed assumption, or scope expansion.
3. Any schema change, package install, destructive action, or commit requires
   separate approval of its exact invocation. No such actions at this checkpoint.

## Steps

- [x] Verify handoff/HEAD, cited evidence, schemas, callers/callees, and tests.
- [x] Run baseline gates using pinned Flutter/Dart 3.44.2.
- [x] Obtain policy decision (C) and refine the implementation direction.
- [x] Obtain execution-mode approval (A — end-to-end).
- [x] Write failing regressions for both deletion and same-ID substitution.
- [x] Implement the chosen policy at both boundaries and truthful preflight UI.
- [x] Cover no-vault/locked/unlocked/partial states, all loan history, failures,
      retries, concurrent vault creation/lending, and unchanged state on refusal.
- [x] Run generation, full gates, coverage and privacy/diff review.
- [x] Complete M03 Result and prepare explicit-path commit approval request.
- [x] Obtain user approval for the exact 25-path staging/commit commands below.
- Commit outcome is recorded in the local handoff after Git verification.

## Out-of-scope observations

N07 settings adoption is still separate from catalogue persistence. N11 widget
lifecycle, M05 archive expansion, M15 row validation, and M02 vault-bearing
restore atomicity remain open. To release the shared FIFO safely, vault-bearing
restore now locks the old session on completion/failure before queued operations
resume. This pulls forward that part of M02's cached-session protection; it does
NOT make the catalogue/vault/covers commit atomic or change corrupt-manifest
preflight behavior. No unrelated fixes, reset flow, or platform changes.

## Result

M03 implemented under policy C. **User approved the exact commit manifest below.**
This plan is included in that commit; its hash and post-commit tree verification
are recorded in the local handoff tracker.
Baseline: Flutter **1097 passed**, Rust **32 passed** / 2 expected ignored;
format **363 files / 0 changed**, analyzer **0 issues** after disabling Flutter's
failed automatic update check with the SDK-verified `--no-version-check` flag.

Final gates (pinned SDK 3.44.2): **1152 Flutter passed / 0 failed** (+55),
**32 Rust passed / 0 failed**, 2 expected ignored; analyzer **0 issues**;
format **371 files / 0 changed**; diff check clean. Flutter coverage log:
`/tmp/pitak-m03-flutter-final.VmuV70` (full log checked for failure markers).
Generation rerun wrote 0 outputs; all **22 tracked generated files** remained
byte-identical. Only DI/session generated hashes differ from HEAD.

Regression evidence: both original M03 tests failed before implementation
(replacement returned success instead of refusal). An initial missing test
import was corrected before counting the merge reproduction. Type inference,
other missing imports and lint findings were corrected; no pending failed gate.

Coverage: planner **40/40 (100%)**, scope **3/3 (100%)**; new session/loan-check
regions **46/46 (100%)**, whole session **310/339 (91.45%)**; merge overwrite
**27/28 (96.43%)**, whole use case **107/118 (90.68%)**; restore planning/lease
region **21/22 (95.45%)**, whole restorer **106/139 (76.26%)** (existing IO paths
remain uncovered). Project **7418/11055 (67.10%)**. Line coverage is not proof
of every interleaving or crash behavior.

Privacy/diff review: no new logging/network calls in changed production lines,
no new persistence of loan indexes/PII, no dependency/platform/crypto/schema
changes. Domain purity checks passed in the full suite. Tests use synthetic
vaults, real in-memory Drift, temporary archives/files, and mocked file pickers;
no live data, device, or power-loss verification. Existing generator SDK/analyzer
language-version warning remains; generation, analysis and tests succeed.

## Approved commit manifest — exactly 25 paths

User approved these exact commands. Stage only these paths, never the local review,
schedule or `.fvm/` cache. Rationale: one buildable M03 policy-C fix with its
regression tests and working plan; no unrelated findings or dependencies.

```sh
git add -- \
  PLAN.md \
  lib/core/di/providers.dart \
  lib/core/di/providers.g.dart \
  lib/features/backup/domain/restore_summary.dart \
  lib/features/backup/infrastructure/restore_backup.dart \
  lib/features/backup/presentation/pages/restore_page.dart \
  lib/features/import_export/application/merge_library_use_case.dart \
  lib/features/import_export/presentation/pages/merge_page.dart \
  lib/features/library/domain/catalogue_replacement_guard.dart \
  lib/features/library/domain/catalogue_replacement_plan.dart \
  lib/features/vault/application/vault_session_controller.dart \
  lib/features/vault/application/vault_session_controller.g.dart \
  test/features/backup/catalogue_replacement_restore_test.dart \
  test/features/backup/migration_matrix_test.dart \
  test/features/backup/restore_backup_test.dart \
  test/features/backup/restore_controller_test.dart \
  test/features/backup/restore_page_test.dart \
  test/features/import_export/merge_library_use_case_test.dart \
  test/features/import_export/merge_page_test.dart \
  test/features/library/catalogue_replacement_failure_test.dart \
  test/features/library/catalogue_replacement_integration_test.dart \
  test/features/library/catalogue_replacement_plan_test.dart \
  test/features/library/replacement_harness.dart \
  test/features/library/replacement_test_guard.dart \
  test/features/vault/vault_session_controller_test.dart
git commit -m "fix(catalogue): preserve loan identities during replacement (M03)"
```
