# Changelog

All notable engineering changes to Pitak are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions
follow the `pubspec.yaml` version (`x.y.z+N`).

This is the **developer** changelog — migrations, format changes, security
fixes, architecture work. User-facing blurbs (≤ 500 chars) live per
versionCode under `fastlane/metadata/android/en-US/changelogs/`.

The release script (`tool/release_build.sh`) refuses to build a version
that has no heading here, so `Unreleased` entries move under the version
heading as part of the `chore(release):` commit.

## [Unreleased]

### Added
- `tool/release_build.sh --sentinel '<ASCII text>'` is now **required**: the
  script extracts the bundle's arm64 `libapp.so` and refuses to pass if the
  sentinel is absent — the check that would have caught both stale-snapshot
  incidents (2026-09-03, 2026-10-18). Non-ASCII sentinels are rejected up
  front (Dart stores such literals as UTF-16, which a byte scan misses).
- `docs/ARCHITECTURE.md` — the app's shape in one place: product promises,
  layer rules and the tests that enforce them, module map, crypto chain, and
  every cross-device data contract (`library.json`, fingerprint, card QR,
  Drift schema rules, `.pitabak` entries, validation bounds).
- `docs/RELEASING.md` — the single release procedure: flavors and purity
  check, per-ABI versionCodes, signing, the stale-artefact trap, the script,
  the Play and F-Droid steps, toolchain pins, Play Console answers.

### Changed
- `README.md` keeps the front-door content (features, privacy posture,
  getting started, quality gates) and points at the two docs for the rest.
- Code comments that cited plan documents by item id (`architecture.md B3`,
  `libNetwork.md §5.9`, `SOLID-PLAN S4`) now carry either the reason inline
  or a pointer into `docs/ARCHITECTURE.md`.
- Fixed: the 1.5.1 heading said versionCode 26; the release is `+27`.

### Removed
- Finished plan documents whose durable content moved into the two docs
  above or already lived in ADRs: `architecture.md`, `SOLID-PLAN.md`,
  `PLAN.md`, `libNetwork.md`, `libNetwork-handoff.md`, `fdroid/README.md`,
  and the empty `rust_builder/README.md`.

## [1.5.1] - 2026-10 (tag `1.5.1`, versionCode 27)

### Added
- **Map pin labels** (design 2026-10-18): the own pin
  and every hub pin carry a permanent name label; any other pin shows its
  label only while selected (pin tap toggles the label, label tap opens the
  pin sheet; hub pins open it directly). "Hub" is derived from the rows —
  `membership != none` or another row's `listedByHubUrl` — not stored. New
  `map_pin_label.dart` widget + `hubSiteUrls`/`isHubRow` helpers.
- **"Confirmed by member" badge**: refresh records whether a hub-listed
  member's own `memberOf` links back to the listing hub (reciprocal consent
  — the hub's `members` entry is the claim, the link-back is the member's
  published agreement). Shown as a chip on list tiles and the map pin sheet
  via `MembershipBadge`.
- Home screen: a map button left of the scan icon opens the Library network
  screen straight on its Map tab (`NetworkPage(initialTab: 1)`).
- Network screen: an "Add bookmark" button beside "Add member" replaces the
  app-bar add-by-URL icon (same dialog and flow).

### Changed
- flutter_map marker anchoring corrected: pins use `Alignment.topCenter`
  (flutter_map's alignment is the marker's position RELATIVE TO the point),
  so pin tips now sit ON their coordinate — `bottomCenter` had floated them
  ~44 px below it.
- Map viewport fit padding is asymmetric (top 120, sides 80, bottom 48) so
  edge pins open with their 96 dp labels on-screen.

### Database
- Schema v4: `network_libraries.confirmed_by_member` (additive
  `INTEGER NOT NULL DEFAULT 0` via `m.addColumn`). The v3 `createTable`
  branch builds the table at its current shape, so the v3/v4 branches are
  `else if` — proven by the v1→current migration test. New snapshot
  `drift_schema_v4.json`, regenerated helpers, data-matrix row
  "v3: a network row survives; confirmed_by_member defaults to false".

## [1.5.0] - 2026-10 (tag `1.5.0`, versionCode 25)

### Added
- **Library network** (ADR 0012; contracts in `docs/ARCHITECTURE.md` §5): save other Pitak libraries
  by URL or by scanning their library card QR in person; distance-sorted
  list with membership/verification badges; user-initiated Refresh with
  bounded discovery (two expansions, 500-row cap) and cancel; pending
  membership confirmation with Reconsider; opt-in OpenStreetMap map tab
  (`flutter_map`, consent-gated `networkMapTilesConsent`, app User-Agent,
  HTTP-freshness tile cache, permanent attribution); own card QR with
  fingerprint fragment for hub add-member flows.
- Publish: `library.json` descriptor (fingerprint, name, site, optional
  location, members/memberOf) rides along in the publish commit; opt-in
  location sharing control (off / approximate ~1 km / exact) governs both
  the descriptor and the `index.html` GPS pin.
- Backup: `.pitabak` now carries `identity.json` (library ID + name) and
  `network.json` (saved-libraries list), announced by new
  `hasIdentity`/`hasNetwork` manifest flags (schema stays 1; both plain
  JSON — documented honest limit). Restore adopts the identity through the
  namespace port and replaces the network rows after the catalogue switch;
  adoption failures are reported, never rolled back.
- `LICENSE` (GPL-3.0-or-later) matching the F-Droid listing; `SECURITY.md`
  disclosure policy; `CONTRIBUTING.md` + PR template; `CHANGELOG.md`;
  `docs/adr/` architecture decision records.
- CI: Dependabot for pub/cargo/github-actions; all actions SHA-pinned; OSV
  scan of both lockfiles; `fdroid-purity` job (no Google deps in the fdroid
  classpath); `update-goldens` workflow (A2, B2).
- Rust gates: `cargo fmt --check`, `clippy -D warnings`, `cargo deny check`
  (replaces cargo-audit); `#![deny(unsafe_code)]` with three documented
  `sqlite3_key` exceptions; `rust-version = "1.96"` pin (A3).
- Tests: drift schema snapshots + verifier-backed migration tests with a
  per-version data matrix (A4); accessibility guideline checks on all 16
  page suites + 2× text-scaling smoke tests (A6); seeded property tests for
  parsers, the merge engine, and the vault blob crypto (B3); six golden
  tests for key screens (B2); an on-device vault smoke test run before each
  release (B1).
- Architecture fitness functions: presentation/application boundary,
  debug-only logging, bare-catch justification, and a file-size ratchet
  (B4, B8).

### Changed
- **Bookmarks replaced by the library network** (D8): the bookmarks feature
  is deleted; its saved links migrate one-time into the `network_libraries`
  table (schema **v3**, data-matrix row included) on first open — on-device
  only — and the prefs key is cleared. The drawer entry is now "Library
  network".
- All diagnostics route through `appLog` (debug builds only; release ships
  no logs to logcat) (B5).
- `tool/release_build.sh` refuses a release whose version has no CHANGELOG
  heading, and `--verify` refuses a release tag that is lightweight,
  unsigned, or not on `HEAD` (B7, B9).
- `lib/core/theme/app_theme.dart` is the single source of both themes;
  `main.dart`, the goldens and the dark-theme a11y tests all render it.
  Goldens use a phone viewport (1080×2400 @ 2.625).
- `AppDatabase` re-asserts the raw-SQL objects (unique indexes, FTS5,
  triggers) in `beforeOpen` on every open and rebuilds a missing FTS index;
  the migration tests prove search works after every upgrade path.
- `flutter_rust_bridge` Dart package pinned to exactly `2.12.0` (matches the
  crate); Dependabot ignores it on both ecosystems.

### Fixed (review of the architectureRefactor branch)
- CI `osv-scan` passed the reusable workflow fewer permissions than its job
  declares, so GitHub rejected the job — the lockfile scan never ran.
- CI `fdroid-purity` failed open: a Gradle failure produced no output and
  the gate printed "clean". It now captures the report, refuses an empty
  one, and self-tests by requiring a match on the `play` classpath.
- Property-test failure messages print a per-case seed that actually
  replays the failing case.
- Architecture gate now also forbids `application → infrastructure` imports
  and recognises multi-line empty catch blocks.

### Security
- Library identities cross devices as SHA-256 **fingerprints**; the raw
  library ID never appears in published files, cards, or logs (D3).
- All descriptor/card/archive input is validated at the boundary: §6 char
  rules for names (control/bidi rejection), the Pages-only URL allow-list
  with a new 2048-char cap, bounded fetches (15 s, 64 KiB, redirect
  re-validation per hop), discovery caps (D10).
- Identity conflicts (a fetched fingerprint that belongs to another saved
  row) are marked `identityConflict` and shown, never auto-merged (D12);
  refused fetches never erase cached data or demote a known conflict.

## [1.4.0] - 2026-10 (tag `1.4.0`, versionCode 24)

### Added
- Export: filter CSV/PDF exports by source type and source detail.
- Publish: the share-card share now carries the site URL as a tappable link.

### Changed
- Reproducible release builds: exact Flutter pin (`.fvmrc` + `pubspec.yaml`
  `flutter:` must match), verified release script, `.fvm/` ignored.
- Publish flow moved out of widget state into `GitHubConnectionController`;
  `GitHubApi` segregated into auth / repo-admin / git-data role interfaces.
- Vault session controller delegates secret lifetime and operation
  serialization to extracted collaborators (`VaultSecretKeeper`,
  `SerialOpQueue`).
- Dependency injection reorganised into `lib/core/di/src/` per-feature
  provider files; `providers.dart` is now a barrel.

### Fixed
- Publish fails closed when the target-repo write throws in
  `createRepo`/`selectRepo`.

### Security
- `Book.validate` ingress gate pinned by an architecture test; all of `lib/`
  scanned for construction sites.
