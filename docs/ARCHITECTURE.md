# Pitak — Architecture

> **What this file is:** the *shape* of the app — what it is, what it promises,
> how the code is laid out, and the data formats that must not change by
> accident. The *rules* for writing code live in `AGENTS.md` (which wins over
> this file). Individual decisions live in `docs/adr/`. Release mechanics live
> in `docs/RELEASING.md`.
>
> The original facts were checked against the code on 2026-10-19; the catalogue
> contracts were reconciled with the remediation implementation on 2026-10-25;
> the Cloudflare Workers publishing host, its stored records and the reader
> reconciliation were reconciled on 2026-10-28 (ADR 0017). When the code
> changes, change this file in the same PR.

---

## 1. What Pitak is

A **privacy-first, offline personal library catalogue** for Android, ported
from a retired Kotlin app with **zero data loss** as the hard guarantee.

- Books, wishlist and the library network live in **Drift/SQLite**.
- Borrowers and loans live in a **SQLCipher-encrypted vault database**.
  Argon2id derives the key-encryption key and AES-256-GCM wraps the vault key;
  the key exists only inside a **Rust core** (`rust/`, crate `pitak_crypto`)
  and never crosses the FFI boundary.
- Import/export: JSON, CSV (incl. Goodreads), PDF (Indic scripts via shaped
  images). `.pitabak` backups restore both Pitak and Kotlin-era archives.
- Opt-in publish of a read-only site to **one active host**: GitHub Pages or
  Cloudflare Workers static assets (ADR 0017); opt-in **library network**
  (saved libraries, hub/member cards, consent-gated OSM map).
- Shipped on **F-Droid** (`dev.khoj.pitaka.fdroid`) and **Google Play**
  (`dev.khoj.pitaka`) from the same tag. **Android is the only target.**
- No telemetry, no crash reporting — by design. The lead developer is a
  beginner (AGENTS §0): one blessed way, no magic, explained decisions.

Permissions: `CAMERA`, `INTERNET`, `USE_BIOMETRIC`. `allowBackup=false` +
`data_extraction_rules.xml` keep everything out of Android Auto Backup / D2D.
minSdk 24 (`maxOf(flutter.minSdkVersion, 23)`; Flutter 3.44.2 supplies 24,
above the `flutter_zxing` floor of 23).

Network egress is user-initiated except for the Play-only update flow:
openlibrary.org and Google Books (ISBN lookup); api.github.com (publish,
device-flow OAuth); `api.cloudflare.com/client/v4` (Cloudflare token
verification, asset upload and deployment — one fixed origin, redirects
refused); remote covers (opt-in, host allow-listed); `library.json`
fetches from saved and discovered libraries (Refresh only);
tile.openstreetmap.org (map, remembered opt-in, only while the map is open).
Publishing also performs a bounded public read-back at the site it just wrote:
the read-back uses the unauthenticated, origin-bound verifier (§5.6), follows
no redirect and may add one `?rb=` cache-buster. The catalogue path checks
`books.json` (up to 12 polls); a Cloudflare publish additionally checks the
`pitak-publish.json` marker, `library.json` (or its real 404), `events.json`
and current poster references. Play builds
check for an update once per launch and start Play's flexible-update flow;
after the user accepts Play's dialog, the Store downloads in the background.
The F-Droid flavor has no Play Core/update library and cannot run that check.

Publishing talks to exactly one host at a time. The app never publishes to
both, never mirrors a site, and never deletes a repository or Worker remotely.

### 1.1 The five product promises

Every change must name the promise it protects. If it protects none, it is
probably over-engineering.

| # | Promise | What it forbids |
|---|---------|-----------------|
| P1 | **Zero data loss** across updates, backups and Kotlin→Pitak restore | untested schema migrations; parsers that throw on hostile files |
| P2 | **Secrets never leak** (vault key stays in Rust; no `String` secrets; no logs/PII) | release-mode logging; unvetted dependencies; unsigned supply chain |
| P3 | **F-Droid stays clean** (no Google libraries in the `fdroid` flavor) | any plugin bump without the purity check (`docs/RELEASING.md` §2) |
| P4 | **Honest, reproducible releases** (pinned toolchain, verified artefact, one signed tag → both stores) | lightweight tags; hand-typed build commands; stale artefacts |
| P5 | **A beginner can maintain it** (one blessed way, no magic, explained decisions) | new frameworks for solved problems; tooling the maintainer cannot run locally |

### 1.2 Explicit non-goals (decided; do not re-open without a trigger)

- **No telemetry or crash reporting** — contradicts P2 and the store listing.
  "Observability" is typed `Failure`s and user-initiated, redacted exports.
- **No certificate pinning for GitHub** (ADR 0010).
- **No second state-management / DI / result / test framework.**
- **No iOS/desktop hardening** — not shipped.
- **No i18n of the UI chrome** until a translation contributor appears;
  Indic support is for *content* (titles, PDF), not chrome.
- **No mutation testing / continuous fuzzing / DCM** — triggers: coverage
  floor ≥ 80 % with suspicion of vacuous tests; a second Rust parser; never.
- **No vault auto-lock** (ADR 0006); **passphrase change is rewrap, not
  rotation** (ADR 0005); **`.pitabak` is not fully encrypted** (§5.5).
- **No Cloudflare Pages, dashboard Git integration, Workers Builds or custom
  domains**, and no "Sign in with Cloudflare" OAuth — the token is pasted
  (ADR 0017). No user Worker code, no Functions, no WebView, no background or
  scheduled publishing.
- **No two active hosts, mirrors or automatic peer redirection**, and no
  machine-readable moved notice for other apps (ADR 0012, ADR 0017). A move is
  a user decision; other phones may *offer* reconciliation and never follow it.
- **No promise that arbitrary files on a Cloudflare Worker survive.** A Pitak
  Worker is dedicated to Pitak and a deploy is a complete asset snapshot; the
  old host becomes a moved page only after the new one is verified.
- **No hard cross-device concurrent-writer guarantee.** The Workers API offers
  no supported conditional deployment, so *one publisher per Worker* is an
  operating requirement, not a UI suggestion (ADR 0017).

---

## 2. Layering

Clean Architecture + DDD. Dependencies point **inward only**:

```
presentation  ->  application  ->  domain  <-  infrastructure
   (UI/State)     (use cases)     (pure)      (impl/IO/db)
```

| Layer | May depend on | Must not contain |
|-------|---------------|------------------|
| `domain` | pure Dart plus the reviewed libraries/codecs allow-listed by `test/architecture/domain_purity_test.dart` (including `dart:convert`, used by `LibraryDescriptorCodec`) | Flutter, Riverpod, platform IO (`dart:io`, `dart:isolate`, HTTP, DB, plugins), unreviewed dependencies |
| `application` | `domain` | widgets, `BuildContext`, concrete repositories, platform IO |
| `infrastructure` | `domain` (implements its ports) | UI, business rules |
| `presentation` | `application`, `domain` | direct DB/HTTP, business logic, `infrastructure` imports |

- **State / DI:** Riverpod with codegen (`@riverpod`). The composition root is
  `lib/core/di/` (`providers.dart` + `src/<feature>_providers.dart`).
- **Errors:** `fpdart` `Either<Failure, T>`; sealed `Failure` in
  `lib/core/error/failure.dart`. No exceptions across layers.
- **Secrets:** `SecretBytes` in Dart (wipeable, redacted `toString`);
  `Zeroizing<>` + `subtle` in Rust. Honest exceptions: the GitHub token, the
  ISBN-lookup key and the Cloudflare API token transit as `String` because
  their APIs are `String`-typed, and a Cloudflare upload/completion JWT lives
  for at most one hour inside one publish operation (ADR 0007). Every
  secret-bearing store is built by `core/security/hardened_secure_storage.dart`
  so the platform options cannot drift.

### 2.1 Enforced by tests (architecture fitness functions)

These fail the build; change them deliberately, never to "make it pass".

| Test | Enforces |
|------|----------|
| `test/architecture/domain_purity_test.dart` | domain imports only the allow-list (pure Dart, `fpdart`, `crypto`, `archive` — ADR 0009); `application/` performs no platform IO (`dart:io`, `dart:isolate`, `path`, `http`, `drift`, prefs, secure storage) |
| `test/architecture/layer_boundaries_test.dart` | no `presentation → infrastructure` imports; no `flutter/material` in `application`; no `print`/`debugPrint` outside `lib/core/platform/app_log.dart`; no `flutter_map` under `core/di` or `application/`; **file-size ratchet** (a file may not grow past its recorded line budget without an explicit allow-list entry — split it instead) |
| `test/architecture/catalogue_item_validation_gate_test.dart` | every `CatalogueItem` construction site goes through `CatalogueItem.validate` (ADR 0004; the entity was `Book` until 2026-10) |
| `test/core/database/migration_test.dart` | a drift schema snapshot exists for the current `schemaVersion`; every past version migrates forward with data intact (§5.4) |

---

## 3. Module map

```
rust/                     crate pitak_crypto — the trusted crypto + vault boundary
  src/crypto.rs           Argon2id KEK; AES-256-GCM wrap/unwrap (single wrap site)
  src/vault.rs            SQLCipher open/read/write; atomic key-file writes
  src/api.rs              flutter_rust_bridge surface — regen bindings after edits
  tests/                  vault_fixture.rs (hermetic), real_archive.rs, properties.rs
lib/
  src/rust/               generated FRB bindings (analyzer-excluded)
  core/
    app_lock/             optional biometric screen gate (NOT a vault lock, ADR 0006)
    async/                serial_op_queue.dart — the one non-reentrant FIFO that
                          serialises publishes, moves and credential/target writes
    crypto/               secret_bytes.dart, secure_passphrase_field.dart (append-only)
    database/             app_database.dart (Drift; schema history in its doc comment)
    di/                   providers.dart + src/<feature>_providers.dart
    error/                sealed Failure hierarchy
    images/               image_downscaler.dart — single choke point for every
                          decoded image (size caps from the header, EXIF/GPS stripped,
                          frame 0 only, runs in Isolate.run)
    network/              bounded_http_fetcher.dart (size cap, deadline, ≤3 re-validated
                          redirects), app_user_agent.dart, osm_tiles.dart,
                          workers_dev_url.dart (the ONE workers.dev grammar, shared
                          by the reader and the publisher)
    platform/             screen_security.dart (FLAG_SECURE), app_log.dart
    security/             hardened_secure_storage.dart — the ONE hardened
                          flutter_secure_storage configuration
    widgets/              app_gate.dart (splash → lock → Library), qr_view/qr_scan_page
  features/
    library/              catalogue items (`CatalogueItem`, the base row of every
                          kind: books, magazine issues, others — ADR 0013);
                          paged SQL reads (CatalogueItemRepository.page);
                          merge engine
    periodicals/          magazine titles (`Periodical`, ISSN, frequency,
                          derived subscription status) and their issues'
                          kind-specific rules: projection, identity keys,
                          cadence, cover fallback (ADR 0013)
    vault/                encrypted borrowers + loans; passphrase + biometric unlock
    wishlist/
    lookup/               barcode scan (flutter_zxing) + ISBN lookup chain
                          (Open Library → Google Books, cached)
    publish/              ONE active host (ADR 0017): GitHub Pages (device-flow
                          auth + git data API) or Cloudflare Workers static
                          assets (pasted restricted token, assets-only Worker);
                          shared section builders, strict complete snapshots,
                          sealed targets, schema-2 manifests, moves/retirement;
                          PII redaction
    events/               event posters for the published site
    network/              library network/bookmarks (ADR 0012): network_libraries
                          table, library.json codec + bounded fetcher, card QR,
                          Refresh/discovery, membership, native catalogue/events
                          viewers (ADR 0015/0016), consent-gated images/OSM map
    backup/               .pitabak writer (worker isolate) + all-or-nothing restore
    import_export/        JSON/CSV/PDF export, Goodreads import, merge UI
    settings/             Appearance · Data · Security (SettingsPage.initialTab)
    app_update/           Play-only flexible updates; inert on F-Droid
    guides/               in-app "How Pitak works" guides (pure content model +
                          pages; deep-links only — no state, no IO)
  features/<f>/{domain,application,infrastructure,presentation}   (every feature)
assets/
  publish/                index.html, events.html (site viewers), moved.html
                          (the retired-site page, rendered from a frozen schema)
  fonts/                  Noto Sans Indic ×10 (PDF), OFL.txt
  branding/
test/                     mirrors lib/; architecture/ = fitness functions;
                          fixtures/vault/ = synthetic hermetic vault
                          (passphrase `test-pass-not-secret`)
integration_test/         on-device smoke journeys (vault; catalogue kinds) over
                          shared helpers — run by hand before a release
drift_schemas/            drift schema snapshots, one per schemaVersion
fastlane/                 store listing + per-versionCode changelogs
fdroid/metadata/          verbatim mirror of the fdroiddata recipe
tool/                     release_build.sh (the only way to build a Play .aab)
```

**Navigation:** `main.dart` → `AppGate` (splash → app-lock if enabled →
Library). Drawer: Borrowers vault · Publish · Wishlist · Magazines · Library
network · Library Bookmarks · Share · How Pitak works · Settings/Share Apps.
The Library FAB opens an add sheet with one entry per item kind (ADR 0013 U1).

**Guides (`features/guides/`).** The copy of the six guides lives in
`domain/guide_catalog.dart` as a typed, immutable model (`Guide` → sealed
`GuideSection`), so the domain-purity gate keeps it free of Flutter and
`guide_catalog_test.dart` can pin its invariants (order, 2–7 steps, ≤ 3
"Good to know", lossless `**bold**`/`` `code` `` markup, one "spokes", 1:1
destinations, exact item counts) without pumping a widget. Icons and target pages are mapped in
presentation from `GuideId` / `GuideDestination`; `GuidePage` takes its
opener as a parameter so tests record the destination instead of pushing
provider-backed pages. Copy record: `docs/mockups/how-pitak-works.md`.

**Naming contract:** the Dart package stays `pitaka`; only user-visible text
says "Pitak". Class names, schema constants and the publish commit message are
a contract with the retired Kotlin app.

---

## 4. The crypto chain

```
backup_blob = base64(salt16).base64(iv12).base64(ciphertext48)
  → Argon2id(t=3, m=65536 KiB, p=1, 32 B, v0x13) over passphrase + salt → KEK
  → AES-256-GCM unwrap → 32-byte vault key MK     (GCM tag failure = wrong passphrase)
  → sqlite3_key(db, raw 32 bytes)                 (raw key via C API, never PRAGMA key)
  → borrowers.db  (rusqlite bundled-sqlcipher; opens zetetic 4.5.4 files)
```

- **MK never crosses FFI.** Dart sends passphrase bytes + blob + path; gets
  rows / ids / typed errors back.
- **Change passphrase** = unwrap with old, rewrap under new (same MK — ADR
  0005). The key file is written temp+rename so a crash cannot lose the vault.
- **Vault biometric** = a *second* wrapping of MK under a random secret S,
  stored only as ciphertext under an Android Keystore AES key that requires
  `BIOMETRIC_STRONG` per use and is invalidated on enrolment change. The
  prompt and the cipher are one `BiometricPrompt.CryptoObject`.
- **App-lock biometric** is unrelated: a UI gate that encrypts nothing.
- `unsafe` is denied crate-wide; the only exceptions are the generated FFI
  glue and the three `sqlite3_key` calls in `vault.rs`.

---

## 5. Wire and storage contracts (cross-device; change only with a version bump)

These formats are read by *other phones* and *older builds*. Additive changes
are fine (unknown keys are ignored); anything else needs a schema bump, a
migration test, and a CHANGELOG entry.

### 5.1 `library.json` (published next to `books.json`; schema 1)

```json
{
  "schemaVersion": 1,
  "fingerprint": "<64 lowercase hex>",
  "name": "Kadugodi Community Library",
  "siteUrl": "https://kadugodi-library.github.io/pitak/",
  "updatedAt": 1760000000000,
  "location": { "lat": 12.99, "lng": 77.76, "precision": "approximate" },
  "members":  [ { "fingerprint": "<64 hex>", "siteUrl": "https://…", "name": "…" } ],
  "memberOf": [ "https://hub.github.io/pitak/" ]
}
```

Parser: `LibraryDescriptorCodec` (network domain). Every rule has a test.

- Required: `schemaVersion` (int), `fingerprint` (exactly 64 `[0-9a-f]`),
  `name` (§5.5 name rule), `siteUrl` (passes `BookmarkUrl.normalize`),
  `updatedAt` (int ≥ 0). Any missing/invalid ⇒ whole descriptor **rejected**.
- `schemaVersion > 1` ⇒ `schemaTooNew` (skipped and reported, never crashes).
- `location` optional: `lat` ∈ [−90, 90], `lng` ∈ [−180, 180], `precision`
  ∈ {`approximate`, `exact`}; any part invalid ⇒ `location` **dropped**,
  descriptor otherwise accepted.
- `members` ≤ 200 entries (valid `fingerprint` + `siteUrl`, optional `name`;
  invalid entries dropped; excess truncated). `memberOf` ≤ 20 allow-listed
  URLs, same handling.
- Unknown keys ignored. Body cap 64 KiB. Fetch deadline 15 s.
- When **writing**: keys in the order shown, `members` sorted by `siteUrl`,
  `memberOf` sorted — so the git blob sha is stable and an unchanged file is
  skipped on publish. Encoding **refuses** a descriptor over 64 KiB or over
  the list caps (the publish fails; nothing is uploaded or deleted).

### 5.2 Fingerprint (the published identity)

`LibraryFingerprint.of(libraryId)` = lowercase hex of
`SHA-256(UTF-8("pitak-library-fingerprint-v1:" + libraryId))`.

The raw library ID is **never published** (ADR 0012); it leaves the device
only in person (pairing QR) or in a backup/JSON export the user hands over.
The domain-separation prefix means this hash can never collide with any other
SHA-256 of the ID. Input must pass `LibraryId.normalizeOrNull` first.

### 5.3 Library card QR (dual-purpose URL)

```
<siteUrl>#pitak-card=1&fp=<64 hex>&n=<percent-encoded name>
```

- A phone camera opens the site (the viewer ignores the fragment; browsers
  never send it to the server). Pitak parses the fragment.
- Grammar: `pitak-card=<version>&fp=<fingerprint>&n=<name>`; version must be
  `1`; unknown `&k=v` pairs ignored; payload ≤ 512 bytes. The URL (without
  fragment) is validated by `BookmarkUrl.normalize` **before** the fragment
  is parsed (`LibraryCardPayload.parse`).
- The **pairing** QR `pitaka-lib:<id>` is a different thing and is rejected on
  the hub "Add member" screen with a clear message — a scan can never adopt
  someone's ID by accident.
- QR error-correction level M.
- The `siteUrl` in a card is the journal's **verified** target
  (`publish_host_state`), never a manifest's `repo` and never a configured but
  unproven address: a failed publish must not move the address a printed card
  points at. A legacy install is migrated once by proving the site serves the
  `books.json` sha its manifest recorded.

### 5.4 Application database (Drift; `lib/core/database/app_database.dart`)

The schema history lives in the doc comment on `schemaVersion`. Rules for a
bump (enforced by `test/core/database/migration_test.dart`):

1. Dump a snapshot:
   `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/`
2. Regenerate test helpers:
   `dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/`
3. Add a row to the data matrix in `migration_test.dart`.

An older build opening a newer database refuses with `SchemaTooNewFailure`
(forward-compat, fail closed). Migrations are transactional and idempotent.

**v5** (ADR 0013) adds `books.kind` (`TEXT NOT NULL DEFAULT 'book'`), the
`magazine_issues` detail table (`item_id → books.id ON DELETE CASCADE`, so
`PRAGMA foreign_keys = ON` is set in `beforeOpen` — no earlier table declares
a FK) and the `periodicals` table, and drops + rebuilds the FTS index with
`notes` added to its columns (the one-time rebuild is timed in
`test/core/database/fts_rebuild_timing_test.dart`: 5 000 rows in well under a
second on a laptop, bound 20 s). The issue identity keys (ADR 0013 D6) are two
PARTIAL unique indexes on `magazine_issues`; drift cannot express those, so
they — and the `periodicals` UNIQUE indexes — are raw SQL in
`_createIndexesAndFts`, covered by the migration test's raw-object census.

**v6** (ADR 0013, remediation S1) changes no table shape. It canonicalizes
`periodicals.periodical_uid` and `magazine_issues.periodical_uid` with the
shared surrounding-whitespace-only trim rule. The repair runs in one
transaction, precomputes canonical UIDs/final D6 keys, and refuses collisions
before its first update. A trim-created collision aborts before any write;
the migration never silently merges identities.

**v7** (ADR 0013/0014, remediation S2) also changes no table shape. It defines
`magazine_issues.issue_date` / `bound_until` and
`periodicals.subscription_start` / `subscription_end` as calendar days at
00:00 UTC. Existing integer columns and wire values remain epoch milliseconds;
`addedDate`, `removedAt`, loan dates and `exportedAt` remain instants. The
migration precomputes every conversion and final D6 key before writing and
aborts on an unrepresentable value or conversion-created collision. A legacy
value already at UTC midnight is canonical; otherwise its calendar fields in
the reading device zone are preserved at UTC midnight. This is idempotent, but
a value that already crossed timezones cannot have its original zone
recovered. Same-device base projections and FTS are not mass-rebuilt because
the visible local day is unchanged. `.pitabak` restore and merge/direct
OVERWRITE instead reproject every stored series before commit, including
artifacts read in a different timezone.

### 5.5 `.pitabak` backup archive (manifest schema 1)

A ZIP with Room-shaped SQLite databases (the Kotlin-era format — the writer
still emits that shape so Kotlin archives and Pitak archives are one format),
cover images, and optional entries announced by manifest flags that **default
to false** (the `hasX` forward-compat pattern):

| Entry | Flag | Content |
|-------|------|---------|
| borrowers vault + key blob | `hasVault` | the **only encrypted** part |
| `identity.json` | `hasIdentity` | `{ "libraryId": "<16–64 hex>", "libraryName": "…" }` — **plain** |
| `network.json` | `hasNetwork` | `{ "schemaVersion": 1, "libraries": [ <NetworkLibrary JSON> … ] }` — **plain** |
| `item_kinds.json` | `hasItemKinds` | `{ "schemaVersion": 1, "kinds": [ { "bookUid": "…", "kind": "magazine-issue" } … ] }` — every **non-book** row; a uid listed nowhere is a book (ADR 0014) — **plain** |
| `periodicals.json` | `hasPeriodicals` | `{ "schemaVersion": 1, "periodicals": [ <the Pitaka-JSON periodical object> … ], "issues": [ { "bookUid", "periodicalUid", "volume", "issueNumber", "issueDate", "boundUntil", "label" } … ] }` (ADR 0014) — **plain** |

- **Honest limit:** books, full magazine-series and issue records, other
  items, wishlist, covers, item-kind mappings, identity and network are plain
  inside the archive; only the vault and its wrapped key blob are encrypted.
  Whole-archive encryption is deferred (trigger: a user asks, or a review
  flags it).
- Restore is **all-or-nothing**: everything is written into a new data folder
  and the app switches to it in one step; a failed restore leaves current data
  untouched.
- Compatibility is **one-way**: Pitak restores Kotlin-era archives; the Kotlin
  app is not a restore target. `books.db` holds the base rows of **every**
  item kind in the Room shape, so a build older than ADR 0013 restores
  magazine issues and other items as plain books (it ignores the two
  kind entries above); a flag-less archive restores exactly as before.
- Hostile-input bounds on read: bounded ZIP extraction (ADR 0009); W2
  `item_kinds.json` / `periodicals.json` entries are capped at 4 MiB of UTF-8
  bytes and 100,000 rows in each `kinds`, `periodicals`, or `issues`
  collection (the codec constants are authoritative; equality is accepted).
  `identity.json` has its own 4 KiB cap; `network.json` has its own 4 MiB /
  5000-row caps. Rows are revalidated, with invalid rows dropped and counted.
- The writer mirrors the W2 reader's `maxBytes` / `maxRows`: it encodes and
  checks both W2 entries before creating a scratch directory, SQLite file, or
  archive bytes. An entry exactly at a cap is readable; anything larger fails
  creation with `BackupTooLargeFailure`, never a backup that its own reader
  would silently downgrade. The worker OUTCOME is plain data only (`Uint8List`
  or a `BackupEntryOverflow` code), which the calling isolate maps to `Either`.
- Restore adjustment counters preserve units. `issueEntriesDropped` counts
  decode-time raw-entry drops and decoded entries left unconsulted because
  their UID is absent from `books.db` or belongs to a non-issue row.
  `issuesDetached` independently counts unique rows declared as issues but
  restored as books for lack of a usable detail entry or matching series,
  deduplicated by `bookUid`. Parse drops do not seed the row counter, so one
  malformed entry plus its declared row can yield one of each; the UI reports
  the different units separately and never sums them.

### 5.6 Validation bounds for everything fetched or scanned

| Bound | Value | Enforced in |
|-------|-------|-------------|
| Descriptor body | ≤ 64 KiB, streamed, aborted over cap | `BoundedHttpFetcher` |
| Descriptor fetch deadline | 15 s whole request, abortable | `BoundedHttpFetcher` |
| Published catalogue body | ≤ 64 MiB, streamed, aborted over cap | `BoundedHttpFetcher`, re-checked by `PublishedCatalogueCodec` |
| Published catalogue deadline | 30 s whole request, abortable — including on route close | `BoundedPublishedCatalogueFetcher` |
| Published catalogue origin | the saved site's canonical root (GitHub Pages or Workers); same origin AND same site directory on the initial URL and every redirect hop | `PublishedSiteUrlPolicy` |
| Published catalogue rows | ≤ 100 000 per collection (`books`, `periodicals`), truncated and reported | `PublishedCatalogueCodec` |
| Published catalogue JSON depth | ≤ 32 (string-aware scan, shared with the descriptor) | `JsonNestingDepth` |
| Published cover body | ≤ 8 MiB, streamed, aborted over cap | `BoundedHttpFetcher` |
| Published cover deadline | 15 s whole request, abortable — including on reload/close | `BoundedPublishedCoverFetcher` |
| Published cover origin | same-site: saved origin AND directory; third-party: the cover allow-list; both re-checked on every redirect hop | `PublishedCoverResolver` |
| Published cover cache | ≤ 100 images / 16 MiB, memory only, LRU eviction, cleared on reload and on route close | `PublishedCatalogueCoverController` |
| Redirect hops | ≤ 3, each re-validated | `BoundedHttpFetcher` |
| URL | https, no userinfo, ≤ 2048 chars; host suffix `github.io` / `pages.dev`, OR the strict `<worker>.<account-subdomain>.workers.dev` root form (exactly two leading labels, no other path) | `BookmarkUrl`, `WorkersDevUrl` |
| Name | 1–80 chars after trim; reject code units < 0x20, 0x7F, U+202A–U+202E, U+2066–U+2069 | `NetworkName` |
| Fingerprint | exactly 64 `[0-9a-f]` | `LibraryFingerprint.isValid` |
| lat / lng | finite, [−90, 90] / [−180, 180] | `GeoPoint.tryCreate` |
| `members` / `memberOf` per file | ≤ 200 / ≤ 20 (truncate, report) | `LibraryDescriptorCodec` |
| Rows per Refresh run | ≤ 500 (stop discovering, report); discovery ≤ 2 hops | `NetworkDiscoveryPlan` |
| Concurrency | 4 in-flight fetches | `RefreshNetworkUseCase` |
| QR payload | ≤ 512 bytes; URL validated before fragment | `LibraryCardPayload` |
| Images | reject > 8192 px / > 40 Mpx from the header; frame 0 only; 400×600 q80 JPEG out | `ImageDownscaler` |
| Publish target URL | derived from the sealed target's identity parts, cross-checked against the stored one; never accepted as an arbitrary `{host, url}` pair | `PublishTarget`, `PrefsPublishHostStore` |
| Publish read-back body | marker ≤ 4 KiB; `library.json` / `events.json` ≤ 64 KiB; catalogue by its own rule; exact expected origin and site directory, **no** redirect followed, one `?rb=` buster allowed | `BoundedPublishedSiteVerifier`, `PublishedSiteUrlPolicy.readBackUrl` |
| Cloudflare API body | ≤ 1 MiB streamed, cancelled over cap; string-aware depth ≤ 16 **before** `jsonDecode`; endpoint-specific string/list/map bounds; whitelisted fields only | `CloudflareJson`, `HttpCloudflareApi` |
| Cloudflare API deadline | 30 s abortable per call; 60 s per upload batch; a redirect is refused | `CloudflareHttpTransport` |
| Cloudflare retries | ≤ 3 total attempts; one `retry-after` honoured up to 60 s; uncertain create/deploy is re-read, never blindly repeated | `HttpCloudflareAccountApi`, `HttpCloudflareDeployApi` |
| Cloudflare accounts | ≤ 4 pages of 50, then the explicit manual Account ID path (never a partial picker) | `HttpCloudflareAccountApi` |
| Cloudflare publish size | ≤ 20 000 files per deploy, ≤ 25 MiB per file; aggregate encoded bytes bounded, one bucket in flight | `CloudflareLimits`, `CloudflareAssetUploader` |

Refusal reasons are coarse enums that never carry URLs or exception text
(a URL can contain the user's API key).

**The native catalogue viewer (ADR 0015)** reads a saved library's
`books.json` only on an explicit row tap, through a viewer-owned HTTP client
with a 66 MiB outer transport guard. The guard is deliberately 2 MiB above the
adapter's 64 MiB cap so the adapter — not the generic client — reports
`tooLarge`; no catalogue above 64 MiB is accepted. The initial URL and every
redirect must stay on the saved site's origin *and* inside its directory
(`PublishedSiteUrlPolicy`), so an allow-listed Pages host cannot redirect a
saved library into another library. The request carries the fixed app
User-Agent plus `Cache-Control: no-cache`, never cookies or auth; decoding and
querying run off the UI isolate; the catalogue and its decoded object graph
live only in auto-dispose providers and disappear when the route closes.

**Covers in that viewer (S5)** are a second, separately gated pipeline. They
are never written to disk or Drift and never enter the local `ItemCover`
materialisation path. Both origin classes — the library's own relative
`covers/…` files and the allow-listed third-party hosts — require
`AppSettings.loadRemoteCovers == true`; unknown/failed settings mean no
request. A same-site cover stays inside the saved site's origin and directory
on every hop; a third-party cover re-checks the cover allow-list on every hop
(preserving Open Library's Internet Archive redirects). Bodies are capped at
8 MiB / 15 s, decoded in a worker isolate with the existing header/pixel
guards and FRAME 0 only, and only the resulting 400×600 JPEG reaches the
image widget: no `Image.network`, no raw fallback, no local persistence.

### 5.7 Pitaka-JSON and `books.json` carry the item kind (ADR 0014)

- **Display and interchange reads are deliberately different.** The Library
  uses paged fail-soft mapping; the vault and cover janitor use fail-soft
  `getAll()`. Export, backup, publish and merge require
  `getAllForInterchange()`: an unknown stored kind or a known issue without its
  detail row returns a typed failure instead of becoming a serialized book.
  Write-back of such a detail-less issue also fails before mutation, preserving
  the raw evidence.
- **Pitaka-JSON** (export / import / merge): `schemaVersion` 3 → **4**. Every
  row in `books[]` gains `kind` (`book` | `magazine-issue` | `other`; absent
  ⇒ `book`); an issue row carries a nested `issue{}`; the document gains a
  top-level `periodicals[]`. The keys `books` and `bookUid` keep their names.
  Older builds refuse a v4 file with the existing "update the app" message
  (a silent import would drop kinds, P1). The v3 shape remains accepted and
  absent kind defaults to book, subject to the cross-kind refusal below. An
  unknown `kind` is skipped and reported, never imported as a book. CSV export
  gains `Kind`, `Series`, `Volume`, `Issue`, `Issue date`, `Bound until` and
  `Issue label`. Issue and subscription dates on these existing integer keys
  are UTC-midnight calendar days (§5.4); instant fields keep their old meaning.
- **Plain JSON import reconciles before writing issues.** One transaction
  builds an incoming-canonical-UID → stored-series map: earlier in-file claims
  win; same UID merges in place; the same canonical ISSN under another UID
  maps to the stored series; a new series uses its actual returned row,
  retaining an incoming UID or using a repository-minted one when absent.
  Covers use `resolveIncomingCover`; omitted added metadata does not erase
  local values. Issues are re-anchored and revalidated; every updated series is
  reprojected LAST. A same-UID cross-kind update refuses
  the whole import with `ValidationFailure`. D6 duplicates between different
  item UIDs skip and count, including earlier in-file claims; a repeated
  same-UID, same-kind row updates instead and releases its previous claim.
  Date-only issues stay additive. Trim-created UID ambiguity is file-level
  fatal: plain import checks inside its already-open transaction before
  catalogue reads/writes, while merge checks before namespace/planning/
  repository IO.
- **Merge keeps distinct series distinct.** UID and canonical-ISSN identity
  precede exact-title fallback, and that fallback is suppressed when both
  sides have valid, different ISSNs. Re-anchoring and final reprojection use
  the same issue relationships as import; overwrite revalidates and reprojects
  the replacement before commit.
- **`books.json`** (published) stays schema **1**. Older viewers ignore
  additive keys, and null optional values are omitted. The exact public key
  sets are:
  - book: `title`, `kind`, optional `titleTransliteration`, `author`, `isbn`,
    `publisher`, `publishedYear`, `genre`, `language`, `coverUrl`, `ageGroup`
    and coarse `availability`;
  - issue: that same item set plus `issue{periodicalUid, volume, issueNumber,
    issueDate, boundUntil, label}` (the nested nulls are omitted too);
  - other: only `title`, `kind`, resolved `coverUrl`, `language` and `ageGroup`
    — never availability, issue data, transliteration, notes, source, or any
    book-specific field;
  - top-level `periodicals[]`: `periodicalUid`, `title`, optional
    `titleTransliteration`, `issn`, `publisher`, `language`, `coverUrl`,
    `frequency` and `ageGroup`. Subscription windows, notes, location,
    source, added metadata, removal metadata and per-device ids stay private.
- **Publish validates linkage before producing artifacts.** One canonical
  resolver refuses missing, blank, noncanonical or duplicate series UIDs and
  noncanonical/unresolved live-issue links before cover IO, viewer/JSON
  construction, manifest save or commit. Removed series have no top-level
  entry but remain available to their live issues for cover fallback. Cover
  paths use SHA-256 of `salt || UTF-8(key)`, truncated to its first 16
  lowercase hexadecimal characters; periodical keys are domain-separated as
  `periodical:<uid>`, ASCII digests remain compatible, and non-ASCII UIDs are
  valid. The v7 viewer adds the kind facet and groups issues under their
  series when a public series entry is present.

### 5.8 Publish host, target and manifest records (ADR 0017)

Publishing is one operation bound to **one sealed target**. `PublishTarget` is
sealed into `GitHubPublishTarget` (owner/repo + expected branch) and
`CloudflarePublishTarget` (account id + Worker name + account subdomain); the
site URL is *derived* from those identity parts, so no code path can accept an
arbitrary host-plus-URL pair. `library.json.siteUrl` always comes from the
target passed to the current operation — that is what lets a move publish the
**new** address while the old site is still the active one.

| Record | Location | Secret? | Meaning |
|---|---|---|---|
| `publish_host_state` | one preferences key | no | Active host, the single `verifiedTarget`, and any pending move |
| `publish_manifest.json` | app documents | no | GitHub schema 2: which app-owned files this phone owns |
| `cloudflare_publish_manifest.json` | app documents | no | Cloudflare schema 2: the complete Worker asset set it owns |
| `cf_connection` | hardened secure storage | **whole record** | Token plus optional account/Worker/address |
| Artifact spool | temporary files | no | Public bytes while one publish runs; deleted afterwards |

- **The journal, not the manifest, is the share truth.** `publishedSiteUrlProvider`
  reads only `verifiedTarget`, and that pointer is written *after* read-back
  proves the site. A `deployed` state, a failed publish or an unverified target
  change never erases it, and a first deployment with no pointer is not
  shareable as live. Pending moves keep the old target selected until
  retirement verifies. Reads distinguish "absent" from "unreadable": corrupt
  pending history fails closed instead of quietly starting over. A legacy
  install is migrated **once**, by proving the site serves the `books.json`
  content sha its old manifest recorded.
- **A manifest is reconciliation state, not a cache.** It decides which public
  files survive the next publish, so its uncertainty has a defined safe
  outcome. A record that does not describe the exact repo+branch, or the exact
  Cloudflare account/Worker/address, claims **nothing** — its file map could
  otherwise authorise deleting another site's files. Shas always come from the
  remote read (GitHub tree) or the local content; tree or Worker paths this
  phone did not write are never adopted, so a later drop cannot delete a
  human's `README.md`.
- **`state` is truthful, in order.** `deployed` means the host accepted the
  write but read-back has not completed; `live` means required read-back
  succeeded for that record's target; `retired` means the site is positively
  identifiable as retired (a moved page, or the retired Worker set below).
- **`hashScheme` gates hashes, not paths.** A different Cloudflare asset-hash
  scheme means "re-hash the bytes", never "forget which files we wrote".
- **The Cloudflare marker is the freshness anchor.** Every deploy writes
  `pitak-publish.json` (`schema`, 128-bit `publishId`, diagnostic
  `publishedAt`, `state`: `live` / `verification` / `retired`). It is public,
  small, and contains no account id, token or deployment id. A matching id is
  *positive evidence*; a 404 is never retirement, and a malformed marker is
  never a fresh site. It detects **observed** staleness — it is not
  compare-and-swap, which is why one publisher per Worker is an operating
  requirement.
- **Snapshots are complete or explicitly incremental.** A move, a
  whole-Worker replacement and a retirement require a strict complete snapshot
  (every read succeeds, every referenced poster/cover resolves to bytes,
  every destination file is accounted for). A missing cover or poster is a
  typed failure, never a silent omission. Replacement is confirmed in two
  phases against a canonical digest that excludes operation-generated ids and
  timestamps (`exportedAt`, `publishId`), so ordinary edits re-prompt but a
  re-run of the same data does not.
- **A retired Cloudflare Worker holds exactly** `index.html`, `404.html` and
  the retired `pitak-publish.json`. A live site serves `Cache-Control:
  no-cache` and `Access-Control-Allow-Origin: *` (deliberate GitHub CORS
  parity) and a real 404 for a missing file. The retired site's `_headers`
  adds the full CSP (`default-src 'none'; style-src 'unsafe-inline';
  base-uri 'none'; form-action 'none'; frame-ancestors 'none'`),
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` and
  `Cache-Control: no-cache`. GitHub cannot send response headers through this
  publishing path, so its moved page keeps only the directives a `<meta>` tag
  enforces — that gap is documented and smoke-tested, never disguised.
- **GitHub retirement** writes the moved `index.html`/`404.html` and deletes
  only exact app-owned paths from the validated manifest, in the same
  expected-head commit; unrelated files always survive.

---

## 6. Standing design decisions (short form; details in `docs/adr/`)

- **Location sharing** is one switch with one meaning — `off / approximate
  (~1 km) / exact`, default off — governing both the published page pin and
  `library.json`. Existing GPS publishers read as `exact` once (first-read rule).
- **Identity conflicts** (a fetched fingerprint already belongs to another
  saved row) are marked with a badge, never auto-merged.
- **A possible library move is an offer, not a decision** (ADR 0017, C10/R17):
  when the SAME fingerprint a saved row already holds as a fact is published by
  a descriptor at a DIFFERENT canonical address that the user added by URL or
  scanned from a card in person, the refresh (and the card scan) offers both
  addresses neutrally instead of flagging a conflict. The offer is ephemeral —
  nothing is written until the user chooses. Accepting is ONE transactional
  merge/delete-plus-repoint that keeps the canonical row's id, local order and
  consent/membership decisions, applies the fresh remote fields, deletes the
  duplicate and preserves both UNIQUE(site_url) and UNIQUE(fingerprint).
  Declining writes nothing. Discovered/hostile rows keep the conflict badge,
  and reachability alone never selects an address.
- **"The URL is the identity"** for saved libraries, hardened by the in-person
  card scan and the fingerprint check on fetch. Signed descriptors deferred.
- **Library list reads are paged in SQL** (`CatalogueItemRepository.page`,
  60 rows, OFFSET/LIMIT); `CatalogueItemSorter` (domain) is the oracle the SQL
  is tested against.
  Language facet matches the stored string exactly (SQLite `lower()` is
  ASCII-only).
- **Merge** is add-only, removal-as-conflict, identity order uid → ISBN →
  fuzzy, single-transaction apply; the plan runs on a worker isolate.
- **Periodical soft links have one canonical identity.** External UIDs may be
  non-ASCII; only surrounding whitespace is trimmed. Domain gates, codecs, D6
  lookups, repositories and companions share that rule, and collisions fail
  closed rather than silently combining series.
- **Issue writes are atomic.** Stored-row lookup, series lookup/projection,
  validation, D6 pre-check and the base/detail write run in one item
  transaction. Series update/reprojection uses the same shared transaction;
  periodical hard delete repeats its issue-count guard inside the repository
  transaction. New issues under a removed series are refused; historical issue
  edits remain possible, and a removed-series scan routes to detail/restore.
- **Calendar days are not instants.** Issue/subscription dates use the pure
  `CalendarDate` rule and UTC calendar fields for arithmetic and display;
  weekly cadence counts days, monthly cadence clamps calendar months, and a
  subscription remains `expiringSoon` throughout its stated local end date.
  `addedDate`, removal/loan timestamps and `exportedAt` remain instants.
- **Cover display does not transfer cover ownership.** A structural
  `CoverOwner` is either a catalogue item or a periodical, and downloads dedup
  by `(owner, URL)`. Materialization re-reads the owner immediately before the
  write and deletes a newly stored file on a mismatch, read failure, or failed
  update instead of overwriting newer data. Forms track deliberate cover edits
  and pending work so Save cannot resurrect a stale cover.
- **Magazine summaries react to the shared library mutation signal.** Import,
  merge, restore and issue hard-delete refresh a live Magazines list without a
  route rebuild; the minute tick exists only for time-derived subscription
  badges. Filtered-empty and genuinely empty libraries are different states,
  and generic item flows use kind-neutral Item wording.
- **PDF text is rendered as shaped images** (correct Devanagari conjuncts;
  consequence: not selectable). Cancel discards — a partial catalogue must
  never pass for a complete one.
- **Publish is one operation, one host, one target** (ADR 0017). Either a
  single atomic git-data commit (GitHub Pages) or a complete assets-only
  deploy of a Pitak-dedicated Worker, both fed by the SAME section builders so
  the two hosts cannot publish different bytes. PII redaction and the
  https-only cover allow-list mirroring the viewer CSP apply to both. The old
  host becomes a moved page only after the new site is verified and the old
  one is verifiably retired, and other phones never follow a move on their
  own.
- **Lookup order:** Open Library → Google Books → in-memory cache; ISBN-10↔13
  retry on double not-found.
- **Catalogue-item hard delete stays vault-gated**; periodical-title hard
  delete uses the issue-count guard instead. Lending on removed items is
  refused.
- **One base row per catalogue item of any kind** (`books` table,
  `CatalogueItem`, `kind` column + sealed `ItemDetails`); kind-specific data
  in a per-kind detail table; **the base row is the lendable unit** and **a
  new kind never touches the vault** (`loans.book_id`). Kinds are
  app-defined. Periodicals are a specific concept, not generic collections
  (ADR 0013; interchange/backup shapes in ADR 0014).
