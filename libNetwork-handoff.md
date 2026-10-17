# libNetwork implementation — handoff (S1–S4 done, S5–S6 + docs remaining)

> **For the next session's agent.** This file is the bridge between what is
> already implemented on branch `libNetwork` and what remains. The spec
> (`libNetwork.md`) is still the authority; `AGENTS.md` still wins over it.
> Read §7 S5–S6 of the spec first — this handoff only records STATE, the
> decisions already made in code, and the gotchas that cost time.
>
> Rewritten 2026-10-17 after committing S4 (supersedes the S1–S3 handoff).

---

## 1. Where the branch stands

Branch `libNetwork` (from `main` @ 80b8e89). Commits, oldest first:

| Commit | Slice | Content |
|--------|-------|---------|
| 88796f5 | — | the spec itself (`libNetwork.md`) |
| 70e5382…ce786b3 (6 commits) | **S1** | GeoPoint+LocationPrecision, LibraryFingerprint, NetworkName, `BoundedHttpFetcher`+`BoundedFetchOutcome` in `lib/core/network/` (BoundedCoverFetcher is an adapter), `AppUserAgent`, generic `QrScanPage<T>`, ADR 0012 + index row |
| 968344e | **S2** | `LocationSharing` setting + first-read rule, sharing-gated GPS pin, descriptor entities + `LibraryDescriptorCodec` (§3.1 complete), `BuildOwnDescriptor`, `PublishLibraryUseCase.call(libraryJson:)` with sha-skip + `deletePaths`, Basic-info segmented control |
| e447f49 | **S3** | `network_libraries` table (schema **v3**, snapshot + helpers + matrix row), `NetworkLibrary` entity, `NetworkRepository` port, `DriftNetworkRepository`, `LibraryCard`+`LibraryCardPayload` (§3.2), `AddMemberUseCase` (§5.7), `BoundedDescriptorFetcher`, `MyLibraryCardController`, `NetworkPage` (Libraries + My card tabs), `AddMemberPage`, tiles/badges, drawer renamed, share-card QR = card payload, publish fills `members` |
| 55ec411 | — | the previous handoff file |
| 46845bc | **S4** | `NetworkDiscoveryPlan` (D10), `RefreshNetworkUseCase`+`RefreshReport` (§5.6), `ConfirmMembershipUseCase`, `LegacyBookmarksReader`+`MigrateLegacyBookmarksUseCase` (D8 — bookmarks feature DELETED, `BookmarkUrl` moved to network domain + gained the §6 2048-char cap), `NetworkController`(`NetworkWindow`) + keepAlive `NetworkRefreshController` (replaces `networkRowsProvider`), Libraries tab: distance sort / stamp+summary / pull-to-refresh + Refresh/Cancel / inline membership prompt + Reconsider / add-by-URL dialog, publish fills `memberOf` from confirmed rows |

**Gate status at 46845bc:** `fvm flutter analyze lib test` → No issues;
`fvm dart format --set-exit-if-changed lib test` → clean;
`fvm flutter test --exclude-tags golden` → **2185 tests, all green**;
build_runner → no uncommitted diffs (pre-commit hook verified). The 6
golden tests fail locally on macOS by design (Linux is the reference
renderer, `dart_test.yaml`); S4 changed nothing the goldens render
(LibraryPage / VaultPage / PublishPage-connection-tab / RestorePage) —
S5 WILL add a golden (`NetworkLibraryTile` + badges) that must be generated
on Linux via the `update-goldens` workflow.

**NOT done yet:** S5 (map), S6 (backup), and the §9 docs sweep — **the docs
for S2, S3 AND S4 are all still unwritten** (PRIVACY.md, README, appDetails,
CHANGELOG). Do them with S5/S6 or as one docs commit before merging.

---

## 2. Environment / tooling facts (verified, don't rediscover)

- Use `fvm flutter` / `fvm dart` (Flutter **3.44.2** pinned in `.fvmrc`;
  bare `dart` on PATH is a different SDK and `pub get` fails the pin).
- Local test command: `fvm flutter test --exclude-tags golden`
  (macOS renderer ≠ Linux golden reference; see `dart_test.yaml`).
- Pre-commit hook (`.githooks`, `core.hooksPath` is set) reruns build_runner
  and **refuses commits while regenerated `.g.dart` files are unstaged**.
  Riverpod embeds a hash of each annotated class body, so touching e.g.
  `network_controller.dart` dirties its `.g.dart`. Consequence: **commit a
  slice atomically** (S2, S3, S4 are single commits) unless the commit
  touches no codegen inputs (S1 was 6 commits). `dart format` also dirties
  `.g.dart` hashes — always run format → build_runner → stage → commit.
- Schema bumps: NOT needed for S5/S6 (no table changes). Procedure (if ever):
  `fvm dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/`
  then `fvm dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/`,
  then a data-matrix row in `test/core/database/migration_test.dart`.
- File-size ratchet (`test/architecture/layer_boundaries_test.dart`):
  unchanged records (settings_page 690 etc.). All S4 files are < 500 lines
  (`refresh_network_use_case.dart` 404 is the biggest; `network_page.dart`
  337 after extracting `add_library_dialog.dart` + `network_refresh_bar.dart`
  into `presentation/widgets/` — keep splitting rather than allow-listing).
- Const gotcha (verified empirically): a nested constructor call inside a
  `const` constructor's initializer list **cannot forward formal parameters**
  and cannot be implicit-const — that's why `BoundedCoverFetcher` and
  `BoundedDescriptorFetcher` have non-const constructors (documented in code).
  Static tear-offs (`LibraryQrPayload.parse`, `BookmarkUrl.normalize`) ARE
  valid constant expressions.
- Lint landmines that bit (very_good_analysis; infos count as failures):
  `comment_references` in `library;` docs can't see class members (qualify
  `[Class.member]` or use backticks); `avoid_equals_and_hash_code_on_mutable_classes`
  — domain can't import `package:meta`, so entities use **`sameAs()` instead
  of `==`** (GeoPoint, NetworkLibrary); `avoid_catching_errors`; SQL string
  literals in tests → `db.customUpdate(..., variables: [Variable(...)])`;
  `avoid_redundant_argument_values` fires on `source: NetworkSource.bookmark`
  (the entity default) and on helper params whose default equals the callee's;
  local `get x =>` declarations are illegal inside function bodies (use a
  function); a Row of two M3 buttons + labels overflows 288 px — use `Wrap`.
- Domain import allow-list (`test/architecture/domain_purity_test.dart`):
  pure dart libs + `fpdart`, `crypto`, `archive` + `features/*/domain/` +
  `core/error/`, `core/text/`, `core/crypto/secret_bytes.dart`. The bookmarks
  feature is GONE; `BookmarkUrl` now lives at
  `lib/features/network/domain/value_objects/bookmark_url.dart`.
- Riverpod testing: autoDispose AsyncNotifier providers read via
  `container.read(xProvider.future)` can be **disposed mid-build** when the
  build has several awaits — keep a listener: `container.listen(xProvider,
  (_, _) {})` (pattern in `my_library_card_controller_test.dart` and both
  new S4 controller tests). ALSO: a `container.listen` in `setUp` fires the
  first build immediately — seeding a fake repo AFTER that leaves the first
  window stale; seed before building the container or `invalidate` first.
- Widget tests: never render `ReaderWidget` (camera). `QrScanPage.buildScanner`
  and `AddMemberPage.scanner` are the injected fake-scanner seams. Tall
  `tester.view.physicalSize` for full pages. a11y trio:
  `test/support/a11y.dart` → `expectMeetsA11yGuidelines`. **Disabled Material
  controls fail textContrast** — keep read-only value rows / enabled buttons.
  Page tests that can trigger a Refresh must override
  `descriptorFetcherProvider` (else the real `httpClientProvider` is built).

---

## 3. Decisions made during S4 implementation (respect or revisit consciously)

- **Controller topology (one direction, no import cycle):**
  `NetworkController.build()` registers `ref.listen(networkRefreshControllerProvider)`
  and `invalidateSelf()`s on the running→settled transition; the refresh
  controller knows nothing about the window controller. Report + stamp live
  in the keepAlive `NetworkRefreshController` (fields `lastReport` /
  `lastFinishedAt`), so they survive navigation and provider rebuilds.
- **Stamp semantics:** `_lastFinishedAt` updates only when the run returned
  Right (a cancelled run DID talk to the network and applied partials, so it
  stamps); a storage failure keeps the old stamp and surfaces as AsyncError
  ("Refresh failed — showing your saved list." inline in `NetworkRefreshBar`).
- **Discovery depth model (D10 reading):** `PlannedRow.depth` — seeds 0;
  rows discovered from a descriptor are depth+1; **leaves (members-list
  discoveries) NEVER expand** (§5.6: "their members/memberOf are not
  expanded"); nothing expands at depth ≥ `maxExpansionDepth` (2). So:
  seed→memberOf hub→members = 2 expansions; a third never happens. Hubs
  discovered at depth 2 are fetched but terminal. Caps: `maxRowsPerRun` 500
  (constructor-injectable `maxRows` for tests), truncation reported.
- **Fingerprint ownership registry (D12):** `_fpOwners` maps fingerprint →
  siteUrl, preloaded from stored rows, extended by member-entry HINTS at
  discovery time (`putIfAbsent` — an existing owner wins) and by fetched
  descriptors. First-writer-wins; the loser gets `identityConflict` and
  NOTHING else updates (no name/location/fetchedAt/membership changes).
  Test-data gotcha: never give a member entry the same fingerprint as the
  listing hub — the hub then cross-row-conflicts with its own member.
- **Refusals never erase cached data** (offline keeps pins/names/`fetchedAt`)
  and **never demote an existing `identityConflict`** (a failed fetch can't
  make a known identity problem invisible — fail closed; commented in
  `_applyRefusal`).
- **RefreshReport** carries `noLongerListed: List<String>` (siteUrls of
  confirmed hubs that dropped me) in addition to the spec's field list —
  §5.6 step 4 demanded a flag; this shape was chosen for a plain-words UI
  summary. `RefreshBar.reportSummary` renders counts only, never URLs.
- **Discovered rows are inserted even when their own fetch was refused** —
  the hub vouched for them; the member-entry hints (name re-validated
  through `NetworkName`, fingerprint) survive on the row and the conflict
  check runs on the NEXT successful fetch.
- **`memberVerified` on refresh** = `isMember && storedFp != null &&
  storedFp == descriptor.fingerprint` — a fetch merely SUPPLYING a
  fingerprint to a previously fp-less member row does not verify it
  (verification means "published == scanned").
- **Migration:** inserts go through `applyRefresh(const [], rows)` (the
  port's one-transaction insert path — no port widening); labels failing the
  §6 character rules degrade to `''` (the row still migrates); the prefs key
  is cleared after commit AND in the no-op paths (absent/corrupt/all-present)
  so a corrupt value can't linger; a clear failure returns Left (next run
  retries harmlessly). `migrateLegacyBookmarksProvider` builds its OWN
  `DriftNetworkRepository` (watching `networkRepositoryProvider` would be a
  cycle) and THROWS `StateError` on Left (providers signal failure by
  throwing; `only_throw_errors` allows Error subclasses) — fail closed:
  screens show their safe error state rather than a half-migrated table.
- **Add-by-URL** returns `NetworkAddOutcome {added, alreadySaved, invalidUrl,
  storageFailed}` (enum, not bool — the UI maps each to one plain sentence).
  An already-saved URL collapses (`alreadySaved`), never duplicates (D13).
- **Membership UX is inline in the tile**, not a dialog: `pending` shows the
  prompt ("'X' lists you as a member. Show that you're a member of it?" with
  Not now / Show membership inside a `Wrap`), `declined` shows a quiet
  "Reconsider" TextButton → back to `pending`. `ConfirmMembershipUseCase`
  refuses `MembershipState.none` (a user action must never erase the signal).
- **D7 mapping has ONE home:** `BuildOwnDescriptor.ownLocation(sharing:, gps:)`
  — used by `build()` AND by the Libraries-tab distance sort. The list NEVER
  reads a device location (D6). Sort: pinned rows nearest-first (title
  tie-break — `List.sort` is not stable), then pin-less rows by name; with no
  own pin, everything by name; display title falls back to the siteUrl.
  NOTE: this display sort overrides the repository's sortOrder ordering on
  screen; `sortOrder` still governs storage order and migration sequence.
- **`BookmarkUrl` gained `maxLength = 2048`** (§6 bounds table demanded it;
  the class carried over from bookmarks without it).
- **Publish `memberOf`** = rows with `membership == confirmed` only —
  pending/declined never publish (a membership is public only by explicit
  choice). `publish_controller_test.dart` covers all three states.
- **`networkRowsProvider` is deleted.** Anything that watched it (only
  `network_page.dart` did) watches `networkControllerProvider` now; screens
  no longer call the repository directly.

---

## 4. Remaining work, concretely

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
- Map tab in `NetworkPage` (third tab — the page is 337 lines, extract the
  tab body to its own widget file if it grows past ~450) opening
  `network_map_page.dart` ONLY after consent (`TilesConsentDialog`: plain
  words, Accept persists via the controller setter, Decline returns to the
  list); `OsmAttribution` permanently visible bottom-right →
  `https://www.openstreetmap.org/copyright` via url_launcher external mode;
  initial viewport = bounds of pins / own pin / world; pin tap ⇒ bottom
  sheet (name, `MembershipBadge`, distance from own pin via
  `GeoPoint.distanceKm`, Open site, Directions
  `geo:<lat>,<lng>?q=<lat>,<lng>(<name>)`).
  Reuse from S4: own pin = `BuildOwnDescriptor.ownLocation(...)` over
  `settingsControllerProvider` (the Libraries tab shows the exact pattern);
  rows come from `networkControllerProvider` (`window.rows`).
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
  NOTE: after restore, anything showing network rows must re-read —
  `NetworkController` rebuilds via `networkRepositoryProvider`; if the
  restore switches the data generation, `appDatabaseProvider` already
  rebuilds everything downstream (verify in the restore controller test).
- Fixtures in `test/features/backup/`: a Kotlin-era archive WITHOUT the
  entries and one WITH; tests per spec §7 S6 (flags default false +
  round-trip, invalid identity.json not adopted + reported, one corrupt
  network row ⇒ others restored + count).
- Docs: README › Backup honest-limit sentence (ID + network list travel in
  the clear), PRIVACY.md line.

### Docs sweep (§9) — owed for S2/S3/S4 already

- **PRIVACY.md**: published location opt-in with precision choice (S2);
  fetching `library.json` from saved sites only on Refresh (S4 — shipped,
  unwritten); one-time bookmarks migration mentions nothing leaves the
  device (S4); OSM tiles while the map is open after consent (S5); archive
  carries library ID + network list in the clear (S6).
- **README.md**: Features bullet (Library network — bookmarks replaced),
  Privacy posture, Backup honest limit, dependency list if it names packages
  (S5).
- **appDetails.md**: §2 feature list, §3 architecture map
  (`features/network/`, bookmarks gone), §9 decisions (D3, D7, D9, D10,
  D11), §11 backlog (spec §10 deferred items), release sentinel string
  `LibraryFingerprint`, §7 Play Console Data-safety note (maintainer
  decision — record the answer).
- **CHANGELOG.md › Unreleased**: Added / Changed (bookmarks → network with
  automatic migration, schema v3, archive entries) / Security (fingerprint,
  bounds, D12 conflict handling).
- fastlane changelog file: at release time only.

### Definition of done (spec §11 checklist, per slice)

analyze 0 issues (infos count) · format clean · build_runner no diff · full
suite green (`--exclude-tags golden` locally) · domain/layer fitness tests
green · §13 checklist · commit atomically (hook!) · docs of §9 in the same
slice (or the agreed single pre-merge docs commit — currently owed).

---

## 5. Quick pointers into the code

| What | Where |
|------|-------|
| Value objects | `lib/features/network/domain/value_objects/` (geo_point, library_fingerprint, network_name, library_card_payload, **bookmark_url** ← moved here in S4) |
| Entities | `…/domain/entities/network_library.dart`, `…/library_descriptor.dart` |
| Codec (wire rules) | `…/domain/library_descriptor_codec.dart` |
| Discovery planner (D10) | `…/domain/network_discovery_plan.dart` (`PlannedRow`, `DiscoveryRole`) |
| Ports | `…/domain/repositories/network_repository.dart`, `…/domain/descriptor_fetcher.dart` (+ `descriptor_fetch_result.dart`) |
| Use cases | `…/domain/usecases/` (add_member, refresh_network + `RefreshReport`, confirm_membership, migrate_legacy_bookmarks + `LegacyBookmark` typedef) |
| Application | `…/application/build_own_descriptor.dart` (pure fn + **`ownLocation` D7 mapping**), `my_library_card_controller.dart`, **`network_controller.dart`** (`NetworkWindow`, `NetworkAddOutcome`), **`network_refresh_controller.dart`** (keepAlive, `RefreshCancelFlag`) |
| Infra | `…/infrastructure/drift_network_repository.dart`, `bounded_descriptor_fetcher.dart`, **`legacy_bookmarks_reader.dart`** (owns prefs key `library_bookmarks`) |
| DI module | `lib/core/di/src/network_providers.dart` (migration → repository → use cases; exported from `lib/core/di/providers.dart`) |
| Shared fetcher | `lib/core/network/bounded_http_fetcher.dart` + `bounded_fetch_outcome.dart` |
| Pages/widgets | `…/presentation/pages/network_page.dart` (+ `sortRowsForDisplay`), `add_member_page.dart`; `…/widgets/network_library_tile.dart` (inline membership prompt), `membership_badge.dart`, **`network_refresh_bar.dart`** (stamp/summary/Refresh/Cancel), **`add_library_dialog.dart`** |
| Publish wiring | `lib/features/publish/application/publish_controller.dart` (members + memberOf from confirmed rows) |
| Table + migration | `lib/core/database/tables.dart` (`NetworkLibraries`), `app_database.dart` (v3), `drift_schemas/app_database/drift_schema_v3.json` |
| Test dirs | `test/features/network/{domain,application,infrastructure,presentation}/`, `test/core/network/`, `test/core/di/network_providers_test.dart` (migration DI wiring), `test/core/widgets/qr_scan_page_test.dart` |

**S5's first edits touch:** `pubspec.yaml`, `app_settings.dart`,
`settings_repository.dart`, `prefs_settings_repository.dart`,
`settings_controller.dart`, the 6 settings-fake test files (list above),
`network_page.dart` (third tab), new `network_map_page.dart` /
`tiles_consent_dialog.dart` / `osm_attribution.dart` /
`osm_tile_provider.dart`.
