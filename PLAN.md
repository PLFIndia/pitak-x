# S9 move and retirement plan

## Understanding

S9 adds user-confirmed moves between GitHub Pages and Cloudflare Workers in
both directions. The destination receives a strict complete snapshot and must
pass full read-back before the source is touched. The old active/verified share
target remains selected until source retirement is verified. Pending Retry and
Skip must be deterministic after every remote or persistent side effect.

## Privacy & threat notes

- Move confirmations disclose complete-snapshot replacement, exact GitHub
  ownership, dedicated-Worker deletion, peer reconciliation, and card reprint.
- Pending journal data is public configuration only: sealed targets, source
  anchor/branch, exact app-owned deletion paths, moved HTML, and retirement
  marker data. Tokens and upload/completion JWTs never enter it.
- Moved HTML escapes the library name and validated destination. Cloudflare
  retired deployments use the R27 response headers; GitHub's meta-CSP limit
  remains explicit.
- Source credentials, exact target, branch/head or publish id are revalidated
  before retirement. A mismatch never falls back to the currently configured
  different target.

## Decision points

- J.5's “after journal switch but before retirement” means after the
  pending-move journal write, not after active-host selection. The latter would
  contradict D.4, F.5, and J.5's final-completion invariant.
- The E.5 example lacks enough state to recover after a remote retirement but
  before the old-manifest commit. The pending journal therefore also carries an
  immutable retirement descriptor: exact moved index/404 bytes, GitHub branch
  and deletion paths, and Cloudflare retirement publish id/timestamp. Retry uses
  those bytes rather than mutable settings or a newer app template. Record this
  as a Part M deviation.
- The existing shared queue is held only by the outer move/retry/skip command.
  Confirmation dialogs run after its release; inner host operations never
  enqueue.

## Steps

- [x] Add validated pending-move/retirement-descriptor models, atomic journal
  transitions, strict prefs decoding, and exact move plans.
- [x] Add the escaped moved-page template/builder and retirement read-back.
- [x] Implement complete GitHub/Cloudflare destination publishing with source
  and destination race checks and digest re-confirmation.
- [x] Implement idempotent GitHub/Cloudflare retirement, including already-
  retired recovery, exact ownership, version-URL gates, and manifest commit.
- [x] Add the outer move controller, Retry/Skip, target-mutation guards, DI,
  confirmation dialog, persistent banner, and truthful result copy.
- [x] Add both-direction crash-matrix, security, architecture, and widget tests.
- [x] Run generation, formatting, analysis, and the non-golden suite; update the
  handoff and Part M records with evidence.

## Result

S9 is implemented end to end in the working tree. The move state machine takes
the shared publish queue only for prepare/confirm/Retry/Skip, records one
atomic pending journal entry with an immutable retirement descriptor, and
switches the active/verified target only after source retirement is verified.
Destination publishing is complete-snapshot-only with a canonical digest
re-check, exact expected-head commit or Cloudflare version-URL gate, and full
origin-bound read-back. Retirement is idempotent for both hosts, including the
already-retired path and the warned, existence-checked Skip.

Tests added: outer state machine and crash boundaries in both directions
(35), host destination/retirement suites (7 GitHub destination, 10 GitHub
source, 9 Cloudflare source, 5 Cloudflare destination), target resolver (6),
setup target-mutation guards (2 + 2), verifiers (10), moved HTML (8), pending
journal (9), move widgets (8), and the outer controller (5) — 116 tests in
total. A real defect was found and fixed while
testing: `ConfiguredMoveTargetResolver` threw `StateError` on an unreadable
Cloudflare credential record instead of returning `setupRequired`; it now
returns null and fails closed. The shared `PendingMoveTargetGuard` removes the
duplicated pending-target rule from both setup use cases.

Gates: `build_runner` leaves no new drift; `dart format` clean; `flutter
analyze` zero issues; full non-golden suite green (4,230 tests on 2026-10-28).
The Linux `publish_connection` golden remains excluded, and real-host J.7
smoke remains S11.

## Out of scope

- Real-host J.7 smoke remains S11.
- The intentionally changed Linux `publish_connection` golden remains excluded
  from local non-golden verification, as in S8 closeout.
