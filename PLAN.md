# Phase 3 — moves and reconnects (L2, RH3, M5, M4, M3, M6, M11)

## Understanding

Phase 3 of `docs/plans/cloudflare-fix-plan-2026-10-29-2-medium.md`. Every
finding is a state the user can enter but not leave, or a write that happens
before the rule that should have stopped it:

- **L2/RH3** — "absent" is decided from a status code alone on both hosts. A
  Cloudflare 404 (permission, wrong account, HTML edge page) reads as "no
  Worker", which gates replacement consent, the new-site decision and Skip.
  GitHub answers 404 for a private repo the token can no longer see.
- **M5** — the pending-move guard runs in `_finalize`, long after
  `selectWorker` saved the candidate and ran a verification deploy. Reconnecting
  during a pending move can therefore deploy a marker over the move's old
  Worker, after which Retry says "source changed" and Skip refuses.
- **M4** — the journal has a "finish" transition but no "undo", and Skip's
  evidence bar (exact credentials + authenticated "not found") cannot be met in
  the cases the plan wrote it for (revoked token, deleted account, renamed
  repo, another phone publishing).
- **M3** — rotating a token drops the confirmed target, so re-picking the same
  live Worker runs the destructive marker-only verification deploy, and the
  dialog claims the other site is untouched.
- **M6** — dialogs open only on a prompt *change*; the tab is disposed
  off-screen, so on return the tile is stuck in `awaitingInput` with every
  button disabled.
- **M11** — `build()` resets `_disposed` but `_operationActive` and the pending
  prompt survive, so an invalidate during a queued command strands a completer
  and every later command silently no-ops.

## Privacy & threat notes

- No new secret path. `CloudflareSetupConstraint` holds only public identity
  parts (account id, subdomain, Worker name) already in the journal.
- The new "absent" rules fail closed: an ambiguous 404 is `notFound`/
  `unreadable`, never "gone". Public absence alone never authorizes anything.
- `GitHubApiException` gains a status kind so 401/403 is "inaccessible", not a
  network failure; the kind is a number, never response text.
- Cancel/Finish copy names the old and new addresses (already public) and never
  a token, JWT or account id.

## Investigation notes

- `statusOnly` in `CloudflareHttpTransport.send` short-circuits both 2xx and
  404, so the body is discarded before any code can be read.
- `CloudflareAccountApi.readAccountSubdomain` already requires 404 + 10007.
- `PublishedSiteReadVerifier` already refuses redirects and distinguishes
  Body/Absent/Unreadable — exactly the GitHub evidence L2 needs.
- `PublishHostState` has `beginMove`/`finishMove`; `PublishHostStateRepository`
  mirrors them. `abandonMove` follows the same shape.
- `CloudflareSetupPrompts` is the one prompt owner; the generation belongs
  there, not in the controller.

## Proposed approach

1. L2: status-first `statusOnly`; `workerExists` requires 404 + `success:false`
   + code 10007; GitHub `skipCheck` requires repo 404 **and** a public 404 for
   `books.json` at the exact old address.
2. M5: `CloudflareSetupConstraint` from the journal, checked before every
   credential save or remote write; prompts prefilled from it.
3. M4: `abandonMove` + `MoveSiteUseCase.abandon()`; sealed `SourceSkipCheck`
   with `finishWithoutRetiring()`; three banner actions with their dialogs.
4. M3: recognise a proven address (journal `verifiedTarget` or a pending move's
   `newTarget`) and finalize without a deploy; defer the user-token save.
5. M6: `initState` + `listenManual(fireImmediately: true)` + post-frame dialog,
   last-shown serial, and a "Cancel setup" action.
6. M11: prompt generation; `_operationActive` per generation; `refreshStatus()`
   replaces the three invalidations.

## Decision points

- M4's "which button appears when" table is implemented as one "Skip
  retirement" action whose result carries `canFinishWithoutRetiring` +
  `oldSiteAnswers`, so the banner offers "Finish without retiring" only after
  the check actually said "inaccessible". No extra remote call on mount.
- M3's proven-address rule covers M5 step 3 (the old endpoint is the journal's
  `verifiedTarget` during a pending move), so setup can re-authorize it
  read-only without a second rule.

## Steps

- [x] L2/RH3: status-first 404, `workerExists` code rule, GitHub `skipCheck`,
      `GitHubApiException` status kind.
- [x] M5: `CloudflareSetupConstraint` + every setup command + prefill.
- [x] M4: `abandonMove`, `abandon()`, `SourceSkipCheck`,
      `finishWithoutRetiring()`, banner actions and dialogs.
- [x] M3: proven-address finalize, deferred user-token save, dialog copy.
- [x] M6: remount prompts, Cancel setup, GitHub prompts.
- [x] M11: prompt generation, per-generation lock, `refreshStatus()`.
- [x] Tests for every item above.
- [x] Records: ADR 0017 Decision 5/5a + S7, Part M, CHANGELOG, handoff, guide.
- [x] Gates: build_runner, format, analyze, non-golden suite (4,400 tests).

## Out of scope

- Phase 4+ findings (moved-page name validation, Version-URL re-checks, copy).
- The Phase 6 real-host run that records the real "script not found" code.

## Result

Phase 3 is implemented end to end.

- **L2/RH3:** `statusOnly` discards only a 2xx body, so a 404 is parsed.
  `workerExists` returns false only for 404 + `success: false` + code 10007;
  any other 404 is `notFound` and an HTML 404 is `malformedResponse`. GitHub's
  Skip check requires a repo 404 **and** a real public 404 at the old root.
- **M5:** `CloudflareSetupConstraint` (derived from the journal) is checked by
  every setup command before any credential save or remote write; prompts
  prefill from `CloudflareSetupHint` and explain why.
- **M4:** `abandonMove` + `abandon()`, sealed `SourceSkipCheck`,
  `finishWithoutRetiring()`, three banner actions with their own dialogs, and
  `GitHubApiException.statusCode` so 401/403 is "inaccessible" (N10).
- **M3:** `markAddressProven` finalizes a proven address without a deploy; a
  user token is verified but saved only at account selection; the verification
  dialog says "This Worker is your live site" when it is.
- **M6:** `initState` + `listenManual(fireImmediately: true)` + post-frame
  dialog that re-reads state, last-shown serial, "Cancel setup", and the same
  remount rule for the GitHub code/repo prompts.
- **M11:** prompt generations, a per-generation lock, and `refreshStatus()`
  replacing the three provider invalidations.

Two files crossed the 500-line ratchet and were split rather than allow-listed:
`cloudflare_setup_journal.dart` (journal-derived rules) and
`cloudflare_connection_status_writer.dart` (status projection).

Tests added: L2 (deploy API 4, GitHub source 3, Cloudflare source 2), M5 (7),
M3 (6), M4 (domain 4, repository 4, use case 8, widgets 2), M6 (section 2,
tile 2, page 1), M11 (controller 3) — 48 new tests.

Records: ADR 0017 Decision 5a + Decision 9, Part M rows 96–101, CHANGELOG,
handoff §9/§13, in-app guide.
