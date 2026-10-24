# Pitak — Architecture

> **What this file is:** the *shape* of the app — what it is, what it promises,
> how the code is laid out, and the data formats that must not change by
> accident. The *rules* for writing code live in `AGENTS.md` (which wins over
> this file). Individual decisions live in `docs/adr/`. Release mechanics live
> in `docs/RELEASING.md`.
>
> Every fact here was checked against the code on 2026-10-19. When the code
> changes, change this file in the same PR.

---

## 1. What Pitak is

A **privacy-first, offline personal library catalogue** for Android, ported
from a retired Kotlin app with **zero data loss** as the hard guarantee.

- Books, wishlist and the library network live in **Drift/SQLite**.
- Borrowers and loans live in an **AES-256-GCM encrypted vault** whose key
  exists only inside a **Rust core** (`rust/`, crate `pitak_crypto`) and
  never crosses the FFI boundary.
- Import/export: JSON, CSV (incl. Goodreads), PDF (Indic scripts via shaped
  images). `.pitabak` backups restore both Pitak and Kotlin-era archives.
- Opt-in publish of a read-only site to GitHub Pages; opt-in **library
  network** (saved libraries, hub/member cards, consent-gated OSM map).
- Shipped on **F-Droid** (`dev.khoj.pitaka.fdroid`) and **Google Play**
  (`dev.khoj.pitaka`) from the same tag. **Android is the only target.**
- No telemetry, no crash reporting — by design. The lead developer is a
  beginner (AGENTS §0): one blessed way, no magic, explained decisions.

Permissions: `CAMERA`, `INTERNET`, `USE_BIOMETRIC`. `allowBackup=false` +
`data_extraction_rules.xml` keep everything out of Android Auto Backup / D2D.
minSdk 23 (the `flutter_zxing` floor).

Network egress, **all user-initiated, never in the background**:
openlibrary.org and Google Books (ISBN lookup); api.github.com (publish,
device-flow OAuth); remote covers (opt-in, host allow-listed); `library.json`
fetches from saved libraries (Refresh only); tile.openstreetmap.org (map,
remembered opt-in, only while the map is open).

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
  rotation** (ADR 0005); **`.pitabak` is not fully encrypted** (§5.2).

---

## 2. Layering

Clean Architecture + DDD. Dependencies point **inward only**:

```
presentation  ->  application  ->  domain  <-  infrastructure
   (UI/State)     (use cases)     (pure)      (impl/IO/db)
```

| Layer | May depend on | Must not contain |
|-------|---------------|------------------|
| `domain` | nothing (pure Dart; allow-listed packages only) | Flutter, IO, JSON codecs, HTTP, DB, Riverpod |
| `application` | `domain` | widgets, `BuildContext`, concrete repositories, platform IO |
| `infrastructure` | `domain` (implements its ports) | UI, business rules |
| `presentation` | `application`, `domain` | direct DB/HTTP, business logic, `infrastructure` imports |

- **State / DI:** Riverpod with codegen (`@riverpod`). The composition root is
  `lib/core/di/` (`providers.dart` + `src/<feature>_providers.dart`).
- **Errors:** `fpdart` `Either<Failure, T>`; sealed `Failure` in
  `lib/core/error/failure.dart`. No exceptions across layers.
- **Secrets:** `SecretBytes` in Dart (wipeable, redacted `toString`);
  `Zeroizing<>` + `subtle` in Rust. Honest exceptions: the GitHub token and the
  ISBN-lookup key transit as `String` because their APIs are `String`-typed
  (ADR 0007).

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
    crypto/               secret_bytes.dart, secure_passphrase_field.dart (append-only)
    database/             app_database.dart (Drift; schema history in its doc comment)
    di/                   providers.dart + src/<feature>_providers.dart
    error/                sealed Failure hierarchy
    images/               image_downscaler.dart — single choke point for every
                          decoded image (size caps from the header, EXIF/GPS stripped,
                          frame 0 only, runs in Isolate.run)
    network/              bounded_http_fetcher.dart (size cap, deadline, ≤3 re-validated
                          redirects), app_user_agent.dart, osm_tiles.dart
    platform/             screen_security.dart (FLAG_SECURE), app_log.dart
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
    publish/              GitHub Pages: device-flow auth + git data API; PII redaction
    events/               event posters for the published site
    network/              library network (ADR 0012): network_libraries table,
                          library.json codec + bounded fetcher, card QR, bounded
                          Refresh/discovery, membership, consent-gated OSM map
    backup/               .pitabak writer (worker isolate) + all-or-nothing restore
    import_export/        JSON/CSV/PDF export, Goodreads import, merge UI
    settings/             Appearance · Data · Security (SettingsPage.initialTab)
    guides/               in-app "How Pitak works" guides (pure content model +
                          pages; deep-links only — no state, no IO)
  features/<f>/{domain,application,infrastructure,presentation}   (every feature)
assets/
  publish/                index.html, events.html (site viewers)
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
network · Share · How Pitak works · Settings. The Library FAB opens an add
sheet with one entry per item kind (ADR 0013 U1).

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

- **Honest limit:** books, wishlist, covers, identity and network are plain
  inside the archive; only the vault is encrypted. Whole-archive encryption is
  deferred (trigger: a user asks, or a review flags it).
- Restore is **all-or-nothing**: everything is written into a new data folder
  and the app switches to it in one step; a failed restore leaves current data
  untouched.
- Compatibility is **one-way**: Pitak restores Kotlin-era archives; the Kotlin
  app is not a restore target. `books.db` holds the base rows of **every**
  item kind in the Room shape, so a build older than ADR 0013 restores
  magazine issues and other items as plain books (it ignores the two
  kind entries above); a flag-less archive restores exactly as before.
- Hostile-input bounds on read: bounded ZIP extraction (ADR 0009), 4 MiB per
  JSON entry, 5000 network rows, every row re-validated, invalid rows dropped
  and counted in the restore summary.

### 5.6 Validation bounds for everything fetched or scanned

| Bound | Value | Enforced in |
|-------|-------|-------------|
| Descriptor body | ≤ 64 KiB, streamed, aborted over cap | `BoundedHttpFetcher` |
| Descriptor fetch deadline | 15 s whole request, abortable | `BoundedHttpFetcher` |
| Redirect hops | ≤ 3, each re-validated | `BoundedHttpFetcher` |
| URL | https, no userinfo, host suffix `github.io` / `pages.dev`, ≤ 2048 chars | `BookmarkUrl` |
| Name | 1–80 chars after trim; reject code units < 0x20, 0x7F, U+202A–U+202E, U+2066–U+2069 | `NetworkName` |
| Fingerprint | exactly 64 `[0-9a-f]` | `LibraryFingerprint.isValid` |
| lat / lng | finite, [−90, 90] / [−180, 180] | `GeoPoint.tryCreate` |
| `members` / `memberOf` per file | ≤ 200 / ≤ 20 (truncate, report) | `LibraryDescriptorCodec` |
| Rows per Refresh run | ≤ 500 (stop discovering, report); discovery ≤ 2 hops | `NetworkDiscoveryPlan` |
| Concurrency | 4 in-flight fetches | `RefreshNetworkUseCase` |
| QR payload | ≤ 512 bytes; URL validated before fragment | `LibraryCardPayload` |
| Images | reject > 8192 px / > 40 Mpx from the header; frame 0 only; 400×600 q80 JPEG out | `ImageDownscaler` |

Refusal reasons are coarse enums that never carry URLs or exception text
(a URL can contain the user's API key).

### 5.7 Pitaka-JSON and `books.json` carry the item kind (ADR 0014)

- **Pitaka-JSON** (export / import / merge): `schemaVersion` 3 → **4**
  (shipped in the magazines run, S18). Every row in `books[]` gains `kind`
  (`book` | `magazine-issue` | `other`; absent ⇒ `book`); an issue row
  carries a nested `issue{}`; the document gains a top-level
  `periodicals[]`. The keys `books` and `bookUid` keep their names. Older
  builds refuse a v4 file with the existing "update the app" message (a
  silent import would drop kinds, P1). An unknown `kind` is skipped and
  reported, never imported as a book. CSV export gains `Kind`, `Series`,
  `Volume`, `Issue`, `Issue date`, `Bound until`, `Issue label`.
- **`books.json`** (published): stays schema **1** — additive `kind` per
  entry (+ `issue{}`), top-level `periodicals[]` with public fields only
  (shipped in the magazines run, S20). Older viewers ignore the new keys.
  The v7 viewer adds the kind facet and groups issues under their series.

---

## 6. Standing design decisions (short form; details in `docs/adr/`)

- **Location sharing** is one switch with one meaning — `off / approximate
  (~1 km) / exact`, default off — governing both the published page pin and
  `library.json`. Existing GPS publishers read as `exact` once (first-read rule).
- **Identity conflicts** (a fetched fingerprint already belongs to another
  saved row) are marked with a badge, never auto-merged.
- **"The URL is the identity"** for saved libraries, hardened by the in-person
  card scan and the fingerprint check on fetch. Signed descriptors deferred.
- **Library list reads are paged in SQL** (`CatalogueItemRepository.page`,
  60 rows, OFFSET/LIMIT); `CatalogueItemSorter` (domain) is the oracle the SQL
  is tested against.
  Language facet matches the stored string exactly (SQLite `lower()` is
  ASCII-only).
- **Merge** is add-only, removal-as-conflict, identity order uid → ISBN →
  fuzzy, single-transaction apply; the plan runs on a worker isolate.
- **PDF text is rendered as shaped images** (correct Devanagari conjuncts;
  consequence: not selectable). Cancel discards — a partial catalogue must
  never pass for a complete one.
- **Publish** is one atomic git-data commit with PII redaction and an
  https-only cover allow-list mirroring the viewer CSP.
- **Lookup order:** Open Library → Google Books → in-memory cache; ISBN-10↔13
  retry on double not-found.
- **Hard delete stays vault-gated**; lending on removed books is refused.
- **One base row per catalogue item of any kind** (`books` table,
  `CatalogueItem`, `kind` column + sealed `ItemDetails`); kind-specific data
  in a per-kind detail table; **the base row is the lendable unit** and **a
  new kind never touches the vault** (`loans.book_id`). Kinds are
  app-defined. Periodicals are a specific concept, not generic collections
  (ADR 0013; interchange/backup shapes in ADR 0014).
