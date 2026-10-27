# Cloudflare Workers publishing — consolidated implementation plan

- **Branch:** `cloudflare` (from `main` at `e8c4d8e`, 2026-10-26).
- **Status:** consolidated design; S0–S5 landed on the branch (see
  `docs/plans/cloudflare-handoff.md` for the per-session record). S2 (the
  disposable-account trial) is the next gate and needs a human; S6–S9 wait for
  its report.
- **Supersedes:** `cloudflare_plan.md` and `cloudflare_plan_amendments.md`.
  Those files remain review history only. Implementation uses this document.
- **Scope:** a library can publish its read-only site (catalogue, events and
  `library.json`) to **Cloudflare Workers static assets** from the phone, as an
  alternative to GitHub Pages. One active host at a time; the old host becomes
  a moved page after the new site is verified.
- **Authoritative contracts:** `AGENTS.md`, `docs/ARCHITECTURE.md`, ADRs 0007,
  0010, 0012, 0015 and 0016, plus the ADR amendments in Part K.
- **Review rule:** the consolidation decisions in A.2 change the original
  product/technical design. They must be reviewed before S0. In particular,
  dedicated Workers and the possible single-writer limitation are explicit
  product decisions, not silent implementation assumptions.

Every session ends green: generated files up to date, `dart analyze`,
`dart format --set-exit-if-changed`, and `flutter test`. The CI gates in
`AGENTS.md` remain required. A session may change this plan only by recording a
deviation in Part M first. It must never silently weaken security, privacy,
compatibility or data-loss rules.

---

# Part A — Decisions and protected promises

## A.1 Original decisions retained

| ID | Decision |
|---|---|
| M1 | **Cloudflare Workers static assets**, using an assets-only Worker. Cloudflare Pages is not used. |
| M2 | **One active host at a time** — GitHub Pages or Cloudflare. Existing GitHub libraries stay on GitHub until their owners move. |
| M3 | **Sign-in with a pasted API token**, scoped to one account with `Workers Scripts · Edit`. OAuth is a later project. |
| M4 | **The old site becomes a moved page** only after the new site is verified. `index.html` and `404.html` link and redirect to the new address. Pitak catalogue/events data is removed. |
| M5 | Other apps **do not automatically follow moves**. They may offer an explicit, user-confirmed address reconciliation when stored identity evidence shows a possible duplicate. |
| M6 | Unknown Cloudflare live state requires an explicit **whole-site replacement** confirmation. It is never described as an additive publish. |
| M7 | Reader and publisher ship in **one release**. Older apps cannot add `workers.dev` libraries until updated. |
| M8 | A disposable-account **trial with the exact least-privilege token** precedes Cloudflare transport and publisher implementation. |

## A.2 Consolidation decisions

| ID | Decision |
|---|---|
| C1 | **A Cloudflare Worker is dedicated to Pitak.** A deploy is a complete Worker-asset snapshot. Arbitrary non-Pitak assets on that Worker are not promised to survive. Adopting an existing Worker requires explicit whole-Worker replacement consent. If this is not accepted, stop and redesign; R17 of the original plan cannot be implemented for Cloudflare otherwise. |
| C2 | **Moves and whole-site replacements require a strict, complete snapshot.** Missing/corrupt metadata or a required asset is a typed failure before any target write. A read-back of degraded output is not success. |
| C3 | **Publish targets are sealed and host-specific.** URLs are derived and cross-checked, never accepted as an arbitrary `{host, siteUrl}` pair. Pending moves persist exact old/new targets and phase in one atomic journal, without tokens. |
| C4 | **GitHub manifests become repo + branch + head aware.** Legacy manifests are reconciled before section merging. Commits use an expected head, and manifest saves are atomic and report failure. |
| C5 | **The Cloudflare publish marker is the freshness anchor.** `liveId` is optional diagnostics only. A marker is not claimed to provide atomic compare-and-swap across devices. |
| C6 | S2 must determine whether a usable conditional-deployment contract exists. If it does not, **one publisher at a time per Worker is an operating requirement**. The marker still fails closed on observed staleness, but no claim is made that it eliminates a simultaneous-writer race. If the maintainer requires a hard multi-writer no-loss guarantee, the assets-only design stops here. |
| C7 | **Retirement is positively identifiable.** A retired Cloudflare deployment retains a small marker with `state: "retired"` and a fresh publish id. `state=retired` locally plus marker 404 is not proof and never bypasses replacement confirmation. |
| C8 | **Version URLs are confirmed disabled before creating any subsequent version**, and confirmed again afterward. Failure blocks the next deployment and prevents retirement completion. The first Worker version is the only pre-deploy exception because there is no older version to expose; it is configured immediately after that deploy. |
| C9 | **Unverified addresses never become publish targets.** A manually supplied account subdomain is a candidate only. It cannot enter `library.json`, a QR card, a share link or a move until exact-origin verification succeeds. |
| C10 | **Reader reconciliation replaces AM-2.** Both URL and fingerprint uniqueness remain. Candidates are detected before conflict suppression, and acceptance performs one transactional merge/delete-plus-repoint. Reachability never chooses the new address by itself. |
| C11 | **Upload memory is bounded end to end.** Hash-keyed byte lookup does not imply retaining all artifact bytes. Byte sources are on demand or spooled; aggregate in-flight encoded bytes are bounded. Serial bucket upload is the initial implementation. |
| C12 | **Moved-page hardening is host truthful.** Cloudflare supplies full CSP and related headers. GitHub retains the CSP directives that work in a `<meta>` tag and documents the directives it cannot enforce. Library name and address are escaped in every template context. |

## A.3 Product promises

- **P1 — no silent loss or downgrade.** A publish never erases the other
  section; a move never retires the source before a complete destination is
  verified; unknown/stale state fails closed; local read failures never become
  empty public content.
- **P2 — hostile boundaries.** New token, new egress and every remote response
  are treated as hostile. Secrets never appear in state, logs, URLs, exceptions
  or user-facing raw response text.
- **P3 — pure Dart app integration.** No WebView, no new Flutter plugin and no
  Google code. Cloudflare Worker code is not shipped unless a separate product
  decision replaces this plan.
- **P4 — release truth.** Documentation, privacy disclosures, smoke tests and
  store answers match actual behavior, including the single-writer limitation
  and dedicated-Worker replacement policy.
- **P5 — one blessed way.** Shared builders, path policy, secure-storage
  options, read-back policy and manifest merge logic have one implementation.
  Architectural changes receive ADRs.
- **P6 — deterministic behavior.** Bounded IO, explicit state machines,
  idempotent retries and crash-point tests are features, not afterthoughts.

## A.4 Non-goals

- Cloudflare Pages, dashboard Git integration, Workers Builds or custom domains.
- OAuth / “Sign in with Cloudflare”.
- One library on two active hosts, mirrors, or automatic peer redirection.
- Machine-readable moved notices for other apps.
- Deleting old repositories or Workers from the app.
- Functions or user Worker code; a WebView; background/scheduled publishing.
- Changes to `books.json`, `events.json` or `library.json` wire formats.
- Preserving arbitrary user assets on a dedicated Cloudflare Worker.
- A hard cross-device concurrent-writer guarantee unless S2 establishes a real
  conditional-deployment contract and the implementation uses it.

---

# Part B — External contract and facts to verify

Facts below come from Cloudflare documentation and Wrangler source reviewed on
2026-10-26. “Observed” behavior is not treated as load-bearing until S2 passes.

## B.1 Address and names

- Address: `https://<worker>.<account-subdomain>.workers.dev/`.
- Worker names used with `workers.dev`: at most 63 letters, digits and hyphens;
  no leading/trailing hyphen. The API name may preserve case; the DNS label is
  lower-case.
- The account subdomain is account-wide and may be permanent. Creating it is
  always explicit.
- A stored/published Workers site has exactly two valid leading DNS labels and
  a canonical root path. Generic host-suffix acceptance alone is insufficient.
- References:
  - https://developers.cloudflare.com/workers/configuration/routing/workers-dev/
  - https://developers.cloudflare.com/workers/static-assets/direct-upload/

## B.2 Asset upload

1. `POST /accounts/{a}/workers/scripts/{name}/assets-upload-session` with a
   manifest of path → `{hash, size}` returns `{jwt, buckets}`.
2. Local `SitePath` values have no leading slash. The infrastructure adapter,
   and only the adapter, adds exactly one leading `/` for Cloudflare manifest
   keys.
3. Each bucket is uploaded to
   `POST /accounts/{a}/workers/assets/upload?base64=true` with the upload JWT as
   bearer. Multipart part name and filename are the asset hash; part
   `Content-Type` becomes the served type; body text is base64.
4. Empty buckets mean the session JWT is already the completion token.
   Otherwise the final successful bucket response supplies the completion JWT.
5. Deploy with the completion JWT in the multipart `metadata` part.
6. Upload and completion JWTs last at most one hour and are bearer secrets.

## B.3 Assets-only deployment

Wrangler emits a metadata-only multipart body for assets without a user Worker.
The API reference still documents module-oriented upload behavior, so T6 must
confirm the metadata-only form on a disposable account.

Relevant asset config:

- `html_handling: "auto-trailing-slash"` (pinned by trial and read-back tests);
- `not_found_handling: "none"` for a live site;
- `not_found_handling: "404-page"` for a retired site;
- `_headers` supplied as a string;
- a fixed reviewed `compatibility_date`, initially `2026-10-26`.

If T6 fails, stop. Do not improvise a Worker module under this plan.

References:

- https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/
- https://github.com/cloudflare/workers-sdk/blob/main/packages/deploy-helpers/src/deploy/helpers/create-worker-upload-form.ts

## B.4 Subdomain, deployments and old versions

- Account subdomain read/check/create uses the Workers subdomain endpoints in
  Part G. Error 10007 means no account subdomain; observed 10032/10031 are
  availability outcomes to re-check in the trial.
- A scoped token may be unable to read/create the account-level subdomain even
  when it can deploy a Worker. The fallback is F.2, not a broader token by
  default.
- Version URLs were previously called preview URLs; Wrangler's config field
  remains `preview_urls`, and API shapes may call it `previews_enabled`.
- When enabled, version URLs are public. With no explicit setting, their
  default can follow the `workers.dev` route. Therefore C8 is mandatory.
- `/deployments` and its latest id are optional diagnostics. No correctness
  decision depends on that endpoint.
- References:
  - https://developers.cloudflare.com/workers/versions-and-deployments/version-urls/
  - https://github.com/cloudflare/workers-sdk/blob/main/packages/deploy-helpers/src/triggers/subdomain.ts

## B.5 Conditional writes

The reviewed script-upload reference does not document a conditional “deploy
only if the live state is still X” parameter. S2 checks current docs, Wrangler
and the disposable API for a supported contract. No undocumented production
header or guess is allowed. Absent such a contract, C6 applies.

## B.6 Limits and API budget

- Free plan: 20,000 files per version, 25 MiB per file, 100 Workers per account.
- Static-file requests are free within Cloudflare's documented terms.
- API budget: 1,200 requests per five minutes per user, shared with dashboard
  use. Honor 429 and `retry-after`.
- References:
  - https://developers.cloudflare.com/workers/platform/limits/
  - https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/
  - https://developers.cloudflare.com/fundamentals/api/reference/limits/

## B.7 Asset hash and content types

- Asset hash:
  `hex(SHA-256(base64(bytes) + extension))[0..32]`.
  Base64 is standard with padding; extension omits the dot and keeps case.
- `package:crypto` supplies SHA-256. Fixed vectors pin the formula, including an
  empty file and extension case.
- Only these published types are accepted:
  - `html` → `text/html; charset=utf-8`
  - `json` → `application/json`
  - `jpg` → `image/jpeg`
- Any other extension refuses the publish before upload.

## B.8 Tokens and errors

- Token shapes include `cfut_…`, `cfat_…` and older 40-character tokens. A value
  object checks shape and a bounded maximum length without retaining or printing
  the value.
- Verify user tokens with `/user/tokens/verify`; verify account tokens against
  the chosen account. `active` does not prove every required Workers write.
- Accounts are listed with bounded pagination. Refusal or truncation has an
  explicit Account ID fallback.
- API errors use `{success, errors, messages, result}`. Read only whitelisted
  fields and numeric error codes. Never display or log raw `message` text.

---

# Part C — Binding engineering rules

## C.1 Targets, snapshots and builders

**R1 — Explicit sealed targets.** `PublishTarget` is sealed:

- `GitHubPublishTarget`: `ownerRepo`, expected Pages `branch`, derived canonical
  `siteUrl` and stable `targetId`.
- `CloudflarePublishTarget`: `accountId`, `workerName`, confirmed
  `accountSubdomain`, derived canonical root `siteUrl` and stable `targetId`.

There is no public constructor accepting an arbitrary host plus URL. Targets
contain no token. `library.json.siteUrl` always comes from the target passed to
the current operation, never from a global/active provider. A move passes the
new target before the active host changes; retirement passes the old target.

**R2 — Strict complete snapshots.** Application builders return
`Either<Failure, PublishSnapshot>`. A complete snapshot is required for moves,
M6 replacement and GitHub “everything”. It means:

- catalogue, periodical, settings, network-descriptor and events metadata all
  read successfully;
- every required local poster/cover resolves to usable bytes;
- every destination file is accounted for, including carried metadata;
- catalogue/poster counts and empty-section warnings come from this snapshot;
- no remote write has happened while it is being built or confirmed.

A corrupt events file is not `EventsContent.empty`. Add a strict publish read
port or correct the repository contract; do not catch-and-empty in the publish
path. **Every** publish uses strict metadata reads. An incremental publish may
reuse an already-published asset on the same target under the existing explicit
fallback rules, but it may not silently drop a referenced poster/cover or
degrade the other section. A complete destination cannot reuse bytes that exist
only on the old host: before any destination write it must materialize them
from the local source, the bounded original remote source, or the verified old
site into the artifact spool, and abort if all sources fail. Valid-input GitHub
bytes remain unchanged; fail-closed handling of unreadable input is a
deliberate recorded behavior fix.

**R3 — Build once, share builders.** Catalogue and events section builders are
extracted after characterization tests pin current GitHub bytes. Host adapters
consume the same built section. Valid-input GitHub bytes remain identical;
wiring edits are mechanical. Deliberate stale-file deletion fixes are recorded,
not hidden behind the byte-identity promise.

**R4 — Complete two-phase confirmation.** If replacement confirmation is
needed, preparation returns a typed `ReplacementRequired` summary and a
canonical snapshot digest without writing. Confirmation re-enters the queue,
revalidates remote anchors and **rebuilds from current local data**. The new
snapshot digest must equal the confirmed one; otherwise the updated counts and
content require another confirmation. The digest covers canonical section
content and asset hashes but excludes operation-generated ids and wall-clock
fields such as `publishId`/`exportedAt`. Restore/data-generation checks are
additional guards, never a substitute for rebuilding, because ordinary edits
may not change a restore generation.

## C.2 Manifests and section merging

**R5 — Manifest meaning is explicit.** A manifest is no longer described as a
mere best-effort cache. It is local reconciliation state whose uncertainty has
a defined safe outcome.

GitHub manifest schema 2 contains:

- `repo`, `branch`, `headSha`, `ownershipConfirmed`;
- `state`: `deployed`, `live` or `retired`;
- every known app-owned path → git blob SHA;
- catalogue cover-source metadata.

Cloudflare manifest schema 2 contains:

- full target identity (`accountId`, `workerName`, `accountSubdomain`,
  canonical `siteUrl`);
- `state`: `deployed`, `live` or `retired`;
- current `publishId`, `hashScheme`, optional diagnostic `liveId`;
- every Worker asset path → content SHA, asset hash, size and content type;
- catalogue cover-source metadata.

`deployed` means the API accepted a deployment but read-back has not completed.
`live` means required read-back succeeded for that manifest's target.
Separately, the host journal stores one `verifiedTarget` for the active host.
That pointer is updated only after required read-back and is the sole source
for share/QR state. A later `deployed` state or an unverified target change does
not erase the previously verified pointer; a first deployment with no pointer
is not shareable as live. `pendingMove.newTarget` may be written only after
that destination has passed R16, and the old active/verified pointer remains
selected until retirement completes.

**R6 — GitHub reconciliation.** Before using a manifest:

- Read the actual Pages configuration and expected branch.
- Read a typed `GitHubTreeSnapshot {repo, branch, headSha, files, truncated}`.
- Missing repo/branch/head match, a legacy manifest or uncertain local state
  causes a rebuild from a complete tree. Only consented app-owned paths enter
  the manifest; unrelated files stay in GitHub's base tree and are not adopted.
- Malformed, failed or truncated tree reads are typed failures, never an empty
  tree.
- `commitFiles` receives `expectedHead`; a mismatch is a typed stale failure.
  `force: false` remains mandatory.
- The returned commit SHA is stored with the merged manifest.

Normal GitHub publishing may reconcile against the current remote tree. A move
may not silently use that rule to overwrite a newer source: F.5 requires the
source anchor to match the phone's last successful publication.

**R7 — One section merge.** `mergeSection` is the only way a section updates a
manifest. It:

- removes exactly the paths owned by that section from the previous app-owned
  set;
- adds the newly built files;
- preserves the other section;
- returns owned obsolete paths for GitHub deletion;
- preserves or replaces cover-source metadata as appropriate;
- rejects unknown or unsafe paths.

Cloudflare's merged map is the complete next Worker snapshot. GitHub's commit
uses the current base tree plus built files and exact owned deletions, so
unrelated repository files survive.

**R8 — Legacy regression is a release blocker.** The regression sequence is:
publish events with two posters → publish catalogue → remove one poster →
publish events → the removed poster is in `deletePaths` and absent from the
manifest. Add equivalent stale-cover and legacy-manifest upgrade tests.

**R9 — Atomic observable saves.** All manifest stores write temp-then-rename.
Save returns `Either<Failure, Unit>` (or an equivalent typed result); failure
is not swallowed. A Cloudflare deploy followed by local save failure reports
“updated but local state could not be committed” and reconciles through the
marker next time. It never pretends nothing changed.

## C.3 Freshness, ownership and serialization

**R10 — Cloudflare marker.** Every normal deploy writes
`pitak-publish.json`:

```json
{
  "schema": 1,
  "publishId": "<128-bit lower-case hex from Random.secure>",
  "publishedAt": 0,
  "state": "live"
}
```

`publishedAt` is epoch milliseconds and diagnostic only. Marker `state`
describes the deployed snapshot kind, not proof that read-back succeeded;
verification is tracked by local manifest state and the journal's
`verifiedTarget`. A retired
deploy uses a fresh id and `state: "retired"`. The verification-only flow in
D.2 uses `state: "verification"`; that state is never accepted as an ordinary
live manifest. The file is JSON, small, public and contains no account id,
token, deployment id or target metadata.

Freshness outcomes:

- marker id matches the manifest, with marker `live` matching local
  `deployed`/`live` and marker `retired` matching local `retired` → known state;
- different id/state, a verification marker during ordinary publish, malformed
  response or unexpected content → unknown;
- Worker absent and marker 404 with no matching local manifest (or during
  explicit first-time setup) → new site;
- Worker absent with a matching local manifest → `SiteUnavailable`; require the
  explicit recreate/setup flow with a complete snapshot, never an incremental
  publish that pretends the old remote is still present;
- Worker present without a valid marker → unknown, including when the local
  manifest says retired;
- retired manifest plus exact matching retired marker → known retired state;
  a return move may proceed with its normal complete-snapshot confirmation.

The marker is fetched at the exact expected origin with a cache-buster and a
small byte cap. It is checked during preflight and again immediately before
deploy. It detects observed staleness; C6 governs the remaining race.

**R11 — One app-wide operation queue.** Catalogue/events/everything publishes,
moves, retirement and host credential/target mutations share one keep-alive
`SerialOpQueue` provider. Setup, disconnect and target changes cannot race a
publish. Interactive dialogs and read-only token/account discovery may happen
outside the queue; every credential/target write and every verification deploy
happens inside it, so the queue is never held while waiting for a user to paste
or choose something. Only the outermost command enqueues; inner steps document
that the queue is already held. Nested enqueue is forbidden because the queue
is not reentrant.

**R12 — Dedicated Worker ownership.** Cloudflare deploys replace the complete
asset set of the dedicated Worker. Existing-Worker adoption and verification
deploys explicitly disclose this. Do not claim arbitrary user files survive.
The only files Pitak creates on a live/retired Worker are the fixed public
files, reserved cover/poster paths and the marker.

**R13 — Exact GitHub ownership.** GitHub never deletes an arbitrary repository
file. Fixed Pitak filenames and reserved `covers/`/`posters/` namespaces are
explained when adopting an existing repository; `ownershipConfirmed` records
that consent. App-created repositories have it by construction. Deletion uses
exact paths from the validated app-owned manifest, never a blind head-tree
prefix sweep. `README.md` and unrelated files always survive.

**R14 — Version URLs fail closed.** For an existing Worker, disable and GET-
confirm version URLs off before creating another version. Reconfirm after the
deploy. Failure before deploy stops the deploy; failure afterward leaves a
visible privacy warning and blocks subsequent deploys until repaired. A move's
pending retirement is not cleared while old versions may be public.

## C.4 Addresses, read-back and reader reconciliation

**R15 — Confirmed addresses only.** `CloudflareSiteUrl` requires exactly
`<valid-worker>.<valid-subdomain>.workers.dev/`, canonical lower-case host,
HTTPS, no userinfo, no non-default port, no query, no fragment and no non-root
path, with an unchanged `BookmarkUrl.normalize` round trip. The reader rejects apex,
one-label, extra-label and non-root Workers addresses; evil suffixes remain
refused.

`UnverifiedCloudflareAddress` is a different type. It may be used only for the
verification flow in F.2. It cannot become a `PublishTarget`, descriptor URL,
share/QR address or active published address.

**R16 — Read-back is origin-bound.** A shared bounded verifier uses an
unauthenticated client and the existing site-policy approach:

- exact expected origin and site directory;
- no cross-origin or cross-directory redirect; publish verification may simply
  refuse all redirects;
- HTTPS and `BookmarkUrl` validation at the initial URL and any permitted hop;
- streamed byte caps and abortable total deadlines;
- a generated `rb` cache-buster is allowed only for publish read-back, without
  weakening the viewer's existing no-query policy.

Before retirement, verify at the new target:

- the fresh Cloudflare marker, when Cloudflare is the destination;
- exact `library.json`, whose `siteUrl` is the new target, when descriptor
  publication is enabled; otherwise the expected `library.json` 404;
- exact `books.json`;
- exact `events.json` when the events section exists;
- current poster references (at most two) and expected removed-poster 404s
  where applicable.

After retirement, verify the moved page at the old root and that old
`books.json` returns 404; on Cloudflare also verify the exact retired marker.
Expected public bytes arriving through another origin do not count.

**R17 — No automatic reader moves.** A possible reader move requires:

- a previously stored fingerprint fact on the canonical row;
- a successfully fetched descriptor with the same fingerprint at another
  canonical address;
- descriptor `siteUrl` equal to that fetched row's canonical address;
- an explicit user-added/bookmark or freshly scanned address, not an arbitrary
  discovered row;
- a neutral user decision when both addresses remain plausible.

Transient failure, timeout, 404 or response-size refusal on the old address is
not proof of direction. A fresh in-person card may offer reconciliation even
while both addresses are live. Hostile/discovered duplicates retain the
existing identity-conflict behavior.

Acceptance calls one repository transaction with expected old/duplicate rows
and the chosen address. It preserves the canonical row id, local order and
consent/membership decisions, applies explicitly defined fresh remote fields,
deletes/merges the placeholder, and respects concurrent local edits through
baseline checks. Both uniqueness constraints remain enforced. Declining makes
no write; automatic following never occurs.

## C.5 Secrets and network discipline

**R18 — Long-lived token.** The Cloudflare token uses the narrow ADR 0007
`String` exception because storage and HTTP APIs are string-typed. It is:

- entered in a masked `SecretOnScreen` dialog with screenshots blocked;
- shape-checked and verified active before storage;
- stored only through the shared `hardenedSecureStorage()` factory;
- never placed in Riverpod state, `toString`, logs, errors, URLs or analytics;
- read once into the narrow operation scope and forgotten on disconnect;
- never persisted in the move journal or publish manifests.

Cloudflare connection data is one versioned secure-storage record containing
the token and optional target/configuration. Whole-record updates prevent a new
token from being paired accidentally with stale account/site fields. The whole
record is treated as secret.

**R19 — Ephemeral JWTs.** Upload/completion JWTs are bearer secrets with the
shortest possible operation/request-scoped lifetime. They are never persisted,
placed in controller/UI state, exposed to presentation or printed by the trial.
A bounded retry closure may reference the active operation's existing value;
it must not copy the JWT into independent retry state or diagnostics. Their
unavoidable immutable-`String` interval is explicitly recorded in ADR 0007 and
`SECURITY.md`; they are not claimed to be wipeable.

**R20 — Fixed API origin and abortable requests.** API traffic goes only to
`https://api.cloudflare.com/client/v4`. API redirects are refused. Credentials
are never forwarded elsewhere. Normal API calls have a 30 s abortable total
deadline; upload batches have 60 s. Multipart bucket upload and metadata-only
deployment must be genuinely abortable, not merely wrapped in
`Future.timeout`. An uncertain timeout is resolved by re-reading remote state,
not blind repetition.

**R21 — Bounded responses and parsing.** API bodies are streamed with a 1 MiB
hard cap before JSON decoding. Rejected bodies are cancelled, not drained.
A string-aware nesting pre-scan enforces a depth cap of 16 **before**
`jsonDecode`, alongside endpoint-specific string/list/map bounds. Public
read-back uses tighter file-specific limits: marker 4 KiB, descriptor 64 KiB,
events 64 KiB, and the existing bounded catalogue limit. Only whitelisted
response fields are read.

**R22 — Retries and accounts.** Reads and idempotent hash uploads use at most
three total attempts with injected deterministic sleep. Honor `retry-after`
once up to 60 s for 429; use bounded retries for 5xx. Worker/subdomain creation
and uncertain deploys are re-read before any retry. Account listing reads at
most four pages of 50; more results produce the manual Account ID path, never a
silent partial picker presented as complete.

**R23 — Paths, files and per-hash bytes.** `SitePath` is the only publish path
representation: relative, non-empty, bounded length, ASCII
`[A-Za-z0-9._-]` segments, no empty/`.`/`..` segment, no leading slash,
backslash, control character or encoded separator. Existing GitHub URL helpers
delegate to it without behavior changes.

Before upload, validate count, per-file size, type and paths. A publish builds
hash metadata for every file and an on-demand/spooled byte source keyed by
hash. If Cloudflare requests a hash with no available bytes, stop before deploy
and enter replacement reconciliation. Identical bytes plus extension produce
one hash and one multipart part, even when used at several paths.

**R24 — Aggregate memory budget.** Raw artifacts, base64 strings, UTF-8/multipart
buffers and concurrent requests all count. Start with one bucket in flight.
Introduce concurrency (never more than three) only with an aggregate encoded-
byte semaphore and measured benefit. The 25 MiB legal single-file limit is not
silently reduced by a smaller bucket guideline. Desktop RSS is informative,
not an Android safety bound; S8 includes fake-server worst-case tests and
Android release/AOT profiling.

Existing local/remote cover and poster downscaling is reused. It is not new
work and stale comments claiming it is absent are corrected during S3.

**R25 — Fixed safe failures.** Expected failures are typed and mapped to fixed
messages. No token, JWT, credential-bearing URL, raw response body or platform
exception text reaches UI or logs. “Your live site was not changed” is used
when only asset bytes were uploaded; “nothing was changed” is not used for an
uncertain outcome.

## C.6 Static output and implementation constraints

**R26 — Live site output.** Live deploys use `not_found_handling: "none"` so a
missing file is a real 404. `_headers` contains:

```text
/*
  Cache-Control: no-cache
  Access-Control-Allow-Origin: *
```

This is deliberate GitHub CORS parity (AM-20). The viewer's existing locked-
step meta CSP remains unchanged.

**R27 — Moved page.** `moved.html` contains the escaped library name and
validated escaped new address, a visible link, a five-second meta refresh and
`<meta name="robots" content="noindex">`. Both hosts retain meta CSP directives
that work there:

```text
default-src 'none'; style-src 'unsafe-inline'
```

Cloudflare retired `_headers` additionally contains exactly:

```text
/*
  Cache-Control: no-cache
  Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer
```

GitHub cannot supply equivalent response headers through this publishing path;
its limitation is documented and smoke-tested rather than disguised.

**R28 — No new runtime package beyond the approved promotion.** `http_parser`
becomes a direct dependency solely for multipart part media types. No plugin,
service locator, alternative state manager or hand-rolled crypto is added.
Riverpod code generation and `fpdart` remain the blessed patterns.

**R29 — Architecture and file size.** Domain remains pure Dart. Presentation
only renders and forwards intents. Every non-generated Dart file stays at or
below 500 lines with no new ratchet entry. Cloudflare account and deploy
adapters are separate files behind a thin facade; publish-page widgets are
extracted before behavior is added.

---

# Part D — User-visible behavior

## D.1 Connection and publish cards

Cloudflare card states:

- **Not configured** — no verified token/target.
- **Partially configured** — token or target setup is incomplete.
- **Address not confirmed yet** — only the manual candidate fallback exists;
  first verification is required.
- **Ready to publish** — target and address are confirmed; the first deploy
  will establish write capability end to end.
- **Configured** — at least one deploy and required read-back succeeded.

Internally distinguish token active, accounts readable, Workers write tested
and address confirmed. Do not call an active/read-only token fully configured.

The Publish card names the active host and verified live/target address. A
configured-but-never-live address is not presented as an already live share
link. GitHub's existing card remains visually unchanged except shared widget
extraction and required ownership consent when adopting unknown repositories.

## D.2 Connect Cloudflare

1. Explain the dedicated-Worker policy and token permission. Open Cloudflare's
   prefilled token-creation page in the external browser.
2. Paste into the masked dialog and shape-check it. Verify a user token
   immediately. For an account token, use the still-unstored token to list or
   select its account, then verify it at that account's verify endpoint. Only
   after the applicable active verification succeeds is the connection record
   persisted.
3. Choose an account from the bounded list when not already selected for an
   account token, or enter an Account ID when listing is refused/truncated.
   Store the account name for display.
4. Read the account subdomain. If permitted, use the returned value.
5. If account-level access is refused, offer an optional manual account
   subdomain. Keep it unverified and show that the first verification checks
   it. Do not silently request broader permissions.
6. Choose a Worker name. For an existing Worker, require explicit consent:
   “This Worker is dedicated to Pitak. Verification or publishing replaces
   **all assets currently on it**.” For a new Worker, the first deploy creates
   it.
7. If the subdomain was manually supplied, run F.2's verification-only deploy
   before full setup or any move. After exact-origin marker verification, the
   candidate becomes a confirmed target.
8. Store the confirmed target last. If no host is active, make Cloudflare the
   active publishing host without claiming its site is live. If GitHub is
   active, leave it active and offer the move rather than switching hosts
   implicitly.

### Verification-only deploy

This is the narrow AM-6 fallback, not a normal publish:

- no `library.json`, books, events, QR update, active-host change or source
  retirement;
- explicit whole-Worker replacement consent if the Worker already exists;
- version URLs handled under C8;
- deploy only a fresh marker with `state: "verification"` (and any minimal
  fixed asset the trial proves necessary);
- enable the `workers.dev` route and fetch that exact marker at the candidate
  origin with the bounded verifier;
- success confirms the address; a following full publish uses a fresh live
  marker and the confirmed target;
- failure leaves the old active site untouched and the card unconfirmed. Any
  marker-only Worker state is disclosed and reconciled on the next attempt.

## D.3 Ordinary publishing

- Catalogue and events buttons publish to the active configured host.
- Success copy distinguishes “verified live” from “deployed but not reachable
  yet”. A deploy that is not read back is never called fully verified.
- A `deployed`-but-unverified state offers **Retry verification**; reconciliation
  never creates another deployment/commit merely to verify the existing one.
- Unknown Cloudflare state first prepares a strict complete snapshot, then
  shows:

> **Replace your Cloudflare site?**
> This phone has no verified record of the current site. Publishing replaces
> the whole Worker with this phone's catalogue (**N items**) and **M event
> posters**. Anything only on the site — including a newer catalogue or other
> posters — will be removed.
> [Replace the site] [Cancel]

Add “Your events page will be empty” at zero posters and “Your catalogue has 0
items” at zero items. The string “Publish everything” does not appear in UI
copy. Internal command names may use `complete`, not that user-facing phrase.

## D.4 Moving

The confirmation names source and destination and includes real catalogue and
poster counts plus empty-section warnings. It explains:

- a complete snapshot is published and verified first;
- the current site is untouched until that succeeds;
- the old address then becomes a moved page;
- Cloudflare retirement removes every other asset on the dedicated Worker;
- GitHub retirement touches only consented Pitak-owned paths;
- peers do not follow automatically; they can add the new address and confirm
  reconciliation when offered;
- the library card must be reprinted.

Progress: preparing snapshot → checking both sites → publishing destination →
verifying destination → recording move → updating old address → verifying old
address.

If the destination cannot be verified, nothing switches or retires. If the
source changes before retirement, retirement stops and the destination remains
available but the move is not completed. While retirement is pending, the old
host and its verified share target remain active and a persistent Retry banner
shows the verified new address. The active host switches only after retirement
verifies. Skip is available only behind a warning for a source
account/repository/Worker that no longer exists; it switches to the verified
new target but never masquerades as successful retirement.

## D.5 Reader reconciliation

When stored evidence produces a candidate, show both addresses neutrally:

> **These addresses may identify the same library.** Choose which address to
> keep. Nothing changes automatically.

For a fresh scanned card, the copy may say that the card identifies the same
library at a different address. The user explicitly chooses the card address or
keeps the saved one. No prompt is based solely on one row being unreachable,
and no discovered/hostile row can trigger an automatic merge.

## D.6 Disconnect

Disconnect forgets the Cloudflare connection record but not the public site's
manifest or the journal's verified share target. It never deletes the remote
Worker. It does
not silently clear a pending move: reconnecting must authorize the exact old
target before retry, or the user must explicitly skip with the warning.
Changing either host's target while a move is pending is blocked for the same
reason.

Events copy remains host-specific: GitHub retains history; Cloudflare old
versions are described as not publicly visible only while the disabled-version
URL invariant holds.

---

# Part E — Code and stored-data plan

## E.1 Domain (`lib/features/publish/domain/`, pure Dart)

Shared site model:

- `site/publish_host.dart` — `github | cloudflare`.
- `site/publish_target.dart` — sealed host-specific targets and derived URLs.
- `site/site_path.dart` — the only safe relative path policy.
- `site/site_section.dart` — catalogue/events/retirement ownership; marker is
  shared and rewritten on every Cloudflare deploy.
- `site/publish_snapshot.dart` — immutable validated snapshot metadata and byte
  source references, not IO.
- `site/previous_publication.dart` — read view used by builders/deciders.
- `site/publish_manifest.dart` — schema-2 GitHub manifest and merge behavior.
- `site/publish_host_state.dart` — active host, verified live target and
  pending-move journal model.
- `site/publish_marker.dart` — pure marker value object and expected-state
  outcomes; byte/JSON codecs live in infrastructure.
- `site/move_plan.dart` — exact writes/deletes for a validated retirement.

Cloudflare:

- `cloudflare/cloudflare_api_token.dart` — static shape check, bounded length,
  no readable token field.
- `cloudflare/cloudflare_account_id.dart`.
- `cloudflare/cloudflare_worker_name.dart` and
  `cloudflare/cloudflare_subdomain.dart`.
- `cloudflare/cloudflare_site_url.dart` and
  `cloudflare/unverified_cloudflare_address.dart`.
- `cloudflare/cloudflare_site_manifest.dart` — schema-2 target matching,
  `hashScheme`, merge and state transitions. Bounded tolerant JSON decoding is
  performed by an infrastructure codec, preserving the pure-domain rule.
- `cloudflare/cloudflare_asset_hash.dart`.
- `cloudflare/cloudflare_content_type.dart`.
- `cloudflare/cloudflare_limits.dart`.
- `cloudflare/cloudflare_api.dart` — segregated account/deploy ports, typed
  results and redacted transport exception.
- `cloudflare/cloudflare_credential_store.dart` — whole-connection port.
- `cloudflare/cloudflare_error_messages.dart`.

Ports for manifest/host-state stores, strict publish reads, artifact byte
sources and published-site verification live beside their consuming domain or
application contracts without importing infrastructure.

## E.2 Application

- `site/catalogue_section_builder.dart` and
  `site/events_section_builder.dart` (R3).
- `site/publish_snapshot_builder.dart` — strict complete/incremental modes.
- `site/publish_site_controller.dart` — prepare/confirm/publish commands and
  replacement state; explicit target always required.
- `site/publish_host_controller.dart` — active host, move state machine and
  pending retry; owns the outer queue entry.
- `github/publish_to_github_use_case.dart` — existing catalogue/events
  orchestration refactored around shared builders, expected head and R6/R7.
- `cloudflare/setup_cloudflare_site.dart` — token/account/subdomain/Worker and
  verification state machine; stores confirmed target last.
- `cloudflare/publish_to_cloudflare_use_case.dart`.
- `cloudflare/retire_cloudflare_site_use_case.dart` and
  `github/retire_github_site_use_case.dart`.
- `cloudflare/cloudflare_connection_controller.dart` — no secret in state.
- `network/application/reconcile_library_move_use_case.dart` — candidate and
  user-confirmed transactional reconciliation.

Core moves/extractions:

- `lib/core/async/serial_op_queue.dart` from the vault feature.
- `lib/core/storage/hardened_secure_storage.dart`, used by both credential
  stores.
- `lib/core/network/workers_dev_url.dart` — one pure Workers host/root grammar
  shared by `BookmarkUrl` and `CloudflareSiteUrl`, so the network feature does
  not import the publish feature.
- `lib/core/network/` gains the genuinely abortable streamed/multipart support
  and shared publish-verification policy; existing viewer policy behavior does
  not change.

The existing events persistence contract is corrected or gains a strict publish
read so parse/read failure cannot masquerade as empty content. The old tolerant
editor behavior, if retained, must be a separately named explicit choice.

## E.3 Infrastructure

- `http_cloudflare_account_api.dart` and
  `http_cloudflare_deploy_api.dart`, plus a thin `HttpCloudflareApi` facade.
- `cloudflare_multipart_request.dart` — streamed/abortable body support and
  per-part media types.
- `secure_storage_cloudflare_credential_store.dart`.
- `cloudflare_publish_marker_codec.dart` and bounded manifest/journal JSON
  codecs in infrastructure; domain files contain no JSON or IO.
- `file_cloudflare_manifest_store.dart` and updated atomic GitHub manifest
  store.
- `prefs_publish_host_store.dart` — **one** `publish_host_state` JSON key.
- `file_publish_artifact_store.dart` — bounded temporary byte spool and cleanup;
  public artifacts only, no JWTs or credentials.
- `bounded_published_site_verifier.dart`.
- `moved_html_builder.dart` using `assets/publish/moved.html`.
- `drift_network_repository.dart` implements transactional move reconciliation
  with expected baselines and explicit per-field merge rules.

## E.4 Presentation and assets

Widgets: `cloudflare_tile.dart`, `cloudflare_token_dialog.dart`,
`cloudflare_name_dialogs.dart`, `cloudflare_verification_dialog.dart`,
`publish_card.dart`, `move_site_dialog.dart`, `replace_site_dialog.dart`,
`pending_move_banner.dart`, and a reader `library_move_dialog.dart`.

`publish_page.dart` is extracted below 350–400 lines before Cloudflare behavior
is added. Dialogs render controller state and forward decisions; they contain
no repository/API logic.

`assets/publish/moved.html` contains escaped placeholders, meta refresh,
noindex and the supported meta CSP from R27.

## E.5 Stored data

| Location | Data | Secret? |
|---|---|---|
| Secure storage, one versioned `cf_connection` record | Token, optional account/target, account name, token expiry, address/write confirmation flags | Entire record treated as secret; target fields are non-secret by nature but kept for cohesion |
| Existing hardened GitHub secure storage | GitHub token and target repo | Token only |
| Shared preferences, one `publish_host_state` key | Schema, active host, optional verified live target, optional pending move with exact old/new targets and phase | No |
| App documents, `publish_manifest.json` | GitHub schema-2 public manifest | No |
| App documents, `cloudflare_publish_manifest.json` | Cloudflare schema-2 public manifest | No |
| Temporary publish spool | Public artifact bytes and hash metadata | No; deleted on success/failure/dispose |
| Memory only, request scoped | API token in use, upload/completion JWTs | Yes; never persisted or placed in UI state |

Cloudflare manifest example:

```json
{
  "schema": 2,
  "target": {
    "accountId": "<32 hex>",
    "workerName": "kadugodi-library",
    "accountSubdomain": "kadugodi",
    "siteUrl": "https://kadugodi-library.kadugodi.workers.dev/"
  },
  "state": "live",
  "publishId": "<32 hex>",
  "liveId": "<optional diagnostic>",
  "hashScheme": "sha256-b64-ext-32",
  "files": {
    "books.json": {
      "sha": "<git-blob-style local content sha>",
      "hash": "<32 hex Cloudflare asset hash>",
      "size": 1234,
      "type": "application/json"
    }
  },
  "coverUrlByBookId": {"42": "https://covers.openlibrary.org/…"}
}
```

Unknown/missing `hashScheme` invalidates stored asset hashes, not the whole
manifest. Re-hash available bytes; missing bytes cause replacement
reconciliation rather than a permanent missing-byte loop.

Host-state journal example (tokens deliberately absent):

```json
{
  "schema": 1,
  "activeHost": "github",
  "verifiedTarget": {"host": "github", "repo": "owner/repo", "branch": "main", "siteUrl": "https://owner.github.io/repo/"},
  "pendingMove": {
    "phase": "retirementPending",
    "sourceAnchor": "<expected GitHub head SHA or Cloudflare publish id>",
    "oldTarget": {"host": "github", "repo": "owner/repo", "branch": "main", "siteUrl": "https://owner.github.io/repo/"},
    "newTarget": {"host": "cloudflare", "accountId": "<32 hex>", "workerName": "library", "accountSubdomain": "name", "siteUrl": "https://library.name.workers.dev/"}
  }
}
```

The example is a GitHub → Cloudflare move awaiting retirement: the old GitHub
target remains active/shareable while the already verified Cloudflare target is
held in `pendingMove.newTarget`. Successful retirement switches both active
fields to Cloudflare and clears `pendingMove` in one write.

On first read of an absent host-state record, the legacy default is GitHub when
a GitHub target exists; otherwise there is no active host until setup completes.
A legacy manifest alone does not populate `verifiedTarget`: one bounded
read-back of its known site is required to migrate that proof; until it
succeeds, the journal makes no verified-live claim.
`publishedSiteUrlProvider` reads only the journal's `verifiedTarget` for the
active host. It does not infer “live” from credentials, setup or a mutable
manifest. Manifest `live` and the journal pointer are written in that order;
a crash between them is reconciled by read-back without another deploy, and the
previous pointer remains truthful meanwhile.

## E.6 Existing files that change materially

- `publish_library_use_case.dart`, `publish_events_use_case.dart`,
  `publish_controller.dart`, `publish_events_controller.dart`: shared strict
  builders, explicit target, queue and read-back.
- `publish_manifest.dart`, `file_publish_manifest_store.dart`: schema 2,
  branch/head reconciliation and atomic typed saves.
- `github_api.dart`, `http_github_api.dart`: typed non-truncated tree snapshot,
  expected-head commit and no error-to-empty-tree collapse.
- `file_events_repository.dart` / `events_repository.dart`: no silent empty on
  the strict publish path.
- `publish_cover_decider.dart`: `PreviousPublication`; complete mode cannot
  silently drop a required cover.
- `github_connection_controller.dart` / `setup_github_repo.dart`: pending-move
  target guards and existing-repo ownership consent.
- `secure_storage_publish_credential_store.dart`: shared hardened factory.
- `timeout_http_client.dart` or a sibling core transport: true abort support for
  streamed/multipart requests; no regression to existing `http.Request`
  handling.
- `network_controller.dart`, `network_refresh_controller.dart`,
  `refresh_network_use_case.dart`, `add_member_use_case.dart`,
  `network_repository.dart`, `drift_network_repository.dart`: C10/R17 reader
  reconciliation.
- `bookmark_url.dart` and `published_site_url_policy.dart`: valid Workers
  grammar and publish-read-back cache-buster support without weakening viewer
  URL rules.
- DI, publish/events pages, network list/guide copy, `pubspec.yaml` and assets.

`github_device_flow.dart`, `github_oauth_app.dart`, viewer/events templates and
native reader codecs remain unchanged except explicitly required copy or shared
URL-policy tests.

---

# Part F — Flows

## F.1 Prepare and confirm a publish

1. Presentation requests an explicit target and section (`catalogue`, `events`,
   or `complete`).
2. The outer controller enters the app-wide queue and resolves credentials and
   exact target. Missing/mismatched configuration fails before HTTP.
3. Read target state and required source anchors. Build the requested section
   or a strict complete snapshot as required.
4. If replacement is needed, return `ReplacementRequired` with real counts and
   release the queue without writing.
5. User confirmation re-enters the queue, rechecks remote anchors and rebuilds
   from current local data. The canonical snapshot digest must match the
   confirmed digest; otherwise updated confirmation is required. Restore/data
   generations are extra guards. Cancel changes nothing.

Presentation never chooses a fallback target and never constructs a target URL.

## F.2 Connect and verify Cloudflare

Follow D.2. The token is stored only after active verification. Whole-record
updates keep token and target cohesive. The confirmed target is stored last.
Any existing-Worker verification or publish requires the dedicated-Worker
consent. Account/subdomain creation is re-read after timeout before retry.

## F.3 Publish to Cloudflare

With the queue already held:

1. **Resolve and preflight:** validate target, token and manifest target match.
   When the token can read it, require the current account subdomain to equal
   the target's confirmed value. Read Worker existence and marker plus actual
   route/version configuration; drift or inaccessibility fails closed.
2. **Old-version gate:** for an existing Worker, disable and confirm version
   URLs before a new version. Failure stops before deploy.
3. **Freshness:** apply R10. Known retired requires exact retired-marker match.
   Unknown enters F.1 replacement, never silent incremental publish. If the
   local state is `deployed` and the marker matches, reconciliation first runs
   read-back for that existing deployment; success saves `live` and updates the
   journal's verified target, while failure stops without creating another
   version. A verification-only retry ends here; a separate new publish may
   continue after reconciliation succeeds.
4. **Section gate:** events require a catalogue in the known manifest unless
   this is a complete publish.
5. **Build:** use shared builders and strict complete mode where required.
   `library.json` uses the explicit target URL.
6. **Merge and validate:** R7 produces the complete next snapshot. Validate all
   paths/types/limits before upload. Unknown manifest paths are refused, not
   carried.
7. **Artifacts:** compute Cloudflare hashes and hash-keyed byte sources. Unknown
   hash schemes are rebuilt. Spool/read bytes under the aggregate budget.
8. **Upload:** create the asset session with the full manifest. Upload requested
   buckets by hash. Missing requested bytes stops before deploy. Asset bytes
   already uploaded are not described as a live-site change.
9. **Final race check:** re-read the marker and source/destination anchors
   relevant to the command. On mismatch, stop before deploy and reconcile.
10. **Deploy:** metadata-only PUT with completion JWT, fixed compatibility date,
    live asset config and live `_headers`.
11. **Route/privacy:** enable the address as needed and reconfirm version URLs
    off. If this cannot be confirmed, expose the privacy warning and block the
    next deploy.
12. **Local commit:** persist the new manifest as `deployed` atomically. Save
    failure is typed; do not claim local reconciliation succeeded.
13. **Verify:** use R16. On success persist `state: live`, then set the host
    journal's `verifiedTarget`; on failure leave `deployed` and report the
    truthful partial outcome without changing the previous verified pointer.
    A later preflight whose marker matches may finish verification without
    replacement.
14. **Result:** fixed message and uploaded-path summary. No JWT or response text
    enters state.

A kill after deploy but before manifest commit leaves a marker the old manifest
does not know; the next publish fails closed into reconciliation. A kill after
`deployed` commit allows exact-marker recovery. Neither case silently replaces
unknown content.

## F.4 Publish to GitHub

1. Resolve the explicit GitHub target and confirm Pages still serves that
   branch.
2. Read a typed head/tree snapshot and reconcile the manifest under R6. If the
   local state is `deployed` and its head matches, first run read-back for that
   commit; success saves `live` and updates the journal's verified target,
   failure stops without another commit, and a verification-only retry ends
   here. A separate new publish may continue after reconciliation.
3. Build with the shared builders. Events retain the catalogue-first gate.
4. Merge the app-owned section and compute exact obsolete owned paths.
5. Commit with `expectedHead` and `force: false`; unrelated repository files
   remain in the base tree.
6. Atomically save merged files, cover-source metadata and returned commit SHA
   as `deployed` without changing the journal's previous verified target.
7. Perform bounded same-origin read-back of `library.json` when enabled (or
   its expected 404) and changed/current machine-readable sections. Events
   gains the same read-back discipline; it is no longer assumed live merely
   because the commit succeeded. On success save `state: live`, then set the
   journal's `verifiedTarget`.
8. A complete move-to-GitHub publish uses a strict complete snapshot and one
   commit that removes every consented app-owned path absent from the live set,
   including a leftover retired `404.html`.

Valid-input output bytes remain pinned by the characterization test. The only
intentional remote behavior changes are the recorded stale-file deletion and
read-back/fail-closed fixes.

## F.5 Move in either direction

Preconditions: both targets configured and address-confirmed, no pending move,
no conflicting target mutation, and the queue is held only by this command.
R4 may release the queue while the user considers a confirmation; every
precondition and anchor is revalidated when the command re-enters it.

1. **Source check:** prove the old source still equals this phone's last live
   publication (GitHub repo + branch + head; Cloudflare target + publish id).
   If stale or unknown, stop and require reconciliation. Do not silently copy
   an older phone snapshot over a newer source.
2. **Destination check:** validate target state and version-URL gate. Unknown
   destination follows replacement reconciliation with explicit consent.
3. **Strict snapshot:** build the complete destination snapshot. Any missing
   asset aborts before target write. Show the D.4 confirmation with real counts
   and apply R4's rebuild-and-digest check before the destination write.
4. **Destination publish:** run F.3 or F.4's complete path with the **new**
   target. The new `library.json` therefore contains the new address.
   Immediately before the destination deploy/commit, recheck both source and
   destination anchors; if either changed, abort that write and reconcile.
5. **Destination verification:** verify every R16 requirement at the new origin.
   Failure stops before pending-state creation or source retirement.
6. **Source recheck:** if the source anchor changed, stop. The destination may
   remain published, but the old active site and journal do not switch.
7. **Record pending:** one host-state write records `retirementPending` with
   exact old/new targets and the source anchor. The old active host and its
   verified share target remain unchanged at this step.
8. **Retire:** revalidate credentials, exact old target and source anchor inside
   the same queue, then run F.6. A mismatch never writes the currently
   configured different target.
9. **Verify retirement:** apply R16's old-site checks. Save the old manifest as
   retired atomically. The old active pointer may now name a moved page, which
   remains truthful while retry is pending.
10. **Complete the switch:** one host-state write sets the new active host and
    its already verified `verifiedTarget`, and clears the completed retirement.
    Share/QR now consistently use the verified new address.

Failure after step 7 leaves a persistent pending journal and the old active
host until step 10 succeeds. Retry is idempotent: it first checks whether the
old site already matches the intended retired state, then performs only
missing work. A remote success followed by local failure never causes a
different target to be retired.

Crash tests are mandatory after every step that has a remote or persistent side
effect.

## F.6 Retire the old site

### GitHub

- Re-read Pages configuration and require the recorded branch and expected
  head.
- Build escaped moved `index.html` and `404.html` from the old target/library
  name and new validated address.
- In one expected-head commit, write those files and delete every other exact
  app-owned path present in the validated manifest. Unrelated files survive.
- Read back the moved root and old `books.json` 404. Save a retired manifest.

### Cloudflare

- Revalidate exact account/Worker, expected live marker and version URLs off.
- Deploy only moved `index.html`, moved `404.html` and a fresh
  `pitak-publish.json` with `state: "retired"`.
- Use `not_found_handling: "404-page"` and retired `_headers` from R27. Every
  other asset on the dedicated Worker is removed, as disclosed.
- Verify moved root, retired marker and `books.json` 404, then save the retired
  manifest with the retirement publish id.

A later move back trusts only an exact matching retired marker. Marker 404 or
mismatch enters replacement confirmation.

## F.7 Reader add/refresh/reconcile

- Card scan detects an already-saved fingerprint before inserting a duplicate
  and offers the explicit reconciliation choice.
- URL-added rows may still start with null fingerprint. During refresh, detect
  old-stored/new-fetched equality before the existing conflict suppression and
  emit an ephemeral candidate; do not persist duplicate fingerprints.
- Discovered rows and ambiguous contested fingerprints remain conflicts, not
  move suggestions.
- User acceptance calls the transactional repository method with baselines.
  Concurrent membership/edits win over stale refresh state.
- Choosing the old or new address is deliberate. There is no automatic redirect
  following and no machine-readable moved-page dependency.

## F.8 Disconnect and pending moves

Disconnect clears the relevant credential record and invalidates providers. It
does not clear verified public manifests or pending history silently. Pending
retry either reauthorizes the exact recorded target or remains blocked. After
the explicit warning, Skip switches the active/verified target to the already
verified destination and clears the journal; it does not mark the old site
retired.

## F.9 Failure map

| Situation | Required behavior |
|---|---|
| Wrong token shape | Fixed paste-again message; nothing stored. |
| Token inactive/expired or 401/403 | Fixed reconnect message; no raw response. Show recorded expiry when known. |
| Token active but Workers write refused | Fixed permission message; state never advances to deploy-tested/configured. |
| Accounts unavailable/truncated | Manual Account ID path; never pretend the list is complete. |
| Subdomain read refused | Candidate-only manual fallback and F.2 verification. |
| Worker/subdomain name taken | Ask again, preserving safe typed input. |
| Worker deleted/inaccessible or account subdomain changed | `SiteUnavailable`; no incremental write. Offer explicit setup/recreation with a complete snapshot and re-verified address. |
| Legacy/uncertain manifest | Rebuild GitHub or reconcile Cloudflare; never treat failure as an empty remote. |
| Missing metadata/poster/cover in complete mode | Typed no-write failure; old site untouched. |
| Marker/head stale | Normal publish stops; explicit reconciliation required. |
| Source anchor changed during move | Do not retire; preserve both sites and show the incomplete-move state. |
| Version URLs cannot be disabled | No subsequent deploy; pending retirement never clears. |
| Missing requested asset hash | Stop before deploy; replacement reconciliation. |
| 429 | Honor bounded `retry-after`, then fixed busy message; live-site truth is precise. |
| Timeout/5xx before deploy | No live deploy claimed; uploaded dedup bytes may exist server-side. |
| Uncertain deploy timeout | Re-read marker/Worker before retry; never blindly repeat. |
| Deploy succeeded, manifest save failed | Report remote update plus local reconciliation failure; marker/head recovers safely. |
| Deploy succeeded, read-back incomplete | State remains `deployed`, not verified `live`; retry verification later. |
| Retirement failed | Keep exact pending journal and Retry; old host/share target remains active until retirement verifies, and the banner exposes the verified new address. |
| Wrong target on reconnect | Refuse retirement; never substitute the new configured target. |
| Over file count/size/type/path limit | Typed failure before upload. |

---

# Part G — HTTP contract

All Cloudflare API calls use HTTPS, the fixed API base and
`User-Agent: AppUserAgent.value`. Authorization is `Bearer <connection token>`
except bucket upload, which uses the upload JWT. Redirects are refused. Fields
not listed are ignored within the bounded parser.

| Purpose | Request | Fields/outcomes |
|---|---|---|
| Verify user token | `GET /user/tokens/verify` | `status`, optional `expires_on` (displayed when present) |
| Verify account token | `GET /accounts/{a}/tokens/verify` | `status`, optional expiry |
| List accounts | `GET /accounts?per_page=50&page={n}`, bounded | `id`, `name`, pagination/truncation |
| Read account subdomain | `GET /accounts/{a}/workers/subdomain` | `subdomain`, 10007, permission failures |
| Check subdomain | `GET /accounts/{a}/workers/subdomains/{name}` | confirmed trial codes/outcomes |
| Create subdomain | `PUT /accounts/{a}/workers/subdomain` | returned `subdomain`; re-read after uncertainty |
| Worker exists | `GET /accounts/{a}/workers/scripts/{name}` | existence only; 404/new vs present |
| Optional deployment diagnostic | `GET /accounts/{a}/workers/scripts/{name}/deployments` | optional opaque id; never load-bearing |
| Upload session | `POST …/workers/scripts/{name}/assets-upload-session` | `jwt`, `buckets` |
| Upload bucket | `POST …/workers/assets/upload?base64=true` | final `jwt`; upload-JWT bearer |
| Deploy | `PUT …/workers/scripts/{name}` | success/typed errors; metadata-only |
| Route/version setting | `POST` then `GET …/workers/scripts/{name}/subdomain` | `enabled`, `previews_enabled`; trial confirms semantics |
| Delete Worker | `DELETE …/workers/scripts/{name}` | trial cleanup only |

Public site verification never sends the API token or upload JWT. Its URLs come
only from the validated target and fixed `SitePath` values.

---

# Part H — Security, privacy and compatibility

- **Token blast radius:** one user-created token, one account, Workers Scripts
  Edit. The guide recommends a library-only Cloudflare account and optional
  expiry. Phone IP filters are not recommended because mobile addresses change.
- **Secret handling:** R18/R19 and fixed messages apply to tokens and JWTs.
  Release builds add no telemetry or secret logging. Trial output uses fixed
  fields, not token-pattern scrubbing as its primary defense.
- **Storage:** one hardened factory supplies identical Android/iOS options to
  every credential store. Disconnect clears the whole connection record.
- **Transport:** system trust store, no pinning, with ADR 0010 generalized to
  publishing APIs. No token ever goes to a `workers.dev`/GitHub public read-back
  URL.
- **Hostile responses:** origin restrictions, abortable deadlines, streamed
  caps, JSON structure bounds and typed parsing apply before any business
  decision. No response text is rendered.
- **Cloudflare learns:** device IP/User-Agent on API calls, uploaded files and
  public site traffic. Uploaded dedup bytes may remain server-side even when no
  deployment occurs. UI failure copy says “live site unchanged”, not that no
  bytes reached Cloudflare.
- **Public history:** GitHub retains Git history. Cloudflare old versions are
  described as hidden only after the version-URL check succeeds. A failure is a
  visible privacy condition, not a successful retirement.
- **Moved pages:** GitHub meta-CSP limitations and Cloudflare header behavior
  are documented accurately. New address and library name are escaped.
- **Reader trust:** fingerprint equality is evidence for a user decision, not
  proof that authorizes automatic repointing. Signed descriptors remain out of
  scope.
- **Compatibility:** no changes to the three existing public wire formats.
  `pitak-publish.json` is a small Pitak-owned operations file, not a peer move
  protocol and not required by older readers.

---

# Part I — Sessions and dependencies

Sessions are small PRs where practical. S0/S1/S2 may proceed independently.
S5's own marker/schema work may proceed in parallel with S2, but no external
Cloudflare behavior becomes load-bearing before the trial confirms it. Each
required ADR/security-policy amendment lands with or before the session that
introduces its behavior (not deferred until S10): ADR 0007, ADR 0010,
`SECURITY.md` and a draft ADR 0017 land in S0 before the secret-bearing S2
trial; ADR 0012 lands with S1; the remaining behavior ADRs land with their
owning sessions. ADR 0017 is finalized with the S2/S10 outcomes. S10 is the
final consistency audit.

| # | Session | Size | Done when |
|---|---|---|---|
| S0 | Review this consolidation; extract publish-page widgets; withdraw dashboard-repo advice; fix stale Cloudflare/downscale copy; land early ADR/security updates | M | Page is ≤400 lines with no behavior change; tests updated; no new ratchet entry; ADR 0007/0010, `SECURITY.md` and draft ADR 0017 are in place before S2. |
| S1 | Reader URL grammar and C10/R17 reconciliation | L | Valid Workers URLs accepted; hostile forms refused; scan/paste/refresh candidates, spoof/transient cases and atomic accept/decline/concurrent-edit tests pass. |
| S2 | Disposable Cloudflare trial | M | Full T1–T16 passes with exact restricted token; conditional-write and version-URL decisions recorded; no secrets in report. |
| S3 | Characterization, strict snapshots, shared builders and bounded verifier | L | Valid GitHub bytes pinned; missing metadata/assets fail before writes; catalogue/events/complete builders and origin-bound read-back tested. |
| S4 | Targets, manifests, queue, journal and hardened storage | L | GitHub schema-2 migration/expected-head/atomic saves green; verified-target migration is read-back gated; outer queue has no nesting; wrong-target journal retry refused. |
| S5 | Cloudflare pure domain | M | Value-object boundaries, strict URLs, paths, hash vectors, schema/hashScheme, merge, marker and ownership tests pass. |
| S6 | Cloudflare HTTP adapters | L | Every Part G call and malformed/hostile response covered; streamed caps and true multipart abort tests pass; two role files plus facade remain under 500 lines. |
| S7 | Connect Cloudflare | L | Restricted-token states, account fallback/pagination, dedicated-Worker consent, candidate verification and whole-record secret tests pass. |
| S8 | Cloudflare publish and replacement | L | F.3/F.9 covered; section survival, marker recovery, replacement warning, per-hash bytes, version gate and aggregate memory tests pass; Android release/AOT memory gate recorded. |
| S9 | Moves and retirement | XL; split PRs | Both directions, exact ownership, read-back, idempotent pending retry and every crash point pass before completion. |
| S10 | Docs and release checklist | M | Every Part K item and ADR amendment done; no contradictory docs remain. |
| S11 | Real-host smoke and cleanup | M | Every Part J smoke step passes; `tool/cloudflare_trial/` removed; final CI/release gates green. |

S6–S9 wait for S2's outcome. If T6 fails or the maintainer rejects a required
C1/C6 consequence, stop rather than patching around the decision.

---

# Part J — Required tests and smoke evidence

## J.1 Domain and manifest tests

- Every token/account/name/address/path boundary, including Unicode, spaces,
  control characters, very long values, userinfo, ports, trailing dots and evil
  suffixes.
- Workers apex, one label, extra labels and non-root paths refused.
- Fixed asset-hash vectors, empty file and extension case.
- `SitePath`: `..`, `/abs`, `a//b`, `a/./b`, backslash, encoded separators and
  over-length input. Existing GitHub URL tests remain green.
- Catalogue publish preserves events; events preserves catalogue; removed
  posters/covers leave; descriptor opt-out removes only `library.json`.
- Unknown paths never deploy. Duplicate bytes/extension produce one hash/part.
- Unknown hash scheme re-hashes available bytes and never loops on missing
  bytes.
- Marker match/mismatch/malformed/404; Worker absent with no manifest vs with
  a matching manifest (`SiteUnavailable`); exact retired marker; retired local
  + 404 remains unknown; account-subdomain drift is refused.
- GitHub legacy manifest rebuild, branch/head mismatch, truncated tree failure,
  expected-head conflict and atomic save failure.
- Manifest write is the only section-merge path and includes cover-source
  metadata.

## J.2 Snapshot and publishing tests

- Complete snapshot fails on catalogue read error, periodical read error,
  corrupt events metadata, missing poster and unreadable required cover.
- Dialog counts come from the validated snapshot; zero counts add warnings;
  changed content after preparation requires revalidation.
- Ordinary catalogue/events publish and full replacement never erase the other
  section unintentionally.
- AM-4 regression plus stale-cover deletion and legacy-upgrade variants.
- `library.json.siteUrl` is the new target in both move directions; the old host
  receives only its retirement write.
- Non-configured or host/URL-mismatched target fails before HTTP.
- Fresh/stale marker and expected-head outcomes; final pre-deploy race check.
- Missing requested hash stops before deploy.
- Version URLs on: subsequent deploy and retirement do not complete.
- Deployed/read-back-failed state does not become verified live; exact-marker
  retry can recover without another deploy.
- The journal's previous `verifiedTarget` survives a failed first deploy and an
  unverified target change; it changes only after read-back. A crash between
  manifest `live` and pointer update reconciles without another deploy.
- Fixed failure messages contain no token, JWT, URL credentials or response
  text.

## J.3 HTTP and memory tests

- Every endpoint: status, error codes, malformed envelope, wrong types,
  excessive depth/lists/strings and over-cap streamed body.
- API redirect refused; no auth forwarded. Public read-back cannot validate
  expected bytes from another origin/directory.
- Actual socket/request abortion for normal API, bucket multipart and deploy
  multipart timeouts.
- 429 `retry-after`, bounded 5xx retries and uncertain-create/deploy re-read.
- Fake server forces duplicate hashes, skewed/oversized buckets and requested
  missing hashes.
- Aggregate byte semaphore covers raw + encoded + multipart copies; three-way
  concurrency cannot exceed the budget. Initial implementation remains serial.
- Android release/AOT profile uses production-equivalent artifact/upload code;
  desktop trial RSS is recorded only as supplementary evidence.
- Trial script passes `dart analyze tool` and
  `dart format --set-exit-if-changed tool/cloudflare_trial` in S2.

## J.4 Reader tests

- Card with saved fingerprint at another address offers reconciliation instead
  of inserting/refusing blindly.
- URL-added null-fingerprint row plus old stored match produces an ephemeral
  candidate before conflict suppression.
- Discovered row or copied hostile fingerprint does not produce a trusted move.
- Old-row timeout/404/oversize alone never selects direction.
- Descriptor `siteUrl` mismatch is not a candidate.
- Both addresses live still permits a fresh in-person card choice.
- Decline writes nothing. Accept leaves one canonical row, preserves local
  order/consent fields and applies defined remote fields.
- Concurrent membership/edit baseline wins; uniqueness of URL and fingerprint
  survives every accept/decline path.

## J.5 Move/crash matrix

For both directions, interrupt or fail:

- after destination asset upload but before deploy;
- after destination deploy but before manifest commit;
- after destination read-back;
- after source recheck but before journal switch;
- after journal switch but before retirement;
- after remote retirement but before old-manifest commit;
- after old-manifest commit but before pending-clear.

At every point assert the permitted live-site state, journal state, next retry
and user message. Until the final completion write, the old active/verified
target must remain selected even when its remote site already redirects. Also
cover stale second phone, source changing during move,
reconnect to a different repo/account/Worker, version URLs still enabled,
missing asset, retirement retry already complete, and explicit Skip.

## J.6 Architecture and security tests

- Domain purity, inward dependencies, Riverpod codegen and 500-line ratchet.
- Both production credential stores use the shared hardened factory.
- Token/JWT absent from state, `toString`, logs, serialization, temp spool and
  exceptions; disconnect clears the connection record.
- `SecretOnScreen` wraps token entry.
- Moved HTML escapes hostile library names and addresses; Cloudflare headers
  appear on root and 404 responses; GitHub meta-CSP limitation is pinned.
- No “Publish everything” user-facing string exists in `lib/`.

## J.7 Real-host smoke (S11)

On a disposable account with the exact restricted token:

1. Connect, including the manual-subdomain fallback if that path is supported
   by the test account setup.
2. Publish catalogue, then events, then catalogue again; events survive.
3. Remove a poster; its old URL returns 404. Removed content is not reachable
   through an old version URL.
4. Verify root/index/events behavior, JSON content types, no-cache/CORS and
   missing-file 404.
5. Reinstall/reset local Cloudflare state; unknown state requires the explicit
   replacement warning with real counts.
6. Move Cloudflare → GitHub: new descriptor has the GitHub address; Cloudflare
   moved page/headers/retired marker verify; old `books.json` is 404.
7. Move GitHub → Cloudflare and verify the reverse, including unrelated GitHub
   `README.md` survival.
8. Exercise pending Retry with simulated local failure; reconnecting to the
   wrong target refuses retirement.
9. Add/scan the moved library on another updated app and confirm reader
   reconciliation without duplicate rows.
10. Disconnect; secrets are forgotten, public share truth remains honest, and
    the remote site is not deleted.

---

# Part K — Documentation and release checklist

- **ADR 0017:** Cloudflare Workers publishing — dedicated Workers, one active
  host, complete snapshots, exact targets/journal, section merging, marker
  freshness, single-writer limitation/conditional-write outcome and moved
  pages.
- **ADR 0007:** three persisted string-token exceptions (GitHub, ISBN,
  Cloudflare) plus narrowly scoped ephemeral upload/completion JWTs.
- **ADR 0010:** no certificate pinning for publishing APIs; system trust store.
- **ADR 0012:** `workers.dev` URL policy and clarified stable fingerprint vs
  mutable address reconciliation; no automatic moved following.
- **ADR 0015:** the native viewer still never repairs identity conflicts;
  explicit reconciliation lives in the saved-library flow, not the viewer.
- **ADR 0016:** events read-back and strict publish-read behavior remain
  compatible with the machine-readable events contract.
- **`docs/ARCHITECTURE.md`:** scope/egress, non-goals, secret exceptions,
  dedicated Worker and single-writer model, feature tree, target/journal state,
  manifest meaning, URL rows and reader reconciliation.
- **`SECURITY.md`:** known limits names all persisted token exceptions and
  ephemeral JWTs; scope notes match ADR 0007.
- **`PRIVACY.md`:** Cloudflare token storage, two hosts, Cloudflare-visible
  data, dedup uploads, dedicated-Worker replacement, moved pages, old-version
  conditions, accepted reader addresses and reconciliation.
- **`docs/RELEASING.md`:** app-access answer, restricted-token setup, Android
  memory evidence and full Cloudflare/move smoke matrix.
- **README, in-app guides, `CHANGELOG.md` and fastlane changelog:** both hosts,
  dedicated Worker warning, move behavior, reader update requirement and
  single-writer limitation. Run `tool/check_fastlane_changelog_chars.py`.
- **Play Console:** update App access and privacy answers to match actual
  behavior.
- Remove or revise stale statements that cover downscaling is not implemented,
  that the manifest is only a harmless cache, or that old versions are hidden
  without a successful version-URL check.

---

# Part L — Trial run (S2)

## L.1 Safety

- Token comes only from `CF_API_TOKEN`; optional `CF_ACCOUNT_ID` and
  `CF_CREATE_SUBDOMAIN` follow the original safety rules.
- Never print/store tokens, JWTs, authorization headers or raw response bodies.
  Print fixed outcome labels, status, whitelisted numeric codes, selected safe
  headers and timings.
- Worker name is `pitak-trial-<8 secure random hex>` and deletion is attempted
  in `finally` after every outcome. Cleanup failure is explicit.
- Create the permanent account subdomain only when explicitly enabled and only
  on a throw-away account.
- Run the entire flow with the exact `Workers Scripts · Edit`, one-account token
  intended for production. A second broad token may be used only to diagnose a
  failed restricted call, never as proof the production flow works.
- Run `dart analyze tool` and format checks manually because `tool/` is outside
  the normal CI lint paths.

## L.2 Checks

| # | Check |
|---|---|
| T1 | User/account token verification reports active; optional expiry shape is recorded. |
| T2 | Account listing works or the documented refusal/manual-ID path is required. |
| T3 | Account subdomain read/check/create behavior with the restricted token is recorded, including 401/403/10000. |
| T4 | New-Worker upload session with SHA-256 keys requests all four sample files. Local no-slash → API leading-slash mapping is verified. |
| T5 | Bucket multipart with per-part content types returns a completion JWT; duplicate-hash behavior is checked. |
| T5b | Synthetic ~2,000 × 100 KB assets record bucket count, largest raw bucket and desktop RSS as informational measurements only. |
| T6 | Metadata-only assets deploy succeeds with fixed config and `_headers`. Failure stops the plan. |
| T7 | Address enable/version disable and GET semantics are confirmed. Record exactly which field controls Version URLs. |
| T8 | Live root/index/JSON/missing-file behavior, HTML redirects, content types, cache and CORS match the contract. |
| T9 | Optional deployment id behavior is recorded; correctness never depends on it. |
| T10 | Second deploy with an unchanged file and removed events file dedupes correctly and removes the live events file. |
| T11 | After a subsequent deploy, the earlier version is not publicly reachable. Test the failure-to-disable path on the disposable Worker. |
| T12 | Retired deploy root/missing path, status, retired headers and retired marker behave as required. |
| T13 | Trial Worker is deleted; cleanup is verified. |
| T14 | Investigate supported conditional-deployment/CAS behavior in current docs, Wrangler and API. Record evidence; no guessed production header. |
| T15 | Prove that disabling version URLs before a subsequent deploy prevents old-version exposure, and record behavior when the setting cannot be confirmed. |
| T16 | Repeat every required endpoint, including deploy, route/version settings and retirement, with the exact restricted token. Any untested write permission blocks S7/S8. |

The maintainer records the sanitized report and all deviations in Part M before
S6. The trial source is removed in S11.

---

# Part M — Consolidated deviations and amendment disposition

This table is the required deviation record for the original plan. It combines
the supplied amendments with the second safety review. Further changes append
rows; they do not silently edit away the history.

| # | Original plan said | Consolidated behavior | Why |
|---|---|---|---|
| 1 | Descriptor URL comes from active target | Explicit sealed target passed through the operation | A move publishes the new target before active-host switch; prevents old URL in new descriptor |
| 2 | Peers add the new address; AM-2 compared two stored fingerprints | Ephemeral candidate + neutral user choice + transactional merge/repoint | URL/fingerprint uniqueness and conflict suppression make AM-2's state impossible; reachability is not proof |
| 3 | “Publish everything” after unknown state | Strict complete snapshot + “Replace the site” warning with real counts | A complete snapshot is destructive and must be built without silent omissions |
| 4 | Manifest merge fixes incomplete section state | Schema-2 merge plus legacy/branch/head reconciliation and atomic saves | Existing stale manifests and post-commit failures otherwise remain load-bearing |
| 5 | Freshness uses live deployment id; AM-5 added marker | Owned marker is authoritative; live id diagnostic; source and destination anchors checked | Avoids unverified endpoint dependency and protects the source of a move |
| 6 | Marker check is optimistic concurrency | Recheck before deploy; S2 decides conditional support; otherwise explicit single-writer limitation | Local queue and marker cannot serialize another device |
| 7 | Retired local state + marker 404 permits plain publish | Exact matching retired marker required; retired deploy retains a fresh `state: retired` marker | 404 cannot distinguish expected retirement from unknown replacement |
| 8 | One permission and subdomain fallback | Full restricted-token trial; candidate-only manual subdomain with verification-only deploy | Active/read access is not write proof; unverified URL cannot enter target/descriptor |
| 9 | One Cloudflare adapter and larger publish page | Role adapters + facade; widgets extracted first | 500-line ratchet |
| 10 | ADR/docs updates only | `SECURITY.md` and ephemeral JWT lifetime included | Security policy must name every accepted String secret interval |
| 11 | Reuse private GitHub path regex | Shared `SitePath` value object | One path policy, no copied security rule |
| 12 | Copy hardened storage options | Shared `hardenedSecureStorage()` factory | Security options must not drift |
| 13 | Worker-code fallback allowed after trial | T6 failure stops this plan | Worker code is a separate product decision |
| 14 | Moved CSP only in meta / then only CF headers | Supported meta CSP on both; full headers on CF; escaping and GitHub limits explicit | Meta ignores several directives; GitHub has no equivalent header channel |
| 15 | Hash formula without scheme marker | `hashScheme` in Cloudflare manifest | Formula changes degrade safely |
| 16 | Missing bytes tracked per path | Hash-keyed on-demand/spooled byte sources | Duplicate files share hash; avoids whole-library memory retention |
| 17 | Bucket memory decided by one desktop trial | Aggregate budget, serial default, fake-server bounds and Android AOT evidence | Server buckets/desktop RSS are not worst-case mobile guarantees |
| 18 | S5 can precede trial around live id | Only self-owned schema/marker work proceeds; no unconfirmed external field is load-bearing | Avoid schema built on an experiment |
| 19 | `expires_on` unused | Show expiry when supplied; expired token maps to fixed reconnect copy | No dead parsed field |
| 20 | GitHub tests strictly unchanged | Valid bytes pinned; mechanical wiring edits and recorded deletion/read-back fixes allowed | Characterization is the real compatibility gate |
| 21 | Trial outside normal lint paths | Manual analyze/format checks required in S2 | Secret-bearing tooling must still compile and be reviewed |
| 22 | JSON-only CORS called GitHub parity | `/*` CORS on live assets | Actual parity and one simple rule |
| 23 | Move can retire after read-back of any built output | Strict complete snapshot; source rechecked before retirement | Read-back cannot detect assets omitted before build |
| 24 | Pending retirement stores host + movedTo in separate prefs; active host switches before retirement | One atomic journal with exact old/new targets, phase and source anchor; active/verified target switches only after retirement verifies | Retry after reconnect must never retire the wrong target or expose an unverified/stale destination as active |
| 25 | R17 preserves arbitrary files on both hosts | Dedicated Worker complete-snapshot policy; exact consented GitHub ownership | A two-file Cloudflare retirement necessarily removes every other asset |
| 26 | Version URLs checked after deploy | Confirm off before subsequent deploy and again after; failure blocks retirement | Prevents exposing the previous full site during replacement/retirement |
| 27 | Existing published-file GET is enough for read-back | Bounded same-origin verifier checks marker, descriptor and current sections | Redirected/public expected bytes do not prove the new origin is live |
| 28 | Existing timeout wrapper covers all requests | True streamed/multipart abort support and uncertain-outcome re-read | Current wrapper does not abort every multipart request type |
| 29 | Existing-repo/head-tree prefixes prove ownership | Existing-repo reserved-path consent and exact manifest-owned deletion | Prefix alone cannot prove a user file was app-created |
| 30 | Move calls publish inside a shared queue | Only outermost command enqueues | Existing `SerialOpQueue` is non-reentrant |
| 31 | Cover downscaling may need to be added | Reuse existing local/remote/poster downscaling and fix stale comments | Avoid duplicate implementation and unnecessary new work |
| 32 | First page of accounts is enough | Four bounded pages, then explicit manual Account ID | No silently incomplete account picker |
| 33 | Published share URL comes from the current manifest/credentials | One journal `verifiedTarget`, migrated only after bounded read-back | A failed/new deployment or target change must not erase a previously truthful share URL or create an unverified one |
| 34 | Reader reconciliation lives in `network/application/` | Implemented at `network/domain/usecases/` (the repo's one blessed use-case location) | AGENTS §3.2 puts use cases under `domain/usecases/`; the network feature already does. Moving one file to a new folder would create a second convention |
| 35 | `refresh_network_use_case.dart` gains the move detector | `RefreshRun` (the per-run state machine) moved to `usecases/refresh_run.dart`; the use case file stayed a thin facade | The addition pushed the file past the 500-line ratchet and R29 forbids a new allow-list entry |
| 36 | Domain may import only listed pure core files | `core/network/workers_dev_url.dart` added to the purity allow-list (the file is pure Dart: label grammar only) | Exists in `core` precisely so the network domain never imports the publish feature (E.2); it holds no IO, Flutter or Riverpod |
| 37 | `EventsRepository.load()` | Renamed `loadForEditor()`; new `loadStrict()` returns `Either<Failure, EventsContent>` for publishing | E.2 requires the tolerant editor read to be a separately named explicit choice, and a corrupt metadata file must never masquerade as empty public content |
| 38 | Builders take the host manifest | Builders take the `PreviousPublication` read view (`shaFor`, `coverSourceFor`, `ownedPaths`) | Same two questions on both hosts, no host-specific fields leaking into the shared builders (E.1) |
| 39 | Coverage/marker work only in S8 | `PublishMode.complete` implemented and enforced in the builders (missing cover/poster fails typed before any write) | R2's strictness is a builder property, not a host property; doing it now keeps S8 from re-implementing it |
| 40 | S3 shipped as one PR | S3 landed in two commits on the branch: (a) shared builders + exact section merge + strict snapshot reads, (b) the origin-bound bounded verifier (`PublishedSiteUrlPolicy.readBackUrl` + `BoundedPublishedSiteVerifier`) wired into the GitHub read-back and the descriptor reuse read. Still open: wiring `PublishSnapshotBuilder` into `PublishController`, and the R4 digest (moved into S4 with the confirmation flow) | Both parts leave the suite green; the verifier was already the read-back for an existing publish, so it was made load-bearing immediately rather than left as dead code. The digest is defined against content that `exportedAt` changes, so it belongs with the flow that consumes it |
| 41 | `PublishSnapshotBuilder.build(...)` reads and builds in one pass; the publish controller feeds raw lists to the use case | Split into `read(reads:, includeEvents:)` → `PublishInputs` (target-free, strict) and `build(inputs:, previous:, now:, mode:)`; `PublishController` implements `PublishReads`; `publish_snapshot_builder.dart` is wired once in DI and shared by every host; read failures are the new typed `PublishReadFailure`, which carries an already-safe sentence instead of a diagnostic | R2 requires an unreadable library to abort before any remote write. Reading first and building against `previous` second is the only order that fails before the keystore, the GitHub API and the manifest are touched — the previous one-pass order did a token read and a `pagesSite` call before discovering the library was unreadable. The same split is the shape R4's prepare→confirm flow needs, and it keeps the shipped failure copy ("Could not read the library…") byte-identical |
| 42 | `PublishMode.complete` is passed "when the move/replacement commands exist" | `PublishController.publish({mode})` already threads the mode into the builder, covered by a controller test (a missing cover refuses in `complete`, degrades in `incremental`) | A destructive mode that no caller can reach is exactly how a flag ends up unimplemented; the seam is now proved end to end before S4/S9 add the commands |
| 43 | `GitHubPublishTarget` carries `ownerRepo`, the expected Pages `branch`, the derived `siteUrl` and a stable `targetId` | The target lands with `ownerRepo`, the derived `siteUrl` and `targetId`; the expected branch joins it with the schema-2 manifest | No caller can know the expected branch before the manifest records it (`PublishManifest` is still schema 1), so a branch field today would be a parameter nothing supplies. R1's field list is completed by the S4 manifest slice, where R6's branch-match reconciliation uses it |
| 44 | The publish controller reads its inputs and the use case derives the target | The controller resolves ONE sealed `GitHubPublishTarget` from local credentials and passes it to the use case; `PublishReads.libraryJson(siteUrl)` builds the descriptor for that target; no second derivation exists | C3 requires `library.json.siteUrl` to be the operation's target. The cost is one local repo-name read before the strict reads (no token, no network, no manifest) — the fail-fast tests still pin that nothing else happens |
| 45 | A manifest missing/stale only causes redundant uploads; a rebuild adopts the repo's whole git tree | Schema-2 record (repo, branch, headSha, ownershipConfirmed, state); shas always come from the typed tree snapshot; a record that does not describe this repo+branch claims nothing; tree paths this phone did not write are never adopted; a missing branch/malformed/truncated tree is a typed failure, never an empty map | The old `headTreeShas` answered `{}` on every failure, indistinguishable from "nothing is published", and adopting the whole tree made a later drop of an app-owned path able to delete a human's file (R6/R13). The behaviour change is deliberate and recorded |
| 46 | `commitFiles` resolves the head itself; a concurrent advance is just an HTTP error | `commitFiles(expectedHead:)` compares the head BEFORE uploading any blob and returns the typed `PublishCommitStale`; `force: false` stays mandatory. A branch that moves between that read and the ref patch still surfaces as the fixed "try again" HTTP message, because that code can also mean a malformed request and is not guessed into "the site changed" | R6 asks for a typed stale failure on a head mismatch; guessing an ambiguous status code into a factual claim would be worse than the generic retry copy |
| 47 | The share URL comes from the current manifest/credentials (row 33) | Landed as E.1/E.5's `PublishHostState` journal: one prefs key, activeHost + verifiedTarget, read by `publishedSiteUrlProvider`. Both publishes record the target only after their read-back proves the site. The legacy migration records the ATTEMPT (`activeHost` always, `verifiedTarget` only when `books.json` really serves the recorded sha) so an unreachable site is not re-fetched on every read | The pointer must survive a failed publish; a record that stays empty would re-run the migration read-back on every share-card open, and a record that claims an unproven target would hand out an address that does not serve the library |
| 48 | F.4 step 2 verifies a `deployed` head before allowing a new commit | Not yet implemented. `state` is written truthfully (`deployed` on commit, `live` only after the read-back, preserved across reconciliation only while it describes the read head) but a `deployed` record does not BLOCK a new publish yet. `PublishMode.complete`'s confirmation flow (R4 digest) is likewise still open | Deferring keeps the deadlock risk out of this slice: blocking on an unreadable site would strand a user whose phone simply cannot reach the CDN. The check and its "unreadable ≠ contradictory" rule belong with the journal's retry command (D.3), where "Retry verification" exists |
| 49 | B.7: the asset hash is `hex(SHA-256(base64(bytes) + extension))[0..32]` | Implemented exactly as written, behind `CloudflareAssetHash.scheme = "sha256-b64-ext-32"`. **The reviewed Wrangler source disagrees**: `packages/deploy-helpers/src/deploy/helpers/hash.ts` computes `blake3(base64(bytes) + extension)` and slices the same 32 hex characters, and the Cloudflare docs name no algorithm ("a 32 hexadecimal character hash of the file"). S2/T4–T5 decides; if the API rejects these hashes the formula changes and `hashScheme` changes with it, which invalidates stored hashes safely (R5) instead of reusing wrong ones | blake3 would need a new runtime dependency, which R28 forbids without a product decision; the plan's formula is the reviewed contract and the trial is the designated gate. Recording it here means the conflict is visible before S6, not discovered as a mystery upload failure |
| 50 | E.3: bounded manifest/journal JSON codecs live in infrastructure | The Cloudflare record's `toJson`/`fromJson` live in `cloudflare_site_manifest.dart`, exactly like `PublishManifest`'s | Two manifests with two codec locations is the drift P5 forbids, and `dart:convert` is already on the domain purity allow-list. The bounded-decoding policy that E.3 is really about (depth/byte caps) applies to HOSTILE remote bodies, which are parsed in infrastructure; a local file this app wrote is read tolerantly and fails closed |
| 51 | The publication state enum is `PublishManifestState` inside the GitHub manifest | Extracted to `site/publish_state.dart` as `PublishState`, shared by both manifests, the marker classifier and the journal | The three states (`deployed`/`live`/`retired`) mean the same thing on both hosts; a second enum would be a second vocabulary for one idea, and the marker classifier would have to translate between them |
| 52 | R15: `CloudflareSiteUrl` validates "with an unchanged `BookmarkUrl.normalize` round trip" | `CloudflareSiteUrl` delegates to the shared core grammar `WorkersDevUrl` (the same one `BookmarkUrl` delegates to); the round trip is asserted in tests rather than implemented by importing the network feature | A publish→network feature import would break the layering rule for no gain: both already share one grammar in `core/network/`, so the round trip is a property of the shared parser, not a second check |
| 53 | E.1 lists `cloudflare_api.dart`, `cloudflare_credential_store.dart` and `cloudflare_error_messages.dart` under the S5 domain slice | S5 lands the value objects, the target, the record and the marker. The ports, the credential-store port and the fixed messages land with S6/S7, where their first adapter and caller exist | A port with no adapter and no caller is dead code (AGENTS §2.4), and S5's own done criteria are the value-object/manifest/marker tests. The files are still domain-only when they land |
| 54 | Part G lists the production HTTP contract; the trial's T11/T15 need a version id to build a version URL | The trial adds ONE trial-only diagnostic read, `GET /accounts/{a}/workers/scripts/{name}/versions`, and probes `https://<version-id>-<worker>.<sub>.workers.dev/`. The probe result is recorded as `unknown` when the shape does not resolve, and the version-URL shape is never used by the app | T11/T15 ask whether an earlier version is publicly reachable, which cannot be answered without a version id. The endpoint is documented and read-only, it is not added to Part G (no production code calls it), and an unresolved probe is reported honestly instead of being guessed into a pass |
| 55 | Row 48 deferred F.4 step 2; F.4 says a failed pre-publish verification "stops without another commit" | Implemented as the maintainer's chosen **Option B**: a `deployed` record whose anchor still matches the remote head is verified before building. `matched` upgrades the record to `live` and lets the journal claim the address; `contradicted` (the site answered with DIFFERENT bytes) stops the publish with a fixed message; `unreachable` (no answer within three short polls) lets the publish proceed. The check is `PublishVerificationCheck` + `PublishedFileReadBack.untilMatchesSha`, wired into both publishes. The standalone "Retry verification" affordance of D.3 is still open (the next publish now retries automatically) | Row 48's own note is the reason: blocking on an unreadable site would strand a user whose phone simply cannot reach the CDN, and a timeout is not evidence that the site changed. The distinction is objective — a fetched body either hashes to the recorded content sha or it does not — so no guessing is involved. The bytes of an earlier publish are not kept; the recorded git blob sha is what makes one fetch enough |





---

# Part N — Final implementation checklist

Do not consider the feature complete until every answer is “yes”:

- [ ] Is every publish call bound to an exact sealed target, with descriptor URL
      derived from that target?
- [ ] Can a corrupt read or missing required asset never produce a complete
      snapshot or retirement?
- [ ] Are source and destination both checked before a move, with the source
      checked again before retirement?
- [ ] Is any multi-writer claim limited to what the actual API guarantees?
- [ ] Are legacy GitHub manifests reconciled before merge, with expected-head
      commits and atomic saves?
- [ ] Are Cloudflare Workers explicitly dedicated, and GitHub deletions exactly
      owned and consented?
- [ ] Are version URLs confirmed off before subsequent deploys and retirement?
- [ ] Is a retired site recognized only by positive evidence, never marker 404?
- [ ] Can an unverified address never reach descriptor, QR, share or move?
- [ ] Can read-back never be satisfied by another origin?
- [ ] Are tokens/JWTs absent from state, logs, journal, spool and errors?
- [ ] Are multipart operations abortable and all response/JSON bounds enforced?
- [ ] Is memory bounded across artifacts, base64, multipart and concurrency?
- [ ] Does reader reconciliation preserve both uniqueness constraints and local
      user decisions without automatic following?
- [ ] Does every move crash point have a deterministic safe retry?
- [ ] Are all docs, ADRs, privacy/store answers and real-host smoke evidence in
      agreement with the shipped behavior?
