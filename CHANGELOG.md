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
- All diagnostics route through `appLog` (debug builds only; release ships
  no logs to logcat) (B5).
- `tool/release_build.sh` refuses a release whose version has no CHANGELOG
  heading, and `--verify` refuses a lightweight release tag (B7, B9).

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
