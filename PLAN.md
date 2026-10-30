# Phase 2 — large libraries upload on slow networks (H2, L8, L5)

## Understanding

Phase 2 of `docs/plans/cloudflare-fix-plan-2026-10-29-1-high.md` fixes three
findings that all bite a real library on a real mobile link:

- **H2** — one 60 s wall-clock number stood in for two questions ("is the
  connection dead?" and "has this run taken too long?"). A 56 MB bucket needs
  ~7.5 Mbit/s to finish in 60 s, so a slow-but-healthy phone was cut off and
  the whole bucket re-sent from byte 0, up to three times.
- **L8** — a non-JSON body was always "unreadable response", even for a 5xx or
  a second 429 (Cloudflare's edge serves HTML there), and a local artifact that
  changed mid-upload was retried as if it were a network error.
- **L5** — spools lived under Documents, which is never cleared, so every
  killed publish left a full copy of the site behind.

The working tree already carried the H2/L8 code (limits, upload-mode
`TimeoutHttpClient`, `CloudflareRequestTiming`, no-blind-resend, session
budget, status-first parsing, `artifactChanged`). This session finishes the
phase: L5, the tests the plan names, and the records.

## Privacy & threat notes

- No new secret path. The upload JWT still lives only inside
  `CloudflareUploadSession.useUploadJwt`; `issuedAtMillis` is a timestamp, not
  a credential, and is never logged or serialized.
- Progress callbacks carry a byte count only — never bytes, paths or headers.
- The spool sweep deletes only real directories named `run-[A-Za-z0-9_-]{1,64}`
  under the app's own `publish_artifacts` roots, never follows links, and never
  touches a folder this process is using. A symlinked root is not swept, so a
  hostile/odd filesystem cannot redirect a delete.
- Spools move from Documents to the OS temporary directory: less data at rest,
  and the OS may clear it. Nothing is backed up (`allowBackup="false"`).

## Investigation notes

- `CloudflareLimits.uploadDeadline` is gone; `deployDeadline` replaces it and
  `CloudflareRequestTiming` is the only place a duration is chosen.
- `TimeoutHttpClient` upload mode is opt-in: every parameter defaults to null,
  so GitHub, lookup and viewer traffic keep the old behaviour.
- `FilePublishArtifactStore` was the only spool writer; the memory scenario and
  seven test files construct it with `baseDir:`.

## Proposed approach

1. `PublishArtifactSpoolRoot` (infrastructure) owns both roots, a lock, and the
   set of run folders in use. `createRunDirectory()` sweeps then creates;
   `release()` unregisters; `sweep()` is separately testable.
2. `appTempDir` keepAlive provider in `platform_providers.dart`.
3. `FilePublishArtifactStore` takes the spool root instead of a base path.
4. Tests: upload-progress client, transport classification/retry policy, deploy
   API 401 + session budget, spool root sweep, and the two real-loopback cases.
5. Records: ADR 0017 Decision 8, ADR 0007, Part M rows 93–95, CHANGELOG.

## Decision points

- A sweep failure must never block a publish (that would be a new dead end), so
  `createRunDirectory` treats cleanup as best-effort while `sweep()` still
  returns a typed `Either` for the test and for callers that care.

## Steps

- [x] H2/L8 code (carried in the working tree): limits, upload-mode client,
      timing profiles, no blind resend, session budget, status-first parsing.
- [x] L5: `PublishArtifactSpoolRoot`, `appTempDir`, store rewiring.
- [x] Tests: upload progress, transport, deploy API, spool root, loopback.
- [x] Records: ADR 0017, ADR 0007, Part M rows 93–95, CHANGELOG, handoff.
- [x] Gates: build_runner (no diff), format clean, analyze zero issues,
      non-golden suite green (4,345 tests).

## Out of scope

- Splitting buckets (plan H2 step 7: optional follow-up after a real-host trial).
- Phase 3+ findings (moves, reconnects, copy) and the Phase 6 real-host run.

## Result

Phase 2 is implemented end to end.

- **H2:** `CloudflareLimits` names each bound (60 s connect, 60 s idle,
  `60 s + 8 MiB ÷ 64 KiB/s` header wait, `60 s + bytes ÷ 64 KiB/s` total capped
  at 20 min, 55 min session budget, 1 MiB blind-resend limit, 256 KiB
  large-body threshold). `TimeoutHttpClient` has an opt-in upload mode that
  counts pulled body chunks and re-arms an idle timer; every new parameter
  defaults to null, so GitHub/lookup/viewer behaviour is unchanged.
  `CloudflareRequestTiming` is the only place a duration is chosen. A failed
  attempt that already sent more than 1 MiB is never blindly re-sent; a 401
  from the bucket endpoint is `uploadTooSlow`; a session older than 55 min
  refuses another bucket.
- **L8:** `_parse` classifies by status first (non-JSON 429/5xx → status-only
  response; non-JSON 4xx stays `malformedResponse`). `CloudflareByteSourceException`,
  `CloudflareAssetHashException` and the base64 chunk check map to the new
  non-retryable `artifactChanged`.
- **L5:** `PublishArtifactSpoolRoot` owns the OS temporary root plus the legacy
  Documents root, a lock and the live-run set. `createRunDirectory()` sweeps
  then creates; the sweep deletes only real `run-[A-Za-z0-9_-]{1,64}` folders
  under the app's own `publish_artifacts` roots, never follows a link, never
  touches a live folder, and never blocks a publish when a delete fails.
  `appTempDir` is a keepAlive provider; the sweep runs on the first `spool()`,
  inside a queued operation.

Tests added: upload-progress client (5), transport H2/L8 groups (8), request
timing (8), deploy API 401 + session budget + rewritten changed-bytes (3), use
case stall/too-slow copy (2), real-loopback stall and slow-drain (2), spool
root (7) — 35 new tests. A defect found while testing: a hash mismatch inside
the upload stream was still classified as a retryable network error, so
`CloudflareAssetHashException` now maps to `artifactChanged`.

Records: ADR 0017 Decision 8 and the S8 spool paragraph, ADR 0007's JWT
lifetime note, ARCHITECTURE §5.6 bounds and the stored-data table, Part M rows
93–95, CHANGELOG "Fixed", handoff §17.
