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

## [1.5.0] - 2026-10 (tag `1.5.0`, versionCode 25)

### Added
- **Library network** (libNetwork.md, ADR 0012): save other Pitak libraries
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
  `docs/adr/` architecture decision records (architecture.md Phase 0).
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
