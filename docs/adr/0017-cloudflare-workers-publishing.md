# ADR 0017: Cloudflare Workers publishing — dedicated Worker, one active host

- **Status:** Accepted (2026-10-28). Proposed 2026-10-26; S2 trial outcomes
  recorded 2026-10-27, S7/S8/S9 implementation outcomes 2026-10-28, and the
  S10 consistency audit reconciled every document that cites it. The S11 Linux
  golden was regenerated on 2026-10-29; the real-host smoke is still
  outstanding, so the *evidence* is not complete — the decision is.
- **Date:** 2026-10-26 (amended 2026-10-29 by the Cloudflare fix plan,
  Phase 1A: published-record ownership, anchor-bound replacement consent,
  Option-B read-back, and the upload-session Worker baseline)
- **Amends:** ADR 0007 (a third persisted `String` token plus ephemeral
  upload/completion JWTs) and ADR 0010 (no pinning for a second publishing
  API). ADR 0012 gains the `workers.dev` reader URL by the same work.
- **Plan:** `cloudflare_plan-final.md` (parts A–N). Related: ADR 0007,
  ADR 0010, ADR 0012, ADR 0015, ADR 0016.

## Context

A library can today publish its read-only site (catalogue, events and
`library.json`) to **GitHub Pages** from the phone. Library owners also want
to publish to **Cloudflare Workers static assets** — same content, one
alternative host — without a WebView, a new Flutter plugin or hand-rolled
crypto (AGENTS §6, §9).

Cloudflare's static-asset API is *whole-Worker*: an assets-only deployment
replaces the complete asset set of the Worker and versions it. That has three
consequences the product cannot hide:

1. Pitak cannot promise to preserve arbitrary files a user put on the same
   Worker. A Worker used by Pitak must be **dedicated to Pitak**.
2. A deploy is a snapshot, so a move or an "unknown remote state" publish
   needs a **complete, validated snapshot**, never a best-effort merge.
3. The API offers no documented "deploy only if the live state is still X"
   conditional write. A marker file can detect *observed* staleness but
   cannot make two devices atomic.

## Decision

1. **Dedicated Worker, assets-only.** A Cloudflare target is
   `https://<worker>.<account-subdomain>.workers.dev/` published by an
   assets-only Worker (no user Worker code). Adopting an existing Worker
   requires explicit whole-Worker-replacement consent. Pitak creates only its
   fixed public files, reserved `covers/` + `posters/` paths and the
   `pitak-publish.json` marker there.
2. **One active host at a time.** Existing GitHub libraries stay on GitHub
   until their owner moves. A move publishes and verifies the destination
   first; the old site becomes a moved page only after that.
3. **Sealed, host-specific targets.** `PublishTarget` is sealed into
   `GitHubPublishTarget` and `CloudflarePublishTarget`; the descriptor URL is
   always derived from the explicit target passed to the operation, never from
   a mutable "active" provider. `library.json` gets the *new* address during a
   move.
4. **Complete snapshots and exact ownership.** Moves, replacements and
   retirements require a strict complete snapshot (catalogue, periodicals,
   settings, events metadata, every required poster/cover bytes) that fails
   typed and write-free when anything is missing. GitHub deletions are limited
   to consented app-owned paths from a schema-2 manifest; unrelated files
   survive.
5. **One atomic journal.** `publish_host_state` (one preferences key) holds
   the active host, the single `verifiedTarget` used for share/QR, and any
   pending move with the exact old/new targets, phase, source anchor and an
   immutable retirement descriptor (the moved-page bytes/schema, exact GitHub
   deletion paths or Cloudflare retired-marker id). It never holds a token.
   Reads distinguish "absent" from "unreadable", so corrupt pending history
   fails closed instead of starting over. The active pointer switches only
   after the destination is verified **and** retirement verifies.
6. **Marker freshness, not compare-and-swap.** Every Cloudflare deploy writes
   `pitak-publish.json` with a fresh 128-bit `publishId` and a
   `live` / `verification` / `retired` state. A matching marker is the
   freshness anchor; the deployment id is diagnostics only. A retired site is
   recognised only by a positive retired marker, never by a 404. Creating the
   asset upload session may itself create the Worker, so a publish re-reads the
   Worker and marker around its own session and adopts only a Worker with a
   never-present marker as its baseline. That is still observed staleness: the
   session request itself is the one window that cannot be attributed.
7. **Version URLs fail closed.** For an existing Worker, version URLs are
   disabled and GET-confirmed off before creating another version, and
   reconfirmed after the deploy. A failure stops the next deploy and blocks
   retirement completion.
8. **Bounded, hostile-boundary transport.** API traffic goes only to
   `https://api.cloudflare.com/client/v4` with `AppUserAgent`, refused
   redirects, a 1 MiB streamed response cap, a JSON depth/bounds pre-scan,
   whitelisted fields and fixed failure messages. Deadlines answer two separate
   questions instead of sharing one number (fix-plan H2): an ordinary API call
   is bounded at 30 s, a metadata-only deploy at 60 s, and an upload by
   *progress* — a 60 s connect bound, a 60 s idle bound between pulled body
   chunks, a 60 s + 8 MiB ÷ 64 KiB/s wait for response headers, and a total of
   `60 s + bytes ÷ 64 KiB/s` capped at 20 min. A failed attempt that already
   sent more than 1 MiB is never blindly re-sent, and a session older than
   55 min refuses another bucket because Cloudflare's upload JWT lives one
   hour. Upload/completion JWTs are ephemeral strings (ADR 0007).
9. **Reader rules.** `workers.dev` addresses are accepted only in the exact
   `<worker>.<subdomain>.workers.dev/` root form. A moved library is a
   *candidate* for the user to confirm — never an automatic follow — and
   acceptance is one transactional merge/repoint that keeps both URL and
   fingerprint uniqueness.

## Consequences

- **Single-writer limitation is disclosed.** The local app-wide operation
  queue serialises this device only. Two devices publishing to one Worker
  concurrently can lose a write; the marker fails closed on *observed*
  staleness but is not claimed to be atomic compare-and-swap. S2/T14 found no
  qualifying supported conditional-deployment contract in the current docs or
  Wrangler source. One publisher at a time per Worker is therefore an operating
  requirement and is documented in README, the in-app guide, the privacy
  disclosure and store answers.
- S2/T6 confirmed assets-only metadata deployment on a disposable account, so
  the assets-only plan proceeds. Shipping user Worker code remains a separate
  product decision, not a fallback.
- A move can leave a verified destination published while the source is not yet
  retired; the journal keeps the old active/verified target truthful and the
  UI shows a persistent retry banner with the verified new address.
- Cloudflare sees device IP/User-Agent on API calls, uploaded files and public
  site traffic; deduplicated asset bytes may remain server-side even when no
  deployment happens. Failure copy therefore says "your live site was not
  changed", not "nothing was sent".
- Moved pages: Cloudflare gets full response-header CSP; GitHub keeps only the
  directives a `<meta>` tag can enforce, and that limitation is documented.
- **S2 confirmed the version-URL gate.** `previews_enabled` is the controlling
  field: the old version was unreachable when off and reachable when on; a
  failed disable left it reachable until a confirmed off. C8/R14 is therefore
  mandatory, not advisory.
- **S2 confirmed the asset-hash formula.** T4–T5 accepted
  `hex(SHA-256(base64(bytes) + extension))[0..32]` with the exact restricted
  token. `hashScheme` remains `sha256-b64-ext-32`; no blake3 dependency is
  added. The stored scheme still protects future migrations.
- **S7 keeps connection credentials cohesive.** One versioned `cf_connection`
  record lives in hardened secure storage and is replaced as a whole. A new
  token starts fresh; user tokens verify immediately, account tokens verify at
  the selected account before their first save. The creation button uses the
  account-owned Workers-scripts-only template so one-account scope is the
  default, while compatible pasted user tokens remain supported.
- **S7 verification is not a live publication.** Manual subdomains stay
  candidates until a marker-only deploy is read back from the exact origin.
  Success stores the confirmed target, but writes no normal live manifest and
  no journal `verifiedTarget`. Manual proof names its exact Worker and cannot
  confirm a different Worker. Host activation is a separate idempotent write;
  its retry never deploys again. A legacy GitHub manifest still counts as an
  active GitHub host without bypassing read-back-gated address migration.
  Post-deploy Version-URL and marker failures expose their privacy/partial
  outcomes explicitly.
- **S7 makes the local queue real.** One keep-alive provider serializes
  catalogue/events publishing, GitHub credential/target mutations, and every
  Cloudflare setup command. Dialogs and other user waits remain outside it.
- **S8 publishes through one active-host command path.** A raw stored-journal
  read chooses the host without manifest IO before strict reads. An absent
  journal alone uses the documented legacy GitHub default; an existing journal
  never falls back from one host's credentials to the other's. One Cloudflare
  use-case factory serves catalogue and events, and the publish card shows the
  configured target separately from the journal's verified share address.
- **S8 makes replacement a two-phase, write-free confirmation.** Unknown,
  positively retired, deleted-Worker and missing-bytes states build a strict
  complete snapshot against an empty previous publication and return a typed
  summary with real counts, a canonical digest, and the remote anchor the user
  reviewed. No route update, bucket upload, deploy, or credential/manifest
  write occurs during preparation; the missing-bytes path may open an upload
  session because that is the protocol's only way to report which hashes remain
  (recorded exception, Part M row 88). Confirmation re-enters the queue and
  rebuilds from current local data; it proceeds only while a fresh preflight
  reports the same anchor, any digest change requires another review, and a
  changed anchor writes nothing and returns a fresh summary. The digest
  excludes operation timestamps and ids, and reads only volatile JSON from the
  spool on demand.
- **S8 bounds build and upload memory together.** A per-file
  `PublishArtifactSink` spools public bytes during section building and leaves
  metadata-only files in Cloudflare snapshots. The assembler deduplicates by
  content hash, and one bucket is streamed at a time through reopenable 64 KiB
  sources. GitHub keeps its original byte-bearing files and byte-for-byte
  behavior. Temporary spools are operation-scoped, cleaned in `finally`, live
  in the OS temporary directory, and swept at the next operation: only real
  `run-` folders under the app's own `publish_artifacts` roots are deleted,
  never a link, never a folder this process is using, and a sweep failure
  never blocks a publish (fix-plan L5).
- **S8 requires complete publication proof.** Freshness is checked at preflight
  and immediately before deployment. Read-back covers the documented set: the
  fresh marker, `books.json`, the root `index.html`, `library.json` or its real
  404, the events files when recorded, at most two posters, and exact
  removed-poster 404s. Covers are not read back: the upload protocol already
  proved every hash before the completion token, and a version is atomic. The
  result is one of `verified`, `contradicted` (a file answered with different
  bytes, or serves a body where a 404 was required) or `unreachable` (nothing
  was proven either way), under a bounded budget: 12 × 5 s inside 90 s after a
  deploy, 3 × 2 s inside 20 s for an earlier record. A matching `deployed`
  record is verified before another deployment: `verified` commits it and
  continues, `contradicted` offers a `recordContradicted` whole-site
  replacement, and `unreachable` continues the publish without marking the old
  record live. Retry verification reports the specific case instead of
  blocking. A `live` manifest with an incomplete journal/connection commit is
  re-proven before repair. Persistence is ordered `deployed`, then `live`,
  journal `verifiedTarget`, and finally the whole secure connection's
  write-proven flag.
- **Verification status.** The J.1–J.6 suites are green (4,212 non-golden
  tests on 2026-10-29), all 10 Linux golden tests pass, and the S10 consistency
  audit reconciled `README.md`, `PRIVACY.md`, `SECURITY.md`,
  `docs/ARCHITECTURE.md`, `docs/RELEASING.md`, `CHANGELOG.md` and the in-app
  guide with the behaviour described here. The `publish_connection` golden was
  regenerated from the Linux workflow on 2026-10-29. What remains is evidence,
  not decision: the **S11 J.7 real-host smoke** on a disposable account. (The
  S2 trial tool, the third S11 cleanup item, was removed on 2026-10-28.)
  Acceptance does *not* claim a supported
  compare-and-swap contract (no such contract exists — see §Decision 6 and
  Consequences) and does not promise that arbitrary user files on a dedicated
  Worker survive.
