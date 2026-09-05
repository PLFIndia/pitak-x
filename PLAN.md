# PLAN.md — current task

Roadmap across sessions: `fix-schedule.md`. This file is the plan for the current
session only.

## Understanding
- Session 1 of the `astra-review.md` remediation (see `fix-schedule.md` §3).
- Task S0: make the full Flutter test suite (including widget tests) run on the
  pinned SDK so later fix sessions can trust widget-level regression tests.
- Baseline: commit `f3a80a8`, version `1.1.10+16`, no application code changed.

## Privacy & threat notes
- Environment-only task; no user data, secrets, or network writes involved.
- `flutter pub get` run `--offline` to avoid unapproved network calls.

## Investigation notes
- Shell `flutter` is 3.41.1; `.fvmrc` pins 3.44.2. The review's compile errors
  (`DisplayCornerRadii`, `ink_sparkle.frag`) came from `build/` (3.1 GB) and
  `.dart_tool/` produced by the wrong SDK.
- Analyze and format passed on the pinned SDK before any change.

## Proposed approach (with OSS references)
- `flutter clean` with the pinned SDK (user-approved destructive action), then
  `flutter pub get --offline`, then `flutter test --no-pub` full suite.
- No OSS adaptation needed.

## Decision points
- `flutter clean` deletes `build/` and `.dart_tool/` — approved by user.

## Steps
- [x] Verify repo state matches `fix-schedule.md` Session 0 record.
- [x] Baseline gates: analyze, format (both pass).
- [x] `flutter clean` (pinned SDK) — approved and run; tracked files untouched.
- [x] `flutter pub get --offline` — lockfile unchanged.
- [x] Full `flutter test --no-pub` — 794 passed, 0 failed, 0 skipped.
- [x] `cargo test --release --frozen` — 30 passed, 2 ignored (expected).
- [x] Update `fix-schedule.md` §1, §3 (S0 row), §5 (Session 1 log).

## Out-of-scope observations
- 31 packages have newer versions blocked by constraints (for N15/dep audit later).
- Previous release follow-up: F-Droid suggested version check (from prior task).
- `astra-review.md`, `fix-schedule.md`, and this file are uncommitted; ask the
  user about committing them at the start of Session 2.

## Result
S0 done. Full Flutter suite is green on the pinned 3.44.2 SDK: 794 tests passed
(previously only 691 non-widget tests were verifiable). Root cause of the review's
test-build failures was stale build artifacts from Flutter 3.41.1; no source change
was needed. Next: B01 (app-lock gate above the whole navigator), starting with a
failing widget test.
