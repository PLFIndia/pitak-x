# libNetwork implementation — handoff (S1–S3 done, S4–S6 remaining)

> **For the next session's agent.** This file is the bridge between what is
> already implemented on branch `libNetwork` and what remains. The spec
> (`libNetwork.md`) is still the authority; `AGENTS.md` still wins over it.
> Read §7 S4–S6 of the spec first — this handoff only records STATE, the
> decisions already made in code, and the gotchas that cost time.
>
> Written 2026-10-17 after committing S3.

---

## 1. Where the branch stands

Branch `libNetwork` (from `main` @ 80b8e89). Commits, oldest first:

| Commit | Slice | Content |
|--------|-------|---------|
| 88796f5 | — | the spec itself (`libNetwork.md`) |
| 70e5382…ce786b3 (6 commits) | **S1** | GeoPoint+LocationPrecision (replaces `PublishContactLinks._parseLatLng`), LibraryFingerprint, NetworkName, `BoundedHttpFetcher`+`BoundedFetchOutcome` extracted to `lib/core/network/` (BoundedCoverFetcher is now an adapter; its test suite passed unchanged), `AppUserAgent` (LookupHttpClient UA now `Pitak (+https://github.com/PLFIndia/pitak-x)`), generic `QrScanPage<T>` (ScanLibraryQrPage deleted), ADR 0012 + index row |
| 968344e | **S2** | `LocationSharing` setting + first-read rule, sharing-gated GPS pin (`render(sharing:)` through ViewerHtmlFactory chain), descriptor entities + `LibraryDescriptorCodec` (§3.1 complete), `BuildOwnDescriptor`, `PublishLibraryUseCase.call(libraryJson:)` with sha-skip and `deletePaths` removal, Basic-info segmented control (edit mode) + view-mode value row |
| e447f49 | **S3** | `network_libraries` table (schema **v3**, snapshot + helpers + matrix row done), `NetworkLibrary` entity, `NetworkRepository` port, `DriftNetworkRepository`, `LibraryCard`+`LibraryCardPayload` (§3.2), `AddMemberUseCase` (§5.7), `BoundedDescriptorFetcher`, `MyLibraryCardController`, `NetworkPage` (Libraries + My card tabs), `AddMemberPage`, tiles/badges, drawer renamed, share-card QR = card payload, publish fills `members` from isMember rows |

**Gate status at e447f49:** `fvm flutter analyze lib test` → No issues;
`fvm dart format --set-exit-if-changed lib test` → clean;
`fvm flutter test --exclude-tags golden` → **2112 tests, all green**;
build_runner → no uncommitted diffs. The 6 golden tests fail locally on
macOS by design (Linux is the reference renderer, `dart_test.yaml`); none of
S1–S3 changes what the goldens render (LibraryPage / VaultPage /
PublishPage-connection-tab / RestorePage), but watch the CI golden job after
pushing — if anything diffs, regenerate via the `update-goldens` workflow.

**NOT done yet:** S4 (refresh/discovery/bookmarks migration + delete
bookmarks), S5 (map), S6 (backup), and the §9 docs sweep (PRIVACY.md,
README, appDetails.md, CHANGELOG — none of the S2/S3 doc lines are written
yet; do them with S4–S6 or as one docs commit before merging).

---

## 2. Environment / tooling facts (verified, don't rediscover)

- Use `fvm flutter` / `fvm dart` (Flutter **3.44.2** pinned in `.fvmrc`;
  bare `dart` on PATH is a different SDK and `pub get` fails the pin).
- Local test command: `fvm flutter test --exclude-tags golden`
  (macOS renderer ≠ Linux golden reference; see `dart_test.yaml`).
- Pre-commit hook (`.githooks`, `core.hooksPath` is set) reruns build_runner
  and **refuses commits while regenerated `.g.dart` files are unstaged**.
  Riverpod embeds a hash of each annotated class body, so touching e.g.
  `publish_controller.dart` dirties its `.g.dart`. Consequence: **commit a
  slice atomically** (S2 and S3 are single commits) unless the commit
  touches no codegen inputs (S1 was 6 commits).
- Schema bump procedure (used for v3, reuse for nothing until the next bump):
  `fvm dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/`
  then `fvm dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/`,
  then a data-matrix row in `test/core/database/migration_test.dart`.
- File-size ratchet: `settings_page.dart` record bumped 682→**690** (S1) in
  `test/architecture/layer_boundaries_test.dart`. Keep new files < 500 lines
  (`network_page.dart` ≈ 260, `drift_network_repository.dart` ≈ 290).
- Const gotcha (verified empirically): a nested constructor call inside a
  `const` constructor's initializer list **cannot forward formal parameters**
  and cannot be implicit-const — that's why `BoundedCoverFetcher` and
  `BoundedDescriptorFetcher` have non-const constructors (documented in code).
  Static tear-offs (`LibraryQrPayload.parse`, `CoverUrlAllowList.sanitize`)
  ARE valid constant expressions.
- Lint landmines that bit (very_good_analysis): `comment_references` in
  `library;` docs can't see class members (qualify `[Class.member]` or use
  backticks); `avoid_equals_and_hash_code_on_mutable_classes` — domain can't
  import `package:meta` for `@immutable` (not on the allow-list), so entities
  use **`sameAs()` instead of `==`** (GeoPoint, NetworkLibrary);
  `avoid_catching_errors` — don't catch ArgumentError from
  `Uri.decodeComponent`, regex-guard `%` escapes first (see
  `LibraryCardPayload._badEscape`); SQL string literals in tests → use
  `db.customUpdate(..., variables: [Variable(...)])` to stay single-quoted.
- Domain import allow-list (`test/architecture/domain_purity_test.dart`):
  pure dart libs + `fpdart`, `crypto`, `archive` + `features/*/domain/` +
  `core/error/`, `core/text/`, `core/crypto/secret_bytes.dart`. The network
  domain currently imports `features/bookmarks/domain/library_bookmark.dart`
  for **`BookmarkUrl`** — see §3.
- Riverpod testing: autoDispose AsyncNotifier providers read via
  `container.read(xProvider.future)` can be **disposed mid-build** when the
  build has several awaits (ID minting) — keep a listener:
  `container.listen(xProvider, (_, _) {})` (pattern in
  `my_library_card_controller_test.dart`).
- Widget tests: never render `ReaderWidget` (camera). `QrScanPage.buildScanner`
  and `AddMemberPage.scanner` are the injected fake-scanner seams; page tests
  drive them with buttons. Tall `tester.view.physicalSize` for full pages.
  a11y trio: `test/support/a11y.dart` → `expectMeetsA11yGuidelines`.
  **Disabled Material controls fail textContrast** — that's why Basic-info
  shows a read-only value row in view mode instead of a disabled
  SegmentedButton (keep this pattern).

---

## 3. Decisions made during implementation (respect or revisit consciously)

- **`BookmarkUrl` still lives in `lib/features/bookmarks/domain/library_bookmark.dart`**
  and is imported by the network domain (codec, card payload, entity,
  descriptor fetcher, build_own_descriptor). **When S4 deletes the bookmarks
  feature, move `BookmarkUrl` first** — suggested new home:
  `lib/features/network/domain/value_objects/bookmark_url.dart` (class name
  unchanged; spec §6 references it). `LibraryBookmark` itself dies with the
  feature; its `fromJson` validation rules must be re-implemented inside
  `LegacyBookmarksReader` (§6 bounds table: "each item re-validated through
  LibraryBookmark.fromJson rules").
- `NetworkLibrary.copyWith` has explicit **`clearFingerprint` /
  `clearLocation` (clears precision too) / `clearListedByHubUrl` /
  `clearFetchedAt`** flags — plain null args can't express "clear". **The S4
  refresh use case must use `clearLocation: true` when a fetched descriptor
  has no location** (a library turned sharing off), and `applyRefresh` is the
  wholesale-write path (`upsertBySiteUrl` deliberately never clears).
- Repository merge contract (port doc): `upsertBySiteUrl` = incoming nulls
  keep stored values, blank name keeps stored name, id/createdAt/sortOrder
  always stored. `applyRefresh(updated, discovered)` = one transaction,
  updated rows overwrite wholesale (may null), discovered rows insert.
- `networkRowsProvider` (autoDispose Future provider over
  `networkRepositoryProvider.loadAll()`) is the S3 stopgap the Libraries tab
  watches; screens `ref.invalidate` it after mutations. S4's
  `NetworkController`/`NetworkRefreshController` should either wrap it or
  replace it — currently `network_page.dart._remove` calls the repository
  port directly from presentation (legal — DI hands out the domain
  interface — but folding remove into the controller in S4 would be tidier).
- `descriptorFetcherProvider` returns the **tear-off**
  `BoundedDescriptorFetcher(...).fetch` (the port is a function type).
- `AddMemberUseCase` sets `fetchStatus: identityConflict` when the FETCHED
  fingerprint differs from the SCANNED one (spec only demanded "never an
  error"; D12's visible-badge shape seemed the honest minimum). The card-scan
  mismatch (stored row vs card) is refused with the exact §5.7 message
  (`AddMemberUseCase.identityMismatchMessage`).
- Publish controller: identity Left ⇒ `PublishFailure('Library identity
  unavailable')`; no target repo ⇒ descriptor skipped, the use case's own
  'Pick a target repo first.' fires first; `BuildOwnDescriptor` Left ⇒
  `libraryJson = null` ⇒ a stale published descriptor is DELETED via
  `deletePaths` (verified: `GitHubGitDataApi.commitFiles` supports it, M14).
- `PublishContactLinks.gpsItem(raw, sharing)` is public (tested): off ⇒ null
  (even for free text — fail closed); approximate ⇒ coarsened href AND
  label; exact ⇒ normalized pair; non-coordinate text keeps the legacy
  search-link fallback under approximate/exact.
- `app_database_test.dart` now asserts `PRAGMA user_version == db.schemaVersion`
  instead of a pinned literal (the pinned 2 broke on the v3 bump).
- UA string changed app-wide to `AppUserAgent.value` (S1) — the lookup test
  asserts the constant, not the old literal.

---

## 4. Remaining work, concretely

### S4 — Read side, discovery, bookmarks migration (Size L; spec §7 S4)

Create (paths per spec §5.1):
- `domain/network_discovery_plan.dart` — pure planner (D10): seeds = all
  rows; `memberOf` links followed from ANY ok descriptor; `members` expanded
  only for seeds and hubs reached via memberOf; caps **500 rows/run**
  (codec already caps 200 members / 20 memberOf per file); truncation
  reported. Unit-testable without IO.
- `domain/usecases/refresh_network_use_case.dart` + `RefreshReport`
  (§5.6 steps 1–5): concurrency **4**, per-fetch deadline/cap already inside
  `BoundedDescriptorFetcher`; cancel token checked between fetches; cancel ⇒
  partial results still applied via ONE `applyRefresh`. Map refusals:
  transport-ish (`disallowedUrl|redirectRefused|tooManyRedirects|httpStatus|
  tooLarge|timedOut|transport`) ⇒ `FetchStatus.unreachable`, `invalid` ⇒
  invalid, `schemaTooNew` ⇒ schemaTooNew. Own-fingerprint ∈ D.members ⇒
  pending membership (unless declined — never re-prompt). Cross-row
  fingerprint collision ⇒ `identityConflict` on this row, nothing else
  updated (D12).
- `domain/usecases/confirm_membership_use_case.dart` — pending →
  confirmed/declined.
- `infrastructure/legacy_bookmarks_reader.dart` — reads + clears prefs key
  `library_bookmarks` (JSON array; per-item validation per §6; corrupt items
  skipped).
- `domain/usecases/migrate_legacy_bookmarks_use_case.dart` — idempotent:
  insert missing siteUrls as `source: bookmark` preserving order via
  `sortOrder`, ONE transaction, clear the prefs key only after commit.
- `application/network_controller.dart` (`NetworkWindow(rows, lastReport,
  lastRefreshedAt)`) + `application/network_refresh_controller.dart`
  (**keepAlive with a justifying comment** — spec §5.11; one run at a time,
  cancel).
- DI (§5.11): `migrateLegacyBookmarksProvider` (Future<Unit>),
  `networkRepositoryProvider` **awaits it first**, `refreshNetworkUseCase`,
  `confirmMembershipUseCase`.
- UI (Libraries tab): distance-sorted when own location known (own pin =
  settings GPS × sharing, via `GeoPoint.parse`/`coarsen` — reuse the D7
  mapping; no device location ever), else name; "last refreshed" stamp;
  pull-to-refresh + Refresh button + cancel; pending-membership prompt with
  "Reconsider" for declined; add-by-URL (BookmarkUrl validation, replaces
  bookmark add); remove (exists already).
- `BuildOwnDescriptor` gains `memberOf` from `membership == confirmed` rows —
  wire in `PublishController._publishBooks` (the fake `_Network` repo in
  `publish_controller_test.dart` already feeds rows; extend the members test
  or add one).
- **Delete**: `lib/features/bookmarks/**`, `lib/core/di/src/
  bookmarks_providers.dart` (+ its `.g.dart` + the export line in
  `lib/core/di/providers.dart`), `test/features/bookmarks/**` — move the
  still-valuable cases (`BookmarkUrl` tests, add/remove flow) into network
  tests. Move `BookmarkUrl` BEFORE deleting (see §3). Check for stragglers:
  `grep -rn "features/bookmarks" lib test`.

Spec test list (§7 S4 Tests) is precise — plan/refresh/migration fakes plus
controller tests via `ProviderContainer(overrides:)`; remember the
autoDispose-listener gotcha.

### S5 — Map (Size M; spec §7 S5)

- pubspec: `flutter_map: ^8.3.2` + `latlong2` pinned to what
  `fvm flutter pub deps` resolves. **Verify every flutter_map symbol against
  `~/.pub-cache/hosted/pub.dev/flutter_map-<ver>/lib/` before use** (spec
  preamble; tile-cache option names, test tile provider, attribution widget
  names). Run the F-Droid purity check (README › "Flavors: what may go
  where") — expected clean (pure Dart, no `android/` in the package).
- Settings wave 2: `AppSettings.networkMapTilesConsent` (default false, key
  `network_map_tiles_consent`) + `setNetworkMapTilesConsent({required bool
  enabled})` on `SettingsRepository`/`PrefsSettingsRepository`/
  `SettingsController._update`. **This breaks the same 6 test fakes as S2
  did** — add the method to: `test/core/di/derived_providers_test.dart`,
  `test/features/backup/restore_controller_test.dart`,
  `test/features/library/book_cover_controller_test.dart`,
  `test/features/library/library_controller_test.dart`, and BOTH repos in
  `test/features/settings/settings_test.dart` (`_FailingSettingsRepo` →
  `throw _boom`, `_GatedSettingsRepo` → `_gate('tilesConsent')`). (Fakes
  with `noSuchMethod` need nothing.)
- `infrastructure/osm_tile_provider.dart`: ONE const
  `OsmTiles.urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'`;
  headers `{'User-Agent': AppUserAgent.value}`; built-in HTTP-freshness cache
  honoured from server headers (fixed-TTL fallback 7 days); **no prefetch**;
  never send `Cache-Control: no-cache`.
- Map tab in `NetworkPage` (third tab) opening `network_map_page.dart` ONLY
  after consent (`TilesConsentDialog`: plain words, Accept persists via the
  controller setter, Decline returns to the list); `OsmAttribution`
  permanently visible bottom-right → `https://www.openstreetmap.org/copyright`
  via url_launcher external mode; initial viewport = bounds of pins / own pin
  / world; pin tap ⇒ bottom sheet (name, `MembershipBadge`, distance from own
  pin via `GeoPoint.distanceKm`, Open site, Directions
  `geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`).
- Tests: consent gating (map never builds without consent), UA header on the
  provider config (unit — no HTTP), attribution present, pin-sheet actions,
  golden of `NetworkLibraryTile` + badges (tag `golden`; **cannot regenerate
  on macOS** — use the `update-goldens` workflow, architecture.md B2), fake
  blank tile provider (no network in tests).
- Docs (§9/S5): PRIVACY.md OSM-tiles paragraph, README dependency + privacy
  posture, appDetails entries.

### S6 — Backup (Size M; spec §7 S6)

- `BackupManifest`: `hasIdentity`, `hasNetwork` (default false, tolerant
  parse; the `hasX` forward-compat pattern already in
  `backup_manifest.dart`).
- `BackupArchiveWriter`: entries `identity.json` / `network.json`;
  `BackupArchiveBuilder.build(identityJson:, networkJson:)` (Strings cross
  the isolate); `CreateBackupUseCase` gathers: identity via
  `LibraryNamespace.current()` — **a Left must NOT block the backup**
  (proceed without identity, say so in the share caption); network via
  `NetworkRepository.loadAll()` → `{"schemaVersion":1,"libraries":[toJson…]}`.
- Restore: `RestoreSummary` + `restoredIdentity: ({String id, String
  name})?` + `restoredNetwork: List<NetworkLibrary>?` (each row through
  `NetworkLibrary.fromJson`; invalid rows dropped + counted);
  `RestoreController` AFTER the catalogue switch: `adopt(id, name)` through
  `settingsControllerProvider.notifier`, then `NetworkRepository.replaceAll`;
  Lefts ⇒ `identityAdopted = false` / `networkRestored = 0` + one plain
  sentence on the restore page; catalogue restore never rolled back.
  `inspectArchive` surfaces `hasIdentity` for the restore-page copy.
- Fixtures in `test/features/backup/`: a Kotlin-era archive WITHOUT the
  entries and one WITH; tests per spec §7 S6 (flags default false +
  round-trip, invalid identity.json not adopted + reported, one corrupt
  network row ⇒ others restored + count).
- Docs: README › Backup honest-limit sentence (ID + network list travel in
  the clear), PRIVACY.md line.

### Docs sweep (§9) — owed for S2/S3 already

- **PRIVACY.md**: published location opt-in with precision choice (S2);
  fetching `library.json` from saved sites only on Refresh (S4); OSM tiles
  while the map is open after consent (S5); archive carries library ID +
  network list in the clear (S6).
- **README.md**: Features bullet (Library network), Privacy posture, Backup
  honest limit, dependency list if it names packages (S5).
- **appDetails.md**: §2 feature list, §3 architecture map (`features/network/`),
  §9 decisions (D3, D7, D9, D10, D11), §11 backlog (spec §10 deferred items),
  release sentinel string `LibraryFingerprint`, §7 Play Console Data-safety
  note (maintainer decision — record the answer).
- **CHANGELOG.md › Unreleased**: Added / Changed (bookmarks → network,
  schema v3, archive entries) / Security (fingerprint, bounds).
- fastlane changelog file: at release time only.

### Definition of done (spec §11 checklist, per slice)

analyze 0 issues (infos count) · format clean · build_runner no diff · full
suite green (`--exclude-tags golden` locally) · domain/layer fitness tests
green · §13 checklist · commit atomically (hook!) · docs of §9 in the same
slice.

---

## 5. Quick pointers into the new code

| What | Where |
|------|-------|
| Value objects | `lib/features/network/domain/value_objects/` (geo_point, library_fingerprint, network_name, library_card_payload) |
| Entities | `…/domain/entities/network_library.dart`, `…/library_descriptor.dart` |
| Codec (wire rules) | `…/domain/library_descriptor_codec.dart` |
| Ports | `…/domain/repositories/network_repository.dart`, `…/domain/descriptor_fetcher.dart` (+ `descriptor_fetch_result.dart`) |
| Use cases so far | `…/domain/usecases/add_member_use_case.dart`; `…/application/build_own_descriptor.dart` (pure fn) |
| Infra | `…/infrastructure/drift_network_repository.dart`, `…/bounded_descriptor_fetcher.dart` |
| Controllers | `…/application/my_library_card_controller.dart` |
| DI module | `lib/core/di/src/network_providers.dart` (exported from `lib/core/di/providers.dart`) |
| Shared fetcher | `lib/core/network/bounded_http_fetcher.dart` + `bounded_fetch_outcome.dart` |
| Pages/widgets | `…/presentation/pages/network_page.dart`, `add_member_page.dart`; `…/widgets/network_library_tile.dart`, `membership_badge.dart` |
| Table + migration | `lib/core/database/tables.dart` (`NetworkLibraries`), `app_database.dart` (v3), `drift_schemas/app_database/drift_schema_v3.json` |
| Test dirs | `test/features/network/{domain,application,infrastructure,presentation}/`, `test/core/network/`, `test/core/widgets/qr_scan_page_test.dart` |
