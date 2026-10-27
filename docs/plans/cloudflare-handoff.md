# Cloudflare publishing — implementation handoff

- **Plan:** [`cloudflare_plan-final.md`](../../cloudflare_plan-final.md) (authoritative;
  its Part M now carries every session's deviation rows 34–53).
- **Branch:** `cloudflare`, nine commits on top of `main` at `e8c4d8e`, plus
  S5 in the working tree (not yet committed — a commit needs approval):

  | Commit | Session | What landed |
  |---|---|---|
  | `9b5cb38` | S0 | Publish-page widget extraction, Cloudflare copy withdrawal, ADR 0007/0010 amended, draft ADR 0017, `SECURITY.md` |
  | `8c413d8` | S1 | Strict `workers.dev` reader grammar, C10/R17 library-move reconciliation |
  | `3205f37` | S3 (part 1) | Shared section builders, exact section merge, strict snapshot reads |
  | `77561ef` | S3 (part 2) | Origin-bound verifier, strict snapshot builder wired into the controller, two-phase read/build, `PublishReadFailure` |
  | `39469e5` | S3 (docs) | Part M rows 41–42, this handoff |
  | `e8fe497` | S4 (part 1) | `core/async/serial_op_queue.dart`, `core/security/hardened_secure_storage.dart` used by all four secret stores |
  | `c3005d1` | S4 (part 2) | Sealed `PublishTarget`/`GitHubPublishTarget`; the descriptor URL comes from the operation's target |
  | `0f509fa` | S4 (part 3) | Schema-2 publish record, typed tree reconciliation, expected-head commits, atomic typed saves, `deployed`→`live` |
  | `f865361` | S4 (part 4) | `PublishHostState` journal + `PrefsPublishHostStore`, read-back-gated migration, the share URL comes from it |
  | *(pending)* | S5 | `SitePath`, shared `PublishState`, Cloudflare value objects, `CloudflarePublishTarget`, schema-2 Cloudflare record, publish marker + freshness classifier |

- **State:** every session gate is green — `build_runner` leaves no diff,
  `flutter analyze lib test integration_test` reports no issues,
  `dart format --set-exit-if-changed lib test integration_test` is clean, and
  the full suite passes (golden excluded).
- **Nothing Cloudflare-side is shipped yet.** No token capture, no API client,
  no Worker upload. The Cloudflare-visible code is the reader's `workers.dev`
  URL grammar (S1) and the S5 pure-domain value objects — see §6 for why that
  is deliberate.

---

## 1. How to verify where we are

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs   # must leave no diff
fvm flutter analyze lib test integration_test                  # zero issues
fvm dart format --set-exit-if-changed lib test integration_test
fvm flutter test --exclude-tags golden
```

Use `fvm …` (Flutter 3.44.2 per `.fvmrc`). The bare `flutter` on `PATH` is a
different SDK and will fail `pub get` on purpose.

---

## 2. S0 — what shipped

**Deliverable:** the publish page is a thin renderer before any Cloudflare
behavior is added; the stale Cloudflare copy is gone; the security/ADR records
exist *before* the first secret-bearing Cloudflare code (plan: "ADR 0007,
ADR 0010, `SECURITY.md` and a draft ADR 0017 land in S0").

| Item | File |
|---|---|
| Page 472 → **324 lines** | `lib/features/publish/presentation/pages/publish_page.dart` |
| GitHub tile (account + target sections, D3 status) | `widgets/github_tile.dart` |
| Cloudflare tile, rewritten copy | `widgets/cloudflare_tile.dart` |
| Shared section card | `widgets/section_card.dart` |
| Provider tile enum/widget only | `widgets/provider_tile.dart` |

Copy changes (no behavior):
- The Cloudflare tile is now titled **Cloudflare Workers** and no longer advises
  "connect the GitHub repo in the Cloudflare dashboard". A dashboard Git
  integration is an explicit non-goal (plan A.4); the body now says only that
  publishing to Cloudflare from this app is not available yet.
- `publish_library_use_case.dart`'s stale claim "cover downscaling is NOT
  ported (Q-P1), covers publish at original size" was **false** — the injected
  local-cover reader has always downscaled (400×600 q80 via `ImageDownscaler`).
  Corrected in S3.

Records:
- **ADR 0007** — three persisted `String` tokens (GitHub, ISBN, Cloudflare)
  plus the two ephemeral Cloudflare JWT shapes.
- **ADR 0010** — no certificate pinning for *publishing APIs* (GitHub,
  Cloudflare), with the origin/redirect/bounds mitigations named.
- **ADR 0017 (draft)** — dedicated assets-only Worker, one active host, sealed
  targets, complete snapshots, one journal, marker freshness, version-URL gate,
  disclosed single-writer limitation.
- `SECURITY.md` — every accepted `String` secret interval listed under known
  limits; scope now says "GitHub and Cloudflare credentials".

---

## 3. S1 — what shipped (reader side, complete)

**Deliverable:** valid Workers URLs are accepted, hostile forms refused, and a
library that changes address produces a *user decision* instead of a dead end.

URL grammar (R15):
- `lib/core/network/workers_dev_url.dart` — one pure grammar: exactly
  `<worker>.<account-subdomain>.workers.dev`, valid worker/subdomain labels,
  lower-case host, no userinfo/port/query/fragment/trailing dot, root path only
  for a stored site.
- `BookmarkUrl` delegates to it; `pages.dev`/`github.io` rules are unchanged.
  `sanitize` still accepts files under a valid Workers host (the viewer must be
  able to read `books.json`), `normalize` rejects any non-root Workers path.
- Tests: `test/features/network/domain/workers_dev_url_test.dart` (apex,
  one-label, extra-label, evil suffix, 63/64-char labels, punycode, ports,
  userinfo, queries) plus Workers cases in `bookmark_url_test.dart`.

Reconciliation (C10/R17):
- `domain/library_move_candidate.dart` — ephemeral evidence: saved row id +
  saved address + the other canonical address + the shared fingerprint
  (+ `hasFetchedFacts`, so a card scan never clears a stored pin).
- Refresh detects the candidate **before** conflict suppression
  (`RefreshRun._recordMoveCandidate`) and reports it in
  `RefreshReport.moveCandidates`; nothing is written and no duplicate
  fingerprint is persisted. Discovered rows keep the conflict badge, and a
  payload whose declared `siteUrl` differs from the address it was fetched from
  is not evidence.
- `AddMemberUseCase` now returns `AddMemberResult`
  (`MemberAdded` | `MemberMoveDetected`); a scanned card whose identity is
  already saved elsewhere offers the choice instead of refusing. When the
  card's address is *also* already saved, it stays a plain identity-conflict
  refusal (that is the refresh flow's job).
- `ReconcileLibraryMoveUseCase` + `NetworkRepository.acceptLibraryMove` — ONE
  transaction: delete the duplicate, repoint the canonical row when the user
  chose the new address, keep the canonical id/`createdAt`/`sortOrder` and
  every consent/membership field, apply fresh remote fields only when a
  descriptor was actually fetched, and fail closed with `StaleStateFailure` if
  either row changed meanwhile or a different row took the target address.
- UI: `LibraryMovePrompt` (shared card) in the saved-libraries list (with a
  "Not the same library" dismissal that writes nothing) and on the add-member
  page (where "keep the saved address" is the dismissal).
- Docs: `ARCHITECTURE.md` §5.6 URL row + §6 decision, ADR 0012 amendment,
  README/PRIVACY host lists and move wording, reader dialog copy.

Tests added: `reconcile_library_move_use_case_test.dart`, drift
`acceptLibraryMove` group, refresh move-offer group, controller `resolveMove`
group, add-member page flow, network page flow (accept + dismiss).

---

## 4. S3 — what shipped, and what is deliberately still open

### 4.1 Shipped (commit `3205f37`)

- **One builder per section** (R3):
  - `application/site/catalogue_section_builder.dart`
  - `application/site/events_section_builder.dart`
  - Both produce `PublishFile`s; `PublishLibraryUseCase` and
    `PublishEventsUseCase` now call them instead of assembling files inline.
  - Byte characterization is pinned by
    `test/features/publish/application/catalogue_section_builder_test.dart`
    (file order, salted cover paths, viewer blob sha
    `6c70bcfe…`, payload key/field shape, redaction of notes/location).
- **One section merge** (R7/M14): `domain/site/section_merge.dart`.
  A publish of one section preserves the other; the section's dropped paths
  become **exact** deletions (stale posters *and* now stale covers leave the
  site); unsafe/foreign paths are refused. Tests:
  `test/features/publish/domain/section_merge_test.dart`.
- **Strict reads + snapshot** (R2):
  - `domain/site/publish_snapshot.dart` (`PublishReads`, `PublishSnapshot`) and
    `application/site/publish_snapshot_builder.dart`. Any failed read aborts
    with nothing written.
  - `PublishMode.complete` is enforced **in the builders**: a referenced cover
    or poster with no usable source is a typed failure before any write
    (`CatalogueSectionBuilder.missingCoverMessage`,
    `EventsSectionBuilder.missingPosterMessage`).
  - `EventsRepository.loadStrict()` returns a typed failure for
    corrupt/unreadable metadata (a missing file is legitimately empty); the
    tolerant editor read is now `loadForEditor()`.
- **Host-neutral plumbing** for the Cloudflare adapter: `PublishFile`,
  `PublishSection`, `SiteSectionOwnership` (exact owned paths per section),
  `PreviousPublication` (`shaFor`, `coverSourceFor`, `ownedPaths`), and
  `PublishCoverDecider` now takes that view instead of the GitHub manifest.

### 4.2 Origin-bound read-back — done in the same session

- `PublishedSiteUrlPolicy.readBackUrl(siteUrl, path, cacheBuster:)` builds the
  only address a verification may fetch: canonical site root + safe relative
  path, optionally one `?rb=<token>`. `sanitizeForSite` (the viewer's no-query
  rule) is untouched and now has a test pinning that.
- `PublishedSiteVerifier` (domain port) +
  `BoundedPublishedSiteVerifier` (infrastructure) — unauthenticated client,
  exact-URL allow-list (so **no** redirect can be followed), streamed cap,
  abortable deadline, null on every refusal.
- `PublishLibraryUseCase` read-back now uses it (`siteUrl` + `books.json`,
  capped at the expected length, fresh buster per attempt), and
  `PublishController` reads the live descriptor through it too — the previous
  unbounded `client.get` path is gone.
- Tests: `test/features/publish/infrastructure/
  bounded_published_site_verifier_test.dart` (exact URL, cache-buster,
  redirect refused, over-cap, non-2xx, refused URL never reaches the network)
  plus the read-back suite in `publish_library_use_case_test.dart`.

### 4.3 S3 remainder — done (commit `77561ef`)

1. **`PublishSnapshotBuilder` is wired into `PublishController`.** The
   controller now *is* the app's `PublishReads`: catalogue
   (`getAllForInterchange`), `periodical.listAll`, `events.loadStrict`, the
   `library.json` assembly and `activeLoanCounts`, each returned as a typed
   `PublishReadFailure` carrying an already-safe sentence. The section builder
   itself comes from the new DI provider `publishSnapshotBuilderProvider`, so
   GitHub and (later) Cloudflare consume ONE wiring and one `books.json`
   encoder (`encodeBooksJsonBytes`).
2. **Two-phase contract.** Reading and building are separate calls:
   `read(reads:, target:, includeEvents:)` → `PublishInputs`, then
   `build(inputs:, previous:, now:, mode:)` → `PublishSnapshot`.
   `PublishLibraryUseCase.call` runs the read phase BEFORE the token,
   `pagesSite` and the manifest, so a library that cannot be read fails without
   a token read, an API call or a manifest load. (`target` arrived with S4: the
   descriptor must be built for the operation's site, C3. The fail-fast
   assertions therefore allow exactly one local target read — deviation 44 —
   and still forbid the token, the API and the manifest.)
3. **`PublishMode.complete` reaches the builder** via
   `PublishController.publish({mode})`, covered by a controller test (missing
   cover refuses in `complete`, degrades in `incremental`). The move/replacement
   *commands* are still S4/S9 work.
4. **Tests added:** `test/features/publish/application/publish_snapshot_builder_test.dart`
   (J.2: failed catalogue/periodical/events read, no-events read, complete-mode
   missing cover/poster, availability flag, counts from the snapshot) plus the
   two read-failure tests in `publish_library_use_case_test.dart`.

### 4.4 S4 — what shipped, and what is deliberately still open

**Shipped (four commits: `e8fe497`, `c3005d1`, `0f509fa`, `f865361`):**

1. **`core/async/serial_op_queue.dart`** — the vault's FIFO moved out of the
   vault feature (publishing must not import vault) and its doc now names both
   callers and the no-nesting rule (M30). `core/security/hardened_secure_storage.dart`
   is the ONE hardened `flutter_secure_storage` configuration: iOS
   accessibility is the only per-store choice, and all four secret-bearing
   stores (publish credentials, cover salt, lookup key, biometric vault record)
   now use it, so the options cannot drift (deviation 12).
2. **Sealed `PublishTarget`** (`domain/publish_target.dart`) with only
   `GitHubPublishTarget` today. `create(ownerRepo)` derives `siteUrl` through
   `githubPagesUrlFor`, so no constructor can take a host + URL pair; the
   catalogue use case takes the target, and `PublishReads.libraryJson(siteUrl)`
   builds the descriptor for it (C3/R1). The controller resolves it once from
   local credentials.

**Shipped since (parts 3–4):**

3. **Schema-2 publish record + reconciliation (R5/R6).** `PublishManifest`
   carries `repo`, `branch`, `headSha`, `ownershipConfirmed` and `state`
   (`deployed`/`live`/`retired`). `GitHubTreeSnapshot` replaced the
   `headTreeShas` map: a missing branch, a malformed body or a truncated
   listing is a typed failure, never `{}`. `GitHubPublicationReconciler` is the
   one read step both publishes use; every claimed sha comes from the tree, a
   record that does not describe the same repo+branch claims nothing, and tree
   paths this phone did not write are never adopted (so a later drop cannot
   delete a human's file).
4. **Atomic typed saves (R9).** `FilePublishManifestStore.save` writes a temp
   file, renames it over the record, and returns `Either`. A landed commit
   whose record could not be saved reports `localStateSaved: false` instead of
   "Published!".
5. **Expected-head commits.** `commitFiles(expectedHead:)` compares the head
   before uploading a single blob and returns `PublishCommitStale`; `force:
   false` stays mandatory.
6. **`publish_host_state` journal (R33).** One prefs key holds `activeHost` +
   `verifiedTarget`; `publishedSiteUrlProvider` reads it, and both publishes
   record the target only after their read-back proves the site. A legacy
   install is migrated ONCE with a bounded read-back of `books.json` against
   the sha its manifest recorded. `PrefsPublishHostStore` rebuilds the sealed
   target from its identity parts and refuses a stored URL that disagrees with
   the derived one (C3).

**Still open in S4 (in dependency order):**

1. **F.4 step 2's pre-deploy check** (deviation row 48): a `deployed` head is
   recorded truthfully but does not block the next publish yet. It belongs with
   the journal's "Retry verification" command (D.3), together with the
   unreadable-vs-contradictory rule that keeps a flaky phone from deadlocking.
2. **`pendingMove` in the journal.** The record is schema 1 with
   `activeHost` + `verifiedTarget`; the move's phase and the exact old/new
   targets are added by S9 (absent field = no move, so no migration).
3. **The events publish still resolves `targetRepo()` itself** — give it an
   explicit target when the move commands land, so both publishes are
   target-driven. (It already builds a `GitHubPublishTarget` from it, so the
   descriptor/read-back/commit are all target-driven; only the *source* of the
   repo string is still the credential store.)
4. **The R4 digest** (§3.4 above) and the move/replacement commands (S9).

### 4.5 Still open from S3

**R4 snapshot digest** — moved into S4 with the confirmation flow (deviation
row 40). The digest must cover canonical section content + content shas but
exclude `exportedAt`/`publishId`, so it must not be a hash of the built bytes
alone (`books.json` embeds `exportedAt`).

---

## 5. S5 — Cloudflare pure domain (in the working tree, commit pending)

**Deliverable:** every Cloudflare value that can reach an API path, a public
address or a published file is validated at construction, and the two records
that decide what survives a deploy exist and are tested. Nothing here talks to
the network, so S5 is independent of the S2 trial.

### 5.1 The one path policy (R23)

`domain/site/site_path.dart` is now the ONLY publish path rule. Before it, the
rule existed twice — a private check in `publish_section.dart` and a regex in
`github_pages_url.dart` — which is how a path accepted by the merge could be
rejected mid-upload. Both delegate to `SitePath` now.

Accepted: relative, non-empty, ≤512 characters, `/`-separated segments of
`[A-Za-z0-9._-]`, no `.`/`..` segment. The allow-list charset is what refuses
`%2F`, `%2e%2e`, spaces, control characters and non-ASCII names automatically.
Nothing is "fixed up": a bad path is refused, because a repaired path is a
different file than the builder asked for. The leading-slash mapping Cloudflare
needs (`books.json` → `/books.json`) deliberately does NOT live here — only the
Cloudflare adapter may add it (B.2).

### 5.2 Value objects (`domain/cloudflare/`)

| File | Rule |
|---|---|
| `cloudflare_api_token.dart` | `cfut_…` / `cfat_…` / legacy 40-char shapes, ≤512 chars, `[A-Za-z0-9_-]` only. No getter: the value is readable only through `use()`, and `toString()` is `CloudflareApiToken(***)` |
| `cloudflare_account_id.dart` | exactly 32 hex characters, folded to lower case (it is an identity) |
| `cloudflare_worker_name.dart` | 1–63 of `[A-Za-z0-9-]`, no edge hyphen; keeps the API spelling and derives `dnsLabel` |
| `cloudflare_subdomain.dart` | DNS label, 1–63, `[a-z0-9-]`, alphanumeric edges, folded to lower case |
| `cloudflare_site_url.dart` | the CONFIRMED address: exactly `<worker>.<sub>.workers.dev/`, HTTPS, no userinfo/port/query/fragment, root path only — via the shared `WorkersDevUrl` |
| `unverified_cloudflare_address.dart` | a candidate for the verification fetch ONLY; no conversion to a target, descriptor, share link or move (C9) |
| `cloudflare_content_type.dart` | exactly `html`/`json`/`jpg` → the three served headers; case-sensitive on purpose |
| `cloudflare_asset_hash.dart` | `hex(SHA-256(base64(bytes) + extension))[0..32]`, pinned by fixed vectors (empty file, extension case) |
| `cloudflare_limits.dart` | the documented limits plus the app's own bounds (1 MiB API body, depth 16, 4 account pages, marker 4 KiB, 30 s/60 s deadlines, fixed compatibility date) |

`CloudflarePublishTarget` joins the sealed `PublishTarget`: the address is
derived from account id + Worker name + subdomain, so no constructor takes a
URL. `PrefsPublishHostStore` rebuilds it from those parts and refuses a stored
URL that disagrees with the derived one.

### 5.3 The two records

- `domain/cloudflare/cloudflare_site_manifest.dart` — schema 2: full target
  identity, `state`, `publishId`, optional diagnostic `liveId`, `hashScheme`,
  path → `{sha, hash, size, type}`, cover-source metadata. It implements
  `PreviousPublication`, so the shared builders read it exactly like the GitHub
  record. A record that does not describe the target claims NOTHING (its file
  map could otherwise authorise deleting another Worker's files). A different
  `hashScheme` keeps the paths but not the hashes, and the merge reports those
  paths in `missingHashes` instead of guessing.
- `domain/site/publish_marker.dart` — the marker value object, the probe
  (`absent` / `unreadable` / `present`) and `classifyFreshness`, which returns
  `known` / `knownRetired` / `unknown` / `newSite` / `siteUnavailable`. Only
  positive evidence produces `known`: a 404 is never retirement, a malformed
  marker is never a fresh site, and a `verification` marker is never a live one.

`PublishState` moved to `domain/site/publish_state.dart` so both manifests, the
marker classifier and the journal share one vocabulary (deviation 51).

### 5.4 Tests

`test/features/publish/domain/site_path_test.dart`,
`domain/cloudflare/cloudflare_value_objects_test.dart`,
`cloudflare_asset_hash_test.dart`, `cloudflare_site_manifest_test.dart`,
`domain/publish_marker_test.dart`, plus the Cloudflare groups in
`publish_target_test.dart` and `prefs_publish_host_store_test.dart`.

### 5.5 What S5 deliberately did NOT land

`cloudflare_api.dart` (the account/deploy ports), the credential-store port and
the fixed error messages land with S6/S7, where their first adapter and caller
exist (deviation 53). A port with no adapter is dead code.

### 5.6 The one open risk from S5

**The asset-hash formula (deviation 49).** The plan says SHA-256; the reviewed
Wrangler source uses blake3 over the same `base64 + extension` input. SHA-256 is
implemented because it is the reviewed contract and blake3 would need a new
dependency (R28). S2/T4–T5 settles it: if the API rejects these hashes, the
formula and `hashScheme` change together, which invalidates stored hashes
safely rather than reusing wrong ones.

## 6. The S2 gate — nothing Cloudflare-side may proceed before it

The plan (§I) says **S6–S9 wait for S2's outcome**. The tool now exists
(`tool/cloudflare_trial/`, written in the S5 commit's follow-up); running it
**requires a human with a disposable account**:

- `tool/cloudflare_trial/` implements T1–T16 per plan Part L: token only from
  `CF_API_TOKEN` (optional `CF_ACCOUNT_ID`, `CF_CREATE_SUBDOMAIN`,
  `CF_TRIAL_SKIP_LARGE`), Worker named `pitak-trial-<8 hex>`, deletion in
  `finally`, and a report of fixed labels / status codes / whitelisted headers
  only — never tokens, JWTs, authorization headers or raw bodies. Its pure
  parts (asset sets, multipart bodies, deterministic large set) are pinned by
  `test/tool/cloudflare_trial_test.dart`; `dart analyze tool` and
  `dart format --set-exit-if-changed tool/cloudflare_trial` are clean.
- Run it on a **disposable account** with the exact
  `Workers Scripts · Edit`, one-account token:

  ```bash
  CF_API_TOKEN=... fvm dart run tool/cloudflare_trial/main.dart
  ```
- Record the sanitized report and the two decisions it settles:
  - **T6** — does a metadata-only assets deploy succeed? If it fails, **stop**;
    shipping Worker code is a separate product decision.
  - **T14/T15** — is there a supported conditional-deployment contract? If not,
    the single-writer limitation in ADR 0017 becomes an operating requirement
    that docs/store answers must state.
- Only after that report: S6 (HTTP adapters) → S7 (connect) → S8 (publish) →
  S9 (moves/retirement).

Until then, do **not** write Cloudflare API code, and do not let a Cloudflare
behavior become load-bearing.

---

## 7. Remaining sessions, in order, with entry criteria

| Session | Entry criterion | Scope reminder |
|---|---|---|
| S4 (remainder) | — | Done: queue extraction, hardened-storage factory, sealed `GitHubPublishTarget`, schema-2 record + tree reconciliation, atomic typed saves, expected-head commits, the host journal + read-back-gated migration. Left: F.4 step 2's pre-deploy check (with the journal's retry command), `pendingMove` (S9), the events publish's explicit target (§4.4) |
| S5 | — (independent of S2) | **Done** (§5): `SitePath`, token/account/worker/subdomain/URL value objects, `CloudflarePublishTarget`, asset hash vectors, content types, schema-2 Cloudflare record + `hashScheme`, marker value object, limits. Left by design: the API/credential ports and fixed messages (S6/S7) |
| S2 | Tool written; needs a maintainer run | `tool/cloudflare_trial/` run on a disposable account + sanitized report + the T6/T14/T15 decisions |
| S6–S9 | S2 report | HTTP adapters, connect flow, publish/replacement, moves/retirement |
| S10–S11 | S6–S9 | Docs/release checklist; real-host smoke; remove `tool/cloudflare_trial/` |

S4 and S5 are the last sessions that can be completed without the trial. If the
goal is "as much as possible without credentials", stop after S5.

---

## 8. Decisions a successor must not silently reverse

- **One builder per section, one merge.** Do not add a second file-assembly path
  for Cloudflare; feed the same `PublishSection` to the Cloudflare adapter.
- **Targets are sealed and explicit.** `library.json.siteUrl` must come from the
  target passed to the operation, never from an "active host" provider. The
  catalogue path already does this; do not re-derive the repo inside a publish
  step (the events path is the last one left, §4.4).
- **One hardened secure store.** Every secret-bearing store is built by
  `hardenedSecureStorage()`; never write a bare `FlutterSecureStorage()`.
- **A card scan never clears a pin.** `LibraryMoveCandidate.hasFetchedFacts`
  exists for exactly that; do not treat a card's null location as "sharing off".
- **Declining a move writes nothing.** Only an accept writes, and it writes in
  one repository transaction with baseline checks.
- **A corrupt read is not empty content.** Publishing uses `loadStrict`; the
  tolerant editor path is explicitly named.
- **Complete mode fails, it does not omit.** A missing cover/poster aborts.
- **`read` before `build`.** The snapshot's read phase runs before any token,
  API call or manifest load. Do not fold it back into one pass: that is what
  makes an unreadable library cost nothing but a local read, and it is the
  shape R4's prepare→confirm flow needs.
- **One builder wiring.** `publishSnapshotBuilderProvider` is the only place
  that assembles the section builders and the `books.json` encoder. A second
  wiring is how two hosts start publishing different bytes.
- **The record is not a cache.** `PublishManifest` schema 2 decides which
  public files survive: shas come from the remote tree, and a path this phone
  did not write is never adopted or deleted. Do not reintroduce a
  "useful anyway, it only causes extra uploads" shortcut for the shas.
- **One reconciliation step.** Both publishes read the tree through
  `GitHubPublicationReconciler`; a second read/rebuild path is how two
  publishes start disagreeing about which files they own.
- **The share address comes from the journal, not the manifest.** A publish
  must not be able to move the advertised address to a site it has not proven.
  The journal write is lazy on purpose: a publish that fails while reading the
  library must not open prefs.
- **A failed save is reported.** `PublishManifestGateway.save` and the journal
  store return `Either`; "Published!" with an unrecorded commit is the bug
  they exist to prevent.
- **Ratchet:** no new allow-list entry. If an addition pushes a file over 500
  lines, split it (that is how `refresh_run.dart`, the three `site/` files,
  `http_github_tree.dart` and `publish_status_copy.dart` came to exist).
- **Domain purity:** `core/network/workers_dev_url.dart` is on the purity
  allow-list because it is pure label parsing. Do not add IO-bearing core files
  to that list.
- **One path policy.** `SitePath` is the only publish path rule. Do not add a
  host-specific regex or a "fix up the path" helper: a repaired path is a
  different file than the builder asked for, and two rules are how one host
  accepts what the other refuses.
- **The marker is not compare-and-swap.** `classifyFreshness` answers "what can
  I prove?", never "am I the only writer". Only positive evidence yields
  `known`; a 404 is never retirement and a malformed marker is never a fresh
  site.
- **An unverified address has no conversion.** `UnverifiedCloudflareAddress`
  exists for the verification fetch only. Do not add a `toSiteUrl()`: C9 says a
  candidate cannot become a target, descriptor, share link or move.
- **A Cloudflare record that does not describe the target claims nothing.** Its
  file map is what authorises a complete-snapshot deploy, so a mismatched
  account/Worker/address must discard the map, not "keep what looks useful".
- **`hashScheme` gates hashes, not paths.** A different scheme means "re-hash
  the bytes", never "forget which files this phone wrote".

---

## 9. Open questions / risks

1. **Single-writer guarantee** — unresolved until S2/T14. Do not claim the
   marker gives compare-and-swap.
2. **`PublishMode.complete` is implemented and reachable** through
   `PublishController.publish(mode:)`, but nothing passes it yet: the move and
   replacement commands arrive in S4/S9. It is covered by a controller test,
   not by a user-facing path.
3. **Catalogue deploy now deletes stale covers.** This is the intended R8 fix,
   but it is a *remote behavior change*: run the J.7 smoke on a real GitHub Pages
   repo before release, and note it in `CHANGELOG.md`.
4. **`PublishSnapshot` has no digest yet** — the replacement confirmation (S4)
   must not be built on it until R4's digest exists. The snapshot is otherwise
   complete: counts, empty-section warnings and `availabilityOmitted` all come
   from it.
5. **S2 has not been run.** `tool/cloudflare_trial/` exists and is
   analyze/format clean, but it needs a disposable account and the exact
   restricted token. Until its report lands, no Cloudflare behavior may become
   load-bearing.
6. **F.4 step 2 is not implemented** (deviation row 48): a `deployed` record
   does not block the next publish, so a commit whose read-back never landed can
   still be built on. The record stays truthful (`deployed`) and the fix belongs
   with the "Retry verification" command.
7. **The journal has no `pendingMove` yet** — schema 1 carries `activeHost` +
   `verifiedTarget` only. S9 adds the field; an absent field must keep meaning
   "no move" rather than requiring a migration.
8. **`bookmark_url.dart` still refuses non-root Workers paths by design**; if a
   library ever publishes under a path (it cannot, per B.1), that assumption
   changes.
9. **The asset-hash formula is unconfirmed (deviation 49).** The plan says
   SHA-256; the reviewed Wrangler source uses blake3 over the same
   `base64 + extension` input, and the docs name no algorithm. S5 implements
   SHA-256 (the reviewed contract; blake3 would need a new dependency, R28).
   S2/T4–T5 decides. If it changes, `hashScheme` changes with it, so stored
   hashes are invalidated rather than reused.

---

## 10. File map for the work so far

**New — network (S1)**
`lib/core/network/workers_dev_url.dart`,
`lib/features/network/domain/library_move_candidate.dart`,
`lib/features/network/domain/usecases/reconcile_library_move_use_case.dart`,
`lib/features/network/domain/usecases/refresh_run.dart`,
`lib/features/network/presentation/widgets/library_move_prompt.dart`.

**New — trial tool (S2)**
`tool/cloudflare_trial/{main,trial_run,trial_http,trial_public,trial_multipart,
trial_assets,trial_report}.dart` + `README.md`,
`test/tool/cloudflare_trial_test.dart`.

**New — publish (S5)**
`lib/features/publish/domain/site/{site_path,publish_state,publish_marker}.dart`,
`lib/features/publish/domain/cloudflare/{cloudflare_api_token,
cloudflare_account_id,cloudflare_worker_name,cloudflare_subdomain,
cloudflare_site_url,unverified_cloudflare_address,cloudflare_content_type,
cloudflare_asset_hash,cloudflare_limits,cloudflare_site_manifest}.dart`.

**New — publish (S3)**
`lib/features/publish/domain/site/{publish_file,publish_section,publish_mode,
previous_publication,section_merge,publish_snapshot}.dart`,
`lib/features/publish/application/site/{catalogue_section_builder,
events_section_builder,publish_snapshot_builder}.dart`.

**New — core (S4)**
`lib/core/async/serial_op_queue.dart` (moved from `features/vault/application/`),
`lib/core/security/hardened_secure_storage.dart`,
`lib/features/publish/domain/publish_target.dart`.

**New — publish (S4, parts 3–4)**
`lib/features/publish/application/{github_publication_reconciler,
publish_status_copy}.dart`,
`lib/features/publish/application/site/{published_file_read_back,
publish_host_state_repository}.dart`,
`lib/features/publish/domain/site/{publish_host,publish_host_state}.dart`,
`lib/features/publish/infrastructure/{github_http_support,http_github_tree,
prefs_publish_host_store}.dart`.

**New — presentation/docs (S0)**
`lib/features/publish/presentation/widgets/{github_tile,cloudflare_tile,
section_card}.dart`, `docs/adr/0017-cloudflare-workers-publishing.md`.

**Materially changed**
`lib/features/publish/application/{publish_library_use_case,
publish_events_use_case,publish_cover_decider,publish_controller}.dart`,
`lib/core/di/src/publish_providers.dart` (one snapshot-builder wiring),
`lib/core/error/failure.dart` (`PublishReadFailure`),
`lib/features/publish/domain/publish_manifest.dart`,
`lib/features/network/domain/{refresh_report.dart,repositories/
network_repository.dart,value_objects/bookmark_url.dart,usecases/
add_member_use_case.dart}`,
`lib/features/network/infrastructure/drift_network_repository.dart`,
`lib/features/network/application/{network_controller,network_refresh_controller,
add_member_controller}.dart`,
`lib/features/events/{domain/repositories/events_repository.dart,
infrastructure/file_events_repository.dart,application/events_controller.dart}`,
`lib/core/error/failure.dart` (`StaleStateFailure`),
`SECURITY.md`, `README.md`, `PRIVACY.md`, `docs/ARCHITECTURE.md`,
`docs/adr/{0007,0010,0012,README}.md`.

**New tests**
`test/core/async/serial_op_queue_test.dart` (moved),
`test/features/publish/domain/publish_target_test.dart`,
`test/features/network/domain/workers_dev_url_test.dart`,
`reconcile_library_move_use_case_test.dart`;
`test/features/publish/application/catalogue_section_builder_test.dart`,
`events_section_builder_test.dart`, `publish_snapshot_builder_test.dart`;
`test/features/publish/domain/section_merge_test.dart`; plus the new groups in
the drift repository, refresh, controller, add-member and network-page suites.

---

## 11. Secrets

No token, JWT, account id or credential is committed anywhere in this work.
The only Cloudflare-shaped strings in the tree are the published-address
grammar, the ADR text and the plan. When the trial tool is written, its report
must stay sanitized (fixed labels, numeric codes) exactly as Part L requires.
