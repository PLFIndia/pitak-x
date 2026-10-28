# ADR 0017: Cloudflare Workers publishing — dedicated Worker, one active host

- **Status:** Proposed (S2 and S7 outcomes recorded 2026-10-27; final wording
  follows the S10 consistency audit)
- **Date:** 2026-10-26
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
   pending move with the exact old/new targets, phase and source anchor —
   never a token. The active pointer switches only after the destination is
   verified **and** retirement verifies.
6. **Marker freshness, not compare-and-swap.** Every Cloudflare deploy writes
   `pitak-publish.json` with a fresh 128-bit `publishId` and a
   `live` / `verification` / `retired` state. A matching marker is the
   freshness anchor; the deployment id is diagnostics only. A retired site is
   recognised only by a positive retired marker, never by a 404.
7. **Version URLs fail closed.** For an existing Worker, version URLs are
   disabled and GET-confirmed off before creating another version, and
   reconfirmed after the deploy. A failure stops the next deploy and blocks
   retirement completion.
8. **Bounded, hostile-boundary transport.** API traffic goes only to
   `https://api.cloudflare.com/client/v4` with `AppUserAgent`, refused
   redirects, abortable 30 s / 60 s deadlines, a 1 MiB streamed response cap,
   a JSON depth/bounds pre-scan, whitelisted fields and fixed failure messages.
   Upload/completion JWTs are ephemeral strings (ADR 0007).
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
- **S8 makes replacement a two-phase, write-free confirmation.** Unknown or
  positively retired state builds a strict complete snapshot against an empty
  previous publication and returns a typed summary with real counts and a
  canonical digest. No route update, upload session, bucket upload, deploy, or
  credential/manifest write occurs during preparation. Confirmation re-enters
  the queue, revalidates remote anchors and rebuilds from current local data;
  any digest change requires another review. The digest excludes operation
  timestamps and ids, and reads only volatile JSON from the spool on demand.
- **S8 bounds build and upload memory together.** A per-file
  `PublishArtifactSink` spools public bytes during section building and leaves
  metadata-only files in Cloudflare snapshots. The assembler deduplicates by
  content hash, and one bucket is streamed at a time through reopenable 64 KiB
  sources. GitHub keeps its original byte-bearing files and byte-for-byte
  behavior. Temporary spools are operation-scoped and cleaned in `finally`.
- **S8 requires complete publication proof.** Freshness is checked at preflight
  and immediately before deployment. Read-back covers the fresh marker,
  `books.json`, descriptor bytes or its real 404, events JSON when present,
  current posters, and exact removed-poster 404s. A matching `deployed` record
  is verified before another deployment; verification failure stops, while a
  successful retry creates no new deployment. A `live` manifest with an
  incomplete journal/connection commit is re-proven before repair. Persistence
  is ordered `deployed`, then `live`, journal `verifiedTarget`, and finally the
  whole secure connection's write-proven flag.
- Follow-up enforcement: session gates S6–S11 of the plan, the D1–D5
  behavioural tests, the J.1–J.6 suites, the J.7 real-host smoke matrix, and
  the documentation check in Part K. The sanitized S2 evidence is in plan Part
  M.1; this ADR is finalized by the S10 consistency audit.
