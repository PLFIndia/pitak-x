# Cloudflare publishing — implementation handoff

- **Plan:** [`cloudflare_plan-final.md`](../../cloudflare_plan-final.md) (authoritative;
  its Part M now carries every session's deviation rows 34–42).
- **Branch:** `cloudflare`, four commits on top of `main` at `e8c4d8e`:

  | Commit | Session | What landed |
  |---|---|---|
  | `9b5cb38` | S0 | Publish-page widget extraction, Cloudflare copy withdrawal, ADR 0007/0010 amended, draft ADR 0017, `SECURITY.md` |
  | `8c413d8` | S1 | Strict `workers.dev` reader grammar, C10/R17 library-move reconciliation |
  | `3205f37` | S3 (part 1) | Shared section builders, exact section merge, strict snapshot reads |
  | `77561ef` | S3 (part 2) | Origin-bound verifier, strict snapshot builder wired into the controller, two-phase read/build, `PublishReadFailure` |

- **State:** every session gate is green — `build_runner` leaves no diff,
  `flutter analyze lib test integration_test` reports no issues,
  `dart format --set-exit-if-changed lib test integration_test` is clean, and
  the full suite passes (golden excluded).
- **Nothing Cloudflare-side is shipped yet.** No token capture, no API client,
  no Worker upload. The only Cloudflare-visible code is the reader's
  `workers.dev` URL grammar (S1) — see §5 for why that is deliberate.

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
   `read(reads:, includeEvents:)` → `PublishInputs`, then
   `build(inputs:, previous:, now:, mode:)` → `PublishSnapshot`. The read phase
   needs no target, so `PublishLibraryUseCase.call` runs it BEFORE the token,
   `pagesSite` and the manifest. A library that cannot be read therefore fails
   without a keystore read, an API call or a manifest load — the fail-fast
   tests in `publish_controller_test.dart` still pass unchanged.
3. **`PublishMode.complete` reaches the builder** via
   `PublishController.publish({mode})`, covered by a controller test (missing
   cover refuses in `complete`, degrades in `incremental`). The move/replacement
   *commands* are still S4/S9 work.
4. **Tests added:** `test/features/publish/application/publish_snapshot_builder_test.dart`
   (J.2: failed catalogue/periodical/events read, no-events read, complete-mode
   missing cover/poster, availability flag, counts from the snapshot) plus the
   two read-failure tests in `publish_library_use_case_test.dart`.

### 4.4 Still open from S3

**R4 snapshot digest** — moved into S4 with the confirmation flow (deviation
row 40). The digest must cover canonical section content + content shas but
exclude `exportedAt`/`publishId`, so it must not be a hash of the built bytes
alone (`books.json` embeds `exportedAt`).

---

## 5. The S2 gate — nothing Cloudflare-side may proceed before it

The plan (§I) says **S6–S9 wait for S2's outcome**, and the trial tool does not
exist yet. It is the next Cloudflare-facing task and it **requires a human**:

- Write `tool/cloudflare_trial/` per plan Part L: T1–T16, token only from
  `CF_API_TOKEN` (optional `CF_ACCOUNT_ID`, `CF_CREATE_SUBDOMAIN`), Worker
  named `pitak-trial-<8 hex>`, deletion in `finally`, and a report of fixed
  labels / status codes / whitelisted headers only — never tokens, JWTs,
  authorization headers or raw bodies.
- Run it on a **disposable account** with the exact
  `Workers Scripts · Edit`, one-account token.
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

## 6. Remaining sessions, in order, with entry criteria

| Session | Entry criterion | Scope reminder |
|---|---|---|
| S4 | — (S3 complete) | Sealed `PublishTarget`, schema-2 manifests (GitHub **and** Cloudflare), `SerialOpQueue` extraction (`lib/features/vault/application/serial_op_queue.dart` → `core/async/`), `publish_host_state` journal (one prefs key, no tokens), `hardenedSecureStorage()` factory shared by both credential stores, atomic typed manifest saves, expected-head GitHub commits, `verifiedTarget` migration gated on a real read-back |
| S5 | — (independent of S2) | Cloudflare pure domain: token/account/worker/subdomain/URL value objects, `SitePath`, asset hash vectors, content types, schema-2 Cloudflare manifest + `hashScheme`, marker value object, limits |
| S2 | S5 may proceed in parallel | Trial tool + maintainer run + report |
| S6–S9 | S2 report | HTTP adapters, connect flow, publish/replacement, moves/retirement |
| S10–S11 | S6–S9 | Docs/release checklist; real-host smoke; remove `tool/cloudflare_trial/` |

S4 and S5 are the last sessions that can be completed without the trial. If the
goal is "as much as possible without credentials", stop after S5.

---

## 7. Decisions a successor must not silently reverse

- **One builder per section, one merge.** Do not add a second file-assembly path
  for Cloudflare; feed the same `PublishSection` to the Cloudflare adapter.
- **Targets are sealed and explicit.** `library.json.siteUrl` must come from the
  target passed to the operation, never from an "active host" provider.
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
- **Ratchet:** no new allow-list entry. If an addition pushes a file over 500
  lines, split it (that is how `refresh_run.dart` and the three `site/` files
  came to exist).
- **Domain purity:** `core/network/workers_dev_url.dart` is on the purity
  allow-list because it is pure label parsing. Do not add IO-bearing core files
  to that list.

---

## 8. Open questions / risks

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
5. **The plan's `tool/cloudflare_trial/` does not exist**, so S2 cannot be
   executed today; a successor must write it first.
6. **`bookmark_url.dart` still refuses non-root Workers paths by design**; if a
   library ever publishes under a path (it cannot, per B.1), that assumption
   changes.

---

## 9. File map for the work so far

**New — network (S1)**
`lib/core/network/workers_dev_url.dart`,
`lib/features/network/domain/library_move_candidate.dart`,
`lib/features/network/domain/usecases/reconcile_library_move_use_case.dart`,
`lib/features/network/domain/usecases/refresh_run.dart`,
`lib/features/network/presentation/widgets/library_move_prompt.dart`.

**New — publish (S3)**
`lib/features/publish/domain/site/{publish_file,publish_section,publish_mode,
previous_publication,section_merge,publish_snapshot}.dart`,
`lib/features/publish/application/site/{catalogue_section_builder,
events_section_builder,publish_snapshot_builder}.dart`.

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
`test/core` none; `test/features/network/domain/workers_dev_url_test.dart`,
`reconcile_library_move_use_case_test.dart`;
`test/features/publish/application/catalogue_section_builder_test.dart`,
`events_section_builder_test.dart`, `publish_snapshot_builder_test.dart`;
`test/features/publish/domain/section_merge_test.dart`; plus the new groups in
the drift repository, refresh, controller, add-member and network-page suites.

---

## 10. Secrets

No token, JWT, account id or credential is committed anywhere in this work.
The only Cloudflare-shaped strings in the tree are the published-address
grammar, the ADR text and the plan. When the trial tool is written, its report
must stay sanitized (fixed labels, numeric codes) exactly as Part L requires.
