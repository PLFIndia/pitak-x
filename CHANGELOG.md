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

## [1.6.0] - 2026-10 (tag `1.6.0`, versionCode 29)

G1 Linux goldens and N3 device journeys completed; final remediation golden,
device, upgrade and timezone verification completed (S11) at `5351034`.

Release sentinel (`tool/release_build.sh --sentinel`): `New magazine title`.

AAB sha256: `58e64873c2109dd053f22a4428335fd5d455a1b5f120dee3236fe8a89926a633`.

### Added
- **Catalogue item kinds** (ADR 0013): every catalogue row has a `kind` —
  `book`, `magazine-issue` or `other` — defined by the app, never by users.
  One base row per physical thing, one lendable unit (the vault is
  untouched — F2), one list, one search index for every kind; kind-specific
  data lives in a per-kind detail table. Domain: `ItemKind`, sealed
  `ItemDetails` (`IssueOf`, `OtherItemOf`), `CatalogueItem.details`/`kind`
  (kind is derived, so the two cannot disagree); the kind cannot change
  after creation (`UpdateIssueUseCase`, D8).
- **Magazines** (`features/periodicals/`): magazine titles (`Periodical`:
  ISSN with mod-11 check digit, frequency, optional subscription window with
  a derived status — untracked / active / expiring within 30 days / lapsed,
  re-stamped once a minute while a list is open), issues as base rows with a
  `magazine_issues` detail row, grouped under their title and lent
  individually; bound volumes as one row with a date range (D4). Title,
  transliteration, publisher, language, year and age group of an issue are
  PROJECTED from the series (`IssueProjection`); editing the series
  re-projects every issue in one transaction. Issue identity for dedup and
  merge: uid → numbered key / bound key → fuzzy title (D6; two partial
  unique indexes). Hard-deleting a title with issues fails closed
  (`PeriodicalHasIssuesFailure`).
- Screens: a **Magazines** page from the drawer (issue count, latest issue,
  subscription badge), a series detail page (subscription card, paged
  issues newest-first, "Add issue", hard delete), the magazine-title form
  and the add-issue form (series picker, bound-volume switch, cadence
  prefill from the latest issue, live title preview), an issue block on the
  item detail page with "Open series". A magazine barcode (`977…`, D11) routes
  through `RouteScannedBarcodeUseCase` (sealed `ScanRoute`) to Add Issue for an
  active existing series, the existing detail/restore flow for a removed
  series (`OpenPeriodical`), or the title form with the ISSN filled in when the
  series is unknown.
- **Magazine remove/restore (N1):** the series overflow offers **Remove from
  library** and **Restore to library** without changing its issues. The hard
  delete refusal now correctly says to delete remaining issues first or mark
  the title as removed; soft-removed issues still count toward that guard.
- **Others:** a built-in catch-all kind (a DVD, a board game, a map) with a
  Description field — the existing notes column, which is now searchable
  (FTS gains `notes`, D10). No kind-specific fields or table (O1); saved
  through the generic catalogue use cases (O3).
- Library screen: kind chips (Books · Magazines · Others; tap again clears),
  a "+" sheet with one entry per kind, row and grid-card badges for issues,
  bound volumes and others; issues without a cover show the series cover
  (W4; the cover janitor counts series covers as live references).
- **Merge** understands v4 files: periodicals are merged first (UID →
  canonical ISSN → exact title, add-only; title fallback is suppressed when
  both sides have valid, different ISSNs), incoming issues are re-anchored to
  the winning series, issue identity (D6) drives matching, and merged series'
  issues are
  re-projected after the apply. Take-theirs is refused across kinds (D8);
  keep-both keeps the row's kind; overwrite replaces and reprojects series too.
- **Guides:** a sixth "How Pitak works" guide, *Books, magazines and other
  items*, first in the index, ending on the Magazines screen.
- `integration_test/catalogue_kinds_smoke_test.dart` (magazine title →
  issue → other item → lend the issue → backup → restore) beside the vault
  smoke, over shared `integration_test/smoke_support.dart`.
- `docs/adr/0013-catalogue-item-kinds.md`,
  `docs/adr/0014-catalogue-interchange-and-backup.md`; ARCHITECTURE §3,
  §5.4, §5.5, §5.7 and §6 describe the kinds, the unreleased v5–v7 schema
  history and the three formats.

### Changed
- **Schema v5 (unreleased feature origin; current schema is v7)**
  (`lib/core/database/app_database.dart`): `books.kind`
  (default `'book'`), new `magazine_issues` (FK cascade to `books`;
  `PRAGMA foreign_keys = ON` — the first real FK in the schema) and
  `periodicals` tables; raw-SQL partial UNIQUE indexes for the issue keys;
  the FTS index is dropped on upgrade and rebuilt once in `beforeOpen` with
  `notes` added to its columns (timed: 5 000 rows well under a second).
- **Schema v6** (remediation S1) canonicalizes periodical/issue soft-link UIDs
  with one surrounding-whitespace-only trim rule. Its atomic repair precomputes
  canonical UIDs/final D6 keys and refuses collisions before writing instead of
  silently merging series; external non-ASCII identities remain supported.
- **Schema v7** (remediation S2) gives issue/subscription dates calendar-day
  semantics at 00:00 UTC through the shared pure-Dart `CalendarDate` rule.
  Titles, years, cadence and subscription status are timezone/DST-stable; a
  subscription remains `expiringSoon` throughout its stated end date and
  becomes `lapsed` the next local day. Legacy conversion is idempotent and
  preflights D6 collisions; restore and overwrite immediately reproject every
  series.
  Added/removed/loan/export timestamps remain instants.
- **Pitaka-JSON schema 3 → 4** (W1): per-row `kind` + nested `issue{}`,
  top-level `periodicals[]` (omitted when empty). Older builds refuse a v4
  file ("update the app"); v3 remains accepted with absent kind defaulting to
  book, subject to the cross-kind UID refusal below. Unknown kinds are skipped
  and counted; an issue whose series is not in the file imports as a book
  with a warning. Same-UID series merge in place without blindly clearing
  covers/metadata; same-canonical-ISSN series under another UID reconcile to
  the stored row. Issues re-anchor to the winning series, and every updated
  series is reprojected last. Export and import require the periodical
  repository — a read failure fails the export (no partial file).
- **`books.json`** (publish, W3) stays schema 1 and gains additive `kind` /
  `issue{}` per entry and `periodicals[]` with public fields only (the
  subscription window, notes, location and source never leave the device);
  the bundled viewer (v7) gets a kind facet and groups issues under their
  title. Series covers upload once under `periodical:<uid>`-keyed paths; a
  publish is refused when the periodicals cannot be read (no partial site).
- **`.pitabak`** (W2): `books.db` keeps its Room shape and holds every kind;
  two new plain entries, `item_kinds.json` (`hasItemKinds`) and
  `periodicals.json` (`hasPeriodicals`), announced by manifest flags that
  default to false. Flag-less archives restore exactly as before for books,
  wishlist, covers, identity and network — and the restore now also clears
  the kind tables, so a flag-less archive honestly restores plain books.
  `RestoreSummary` reports kinds applied, periodicals restored, issues
  linked / detached, rows skipped for an unknown kind, periodicals dropped,
  and unreadable kind entries. A backup fails when the periodicals cannot
  be read (no partial snapshot).
- CSV export gains `Kind`, `Series`, `Volume`, `Issue`, `Issue date`,
  `Bound until`, `Issue label` columns after the classic ones.
- `CatalogueItem.validate` and `Periodical.validate` are the two ingress
  gates; `test/architecture/catalogue_item_validation_gate_test.dart` scans
  every construction site of both (AGENTS §3.3).
- **Display versus interchange reads** (remediation S1): paged Library mapping
  and the vault/cover-janitor reads retain fail-soft behavior. Export, backup,
  publish and merge use `getAllForInterchange()`, which refuses an unknown
  stored kind or a known issue missing its detail row instead of serializing it
  as a book. Detail-less issue write-back also fails before mutation.
- **Rename (no behaviour change):** `Book` → `CatalogueItem`, `bookUid` →
  `itemUid`, `BookSourceType` → `ItemSourceType`, `BookSort` → `LibrarySort`,
  `BookRepository` → `CatalogueItemRepository` (+ Drift impl, mapper, use
  cases, providers), `BookPage`/`BookSorter`/`BookRow` widget/`BookGridCard`/
  `BookCover`/`BookDetailPage` → `CatalogueItem…` / `ItemCover`,
  `LendDecision.forBook` → `forItem`, `Loan.bookId` → `itemId`,
  `PublishBook` → `PublishItem`, `ImportPayload.books` → `items`. Every
  persisted and wire name (`books`, `book_uid`, `bookUid`, `book_id`,
  `books.db`, `books.json`) is unchanged.
- File-size ratchet: `drift_catalogue_item_repository.dart`,
  `catalogue_item_detail_page.dart`, `library_merge_engine.dart`,
  `merge_page.dart` and `restore_backup.dart` were split under the 500-line
  cap and left the allow-list (`layer_boundaries_test.dart`).

### Fixed
- `integration_test/vault_smoke_test.dart` could not pass as written: it
  looked for a `Title` field and a `Save` button the book form does not have
  (`Title *` / `Add book`), and opened the drawer from the item detail page,
  which has none. Rewritten over the shared helpers, which also scroll to
  below-the-fold buttons (a form's lazy list does not build them) and
  tolerate a vault created by a sibling smoke file in the same run.
- **Atomic issue writes and removed-series scans** (remediation S3): series
  lookup/projection, stored-row validation, D6 pre-check and issue write now
  commit in one transaction. New issues under a removed series fail before
  writing; historical issue edits remain allowed, and a removed ISSN scan opens
  the existing series detail/restore flow instead of the add-issue form.
- **Import reconciliation and D6 integrity** (remediation S4): same-ISSN /
  different-UID imports keep their issues linked to the stored series; same-UID
  imports preserve local identity and reproject every issue. Same-UID
  cross-kind updates refuse the import and roll back without deleting the
  original kind/details. D6 duplicates between different item UIDs are skipped
  and counted after re-anchoring, including earlier claims in the same file;
  repeated same-UID, same-kind rows update instead. Trim-created UID ambiguity
  is file-level fatal: plain import refuses before catalogue reads/writes, and
  merge refuses before namespace/planning/repository IO.
- **Lossless bundles and bounded backups** (remediation S5): v4 ZIP import keeps
  periodicals, wishlist and warnings, validates series collections/covers, and
  stages shared cover leaves once. The writer checks both W2 entries against
  the reader's byte/row caps before scratch-directory, SQLite, or ZIP creation
  and returns a safe `BackupTooLargeFailure` (“This catalogue is too large for
  this backup format. Nothing was exported.”) rather than creating an
  unreadable archive. Restore reports raw dropped issue entries separately from
  unique detached item rows.
- **Distinct-ISSN merge identity** (remediation S6): exact-title fallback no
  longer conflates series when both sides have valid, different ISSNs; their
  issues remain attached to the correct series after apply.
- **Cover ownership and async form safety** (remediation S7): scheduler dedup
  uses structural `(owner, URL)` identity, remote series covers materialize on
  the series rather than an issue displaying its fallback, and issue detail
  uses the same own-then-series rule as lists and publish. Materialization
  re-reads immediately before writing so mid-download edits survive. Forms
  preserve untouched current covers, block Save during cover work, and reject
  stale Add Issue prefill responses after series changes or user input.
- **Publish redaction and linkage** (remediation S8): an Other allows exactly
  `title`, `kind`, resolved `coverUrl`, `language` and `ageGroup` (null
  optionals omitted), never availability or book/private data. Cover IDs
  use SHA-256(salt + UTF-8(key)), truncated to 16 lowercase hex characters, so
  canonical non-ASCII series UIDs no longer abort publish. Missing, duplicate,
  noncanonical or unresolved series links fail safely before cover IO or
  artifact creation; removed-series cover fallback remains available to live
  issues.
- **Magazine and Library UI correctness** (remediation S9): import, merge,
  restore and real issue hard-delete immediately refresh a kept-alive
  Magazines list. Filtered-empty results say “No items match these filters.”
  with independent Clear search / Clear filters recovery; Add/Import appears
  only for a genuinely empty unfiltered library. Generic detail, scan,
  remove/delete, lending, missing-row, error and native fallback copy uses
  Item/item (including `Item #id`), while book-specific and wishlist wording
  remains unchanged.
- **Actionable newer-artifact refusal** (verification S11): plain JSON and v4
  ZIP files from a newer Pitak schema return a typed refusal with “Update the
  app before importing”, including malformed newer bundles. They can no longer
  fall through to a false Import complete or an unexplained generic corrupt-file
  message. The Fastlane character check is now a checked-in tool with CI coverage
  for Unicode text, the exact 500-character boundary, over-limit input, and
  incomplete or unexpected file sets.

### Security
- Updated Tokio 1.52.3 → **1.54.1** for **RUSTSEC-2026-0386** (`372ad3b`).
  No Rust source changed in that commit; Rust format, clippy,
  dependency/advisory checks and release tests passed, followed by green PR
  OSV and Rust-core checks at `372ad3b`. S11 re-scanned the remediation HEAD
  in CI (run `40185782934`).

### Removed
- `FindByIsbnUseCase`, `findByIsbnUseCaseProvider` and the library page's
  `routeScannedIsbn` — superseded by `RouteScannedBarcodeUseCase`.

## [1.5.2] - 2026-10 (tag `1.5.2`, versionCode 28)

Release sentinel (`tool/release_build.sh --sentinel`): `How Pitak works`.

### Added
- **How Pitak works** — five short in-app guides (publish, map,
  backup/restore/export/import, vault & lending, hubs & members) from the
  drawer; each ends with a button to the screen it describes. The copy is a
  typed, pure-Dart model (`features/guides/domain/`) with its invariants
  under test. Settings can now be opened on a given tab
  (`SettingsPage.initialTab`, `SettingsTab`), mirroring `PublishTab`.
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
- Restore copy: the library logo is **not** restored (the setting that marks
  a cover file as the logo is not in a `.pitabak`; `RestoreController`
  clears a dangling reference). Restore said covers "including the library
  logo" are replaced; it now lists the logo with the other things a restore
  does not bring back, matching the Create-backup page and the backup guide.
- `settings_page.dart` left the file-size-ratchet allow-list: the community
  library section (Show / Scan library QR, Start a new library) moved to
  `widgets/community_library_section.dart` unchanged.

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
