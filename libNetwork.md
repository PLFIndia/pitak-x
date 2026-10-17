# libNetwork.md — Library Network map (bookmarks → network, hub cards, OSM map)

> **Origin:** design discussion 2026-10-17 (user + agent). Every "verified"
> fact below was read from source on that date; where something is a choice
> it is numbered in §2 so it can be challenged in one place.
>
> **Status:** SPECIFIED, not started. Implement in the slice order of §7; each
> slice is independently shippable and ends "✅ green" = one or more commits.
>
> **Governance:** `AGENTS.md` wins over this file. Every slice must pass the
> Agent Decision Checklist (AGENTS §13) before it is "done". If this file and
> `AGENTS.md` disagree, STOP and surface the conflict — do not guess.
>
> **For the implementing agent — read before touching code:**
> - Never invent an API. Every `flutter_map` / `latlong2` symbol named here is
>   *expected*; confirm it against the installed package source
>   (`~/.pub-cache/hosted/pub.dev/flutter_map-<ver>/lib/`) before use (AGENTS §2.1).
> - The repo's lead developer is a beginner (AGENTS §0): explain non-obvious
>   choices in one-line comments, in plain words.
> - Use the exact file paths, class names and provider names in §5. They were
>   chosen to match existing conventions (one blessed way).
> - Run the gate commands in §11 after every slice. No slice merges red.

---

## 0. How to read this file

- §1 — what the feature is, in plain English (what libraries and users do).
- §2 — decisions D1–D14 (final unless the user re-opens one).
- §3 — wire contracts: `library.json`, the card QR, backup entries. These are
  cross-device/cross-version contracts — change them only with a version bump.
- §4 — verified facts about the codebase this builds on (file:line).
- §5 — target architecture: every new/changed file, port, provider, table.
- §6 — threat model and the validation bounds table.
- §7 — slices S1–S6: steps, tests, acceptance, explicitly-NOT-doing.
- §8 — test plan. §9 — docs to update. §10 — deferred with triggers.
- §11 — commands and the per-slice checklist.

Sizes: **S** ≈ half a day, **M** ≈ 1–2 days, **L** ≈ 3+ days.

---

## 1. The feature in plain English

**What it is.** A "Library network" screen that shows the other Pitak
libraries you care about on a map (and in a distance-sorted list). Each pin
is a library that *chose* to share its location. Tapping a pin opens that
library's published catalogue site or hands off to your maps app for
directions.

**No server.** Each library's location lives in a tiny public file
(`library.json`) on that library's *own* published site — the same GitHub
Pages (later: Cloudflare Pages) site Pitak already publishes `books.json` to.
Your phone reads those files directly, one per library, when you tap
Refresh. Nothing runs in the middle.

**Hub and members.** A hub library (any library — there is no "hub" role in
code) adds members **only** by scanning a member's Pitak library card QR in
person. The hub then publishes its member list inside its own
`library.json`. A member bookmarks the hub once and, on Refresh, sees the
whole network. A stranger who bookmarks just one member also sees the whole
network, because each member's file points back at its hub.

**What a library does.**
1. Settings → Publish → Basic info: enter latitude/longitude (field already
   exists), set **"Share my location on the network map"** to *approximate*
   (≈ 1 km) or *exact*. Default is off.
2. Publish as usual. `library.json` now rides along in the same commit.
3. Bookmark the hub's site address once. Open Library network → Refresh.
4. (Hub) Add member → scan their card → publish. (Member) when the app
   notices the hub lists you, confirm "show that I'm a member of X" → publish.

**What the app asks of users.**
- Explicit consent before location is public (switch + precision choice, with
  the same "shown publicly" caution the contact fields have).
- A tap to refresh; a tap to open the map. Nothing in the background.
- One-time consent that map imagery comes from OpenStreetMap (they see your
  IP and the viewed area). The list view works without it.
- No new Android permissions. Coordinates are typed, not captured.
- Bookmarks move into the network screen automatically (one-time migration).

---

## 2. Decisions (D1–D14)

| # | Decision | Why / consequence |
|---|----------|-------------------|
| D1 | Map = **your saved libraries** (bookmarks + cards + discovered), pins only for those with a published, opted-in location. | No hub needed to get value. |
| D2 | Hub "Add member" accepts **only** the library card QR (§3.2). The pairing QR `pitaka-lib:<id>` is **rejected** on that screen with a clear message. | A scan can never adopt someone's ID by accident. |
| D3 | The raw library ID is **never published**. Sites and cards carry a **fingerprint** = SHA-256 (§3.3). | Keeps today's property: the ID leaves the device only in person / in a JSON export you hand over. |
| D4 | Library ID, name and the network table go into `.pitabak` **in the clear** (new entries `identity.json`, `network.json`, manifest flags). Whole-archive encryption is a separate future feature (§10). | Consistent with the archive's existing honest limit (README › Backup) and with the JSON export, which already carries the ID in clear. |
| D5 | In-app map via **`flutter_map`** + OSM raster tiles; **list view** (distance-sorted) is the tile-free fallback. No Google Maps SDK (F-Droid purity, P3). | `flutter_map` 8.3.2 is pure Dart (verified: pub.dev deps are all Dart packages, no `android/`). |
| D6 | **Manual coordinates only** in v1 (reuse `publishContactGps`). No location permission, no native code. | In-app GPS capture needs flavor-split Kotlin (ADR 0008 pattern) — deferred (§10). |
| D7 | Location sharing setting `LocationSharing { off, approximate, exact }`, default **off**; `approximate` = round to 2 decimals (~1.1 km). It governs **both** `library.json` and the existing GPS pin on `index.html`. | One switch, one meaning. Existing users with a GPS value get `exact` on first read (behaviour-preserving, §5.4). |
| D8 | The **bookmarks feature is replaced** by the network feature (`lib/features/bookmarks/` deleted; one-time prefs → Drift migration). ADR 0012. | A bookmark is a network row without a fingerprint/location. Two lists would be two truths. |
| D9 | **Card QR encoding = the site URL with a fragment** (§3.2), not a new `pitaka-card:` scheme. | One QR works for a phone camera (opens the site; the viewer ignores the fragment — verified: `assets/publish/index.html` never reads `location.hash`) **and** for Pitak (parses the fragment). The visiting-card PNG keeps a single QR. |
| D10 | Discovery is **bounded, two expansions max** (§5.6): `memberOf` links are followed from any row; `members` lists are expanded only for seeds and for hubs reached via `memberOf`. Hard caps: 500 rows per run, 200 members per file, 20 `memberOf` per file. | Deterministic, predictable traffic, no crawling the world. |
| D11 | Refresh and tiles are **user-initiated only**. No background work, ever. OSM tile consent is a remembered opt-in (`networkMapTilesConsent`, default off) — same shape as `loadRemoteCovers`. | PRIVACY.md promise: "no background or silent network connections". |
| D12 | Identity conflicts (a fetched fingerprint already belongs to another saved row) are **not auto-merged**: the row is marked `identityConflict` and shown with a badge. | Fail closed and visible (AGENTS §2.7). Merge action deferred (§10). |
| D13 | Trust model stays "**the URL is the identity**" (today's bookmarks), hardened by the in-person scan for membership and the fingerprint check on fetch. Signed descriptors deferred (§10). | Right-sized; no key management for v1. |
| D14 | The shared bounded fetcher is **extracted** from `BoundedCoverFetcher` into `lib/core/network/bounded_http_fetcher.dart`; the cover fetcher becomes an adapter over it. Existing cover-fetcher tests must pass unchanged. | AGENTS §0 "fix the foundation": 150 lines of security code are not copy-pasted. |

---

## 3. Wire contracts (cross-device; versioned)

### 3.1 `library.json` (published next to `books.json`, schema 1)

```json
{
  "schemaVersion": 1,
  "fingerprint": "3b7c…64 lowercase hex…",
  "name": "Kadugodi Community Library",
  "siteUrl": "https://kadugodi-library.github.io/pitak/",
  "updatedAt": 1760000000000,
  "location": { "lat": 12.99, "lng": 77.76, "precision": "approximate" },
  "members": [
    { "fingerprint": "…64 hex…", "siteUrl": "https://…github.io/…/", "name": "…" }
  ],
  "memberOf": [ "https://hub.github.io/pitak/" ]
}
```

Rules (parser = `LibraryDescriptorCodec`, §5.2; every rule has a test):
- Required: `schemaVersion` (int), `fingerprint` (exactly 64 `[0-9a-f]`),
  `name` (trimmed, 1–80 chars, no control / bidi-override chars),
  `siteUrl` (passes `BookmarkUrl.normalize`), `updatedAt` (int ≥ 0).
  Any required field missing/invalid ⇒ the whole descriptor is **rejected**
  (`invalid`).
- `schemaVersion > 1` ⇒ `schemaTooNew` (skipped, reported, never crashes).
- Optional `location`: `lat` ∈ [−90, 90], `lng` ∈ [−180, 180], `precision`
  ∈ {`approximate`, `exact`}; any part invalid ⇒ `location` **dropped**
  (library appears without a pin), descriptor otherwise accepted.
- Optional `members`: array ≤ 200; each entry needs valid `fingerprint` +
  `siteUrl` (+ optional `name`, same rule as above); an invalid entry is
  dropped; more than 200 ⇒ the list is truncated to the first 200.
- Optional `memberOf`: array ≤ 20 of allow-listed URLs; invalid entries
  dropped; truncated at 20.
- Unknown keys ignored (additive evolution without a bump).
- Body cap **64 KiB** (200 members × ~250 B ≈ 50 KiB). Fetch deadline 15 s.
- Output ordering when *writing*: keys exactly in the order shown; `members`
  sorted by `siteUrl`; `memberOf` sorted — so the git blob sha is stable and
  the incremental publish skips an unchanged file.

### 3.2 Library card QR (dual-purpose URL)

```
<siteUrl>#pitak-card=1&fp=<64 hex>&n=<percent-encoded name>
```

Example: `https://kadugodi-library.github.io/pitak/#pitak-card=1&fp=3b7c…&n=Kadugodi%20Community%20Library`

- `siteUrl` is the library's published root URL (allow-listed host, https,
  no userinfo) — the same string `publishedSiteUrlProvider` returns.
- Fragment grammar: `pitak-card=<version>&fp=<fingerprint>&n=<name>`;
  version must be `1`; `fp` exactly 64 lowercase hex; `n` percent-encoded
  UTF-8, decoded name 1–80 chars after trim, same character rules as §3.1.
  Unknown extra `&k=v` pairs ignored. Total payload ≤ 512 bytes.
- Parser `LibraryCardPayload.parse(raw)` → `LibraryCard?` (null = not a
  card). It **first** checks the URL (without fragment) with
  `BookmarkUrl.normalize`; only then parses the fragment. A `pitaka-lib:`
  payload is reported separately so the UI can say "that is a pairing code".
- Why a fragment: browsers never send it to the server; GitHub Pages serves
  the same page; a phone camera opens the site; Pitak parses the card.
- Error-correction level M (matches `QrView`, `lib/core/widgets/qr_view.dart`).

### 3.3 Fingerprint

`LibraryFingerprint.of(libraryId)` = lowercase hex of
`SHA-256(UTF-8("pitak-library-fingerprint-v1:" + libraryId))`.

- Domain-separation prefix so the hash can never be confused with any other
  SHA-256 of the ID elsewhere.
- Input must pass `LibraryId.normalizeOrNull` first; the function returns
  `null` for an invalid ID (never hashes junk).
- 128-bit random IDs ⇒ the hash is not invertible in practice; the ID stays
  private. `package:crypto` is on the domain allow-list (verified,
  `test/architecture/domain_purity_test.dart:67`).

### 3.4 Backup archive additions (`.pitabak`, manifest schema stays 1)

Two new entries, each announced by a new manifest flag that **defaults to
false** (the `hasX` forward-compat pattern, `backup_manifest.dart:5-7`):

| Entry | Flag | Content |
|-------|------|---------|
| `identity.json` | `hasIdentity` | `{ "libraryId": "<16–64 hex>", "libraryName": "…" }` |
| `network.json` | `hasNetwork` | `{ "schemaVersion": 1, "libraries": [ <NetworkLibrary JSON, §5.2> … ] }` |

- Kotlin-era and older Pitak archives lack both ⇒ flags false ⇒ restore
  does nothing new. No `knownSchemaVersion` bump (additive).
- Restore validates `identity.json` with `LibraryId.normalizeOrNull`; an
  invalid ID ⇒ identity not adopted, reported in the summary, catalogue
  restore unaffected.

---

## 4. Verified facts (what this builds on)

| Fact | Where |
|------|-------|
| Bookmarks today: `LibraryBookmark(label, url)`; URL allow-list `BookmarkUrl.normalize` (https, no userinfo, host `github.io`/`pages.dev` or subdomains). Stored as one JSON array under prefs key `library_bookmarks`. | `lib/features/bookmarks/domain/library_bookmark.dart`, `…/infrastructure/prefs_bookmarks_repository.dart:23` |
| Library ID: 16–64 lowercase hex, minted lazily; validated by `LibraryId.normalizeOrNull`. Pairing QR payload `pitaka-lib:<id>` (cross-app contract — must not change). | `lib/features/library/domain/value_objects/library_id.dart`, `…/library_qr_payload.dart` |
| Library identity is owned by `SettingsController` via the `LibraryNamespace` port (`current()`, `adopt(id, name)`); writing the ID behind the controller is a known bug class (N07). | `lib/features/settings/domain/library_namespace.dart`, `settings_controller.dart:155-215` |
| GPS today: `AppSettings.publishContactGps` ("lat, lng" string), edited in Publish › Basic info, rendered on `index.html` as an exact Google-Maps pin by `PublishContactLinks.locationHref`; lat/lng parsing is a private `_parseLatLng`. | `lib/features/settings/domain/app_settings.dart:117`, `lib/features/publish/presentation/widgets/basic_info_tab.dart`, `lib/features/publish/domain/publish_contact_links.dart:74-96` |
| Publish writes `books.json` + `index.html` (+ covers) as ONE commit; files are added via `_desiredFile(path, bytes, manifest)`; `PublishContact` is built in `PublishController._publishBooks` from settings. Events publish is the precedent for a second file (`events.html`). | `publish_library_use_case.dart:236-240`, `publish_controller.dart:62-110`, `publish_events_use_case.dart:160-167` |
| Published site URL: `publishedSiteUrlProvider` (null until first successful publish); `githubPagesFileUrl(ownerRepo, relativePath)` builds file URLs. | `lib/core/di/src/publish_providers.dart:194-198`, `lib/features/publish/domain/github_pages_url.dart:54,70` |
| Bounded fetcher: allow-list → abortable deadline → manual redirects re-validated per hop → streaming byte cap → never drain rejected bodies. Returns the publish-domain `CoverFetchResult`. | `lib/features/publish/infrastructure/bounded_cover_fetcher.dart`, `…/domain/cover_fetch_result.dart` |
| HTTP clients: `httpClientProvider` (60 s, 64 MiB), `lookupHttpClientProvider` (10 s/30 s + UA `'Pitaka/1.1 (https://github.com/PLFIndia)'`). | `lib/core/di/src/platform_providers.dart:49-74`, `lib/core/network/lookup_http_client.dart:45` |
| Drift: `AppDatabase` schemaVersion 2, tables `Books`, `WishlistBooks`; raw-SQL indexes/FTS in `beforeOpen`; snapshots in `drift_schemas/app_database/`; migration test with a data matrix; bump procedure documented. | `lib/core/database/app_database.dart:21-50`, `test/core/database/migration_test.dart:95-106`, `README.md:276-284` |
| Backup: entries `manifest.json`, `books.db`, `wishlist.db`, `borrowers.db`, `backup_blob`, `cover_*`; builder runs in an isolate; **settings are NOT in a backup** (N04). Restore: inspect → validate → all-or-nothing switch; `RestoreController` has a post-restore hygiene hook. | `backup_archive_writer.dart:64-69`, `restore_controller.dart:136-160`, `backup_archive_builder.dart:26-31` |
| QR rendering: `QrView(data, size)` (pure `qr` package). Scanning: `ScanLibraryQrPage` (flutter_zxing) hard-wired to `LibraryQrPayload.parse`. Visiting card prints `QrView(data: url, size: 254)`. | `lib/core/widgets/qr_view.dart`, `lib/features/settings/presentation/pages/scan_library_qr_page.dart`, `library_share_card.dart:368` |
| Drawer destinations: Borrowers vault · Publish to web · Wishlist · **Bookmarks** · Share Library Website · Settings. | `lib/core/widgets/app_drawer.dart:73-120` |
| Fitness functions: domain import allow-list (`fpdart`, `crypto`, `archive`; `core/error/`, `core/text/`, `core/crypto/secret_bytes.dart`); application may not import infrastructure or `package:http`/`drift`/prefs; presentation may not import infrastructure/drift/`core/database`; no `print`/`debugPrint` outside `app_log.dart`; bare catches need a comment; **500-line file ratchet**. | `test/architecture/domain_purity_test.dart`, `test/architecture/layer_boundaries_test.dart:36-200` |
| Test helpers: `test/support/a11y.dart` (`meetsGuideline` trio for every page test), `test/support/fuzz.dart`. | `test/support/` |
| CI gates incl. F-Droid purity (`fdroidReleaseRuntimeClasspath` free of Google code), OSV scan of `pubspec.lock`, golden tests. | `.github/workflows/ci.yml` |
| OSM tile policy (fetched 2026-10-17): unique stable `User-Agent` naming the app; visible attribution; honour cache headers (≥ 7 days if not); HTTPS `https://tile.openstreetmap.org/{z}/{x}/{y}.png`; **no prefetch / offline download**; no `no-cache` headers. | https://operations.osmfoundation.org/policies/tiles/ |
| `flutter_map` 8.3.2, BSD-3, "100% pure-Flutter"; deps: async, collection, dart_earcut, dart_polylabel2, http, latlong2, meta, path, path_provider, proj4dart, uuid. Built-in HTTP-freshness tile caching exists in the 8.x line (changelog #2082/#2125). | https://pub.dev/packages/flutter_map |

---

## 5. Target architecture

### 5.1 Folder layout (new feature `network`)

```
lib/features/network/
  domain/
    value_objects/
      geo_point.dart              GeoPoint (lat/lng VO, parse, coarsen, distanceKm)
      library_fingerprint.dart    LibraryFingerprint.of(id) / isValid
      library_card_payload.dart   LibraryCard + LibraryCardPayload.encode/parse (§3.2)
      network_name.dart           NetworkName.normalizeOrNull (1–80 chars, char rules)
    entities/
      network_library.dart        NetworkLibrary (immutable row), NetworkSource,
                                  MembershipState, FetchStatus, toJson/fromJson
      library_descriptor.dart     LibraryDescriptor (+ MemberEntry) = parsed library.json
    library_descriptor_codec.dart LibraryDescriptorCodec.decode/encode (§3.1 rules)
    network_discovery_plan.dart   pure planner: which rows to fetch/expand (D10)
    repositories/
      network_repository.dart     port (Drift impl in infrastructure)
    descriptor_fetch_result.dart  sealed DescriptorFetched | DescriptorRefused(reason)
    descriptor_fetcher.dart       typedef DescriptorFetcher = Future<DescriptorFetchResult> Function(String url)
    usecases/
      add_member_use_case.dart
      confirm_membership_use_case.dart
      refresh_network_use_case.dart
      migrate_legacy_bookmarks_use_case.dart
  application/
    network_controller.dart       AsyncNotifier<NetworkWindow> (rows + last refresh report)
    network_refresh_controller.dart  AsyncNotifier running one refresh at a time (cancel)
    my_library_card_controller.dart  builds the card payload from identity + site URL
  infrastructure/
    drift_network_repository.dart
    bounded_descriptor_fetcher.dart  (adapter over core BoundedHttpFetcher)
    legacy_bookmarks_reader.dart     reads + clears prefs key `library_bookmarks`
    osm_tile_provider.dart           tile URL const, UA headers, cache config
  presentation/
    pages/
      network_page.dart            tabs: Libraries (list) · Map · My card
      network_map_page.dart        flutter_map view (opened from Map tab after consent)
      add_member_page.dart         scan flow + result
    widgets/
      network_library_tile.dart
      membership_badge.dart
      tiles_consent_dialog.dart
      osm_attribution.dart
lib/core/di/src/network_providers.dart     all providers for the feature
lib/core/network/bounded_http_fetcher.dart  extracted generic fetcher (D14)
lib/core/network/bounded_fetch_outcome.dart sealed core outcome (bytes | refusal)
lib/core/network/app_user_agent.dart        ONE UA constant (lookup + tiles + descriptors)
lib/core/widgets/qr_scan_page.dart          generic QrScanPage<T> (replaces ScanLibraryQrPage)
```

Deleted at the end of S4: `lib/features/bookmarks/**`,
`lib/core/di/src/bookmarks_providers.dart`, `test/features/bookmarks/**`
(their cases move to the network tests, see §8).

### 5.2 Domain types (pure Dart — no Flutter/IO/Riverpod)

```dart
/// A validated coordinate pair. Value Object: construction = validation.
final class GeoPoint {
  static GeoPoint? tryCreate(double lat, double lng);   // range check, finite
  static GeoPoint? parse(String raw);                   // "lat, lng" — replaces PublishContactLinks._parseLatLng
  GeoPoint coarsen();                                   // round both to 2 decimals (≈1.1 km)
  double distanceKm(GeoPoint other);                    // haversine, R = 6371.0088
  bool sameAs(GeoPoint other);                          // no ==/hashCode (lint: non-@immutable)
}

enum LocationPrecision { approximate, exact }
enum NetworkSource { bookmark, card, discovered }      // how the row got here
enum MembershipState { none, pending, confirmed, declined } // am *I* a member of THIS row (a hub)?
enum FetchStatus { never, ok, unreachable, invalid, schemaTooNew, identityConflict }

final class NetworkLibrary {
  final int id;                        // Drift PK (0 = unsaved)
  final String siteUrl;                // natural key, BookmarkUrl-normalized
  final String name;                   // NetworkName
  final String? fingerprint;           // null until fetched/scanned
  final GeoPoint? location;
  final LocationPrecision? precision;
  final NetworkSource source;
  final bool isMember;                 // I (hub) added this library by card
  final bool memberVerified;           // fetched fingerprint == scanned fingerprint
  final String? listedByHubUrl;        // for discovered rows: which hub listed it
  final MembershipState membership;    // I am a member of THIS hub
  final FetchStatus fetchStatus;
  final int? fetchedAt;                // epoch ms
  final int createdAt;
  final int sortOrder;                 // preserves old bookmark order
  // toJson/fromJson for network.json (§3.4); fromJson re-validates every field
}

final class LibraryDescriptor { fingerprint, name, siteUrl, updatedAt, location?, precision?, members: List<MemberEntry>, memberOf: List<String> }
final class MemberEntry { fingerprint, siteUrl, name }

sealed class DescriptorFetchResult {}
final class DescriptorFetched extends … { final LibraryDescriptor descriptor; }
final class DescriptorRefused extends … { final DescriptorRefusal reason; }
enum DescriptorRefusal { disallowedUrl, redirectRefused, tooManyRedirects, httpStatus, tooLarge, timedOut, transport, invalid, schemaTooNew }
```

`LibraryDescriptorCodec.decode(List<int> bytes) → Either<DescriptorRefusal, LibraryDescriptor>`
and `encode(LibraryDescriptor) → List<int>` (stable key order, §3.1).

### 5.3 Repository port

```dart
abstract interface class NetworkRepository {
  Future<List<NetworkLibrary>> loadAll();                               // sortOrder, then name
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(NetworkLibrary row); // insert or update; never clears fingerprint/location to null unless told
  Future<Either<Failure, Unit>> removeById(int id);
  Future<Either<Failure, Unit>> replaceAll(List<NetworkLibrary> rows);   // restore path, one transaction
  Future<Either<Failure, Unit>> applyRefresh(List<NetworkLibrary> updated, List<NetworkLibrary> discovered); // ONE transaction
  Future<int> count();
}
```

Drift table `NetworkLibraries` (`network_libraries`) in
`lib/core/database/tables.dart`; uniqueness via Drift `uniqueKeys` (NOT raw
SQL — nothing here needs Room compatibility, and the snapshot must see it):

| column | type | notes |
|--------|------|-------|
| `id` | INTEGER PK autoincrement | |
| `site_url` | TEXT NOT NULL | unique |
| `name` | TEXT NOT NULL default '' | |
| `fingerprint` | TEXT NULL | unique among non-null (`uniqueKeys` + nullable: verify Drift emits a plain UNIQUE, which SQLite treats as unique-among-non-null) |
| `lat` REAL NULL, `lng` REAL NULL, `precision` TEXT NULL | | |
| `source` | TEXT NOT NULL | enum name |
| `is_member` INTEGER NOT NULL default 0, `member_verified` INTEGER NOT NULL default 0 | | |
| `listed_by_hub_url` | TEXT NULL | |
| `membership` | TEXT NOT NULL default 'none' | |
| `fetch_status` | TEXT NOT NULL default 'never' | |
| `fetched_at` INTEGER NULL, `created_at` INTEGER NOT NULL, `sort_order` INTEGER NOT NULL | | |

`AppDatabase.schemaVersion` → **3**; `onUpgrade`: `if (from < 3) await m.createTable(networkLibraries);`
Schema history comment updated. Follow README › "Schema version bumps" (dump
snapshot `drift_schema_v3.json`, regenerate helpers, add data-matrix row
"v2: books + wishlist survive; `network_libraries` exists and is empty").
Add the new unique indexes to nothing — they are drift-visible (not in
`_rawSqlObjects`).

### 5.4 Settings changes

- `AppSettings.publishLocationSharing: LocationSharing` (`off | approximate | exact`), default `off`.
  Prefs key `publish_location_sharing`. **First-read rule** (`PrefsSettingsRepository`):
  key absent **and** `publishContactGps` non-blank ⇒ `exact` (preserves the
  pin existing users already publish); key absent and GPS blank ⇒ `off`.
  Document in a comment and test both branches.
- `AppSettings.networkMapTilesConsent: bool`, default `false`. Prefs key
  `network_map_tiles_consent`.
- `SettingsRepository`: `setPublishLocationSharing(LocationSharing)`,
  `setNetworkMapTilesConsent({required bool enabled})`; `SettingsController`
  mirrors them through `_update` (the single serialised writer, M16).
- `PublishContactLinks.render` gains a `sharing: LocationSharing` parameter:
  `off` ⇒ no GPS pin (address search link unaffected); `approximate` ⇒
  `GeoPoint.parse(gps)?.coarsen()`; `exact` ⇒ as today. `_parseLatLng`
  deleted in favour of `GeoPoint.parse`.
- Publish › Basic info tab: the GPS field gets a 3-way segmented control
  beneath it ("Not shared / Approximate (~1 km) / Exact") + the existing
  public caution text extended with one sentence about the network map.

### 5.5 Publish integration

- `PublishLibraryUseCase.call` gains `required List<int>? libraryJson`
  (null ⇒ the file is not written and, if present in the manifest, is
  **removed** from the tree — use the existing delete path if the git-data
  API has one; otherwise write an empty-members, no-location descriptor.
  **Verify** `GitHubGitDataApi` supports deletions before choosing; if not,
  always write the descriptor — it is never secret).
- `PublishController._publishBooks` builds the descriptor via a pure
  `BuildOwnDescriptor` function (application): identity from
  `settingsControllerProvider.notifier.current()` (fingerprint of the ID;
  a Left ⇒ publish refused with "Library identity unavailable"), name =
  `settings.libraryName` (blank ⇒ "Pitak library"), `siteUrl` from
  `githubPagesUrlFor(ownerRepo)`, `location` per D7, `members` = rows with
  `isMember` (sorted), `memberOf` = rows with `membership == confirmed`.
- `_desiredFile('library.json', libraryJson, manifest)` added next to
  `books.json`. Incremental publish already skips unchanged shas.
- Events publish (`publish_events_use_case.dart`) is untouched.

### 5.6 Refresh algorithm (`RefreshNetworkUseCase`, pure plan + ports)

Inputs: all rows, own fingerprint, `DescriptorFetcher`, clock, cancel token.

1. **Seeds** = every saved row (bookmark, card, discovered). Fetch each
   row's `<siteUrl>library.json` (siteUrl always ends with `/`; use
   `Uri.resolve`). Concurrency 4. Per-fetch deadline 15 s, body cap 64 KiB.
   Cancel token checked between fetches; cancel ⇒ partial results are
   still applied (they are each individually valid).
2. **Apply per row**: `ok` ⇒ name, location/precision, fingerprint
   (if row.fingerprint null ⇒ set; if set and differs ⇒ `identityConflict`,
   nothing else updated), `fetchedAt`; `memberVerified = isMember && match`.
   Refusals map to `FetchStatus` (unreachable | invalid | schemaTooNew).
   If the fetched fingerprint equals a *different* row's fingerprint ⇒
   `identityConflict` on this row (D12).
3. **Expansion** (D10): for each `ok` descriptor D of row R:
   - `D.memberOf` ⇒ new `discovered` rows (hubs) if siteUrl unknown; they
     are fetched in this run **and** their `members` expanded.
   - `D.members` ⇒ expanded only if R is a seed or a hub reached via
     `memberOf` in this run: new `discovered` rows with
     `listedByHubUrl = R.siteUrl`, fetched for their pin only (their
     `members`/`memberOf` are **not** expanded).
   - Caps: stop creating rows at 500 total; truncation is reported.
4. **Own membership**: if own fingerprint ∈ `D.members` of row R and
   `R.membership == none` ⇒ set `pending` (UI prompts; confirm ⇒
   `confirmed`, dismiss ⇒ `declined`; `declined` is never re-prompted
   unless the user taps "Reconsider"). If own fingerprint is *absent* from a
   hub that was `confirmed` ⇒ keep `confirmed` but flag `noLongerListed`
   in the report (user decides).
5. `applyRefresh(updated, discovered)` in ONE transaction; then return
   `RefreshReport(fetched, unreachable, invalid, schemaTooNew, discovered,
   truncated, pendingMemberships, conflicts, cancelled)`.

`NetworkDiscoveryPlan` (domain) decides steps 1 and 3 purely from the row
list + descriptors so the policy is unit-testable without IO.

### 5.7 Hub "Add member" (`AddMemberUseCase`)

Input: `LibraryCard` (from the scanner). Steps: normalise siteUrl → find
row by siteUrl → if none: insert `source: card, fingerprint, name,
isMember: true, memberVerified: false` → if existing: set `isMember`,
`source` stays, fingerprint: null ⇒ set; equal ⇒ keep; different ⇒ return
`Left(ValidationFailure)` with message "This card's identity does not
match the saved library at this address." → then one immediate bounded fetch
to set `memberVerified` (a refusal leaves it false with a visible
"unverified" badge; never an error). The scanner screen rejects
`pitaka-lib:` with "That's a pairing code. Ask the library to show its
library card instead." (D2).

### 5.8 Own card (`MyLibraryCardController`)

State: `AsyncValue<LibraryCard?>` — null when not published yet or identity
unavailable. Payload = §3.2 from `current()` identity + `publishedSiteUrl` +
`libraryName`. The "My card" tab shows `QrView(data: payload)` and a
"Share as image" button that reuses the visiting-card pipeline
(`library_share_card.dart` gets the card payload as its QR `data` instead of
the bare URL — the printed link line is unchanged).

### 5.9 Map (`network_map_page.dart`)

Expected `flutter_map` API (verify every name against the installed
version before use): `FlutterMap(options: MapOptions(initialCenter,
initialZoom, interactionOptions), children: [TileLayer(urlTemplate,
tileProvider: NetworkTileProvider(headers: {'User-Agent': AppUserAgent.value}),
…), MarkerLayer(markers: …), RichAttributionWidget/SimpleAttributionWidget])`.
`LatLng` from `latlong2` (add as a direct dependency; it is already
transitive).

- Opens only after `networkMapTilesConsent` is true; the first tap shows
  `TilesConsentDialog` (plain words: imagery from OpenStreetMap, they see
  your IP and the area you view; Accept persists the setting; Decline
  returns to the list).
- Tile URL template lives in ONE const (`OsmTiles.urlTemplate`); never send
  `Cache-Control: no-cache`; enable the built-in tile cache (verify the
  provider's cache option names in the installed source; honour server
  headers; if a fixed TTL is the only option, use 7 days); **no prefetch**
  of any kind (OSM policy).
- Attribution "© OpenStreetMap contributors" permanently visible
  (bottom-right), tapping opens `https://www.openstreetmap.org/copyright`
  via `url_launcher` (external application mode).
- Initial viewport = bounds of all pins (or the user's own pin if they have
  one, or a world view). No device location is ever read.
- Pin tap ⇒ bottom sheet: name, badges (member / verified / confirmed /
  listed-by-hub / conflict), distance from own pin (if any), "Open site"
  (url_launcher), "Directions" (`geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`).
- The list tab is the default landing; it needs no tiles and works offline.

### 5.10 Backup / restore integration

- `BackupArchiveBuilder.build` gains `required String? identityJson,
  required String? networkJson` (already-encoded UTF-8 JSON strings built by
  `CreateBackupUseCase` from `LibraryNamespace.current()` and
  `NetworkRepository.loadAll()`; strings cross the isolate boundary
  trivially). Writer adds the two entries and sets `hasIdentity`/`hasNetwork`.
- `RestoreBackup.restore` returns `RestoreSummary` extended with
  `restoredIdentity: ({String id, String name})?` and
  `restoredNetwork: List<NetworkLibrary>?` (parsed + validated, not yet
  applied). `RestoreController` then, **after** the catalogue switch
  succeeded: `adopt(id, name)` through `settingsControllerProvider.notifier`
  (the `LibraryNamespace` owner), then `NetworkRepository.replaceAll`.
  Either Left ⇒ `summary.identityAdopted = false` / `networkRestored = 0`
  with a plain sentence on the restore page ("The library identity in this
  backup could not be adopted; your current identity is unchanged.").
  Catalogue restore is never rolled back for these (they are additive).
- `inspectArchive` surfaces `hasIdentity` so the restore page can say
  "This backup carries the library identity for '<name>'; restoring adopts it."

### 5.11 DI (`lib/core/di/src/network_providers.dart`)

```dart
@riverpod Future<NetworkRepository> networkRepository(ref)      // DriftNetworkRepository over appDatabaseProvider;
                                                                // awaits migrateLegacyBookmarksProvider first (idempotent)
@riverpod Future<Unit> migrateLegacyBookmarks(ref)              // prefs key → rows, ONE transaction, then clears the key
@riverpod DescriptorFetcher descriptorFetcher(ref)              // BoundedDescriptorFetcher(client: httpClientProvider)
@riverpod RefreshNetworkUseCase refreshNetworkUseCase(ref)
@riverpod AddMemberUseCase addMemberUseCase(ref)
@riverpod ConfirmMembershipUseCase confirmMembershipUseCase(ref)
```

Controllers live in `features/network/application/` (`@riverpod class …`).
`NetworkRefreshController` is `keepAlive` (a refresh survives navigation,
same justification as `ExportController`), with a comment saying why.
Export the module from `lib/core/di/providers.dart`; delete the bookmarks
export at the end of S4.

### 5.12 Shared pieces touched (behaviour-preserving refactors)

- `lib/core/network/bounded_http_fetcher.dart` — generic: `sanitize`
  callback, `timeout`, `maxBytes`, `maxRedirects`; returns
  `BoundedFetchOutcome` (`FetchedBytes(bytes)` | `FetchRefused(reason)`
  with the same reason set as `CoverRefusal` minus `notAnImage`).
  `BoundedCoverFetcher` becomes a thin adapter (allow-list =
  `CoverUrlAllowList.sanitize`, maps outcome → `CoverFetchResult`).
  `test/features/publish/bounded_cover_fetcher_test.dart` passes unchanged.
- `lib/core/network/app_user_agent.dart` — `AppUserAgent.value =
  'Pitak (+https://github.com/PLFIndia/pitak-x)'`; `LookupHttpClient.userAgent`
  now references it (one UA for lookup, descriptor fetches and tiles;
  the version number is omitted on purpose so it cannot drift from pubspec).
- `lib/core/widgets/qr_scan_page.dart` — `QrScanPage<T>({required String
  title, required T? Function(String raw) accept, String? rejectedHint,
  bool Function(String raw)? isKnownOtherPayload})`; pops `T` on accept.
  `ScanLibraryQrPage` is deleted; Settings calls `QrScanPage<String>(accept:
  LibraryQrPayload.parse, …)`; its page test moves with it.
- `lib/core/widgets/app_drawer.dart` — "Bookmarks" → "Library network"
  (`Icons.hub` or `Icons.map`), opens `NetworkPage`.

---

## 6. Threat model and bounds

**Assets:** the user's IP/UA and viewed region (tiles, descriptor fetches);
the library's physical location (published only by choice); the raw library
ID (never published); device memory/time (hostile files).

**Hostile inputs:** every fetched `library.json`; every scanned QR; the
legacy prefs value; `network.json`/`identity.json` from any archive.

| Bound | Value | Enforced in |
|-------|-------|-------------|
| Descriptor body | ≤ 64 KiB, streamed, aborted over cap | `BoundedHttpFetcher` |
| Descriptor fetch deadline | 15 s whole request, abortable | `BoundedHttpFetcher` |
| Redirect hops | ≤ 3, each re-validated by `BookmarkUrl.normalize` | `BoundedHttpFetcher` |
| URL | https, no userinfo, host suffix `github.io` / `pages.dev`, ≤ 2048 chars | `BookmarkUrl` |
| Name | 1–80 chars after trim; reject code units < 0x20, 0x7F, U+202A–U+202E, U+2066–U+2069 | `NetworkName` |
| Fingerprint | exactly 64 `[0-9a-f]` | `LibraryFingerprint.isValid` |
| lat / lng | finite, [−90, 90] / [−180, 180] | `GeoPoint.tryCreate` |
| `members` / `memberOf` per file | ≤ 200 / ≤ 20 (truncate, report) | `LibraryDescriptorCodec` |
| Rows per refresh run | ≤ 500 total (stop discovering, report) | `NetworkDiscoveryPlan` |
| Concurrency | 4 in-flight fetches | `RefreshNetworkUseCase` |
| QR payload | ≤ 512 bytes; URL validated before fragment parsed | `LibraryCardPayload` |
| Legacy prefs value | each item re-validated through `LibraryBookmark.fromJson` rules; corrupt ⇒ skipped | `LegacyBookmarksReader` |
| `network.json` restore | every row re-validated via `NetworkLibrary.fromJson`; invalid rows dropped and counted | `RestoreBackup` |

Rules: no `print`/`debugPrint`; refusal reasons are coarse enums, never
carry URLs; no raw exception text in UI; every `catch` typed or commented;
`Either<Failure, T>` across layers; no background work.

---

## 7. Slices

Each slice: **Why** · **Steps** · **Tests** · **Acceptance** · **NOT doing**.
Commit messages are suggestions in Conventional Commits.

### S1 · Foundation — Size M

**Why.** The value objects, the shared fetcher and the ADR are the ground
everything else stands on; shipping them first keeps every later diff small
and reviewable. No user-visible change.

**Steps.**
1. `GeoPoint` + `LocationPrecision` in `lib/features/network/domain/value_objects/geo_point.dart`.
   Replace `PublishContactLinks._parseLatLng` with `GeoPoint.parse`
   (publish domain importing network domain is allowed: `features/*/domain/`).
   ✅ green — `refactor(publish): GeoPoint value object replaces private lat/lng parser`
2. `LibraryFingerprint` (§3.3) + `NetworkName` (§6 char rules).
   ✅ green — `feat(network): LibraryFingerprint and NetworkName value objects`
3. Extract `BoundedHttpFetcher` + `BoundedFetchOutcome` to `lib/core/network/`;
   `BoundedCoverFetcher` becomes the adapter. Existing tests untouched and green.
   ✅ green — `refactor(network): extract BoundedHttpFetcher from BoundedCoverFetcher (D14)`
4. `AppUserAgent` constant; `LookupHttpClient.userAgent` references it.
   ✅ green — `refactor(network): single AppUserAgent constant`
5. `QrScanPage<T>` in `lib/core/widgets/`; Settings switches to it;
   `ScanLibraryQrPage` deleted; its test moves. ✅ green —
   `refactor(settings): generic QrScanPage replaces ScanLibraryQrPage`
6. `docs/adr/0012-library-network-replaces-bookmarks.md` (template in
   `docs/adr/0000-template.md`; add the row to `docs/adr/README.md`).
   Records D3, D8, D9, D13 and the "URL is the identity" trust model.
   ✅ — `docs(adr): 0012 library network replaces bookmarks`

**Tests.** `geo_point_test` (range, NaN/∞, parse variants incl. "12.5,77",
"12.5 , 77.0", rejects "12;77", coarsen rounding incl. negatives, haversine
against two known pairs), `library_fingerprint_test` (known vector; rejects
invalid ID; 64 hex), `network_name_test` (bounds, control + bidi
rejection), `bounded_http_fetcher_test` (port the cover-fetcher cases to
the generic one: allow-list, redirect re-validation, cap, timeout abort,
no-drain), `publish_contact_links_test` still green, `qr_scan_page_test`.

**Acceptance.** `flutter analyze` 0 issues; all suites green; no file over
500 lines; `domain_purity_test` + `layer_boundaries_test` green.

**NOT doing.** Any UI, any table, any dependency add.

### S2 · Publish side — Size S

**Why.** Members can start publishing their location before any map exists;
hubs can publish nothing yet (no table) — the descriptor simply has an
empty `members`.

**Steps.**
1. `AppSettings.publishLocationSharing` + first-read rule (§5.4);
   repository + controller setters. ✅ green
2. `PublishContactLinks.render(sharing:)`; `index.html` pin obeys D7. ✅ green
3. `LibraryDescriptor`, `MemberEntry`, `LibraryDescriptorCodec` (encode +
   decode, §3.1 rules, stable ordering). ✅ green
4. `BuildOwnDescriptor` (application, pure function over settings +
   identity + site URL; `members`/`memberOf` empty until S3/S4).
   `PublishLibraryUseCase.call(libraryJson:)`; `PublishController` wires it.
   ✅ green
5. Basic info tab: segmented control + caution sentence. ✅ green
   — `feat(publish): opt-in location sharing and library.json descriptor`

**Tests.** settings repo first-read rule (both branches); contact-links
off/approximate/exact; codec: every §3.1 rule (required-field rejection,
schemaTooNew, location dropped on bad lat, members truncation at 200,
memberOf at 20, unknown keys ignored, stable byte output for equal input);
`publish_library_use_case_test` gains "library.json is in the desired file
set and skipped when sha unchanged"; `basic_info_tab` widget test for the
control; `meetsGuideline` trio.

**Acceptance.** A publish from a device with sharing *off* yields a
`library.json` without `location` and an `index.html` without the GPS pin;
*approximate* yields 2-decimal coordinates in both.

**NOT doing.** Reading anyone's descriptor; the network table.

### S3 · Card + hub membership — Size M

**Why.** Hubs need the table and the scan flow before anyone can see a
network. Also the first schema bump — follow the documented procedure.

**Steps.**
1. `NetworkLibraries` table; `schemaVersion = 3`; `onUpgrade` branch;
   dump `drift_schema_v3.json`; regenerate `test/core/database/generated/`;
   data-matrix row for v2 → v3. ✅ green — `feat(database): network_libraries table (schema v3)`
2. `NetworkLibrary` entity (+ JSON), `NetworkRepository` port,
   `DriftNetworkRepository`. ✅ green
3. `LibraryCard` + `LibraryCardPayload` (§3.2) incl. "is a pairing code"
   detection. ✅ green
4. `AddMemberUseCase` (§5.7) + `DescriptorFetcher` port +
   `BoundedDescriptorFetcher`. ✅ green
5. `MyLibraryCardController`; visiting card's QR `data` becomes the card
   payload (link line unchanged). ✅ green
6. `NetworkPage` with tabs Libraries · My card (the Map tab is **absent**
   until S5 — no "coming soon" placeholders in shipped UI);
   `AddMemberPage`; drawer entry renamed; `network_providers.dart` exported.
   `BuildOwnDescriptor` now fills `members` from `isMember` rows.
   ✅ green — `feat(network): library card QR, hub add-member flow, network page`

**Tests.** migration test (v1→3, v2→3, matrix row); repository CRUD incl.
unique-URL upsert and fingerprint uniqueness among non-null; card payload
(encode/parse round-trip, rejects non-allow-listed URL even with a valid
fragment, rejects version 2, rejects 513-byte payload, pairing-code
detection); add-member use case (new row, upgrade bookmark, identity
conflict Left, verification true/false/unreachable); `network_page_test`,
`add_member_page_test` with `meetsGuideline`; share-card test updated for
the new QR data.

**Acceptance.** Scanning a card from another device (manual test, two
phones or one phone + a printed QR) adds a member; publishing yields
`members` in `library.json`; scanning a `pitaka-lib:` code shows the
rejection message and adds nothing.

**NOT doing.** Refresh/discovery; map; deleting the bookmarks feature.

### S4 · Read side, discovery, bookmarks migration — Size L

**Why.** This is the feature's value: Refresh turns saved URLs into pins and
networks. It also retires the old bookmarks feature in the same slice so
there is never a moment with two lists.

**Steps.**
1. `NetworkDiscoveryPlan` (pure, D10) + `RefreshNetworkUseCase` (§5.6) +
   `RefreshReport`. ✅ green
2. `NetworkRefreshController` (keepAlive, one run at a time, cancel) and
   `NetworkController` (`NetworkWindow(rows, lastReport, lastRefreshedAt)`).
   ✅ green
3. `ConfirmMembershipUseCase` (pending → confirmed/declined);
   `BuildOwnDescriptor` fills `memberOf`. ✅ green
4. `LegacyBookmarksReader` + `MigrateLegacyBookmarksUseCase` (idempotent:
   insert missing `siteUrl`s as `source: bookmark` with `sortOrder`, one
   transaction, then clear the prefs key; a second run is a no-op).
   `networkRepositoryProvider` awaits it. ✅ green
5. Libraries tab: distance-sorted when own location known (else name),
   badges, "last refreshed", pull-to-refresh + Refresh button, cancel,
   pending-membership prompt, add-by-URL (replaces bookmark add), remove.
   ✅ green
6. Delete `lib/features/bookmarks/**`, `bookmarks_providers.dart`, its
   export, `test/features/bookmarks/**` (cases moved). ✅ green —
   `feat(network): refresh, discovery and membership confirmation; bookmarks migrated (ADR 0012)`

**Tests.** discovery plan: hub seed expands members (1 expansion); member
seed → memberOf hub → members (2 expansions); third expansion never
happens; 500-row cap with truncation flag; duplicate URLs collapse;
identity conflict; own-fingerprint detection → pending; declined never
re-prompted. Use case with a fake fetcher: partial failure, cancel
mid-run applies partial results, one transaction. Migration use case:
corrupt prefs skipped, idempotent, key cleared only after commit.
Controller tests with `ProviderContainer` overrides. Page tests +
`meetsGuideline`.

**Acceptance.** Device bookmarks the hub → Refresh → every member with
sharing on has coordinates in the list; device bookmarks one member →
Refresh → the hub and all members appear; offline → cached list with the
stamp; the old Bookmarks screen is gone and old bookmarks are present as
rows.

**NOT doing.** Any tile/network imagery.

### S5 · Map — Size M

**Why.** The picture. Separate slice because it adds a dependency and a new
third-party egress, each needing its own review (OSV, F-Droid purity,
privacy policy).

**Steps.**
1. `pubspec.yaml`: `flutter_map: ^8.3.2`, `latlong2` (pin to the version
   `flutter pub deps` resolves). Run the F-Droid purity gate locally
   (README › Flavors) — expected clean (pure Dart). PR note justifies the
   dependency (size, maintenance, license BSD-3, no native code). ✅ green
2. `OsmTiles` const + tile provider config (§5.9), `OsmAttribution`,
   `TilesConsentDialog`, `networkMapTilesConsent` setting. ✅ green
3. `NetworkMapPage` + Map tab; pin sheet with Open site / Directions.
   ✅ green — `feat(network): map of saved libraries (flutter_map + OSM, opt-in)`
4. PRIVACY.md + README + appDetails entries (§9). ✅ —
   `docs: privacy policy covers network refresh, OSM tiles and published location`

**Tests.** consent dialog gating (map never builds without consent);
`User-Agent` header present on the tile provider (unit test over the
provider config, not over HTTP); attribution widget present; pin sheet
actions; golden of the list tile + badges (per architecture.md B2; run the
`update-goldens` workflow for Linux PNGs). Do **not** render real tiles in
tests (no network in tests — override the tile provider with an in-memory
blank provider; verify the API for a test tile provider in the installed
source).

**Acceptance.** First Map tap shows the consent dialog; Decline returns to
the list and nothing was fetched; Accept remembers; attribution visible;
rotating the phone keeps the viewport; airplane mode shows cached tiles /
grey tiles and all pins.

**NOT doing.** Offline tile download, clustering, custom tile servers,
device location.

### S6 · Backup — Size M

**Why.** Restoring on a new phone must not mint a new ID (the hub would stop
recognising the library) and must keep the network list.

**Steps.**
1. `BackupManifest` flags `hasIdentity`, `hasNetwork` (default false; parse
   tolerant). ✅ green
2. Writer entries; `BackupArchiveBuilder.build(identityJson:, networkJson:)`;
   `CreateBackupUseCase` gathers both (identity via `LibraryNamespace`;
   a Left ⇒ backup proceeds **without** identity and says so in the share
   caption — never blocks a catalogue backup). ✅ green
3. Restore: parse + validate; `RestoreSummary` fields; `RestoreController`
   adopts identity then replaces network rows after the catalogue switch;
   restore page copy. ✅ green
4. `test/core/database/migration_test.dart` data-matrix unaffected (archive
   ≠ Drift) — instead extend `test/features/backup/` fixtures: a v1 archive
   without the entries (Kotlin-era) and one with. ✅ green —
   `feat(backup): identity.json and network.json travel in .pitabak (D4)`
5. README › Backup/Restore honest-limit sentence + PRIVACY.md line. ✅

**Tests.** manifest flags default false and round-trip; writer emits both
entries and flags; restore of an archive without them changes neither
identity nor network; with them adopts identity through the namespace port
(fake) and replaces rows; invalid `identity.json` ⇒ not adopted + reported;
`network.json` with one corrupt row ⇒ others restored, count reported.

**Acceptance.** Backup on phone A → restore on phone B → B's "My card"
shows the same fingerprint as A's; B's network list equals A's.

**NOT doing.** Whole-archive encryption (§10).

---

## 8. Test plan (summary)

| Layer | What | Where |
|-------|------|-------|
| Domain | every VO boundary, codec rule, discovery-plan rule, card payload rule | `test/features/network/domain/` |
| Application | use cases success + each failure path; controllers via `ProviderContainer(overrides:)`; refresh cancel | `test/features/network/application/` |
| Infrastructure | Drift repo (in-memory `NativeDatabase.memory()`), bounded descriptor fetcher with `MockClient`, legacy reader | `test/features/network/infrastructure/` |
| Presentation | page tests with `meetsGuideline` trio; golden for the tile; consent gating | `test/features/network/presentation/` |
| Architecture | existing fitness tests stay green; add `network` to any allow-list only with a comment | `test/architecture/` |
| Database | v1→3, v2→3 + data-matrix row | `test/core/database/migration_test.dart` |
| Backup | fixtures with/without new entries | `test/features/backup/` |
| Security | descriptor refusals carry no URL; no `print`; fingerprints never equal the ID; `identityConflict` never overwrites | spread across the above, named `…security…` |

Coverage: domain + application ≥ 90 % on touched code (AGENTS §10); CI
ratchet must not drop.

---

## 9. Docs to update (same PR as the slice that changes behaviour)

- `PRIVACY.md` › "When anything leaves your device": (S4) fetching
  `library.json` from the GitHub/Cloudflare Pages sites you saved, only on
  Refresh; (S5) OpenStreetMap tiles while the map is open, after consent;
  (S2) published location is opt-in with precision choice; (S6) the backup
  archive also contains the library ID and network list in the clear.
- `README.md`: Features bullet (Library network), Privacy posture, Backup
  honest limit, dependency list if it names packages.
- `appDetails.md`: §2 feature list, §3 architecture map (`features/network/`),
  §9 decisions (D3, D7, D9, D10, D11), §11 backlog (deferred items of §10),
  sentinel string for the release (e.g. `LibraryFingerprint`).
- `CHANGELOG.md` › Unreleased: Added / Changed (bookmarks → network,
  schema v3, archive entries) / Security (fingerprint, bounds).
- `fastlane/metadata/android/en-US/changelogs/<code>.txt` at release time.
- `docs/adr/0012-…` (S1) and the ADR index row.
- Play Console Data safety: the app still collects nothing; published
  location is a user-directed transfer. Maintainer decision, not code —
  record the answer in `appDetails.md` §7.

---

## 10. Deferred (with triggers)

| Item | Trigger |
|------|---------|
| In-app GPS capture (flavor-split Kotlin over framework `LocationManager`, ADR 0008 pattern) | Users report typing coordinates is a blocker. |
| Whole-archive encryption of `.pitabak` | A user asks for encrypted backups, or a review flags plain identity in archives. |
| Signed `library.json` (per-library key, verify on fetch) | Observed spoofing of a library's descriptor. |
| Identity-conflict merge action | A real conflict is reported more than once. |
| Cloudflare Pages publish target | Already deferred in appDetails §9; `BookmarkUrl` already accepts `pages.dev`. |
| Network map on the **published** `index.html` | Would need the viewer CSP to allow OSM — only if libraries ask for a public map. |
| Configurable tile server | OSM policy recommends it; add a settings field if OSM ever blocks or throttles. |
| Marker clustering | > 200 pins in one viewport in practice. |

---

## 11. Commands and per-slice checklist

```bash
cd ~/development/pitak_flutter
fvm flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze lib test            # No issues found!
dart format --set-exit-if-changed lib test
fvm flutter test                        # all green; or by dir: fvm flutter test test/features/network
# schema bump (S3 only):
dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/
dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/
# F-Droid purity (S5): see README.md › "Flavors: what may go where"
```

Before calling a slice done (AGENTS §13):
- [ ] Robust solution, not a patch; foundation fixed where touched.
- [ ] Layer rule respected (domain free of Flutter/Riverpod/IO; application free of `http`/`drift`/prefs; presentation free of infrastructure).
- [ ] Providers via `@riverpod` codegen; `keepAlive` justified in a comment; disposal registered.
- [ ] Every external input validated at the boundary (§6 table).
- [ ] No secrets involved — confirm the raw library ID appears in **no** published file, QR, or log.
- [ ] `Either<Failure, T>`; fail closed; coarse refusal reasons.
- [ ] Tests added per §8, `ProviderContainer` overrides, security cases named.
- [ ] Non-obvious choices explained in one-line comments for a beginner.
- [ ] Docs of §9 updated in the same PR.
- [ ] Anything ambiguous ⇒ asked, not guessed.
