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

## [1.9.7] - 2026-11 (tag `1.9.7`, versionCode 39)

Release sentinel (`tool/release_build.sh --sentinel`):
`ask, but still let you lend`.

AAB sha256: `9f35237ce30ebfeece65844e07cb1d9a175242b0227c50e55e9d05a050bbbc6e`.
The 183-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT; 171.4 s in Gradle) passed
upload-signature (`pitak-upload`), package/version and fresh arm64
Dart-sentinel verification. Built from `main` at the release commit
`4e0e14c`; `pubspec.lock` was unchanged. Every 64-bit native `LOAD`
alignment was at least 16 KiB (`llvm-readelf -l`, NDK 28.2: `libapp.so`
and `libflutter.so` 0x10000, the rest 0x4000; `armeabi-v7a`
`libpitak_crypto.so` and `libsqlite3.so` remain 4 KiB, as §7 allows for
32-bit). `bundletool dump config` was not run on this machine (bundletool
not installed). Uploaded to Play Console by the maintainer on 2026-11-09.

### Changed
- **Availability tag colours (UI):** *Available* is green and *Not
  available* is red in the in-app viewer, the same pair the published site
  uses (`assets/publish/index.html`). Before, both tags shared one neutral
  container colour. One shared source,
  `lib/core/theme/availability_colors.dart`, with a contrast test pinning
  every pair at ≥ 4.5:1 on both themes.
- **Library catalogue cards fit their text (app only):** the list row's
  text now uses the full width beside the cover — a badge column used to
  take half the space even when empty, cutting long titles. Titles get up
  to 3 lines and authors up to 2. Below them, one line that wraps: the
  shelf location (bold), the Issue / Removed / Needs info pills and
  **Copies:** 2 · 1 out (the out count in red, only while the vault is
  unlocked; replaces "×2"). The library no longer shows a "Not available"
  pill: when every copy is out the shelf line turns red and its icon
  becomes an "out" tray (screen readers hear ", not available"); with no
  shelf set the line reads "Not available". Removed items are dimmed. On
  tablets the grid keeps its cover pills, covers keep a fixed book shape,
  and each cell's height is computed from the line caps at the user's
  font size, so long text never overflows. The published pages keep their
  Available / Not available tags; `location` is still never published.
- **Borrowers vault:** lending rules moved from an app-bar icon to an
  expandable card at the top of the unlocked borrower list; the card header
  always shows the rule in force ("Off", "Max 3 · Warn"). The Pending
  (bell) page was retired: overdue and due-soon loans live in Borrowed
  Items, and items needing info are already marked in the library list.
  The app bar keeps only Lock. The card and the borrowers share one scroll
  view, so a half-edited rule survives scrolling a long list.
- **Borrowed Items:** the message-template dropdown and the app-bar
  "Message templates" action were replaced by one expandable "Reminder
  message" card. Its header is the picker (one chip per template, plus
  Add); the body previews the selected template's three messages and, for
  custom templates, offers Edit / Duplicate / Delete. The separate Message
  templates page is gone; its "Reset to built-in" recovery lives in the
  card's error state. The card, filters and loans scroll as one page
  (`CustomScrollView`), so many templates or a short landscape screen can
  no longer overflow the layout.
- **How Pitak works:** the vault guide now points to Borrowed Items, the
  Reminder message card and the Lending rules card instead of the retired
  Pending page, and Return no longer goes through Edit; the wishlist guide
  gives the real path to **Look up ISBN after scanning** (Settings →
  Appearance → Library).

### Removed
- `PendingPage`, `pendingSnapshotProvider` and the `PendingSnapshot` domain
  helper (no remaining callers); `LendingRulesPage` and
  `ReminderTemplatesPage` (replaced by the cards above).

### Security
- **RUSTSEC-2026-0459 / CVE-2026-119375 (SQLite < 3.54.0, crafted `-wal`
  page size):** a reviewed, time-boxed exception until **2026-12-09**
  (`rust/osv-scanner.toml` `ignoreUntil` fails CI again on that date;
  mirrored in `rust/deny.toml`). The vault's SQLCipher bundles SQLite
  3.45.3; no crate release yet bundles SQLCipher on SQLite ≥ 3.54 (the
  scanner's suggested `libsqlite3-sys` 0.39 still ships SQLite 3.53.4 for
  SQLCipher builds, so it would hide the finding without fixing it;
  rusqlite PR #1932 is pending). Exposure needs a crafted database plus a
  sibling `-wal` from a less trusted party; restore never writes
  archive-supplied companion files, now pinned by a test. The Dart-side
  SQLite (3.52.0, end-of-life `sqlite3_flutter_libs`) is noted as a
  follow-up. Analysis: `docs/plans/sec-rustsec-2026-0459.md`.

### Tests
- New: `availability_colors_test`, `published_item_badges_test`,
  `shelf_location_line_test`, `lending_rules_card_test`,
  `reminder_template_card_test` (page tests ported case-for-case),
  `copies_label_test`, `catalogue_grid_delegate_test`.
- Regression (text fit): the row's title column is ≥ 75 % of the row (it
  was 41 %); a title and author that the old half width cut now fit their
  3 / 2 line caps; long everything at 1.0 / 1.3 / 2.0× text on a 320 dp
  phone and in the tablet grid never overflows, and the grid cover keeps
  its book shape; the grid's columns equal Flutter's own delegate at six
  widths; the copies label is readable (≥ 4.5:1) on the list surface and
  on its cover pill in both themes.
- Regression: Borrowed Items with the maximum 21 template chips on phone
  portrait, landscape (grid) and a small phone at 1.3× text, collapsed and
  expanded, with the loans still reachable; an unsaved lending-rule edit
  survives scrolling 60 borrowers away and back; each template chip is its
  own screen-reader node; the shelf line's removed tone.
- Goldens: the library, published-catalogue and vault-unlock PNGs (five
  files; the locked vault app bar no longer shows the Lending rules icon)
  are regenerated on the Linux reference renderer (`update_goldens.yml`);
  the library pair again after the text-fit change. The fixture gives one
  row a shelf location so the new line is pinned.

## [1.9.6] - 2026-11 (tag `1.9.6`, versionCode 38)

Release sentinel (`tool/release_build.sh --sentinel`):
`pausedForNoLibraries`.

AAB sha256: `90c7f5e601c7a8d1ae7b35266a25c6890115ed823a14a82e1fe4a21617c9b60e`.
The 199-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT; 186.6 s in Gradle) passed
upload-signature (`pitak-upload`), package/version and fresh arm64
Dart-sentinel verification. Built from `notifications` at HEAD `fee39f3`;
`pubspec.lock` was unchanged. Every 64-bit native `LOAD` alignment was at
least 16 KiB (`armeabi-v7a` `libpitak_crypto.so` and `libsqlite3.so` remain
4 KiB, as §7 allows for 32-bit); the bundle config enables uncompressed
native libraries with 16 KiB page alignment and `extractNativeLibs=false`.

### Added
- **Background event alerts (ADR 0024, Android only):** a WorkManager
  periodic job (about every 12 h, `NetworkType.connected`, battery-not-low)
  reads `events.json` of user-saved libraries (`bookmark`/`card` rows only,
  strict raw-token SQL) through a dedicated read-only `sqlite3` connection
  that peeks the active data generation and never opens Drift, and posts
  one grouped `flutter_local_notifications` alert per library (stable
  SHA-256-derived id, private lock-screen visibility, feature tag) plus a
  summary. Settings live in `events_watch_settings.json` (foreground-only
  writer; incarnation + epoch token) and worker bookkeeping in
  `events_watch_state.json` (worker-only writer through a serialized
  reducer); both bounded, strictly decoded and atomically replaced. First
  sight and every re-enable baseline quietly; `304`/`404`/partial/newer-
  schema reads withhold alerts; a blocked channel writes a revocation marker
  that only a foreground token change supersedes; an ON setting with no
  registered job requires explicit Resume, except when Pitak itself paused
  for having no saved library — saving one resumes checks automatically.
  Default ON is offered with an
  explanation on first use, never scheduled silently. Multi-line captions
  are folded to one line in the notification body. Requires core-library
  desugaring (`desugar_jdk_libs 2.1.4`); F-Droid classpath verified free of
  gms/play/firebase/mlkit. Debug builds add a "Run check now" action in
  Settings for device testing (absent from release builds).
- `DataGenerations.peekActive()` — side-effect-free generation resolver for
  background work; `CapacityFailure` in the sealed failure hierarchy.
- **Borrower lending limits (ADR 0023):** an optional 1–99 active-loan cap per
  borrower, off by default. Warn asks for named confirmation and retries the
  identical captured lend; Refuse has no override and rechecks the count inside
  the vault write FIFO. Lending rules are available even while locked, use a
  strict versioned preferences document with no borrower data, and fail closed
  with an editable recovery form if that document is unreadable.

## [1.9.5] - 2026-11 (tag `1.9.5`, versionCode 37)

Release sentinel (`tool/release_build.sh --sentinel`):
`PrepareLoanReminderUseCase`.

AAB sha256: `403dc6c3344dbfa3663db2c7e4ea38952fb5a9ba23d912a2697d11c5db3c5363`.
The 195-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT; 184.4 s in Gradle) passed
upload-signature, package/version and fresh arm64 Dart-sentinel
verification. Built from `reminders` at HEAD `6caf0ed`; `pubspec.lock`
was unchanged. Every 64-bit native `LOAD` alignment was at least 16 KiB
(`armeabi-v7a` `libpitak_crypto.so` and `libsqlite3.so` remain 4 KiB, as
§7 allows for 32-bit); native libraries are uncompressed and
`extractNativeLibs=false`.

### Added
- **Borrowed Items (vault):** a drawer destination that lists every active
  loan as a catalogue-style card (cover, title, borrower, due status, Call
  and WhatsApp actions) with All / Overdue / Due soon (72 hours) / No due
  date filters. The list is vault-gated — nothing is shown while the vault
  is locked — and viewing it never downloads a cover (`owner: null`).
- **Loan reminders:** one tap prepares a reminder message plus the item's
  local cover and hands both to the OS share sheet. The cover is read through
  the new `LocalCoverReader` (8 MiB source cap, metadata-stripped JPEG
  re-encode, no network); if it cannot be sanitized the app offers
  "Share text only" instead of falling back to raw bytes. The maintainer
  picks the conversation and sends; nothing is sent automatically and no
  reminder history is kept.
- **Message templates:** named reminder templates in any language with a
  selected default, stored as a versioned preferences document holding
  template text only (never rendered messages or borrower details). The
  editor warns not to include private details.

## [1.9.4] - 2026-11 (tag `1.9.4`, versionCode 36)

Release sentinel (`tool/release_build.sh --sentinel`):
`RestoreFromPublishedSiteUseCase`.

AAB sha256: `beb90691e779e58b577db6c537648de07e7bd43f166c993310006bd0920b2541`.
The 186-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT) passed upload-signature,
package/version and fresh arm64 Dart-sentinel verification. Built from
`remoteImport` at HEAD `655d810`; `pubspec.lock` was unchanged. Every 64-bit
native `LOAD` alignment was at least 16 KiB; native libraries are uncompressed
and `extractNativeLibs=false`.

### Added
- **Restore from your own published site (ADR 0021):** Publish → Connection
  can restore public catalogue fields and same-site covers from the active
  GitHub Pages or Cloudflare target into an empty catalogue. The defensive
  mapper preserves periodical relationships, reports duplicates and losses,
  and refuses newer/ambiguous payloads. Cover consent defaults on, with
  sequential decoding and independent request, time, raw-byte and retained-
  byte budgets; third-party links remain consent-gated.
- **Published identity recovery:** a valid `library.json` fingerprint is
  preserved through a durable target-bound journal, startup/identity-only
  retry, and later `.pitabak` backups. Publish, card and refresh use the
  override. Empty-catalogue publish guards and non-destructive Cloudflare
  Worker adoption prevent a fresh install from overwriting its only recovery
  copy. Guides and privacy documentation explain account safety, private
  fields that cannot return, and the site details to re-enter.

## [1.9.3] - 2026-11 (tag `1.9.3`, versionCode 35)

Release sentinel (`tool/release_build.sh --sentinel`): `NetworkMapIcon`.

AAB sha256: `5767a421d89a116f76105d3ced03a3a2f697b99fa07411acf33318cd15d16df5`.
The 216-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT) passed upload-signature,
package/version and fresh arm64 Dart-sentinel verification. Built from the
local `main` working tree at HEAD `4945b8f` plus the uncommitted release and
follow-up changes; `pubspec.lock` was unchanged.

### Fixed
- **Home quick-add honours ISBN lookup after scanning:** Library → Scan to add
  now runs one metadata lookup for a new ISBN when the existing setting is on.
  Default-off and unavailable settings stay manual, an in-flight automatic
  lookup cannot be duplicated by the explicit Lookup button, and existing-item
  and magazine routes are unchanged.

### Changed
- **Clearer Network map action:** the home app bar uses a filled primary-colour
  map with a small tertiary-colour location pin; its tooltip and destination
  are unchanged.

## [1.9.2] - 2026-11 (tag `1.9.2`, versionCode 34)

Release sentinel (`tool/release_build.sh --sentinel`): `IsbnLookupField`.

AAB sha256: `5da0faccbea67357e14cbc3f8412357456287b83ddb46df0d3fabf06d779ea7a`.
The 216-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT) passed upload-signature,
package/version and fresh arm64 Dart-sentinel verification. Built from `main`
at `4945b8f` plus this release metadata; `lib/` and `pubspec.lock` were
unchanged by the release preparation.

### Added
- **Optional immediate ISBN lookup after scanning:** Settings → Library gains
  **Look up ISBN after scanning** (default off). Add book and Add to wishlist
  keep the current scan-then-Lookup behavior unless it is enabled; the explicit
  Lookup button remains available for retries and edited ISBNs. Unavailable
  settings fail closed to manual mode, metadata still fills only empty fields,
  and scanning never saves an item. Library quick-add routing is unchanged.
  The shared ISBN row/scan flow and Settings tile are extracted into cohesive
  presentation files, preserving the file-size ratchet.

## [1.9.1] - 2026-11 (tag `1.9.1`, versionCode 33)

Release sentinel (`tool/release_build.sh --sentinel`): `GitHubBlobPacer`.

AAB sha256: `f6250cf4082179205c899767d78f0b1cceb278b917e271bbe2ba51fbbaeb8e6c`.
The 221-second `tool/release_build.sh` build (its own `flutter clean`, locked
dependencies, Rust for three ABIs and Dart AOT) passed upload-signature,
package/version and fresh arm64 Dart-sentinel verification. Built from
`publishOptimisation` at `e5e0179` plus this release metadata; `lib/` and
`pubspec.lock` were unchanged by the release preparation.

### Added
- **Availability fast lane (ADR 0019; publish-optimisation Phase 1, S2–S8):**
  after a loan or return, the app publishes a small `availability.json`
  (`{"schemaVersion":1,"keySet":…,"asOf":…,"out":[…]}`: the sorted public
  keys of items whose every copy is lent out, never kind Other, `asOf`
  floored to the minute) without rebuilding `books.json` or reading a cover.
  The keepAlive `AvailabilityAutoPublisher` starts with the app
  (`main.dart`) and drives the plain-Dart `AvailabilityLane`: the set is
  saved before it is published (lane store, one SharedPreferences key, public
  keys and times only), so it still goes out after the vault locks; 20 s
  debounce; GitHub also 6 min spacing and ≤ 10 commits per rolling hour, every
  commit counted by `CommitRecordingGitHubApi`; bounded backoff 1/2/5/10 min;
  retries on resume (`AvailabilityLifecycleRelay`), **Update availability
  now** and a successful catalogue publish. In-process only; the catalogue is
  read only while loan counts are known.
  - GitHub: `PublishAvailabilityUseCase` commits only that file (or its
    deletion), saves the record `deployed`, and `DeferredPublishVerification`
    proves it outside the publish queue (30 s, then every 10 s to 150 s).
  - Cloudflare: `PublishAvailabilityToCloudflareUseCase` deploys a complete
    version uploading only the file and the marker, reads both back (first
    round at once), and can never prepare a whole-site replacement.
  - Gates inside the queue: an active host, no pending move, and for a write
    this phone's own keyed `books.json` live (`catalogueKeyed`). A file whose
    keys the live catalogue may no longer carry is deleted.
  - **Settings → Data → Publishing:** "Update availability on my site
    automatically" (`AppSettings.autoPublishAvailability`, default on; off
    publishes one removal). **Publish → Connection** gains an Availability
    card with the status, **Update availability now** and a one-time notice.
  - `availabilityLaneActivatedProvider` stays as the build's kill switch.
- **Readers:** the web viewer (v8) and the native viewer read
  `availability.json` (bound to the catalogue by `keySet`; AV15 caps: 1 MiB,
  100,000 keys, key pattern, newer schema ignored) with one per-item rule,
  pinned by shared fixtures and a web/native parity test; *Available / Not
  available* labels ("All out" retired), an **Available now** filter and an
  "N of M available · updated <time>" summary. The web viewer re-checks every
  60 s while visible; the native viewer keeps a third saved copy (ADR 0018).
- **Guide:** "Put your catalogue online" gains **Which host suits you?** and
  a worked example (P7); its GitHub minutes are pinned to `AvailabilityPacing`.
- **Covers already online are not produced again (ADR 0020;
  publish-optimisation Phase 2 Fix 1, S9):** an incremental catalogue publish
  reuses a cover — no read, no re-encode, no upload — when the publish record
  names the same source for it, holds its file and carries the current
  `coverRendition` (`PublishCoverRendition` 1 = `ImageDownscaler` defaults,
  400 × 600 q80, metadata stripped). An unchanged republish now produces 0
  covers and adding one book produces 1, whatever the library size (S0
  measured 4 min 46 s of cover work per publish at 1,000 covers). Complete
  snapshots (moves, replacements) still read every cover. The first catalogue
  publish after this update produces every cover once (remote covers are
  fetched once more), and identical bytes upload nothing.
- **Backups carry the website publishing record (ADR 0014 amendment W5,
  ADR 0020 Decision 7; publish-optimisation Phase 2 Fix 2, S11).** A new
  plain entry `publish_state.json` (`hasPublishState`, manifest schema still
  1): the cover salt, the GitHub and Cloudflare publish records and the
  journal's active host and verified address — never a token or credential,
  a pending move, the unconfirmed Cloudflare deploy, the upload journal or
  the lane store. Written only when the phone has published, best-effort (a
  record that cannot be read is left out and the Create-backup page says so).
  A restore adopts it **only on a phone that has not published itself**
  (product owner, 2026-11-02): nothing set up, or connected to the backup's
  own site but never published there; otherwise "Publishing settings on this
  phone were kept." Adoption runs after the switch inside the publish queue
  (`RestoredPublishStateAdopter` through the J9 keys guard), writes salt →
  records → journal with `catalogueKeyed` cleared, undoes every write on a
  failure, and keeps local cover sources only for covers the archive carries.
  A restored phone therefore keeps the same cover names and uploads no cover
  that is already online. **S15 B3 proved this on one real device across the
  two flavours:** a backup from the F-Droid app (phone A) restored onto the
  fresh Play app (phone B), whose next catalogue publish read 0 covers,
  reused 10 and committed no `covers/*` (restore acceptance in
  `publishOptimisation_PLAN.md`).
  Archives without the entry restore exactly as before.

### Changed
- **`books.json`** (schema still 1, additive): every item carries `key`
  (SHA-256(salt ‖ `"item:" + id`), first 16 hex) and the document a top-level
  `keySet`. Every catalogue publish now reads the cover salt and fails closed
  ("Pitak could not read its publishing key. Nothing was published.").
- The inline tag goes through `isBookUnavailable` (the clamp the old copy
  lacked; identical output for valid rows).
- GitHub records store the **proof path** of their last commit and the
  pre-publish check reads it; a removal is proven by an exact 404.
- A restore or an overwrite merge first clears `catalogueKeyed` in both
  publish records and the lane's saved sets, inside the publish queue; a
  reset that cannot be saved refuses the restore with the device unchanged
  (J9).
- The Cloudflare deploy pipeline no longer depends on the replacement
  preparation; both Cloudflare use cases share `CloudflarePublishStarter`.
- Both publish records gain the additive `coverRendition` (absent = unknown,
  every cover produced once). It reads as unknown for a GitHub record whose
  branch has a cover changed by someone else (the next publish puts this
  phone's covers back) and for a Cloudflare record whose hashes this build
  cannot use. A remote cover is now reused only under the current rendition
  too, so a recipe change reaches every cover.
- The record now stores the source each published cover file really shows,
  trimmed; a cover that fell back to an older file of unknown origin records
  none and is tried again next time.
- A restore (and an overwrite merge) also makes both publish records forget
  their LOCAL cover sources before the generation switch, so covers restored
  under a known file name are read again (ADR 0020 Decision 4).
- New fitness function `test/architecture/cover_files_immutable_test.dart`:
  a stored cover file never changes once saved (CV1).
- **GitHub never receives bytes it already holds (ADR 0020 Decision 6,
  publish-optimisation Phase 2 Fix 3, S10).** Every GitHub commit
  (catalogue, events, availability, move, retirement) is planned by the pure
  `GitHubCommitPlan`, and `GitHubGitDataApi.commitFiles` now takes the plan
  instead of a file list. A file is sent as a blob only when it changed, its
  sha is nowhere in the branch's head tree (any path, owned or not) and the
  same commit has not already sent those bytes; otherwise the tree names the
  existing blob. `ReconciledPublication.knownBlobShas` /
  `GitHubTreeSnapshot.blobShas` carry the head tree's blobs. A phone whose
  record was lost, a move back to a repository that still holds the covers,
  items sharing one picture and the moved `index.html`/`404.html` pair no
  longer re-send bytes. `uploadedPaths`, the "uploading" phase and the S0
  `bytes` count report real uploads only. Deletions are unchanged. Proven
  against the real API on a throwaway repository.
- **A large GitHub publish finishes across attempts instead of never (plan
  J8; publish-optimisation S10b, product decision (a) resume + (b) pacing).**
  GitHub limits content creation to about 80 requests a minute and 500 an
  hour, so a first publish or a move of more than a few hundred new covers
  was refused partway, and every retry re-sent everything. Now:
  - blob requests are paced, at most one a second (`GitHubContentLimit`);
  - GitHub's rate-limit answer (403/429 with "rate limit", `retry-after` or
    `x-ratelimit-remaining: 0`) is its own result, `PublishCommitRateLimited`,
    with the message "GitHub limits how much one account can upload in an
    hour, and it paused this upload. N of M files are already on GitHub and
    will not be sent again. Nothing on your site has changed yet. Publish
    again in about an hour to send the rest." (a move and a retirement name
    their own next step; the availability lane says "GitHub paused uploads
    from your account for a while.");
  - every blob GitHub confirms storing is remembered per repository in
    `github_upload_journal.json` (app documents; public shas and times only),
    and the next attempt names those blobs instead of sending them
    (`ResumableUploadGitHubApi`, wrapping every commit). The site still
    changes in ONE atomic commit at the end. GitHub's pause is kept too
    (`retry-after`, else 1, 2, 4 … minutes, at most an hour): no commit, not
    even the lane's, is sent before it ends.
  - The commit flow moved from `HttpGitHubApi` to `GitHubCommitWriter`
    (`http_github_commit.dart`; 547 → 445 lines, off the size ratchet).
  Verified against the real API: a tree may name blobs a refused attempt
  left behind, 2 minutes and 65 minutes later; a tree naming an unknown blob
  is refused with 422, which makes the journal forget the blobs it named.
- The cover salt can be replaced, by that adoption only: a separate port
  `ReplaceablePublishCoverSaltStore.replace` (length-checked before the
  write); `publish_salt_invariant_test.dart` pins the one reviewed writer.
- `PublishTargetJson` (publish domain) is the one target JSON shape, shared
  by the host journal (`PrefsPublishHostStore`, stored format unchanged) and
  the backup entry.
- The Restore screen's two read-only views moved to
  `backup/presentation/widgets/restore_summary_widgets.dart` (the page sat at
  the 500-line ratchet); the backup copy and the backup guide now say what
  publishing data travels ("your GitHub or Cloudflare sign-in" is what does
  not).
- `PRIVACY.md` (effective 2026-11-04): availability updates automatically;
  the viewer requests and saves `availability.json`; backups carry the
  website publishing record (no credentials). Its site-check paragraph now
  distinguishes Cloudflare's 12-read check from GitHub Pages' deferred 13-read
  proof for catalogue and events publishes (J18; wording only).
- **A GitHub catalogue or events publish returns at commit time** (plan SP1,
  S12; ADR 0017 amendment of 2026-11-02). The use cases save the commit
  `deployed` and return a `DeferredVerificationRequest`
  (`PublishSuccess.verification`); no public read follows the commit inside
  the publish queue, so the button and the queue are free ~40 s sooner. The
  keepAlive `PublishGoingLive` runs the lane's `DeferredPublishVerification`
  after the queue is released; on proof it marks the record `live`, records
  the verified address and refreshes `publishedSiteUrlProvider` and
  `publishSiteStatusProvider`. The card's line follows it: "Published — going
  live (usually within a minute)." → "Published! Your site is live."; the
  Events screen shows one "going live" message with the address. The guide's
  first-publish step and its mockup mirror say so. `PublishPhase.pagesBuilding`
  is gone; the catalogue and events timing lines no longer have `readBack`.
- GitHub records gain the additive `committedAt` (when GitHub accepted the
  recorded commit; required by `afterCommit`, kept by reconcile only for the
  same head, checked as a whole non-negative number in `publish_state.json`).
  The pre-publish check treats other bytes inside the 10-minute Pages build
  window after it as `stillBuilding` (carry on, do not mark live), so a
  publish started while Pages still builds the previous commit — the lane's
  included — no longer stops with "Your site is showing something different…".
  `PublishManifest`'s three derived records now share one private copy.
- **Cloudflare publishes send their independent reads side by side** (plans
  SP2 and SP3, S13; ADR 0017 amendment of 2026-11-02). The read-back reads
  its first round at once — every deploy and every earlier-record check, no
  longer only the availability lane's — and runs at most four reads at a time
  (`CloudflarePublicationVerifier.defaultMaxConcurrentReads`), started in path
  order; no read starts after the deadline. The three preflights of each
  publish start the subdomain, Worker-presence and marker reads together (the
  route read still waits for presence) and judge the answers in the old order,
  so every result and typed failure is unchanged. Budgets keep their numbers;
  `CloudflareReadBackBudget.afterAvailabilityDeploy` and `immediateFirstRound`
  are gone (the lane uses `afterDeploy`). No screen or wording changes.
  S15's combined Phase 2+3, pre-S16 build measured an unchanged test-library
  Cloudflare publish at **19.9 s** (S0: 25.0 s) and add-one at **19.1 s**
  (S0: 25.7 s). These are whole-pipeline totals, not isolated SP2/SP3 savings.
  The separate C4 lane sample missed its internal read-back p90 budget (38.4 s), while
  lend → visible had a 39 s median; the product owner kept "usually under a
  minute" and left the p90/J23 observation open (Cloudflare wording decision
  in `publishOptimisation_PLAN.md`).
- **A GitHub publish skips the file-list read when nothing moved** (plan SP4,
  S14; ADR 0017 amendment of 2026-11-03). `GitHubGitDataApi.headTree` is
  split into `branchHead` (one ref read) and `treeAt` (the commit and its
  recursive tree); the reconciler reads the head first and, when this
  phone's record is `live` for the same repository and branch at exactly
  that head, reconciles from the record
  (`PublishManifest.reconciledAtUnchangedHead`, the same `reconciledFrom`
  rules) without the tree request. Blob reuse then knows the record's own
  blobs. A move always reads the whole tree. GitHub records gain the
  additive `adoptedFromBackup`, set by the restore adopter, so another
  phone's record is read against the tree once before it is trusted; the
  lenient record reader moved unchanged to `publish_manifest_json.dart`. The
  GitHub `reconcile` timing mark reports `treeReads`.
- **A GitHub Pages site carries an empty `.nojekyll`** (plan SP5, S14; same
  amendment). Measured on real Pages builds of Pitak-shaped sites, skipping
  Jekyll cut the median build by 23 % on a 10-cover site and 17 % on a
  1,000-cover site (5 builds each; push → served 29 % and 20 %) with
  byte-identical served files. The catalogue section owns the file
  (`GitHubPagesNoJekyll`) and writes it only for a GitHub Pages target
  (`CatalogueInputs.gitHubPagesSite`, decided from the target when the
  inputs are read); existing sites gain it with their next catalogue
  publish, a move to GitHub carries it, Cloudflare never gets it.
- **The cover salt is read once per publish** (S16, one salt read in
  `publishOptimisation_PLAN.md`; ADR 0019 Decision 3 clarification of 2026-11-04). Before, every cover
  decision read the salt from secure storage again (about 72 ms each on the
  test phone), so an unchanged republish of 1,000 covers spent 73 of its
  90 s there although it read no cover file. `PublishItemKeys.namingFor`
  now reads the salt once and returns the keys, the key-set id and a pure
  `PublishCoverNames` together; the snapshot builder hands them to the
  catalogue builder as one value and the decider names covers from it per
  call, holding no salt store. `PublishCoverIds` keeps only the static hash
  helpers; `publishCoverIdsProvider` becomes `publishCoverSaltStoreProvider`.
  Hash inputs are unchanged, so every cover keeps its file name and nothing
  is uploaded again. An architecture test pins the three remaining readers
  of the salt. Measured on the 1,001-item Cloudflare fixture (2026-11-04):
  an unchanged republish takes **17.2 s instead of 90.1 s**, its cover
  stage 24 ms instead of 72.6 s with 0 covers read and 1,001 reused;
  adding one book with a new photo takes **39.5 s instead of 112.9 s**, its
  cover stage 174 ms with exactly 1 cover read. S16 re-measured the fixture
  only; it did not re-measure a small library.

### Fixed
- **Android launcher icon: no more white ring.** The app shipped only a flat
  square icon, so Android 8+ launchers shrank it onto a white plate inside
  their icon shape (a saffron square in a white circle). It is now an
  adaptive icon: a saffron background layer (`@color/ic_launcher_background`)
  and the open book on a transparent foreground layer
  (`mipmap-*/ic_launcher_foreground.png`, `mipmap-anydpi-v26/ic_launcher.xml`),
  so the whole shape is saffron. The book is drawn at `ADAPTIVE_GLYPH_SCALE`
  1.10 (product owner's choice) so it stays inside the launcher's safe zone
  on every shape. All of it is generated by `tool/gen_app_icon.py`; the flat
  PNGs (Android 7, iOS, macOS, store listing, in-app and PDF copies) are
  byte-for-byte unchanged, so no golden changes.
- A damaged local `publish_manifest.json` whose `ownershipConfirmed` was not
  a bool threw a `TypeError` the store did not catch; it now reads as "not
  confirmed" (plan J16).
- A GitHub catalogue publish after an unconfirmed **events** commit could
  mark that commit live from an unchanged `books.json` (plan A.1 item 8).
- Web viewer: the "This file was created by a newer Pitak" notice was
  overwritten by the item count at once.
- A remote cover whose new URL failed to download once kept its old picture
  for good: the record stored the new URL over the old file, so later
  publishes skipped it (ADR 0020 Decision 2).
- **Optimisation review remediation (`opt-fixes.md`, items 1–16):**
  - Availability input reads and lane application are serialized in trigger
    order, so an older answer cannot overwrite a newer one.
  - GitHub redirects are refused; a renamed repository is adopted only when
    its canonical owner/repository identity matches.
  - The restore pointer rename is the commit point. Old-generation cleanup is
    best-effort and retried, never misreported as a failed activation.
  - Identity adoption rolls back where possible and truthfully reports partial
    adoption.
  - Complete read-back is deadline-bounded with at most four concurrent reads.
  - GitHub artifacts use operation-scoped spools instead of retaining the whole
    produced site; exact sizes are preserved and only upload bytes are opened.
  - App lock re-locks when picker grace expires in the background.
  - Rust and Kotlin native secret buffers are wiped on validation,
    cancellation and success paths.
  - Web availability uses status-aware, bounded streaming; over-cap bodies are
    refused before parsing and there is no unbounded `arrayBuffer()` fallback.
  - Share UI distinguishes hand-off from proof of saving and handles dismissed,
    unavailable and throwing outcomes without losing retry.
  - Restore's terminal result survives route pop/reopen until a new archive is
    chosen; duplicate-run refusal and passphrase disposal are unchanged.
  - A QR join is announced only after the library ID is persisted; a failed
    write keeps the old identity and starts no merge.
  - Provider-status colours meet at least 4.5:1 on the real card colour in both
    themes, expanded and collapsed; text labels and icons remain.
  - Editable settings fields await saves, keep failed input open, reject
    duplicate submits and follow external values only while idle.
  - Published-cover recency is touched only for an actual cached-image hit,
    not failure dedupe, queued misses, disabled consent or disposed sessions.
  - One process-wide `GitHubBlobPacer` paces blob starts across commits;
    backward clocks remain capped and each commit moves the ref exactly once.

## [1.9.0] - 2026-10 (tag `1.9.0`, versionCode 32)

Release sentinel (`tool/release_build.sh --sentinel`): `Set up Cloudflare Workers`.

AAB sha256: `141b25d855b4ca31ef85d6ae50a6f9ae29d4b72d8fa49017ecb066e965890620`.
The 206-second `tool/release_build.sh` rebuild (its own `flutter clean`, then
Rust for three ABIs and Dart AOT) passed upload-signature, package/version,
Bundletool/ZIP-integrity, fresh-timestamp, all-ABI Dart-sentinel (plus
`Replace and move` and `Showing your saved copy from`), 64-bit ELF-alignment
and `PAGE_ALIGNMENT_16K` verification. Built from `cloudflare` at `651d694`
(CI green) before PR #20 merged.

### Added
- **Saved copies of opened libraries (ADR 0018):** the native viewer keeps
  the last `books.json` and `events.json` of each saved library in the OS
  cache directory and revalidates them on every open with the host's `ETag`
  (`If-None-Match`; `304` downloads nothing). When the host can't be checked,
  the saved copy is shown with a note naming when it was last confirmed and
  why. Saved bytes are SHA-256/size-verified and re-decoded by the bounded
  codecs; tags are grammar-checked before they are stored or sent. All copies
  share a 200 MiB cap (least recently opened library evicted first), are
  excluded from device backups and `.pitabak`, and are deleted when the
  library leaves the saved list (remove, restore or move). Supersedes ADR
  0015 decision 3; covers and posters stay memory-only.
- **Publish to Cloudflare Workers:** connect with a restricted API token
  scoped to one account (`Workers Scripts · Edit`), choose the account,
  `workers.dev` subdomain and a Worker dedicated to Pitak, prove the address
  with a marker-only deploy, then publish the catalogue and events to an
  assets-only Worker. An unknown remote state requires an explicit
  whole-Worker replacement whose dialog shows real item and poster counts;
  cancelling writes nothing.
- **Read and reconcile `workers.dev` libraries:** strict
  `<worker>.<subdomain>.workers.dev` root addresses are accepted and hostile
  forms refused. When a saved library's fingerprint reappears at another
  verified address, both addresses are offered neutrally and accepting is one
  transactional merge/repoint that keeps URL and fingerprint uniqueness;
  declining writes nothing and nothing follows a move automatically.
- **Move a library site between GitHub Pages and Cloudflare Workers (S9):** a
  user-confirmed move publishes and verifies a complete destination snapshot
  before touching the old site, records one atomic pending-journal entry with
  the exact moved-page bytes and app-owned deletion paths retirement will use,
  and switches the share/QR address only after the old site is verifiably
  retired. Retry resumes only missing work; Skip requires the old repository or
  Worker to be gone and never pretends it was retired.
- **Persistent move recovery UI:** the publish card shows the verified new
  address plus a Retry/Skip banner until completion, warns before Skip, and
  states that peers do not follow a move automatically and the card must be
  reprinted.
- **How Pitak works: three new guides (nine in total).** *Set up Cloudflare
  Workers* lists every value the Cloudflare setup asks for (API token,
  account / Account ID, `workers.dev` subdomain, Worker name), says where to
  find each one in Cloudflare's dashboard, and walks through token creation
  and the in-app prompts; *Events and posters* covers the Publish → Events
  tab; *Wishlist: books to buy* covers adding wanted books and moving one into
  the library. New deep links open the Events tab and the Wishlist. The
  publish guide's Cloudflare part is now a short pointer, and the map guide no
  longer calls every site address "the GitHub Pages link".
  `guide_catalog_test.dart` pins the guide's token name and Account ID length
  to the setup code, so the copy cannot silently drift from it.

### Changed
- **Guide copy split by topic:** `guide_catalog.dart` now holds only the index
  order and lookup; the guides live in `features/guides/domain/catalog/`
  (library, publishing, data-and-network) to stay under the 500-line
  file-size ratchet. No behaviour change.
- **One publish pipeline for both hosts:** catalogue and events are built by
  ONE set of section builders, merged by ONE section rule, and every publish
  is bound to one sealed target, so `library.json` always carries the address
  of the operation that wrote it. The host adapters consume the same bytes.
- **GitHub writes are head-aware and fail closed:** a schema-2 publish record
  (repo, branch, head, ownership consent), typed non-truncated tree
  reconciliation, expected-head commits, atomic typed saves, and
  `deployed` → `live` only after read-back proves the site. A record that no
  longer describes the repo+branch claims nothing instead of authorising
  deletions, and tree paths this phone did not write are never adopted.
- **A corrupt read is not empty content:** publishing uses strict reads, so a
  damaged events file is a typed failure rather than an empty public page; the
  tolerant editor read is now explicitly `loadForEditor()`.
- **Stale covers are deleted on the next publish.** This is a deliberate
  remote-behaviour change: a cover that is no longer referenced leaves the
  site instead of lingering at its old URL.
- **One target-mutation rule:** GitHub repository setup and Cloudflare Worker
  setup now share the pending-move guard, so neither can change a target while
  a move is being recovered.
- **App icon: the book now lies open face-up.** The pages used to rise to a
  peak at a wide saffron spine band, which read as a book left open
  face-down. Now three cues say "face-up": the pages curve down into the
  centre fold, the paper is shaded toward a crease line, and a cream cover
  edge shows below the pages. Same saffron tile and cream paper; the glyph
  stays centred. Every PNG was regenerated from `tool/gen_app_icon.py`:
  launcher icons (Android, iOS, macOS), the in-app and PDF copies under
  `assets/`, and the store icon and feature graphic
  (`tool/gen_play_assets.py`). The library goldens that show the logo were
  regenerated on Linux (`update-goldens` workflow).
- **"Not showing yet" after a move is explained:** when the new site was
  written but did not appear within the wait, the move now says the library
  was copied, that a new GitHub Pages site can take 10 minutes or more
  (the same budget the check waits for), that the current site was not
  changed, and to choose Move to other host again. The Cloudflare
  destination says the same after an accepted deploy.
- **A completed move clears the reader's identity-conflict badge:** a 404/410
  for `library.json` is now `DescriptorRefusal.notPublished` (other non-2xx
  stay `httpStatus`). On that answer, which is what a moved page gives, a
  known conflict badge becomes `unreachable`; the row keeps its identity and
  cached facts, an offline site still keeps the badge, and the other address
  keeps its own badge or move offer (never an auto-merge).
- **Replacement consent depends on content, not existence:** the Worker read
  now tells an empty Worker (exists with no versions, code 10222) from one
  with content (`CloudflareWorkerPresence`). Only a Worker with content asks
  for replacement consent in setup, warns that verification replaces its
  assets, or makes a publish or move ask to replace "content this phone did
  not publish" (ADR 0017 amended).
- **Worker-name case listing removed:** Cloudflare refuses Worker names with
  capitals (HTTP 400, code 10016, proven on the real host), so
  `CloudflareWorkerNameGuard`, `listWorkerNames` and their messages and limits
  are deleted. New names stay lower-case; stored names keep working.
- **Replacement and recreate dialogs explain the case:** missing files, a
  deleted Worker, and a changed destination or address each get their own
  title, body and button, and the dialog re-opens with a "the site changed"
  warning when Cloudflare moved after the review.
- **Moving to a Cloudflare Worker that no longer exists** is now a normal
  move whose review says Pitak creates the Worker with the whole library.
- **An events-only publish reads only the events:** it no longer depends on the
  catalogue, magazine titles or `library.json` being readable, and it no longer
  re-reads covers it will not write. The catalogue is still carried from the
  trusted publish record.

### Fixed
- **Contradictory Cloudflare tile after a publish:** the tile no longer shows
  "write access … verified" next to "The first publish will test Workers write
  access." The write-access line is derived from the connection status, and
  the setup message only reports what setup did.
- **Stale review text while publishing:** after confirming a replacement, the
  publish card no longer shows "Review site replacement" for the minute the
  deploy and read-back take; it shows "Publishing…".
- **Cancel move is no longer offered when it can only be refused:** the old
  address is checked before the confirmation dialog, and Cancel disappears once
  the old address is known to show the moved page (including after a final
  switch that failed after retirement). Retry remains.
- **No second, empty review for a different Worker:** a Worker that exists
  with no versions (left by an interrupted first publish) no longer triggers a
  replacement review on top of the "Publish to a different site?" review.
- **Unreadable Cloudflare credentials during a move:** the move target resolver
  threw a `StateError` (not caught by `on Exception`) instead of reporting that
  setup is required; it now fails closed with the fixed setup message.
- **Cloudflare publishing can no longer reach a dead end:** a stored record
  for another Worker or address now claims nothing instead of failing every
  publish; a deleted Worker is offered a recreate review instead of refusing
  forever; and Retry verification with no matching record says there is
  nothing to verify.
- **A whole-site replacement for missing files can be confirmed:** consent was
  checked against a freshness category instead of the remote state the user
  reviewed, so a repair offered for files Cloudflare no longer holds could
  never be confirmed. Confirmation is now bound to that remote anchor.
- **The first publish to a new Worker no longer reports "stale":** if the
  upload session creates the Worker, the publish re-reads the Worker and marker
  around its own session instead of mistaking its creation for a foreign
  change.
- **A Cloudflare connection that can’t be read is no longer a dead end:** the
  Connection tile explains it and lets the user forget the unreadable record
  (only the token key is deleted; the site, Worker and share link are
  untouched) instead of asking for an app restart.
- **An unreadable publishing record can be reset:** the publish card offers
  "Reset publishing record" only when the journal cannot be decoded, behind a
  dialog that says the sites and the old content are unchanged. It never acts
  as a general reset.
- **Switching tabs no longer cuts a Cloudflare publish:** the API facade now
  lives as long as the app process instead of as long as the Connection tab is
  visible, so in-flight requests are no longer closed mid-publish.
- **A failed settings save no longer breaks publishing or the settings
  screens:** the last saved value stays loaded, the screen says it couldn’t
  save that setting, and a publish keeps its progress instead of freezing.
- **Cloudflare read-back tells the truth about why it failed:** it reads only
  the documented set (never covers) and distinguishes a contradicting site
  from an unreachable one, under a bounded deadline. A contradicted earlier
  deployment asks for a replacement instead of blocking; an unreachable one no
  longer blocks an ordinary publish.
- **Large libraries upload on slow connections:** an upload is now bounded by
  progress instead of one 60 s number — a 60 s connect bound, a 60 s idle bound
  between body chunks, a size-derived total (up to 20 min), and a 55 min
  session budget for Cloudflare's one-hour upload token. A failed attempt that
  already sent more than 1 MiB is never blindly re-sent, so a slow link no
  longer spends the same mobile data three times. A stall or an expired upload
  token now says so and suggests Wi-Fi instead of "Reconnect Cloudflare".
- **A non-JSON Cloudflare error is classified by status:** an HTML 5xx or a
  second 429 is a server or rate-limit answer, not "unreadable response", while
  an HTML 403 still cannot trigger the setup fallbacks. A site file that
  changed or vanished mid-upload stops the publish with "Publish again" instead
  of being retried with different bytes.
- **Publish spools live in temporary storage and are swept:** a killed publish
  no longer leaves a full copy of the site in Documents. Spools are created in
  the OS temporary directory, and the next operation deletes stale `run-`
  folders under the app's own roots — never a link, never a folder in use, and
  a failed delete never blocks a publish.
- **A pending move can always be finished, skipped or cancelled:** the banner
  now offers all three. Cancel keeps publishing to your current site and leaves
  the already-published copy online until you delete it; "Finish without
  retiring" appears only when Pitak cannot sign in to the old site, and Skip
  still requires the old repository or Worker to be gone.
- **"Not found" now means not found:** a Cloudflare 404 without Cloudflare's
  own not-found code, or a GitHub repository 404 whose old address still
  answers, no longer counts as "the site is gone". Both fail closed instead of
  authorising a replacement or a Skip.
- **Reconnecting during a move can no longer overwrite the old site:** every
  setup step checks the account, subdomain and Worker against the pending move
  before saving anything or writing remotely, and the prompts prefill the exact
  address with "Reconnect to … to finish your move."
- **Rotating a Cloudflare token no longer replaces your live site:** picking the
  Worker that is already your verified site finalizes without the marker-only
  verification deploy, and a new token is not saved until you choose an account,
  so abandoning setup keeps the old connection.
- **A setup prompt is never stranded:** dialogs reappear when you return to the
  tab, a rebuild no longer opens the same prompt twice, and "Cancel setup" is
  available while a prompt is waiting.
- **A library name can no longer break every move:** a pasted tab or other
  control character in the library name used to be discovered only after the
  new site was published, so every attempt failed at the same point with no way
  to resume. The name is normalized before anything is written, and a moved
  page that cannot be prepared stops with "Nothing was changed."
- **Older versions can no longer stay publicly reachable:** Version URLs are
  re-checked after the last moment before a deploy and before every
  "verified", "repaired", "completed" or adopted-move message. "Retry
  verification" may now switch them off (a setting change, never an upload or
  deploy); if it cannot, the fixed privacy message blocks further deploys.
- **A deployment that reached Cloudflare but lost its answer is recognised next
  time:** the attempt is recorded before it is sent, so the next publish or
  "Retry verification" proves it and finishes instead of offering a whole-site
  replacement for your own deploy. An attempt that never landed leaves the old
  record untouched.
- **Cloudflare messages now match what happened:** a check of an earlier
  publish says "Verified", not "Published!"; a publish that could not record
  its own state says the previous site is live and the new changes were not
  published; "Retry verification" appears only where it can change the outcome;
  and an uncertain deploy says to check before publishing again instead of
  suggesting a reconnect.
- **A move reports which save or step failed:** if the new site is live but its
  record could not be saved, the message says so; a failure after the
  deployment was accepted says that; and a change on the destination is no
  longer reported as a change on the old site.
- **Moving into a Worker that already has content asks first:** the review
  names the Worker, says the move replaces everything on it, and the button
  says "Replace and move". If that content changes after the review, Pitak asks
  again instead of writing.
- **Cloudflare shows the same specific library-read message as GitHub:** an
  unreadable library or an oversized member list now says exactly that instead
  of a generic "could not read your library".
- **Pre-2026 Cloudflare tokens can connect again:** the unprefixed
  40-character shape was issued for old user *and* old account tokens, so setup
  now tries the personal-token check first and, only if Cloudflare refuses it,
  asks which account it belongs to and verifies it there. Nothing is saved
  until that account check says "active"; timeouts, 5xx and inactive tokens are
  reported as-is and never fall back.
- **"Keep saved address" changes nothing on the kept library:** only the
  duplicate row is deleted. A public fingerprint can no longer let the other
  site rename or re-pin the row you chose to keep.
- **A Cloudflare account with an unrenderable name no longer hides the list:**
  bidi, zero-width, control and separator characters are replaced by
  "Account …{last 4}", the replacement is never saved, and the manual Account
  ID path stays available.
- **Moving off GitHub Pages waits for GitHub's build:** verifying the old
  address now uses the same "up to 10 minutes" budget as publishing to GitHub,
  and the progress line says a build can take a few minutes. Cloudflare keeps
  its shorter wait.
- **New Cloudflare Worker names are lower case:** the field shows the
  lower-cased name as you type, and a Worker whose name differs only in letter
  case is refused before anything is written. Existing mixed-case Workers keep
  working.
- **A failed preference save no longer looks saved:** a failed journal,
  settings or share-card write restores what the app previously read, so a
  pending move or a chosen style cannot appear set for the rest of the session
  and disappear after a restart.

### Security
- **Cloudflare secrets stay out of state:** the token and target live in ONE
  versioned `cf_connection` secure-storage record that is replaced as a whole
  (a new token never pairs with a stale Worker); upload/completion JWTs are
  request-scoped and never persisted, logged, spooled or placed in UI state;
  and every secret-bearing store now uses the shared hardened
  `flutter_secure_storage` factory.
- **A pasted Cloudflare token is not a login credential:** the token field is
  explicitly excluded from autofill and from the keyboard's personalised
  learning, and the external token-creation page reports when it cannot open
  instead of appearing to work. Account display names pass one shared
  safe-text rule (C0/C1, zero-width, bidi, separators, BOM) before they can be
  drawn or stored.
- **Version URLs fail closed:** the app confirms a Worker's version URLs are
  off before creating another version, and blocks further deploys — and
  retirement completion — while an older copy of the site could be public.
- **Publishing egress is bounded and hostile-input safe:** fixed API origin,
  refused redirects, genuinely abortable deadlines, streamed response caps, a
  JSON depth/bounds pre-scan before decoding, whitelisted error codes, and
  fixed failure messages that never carry a token, URL or response body.
- **Cloudflare records fail closed:** an unsupported schema/state or a single
  malformed file entry invalidates the whole record, forcing explicit
  replacement reconciliation instead of a partial deploy that silently drops a
  remote asset.
- **Argon2 uses the fixed digest chain:** Argon2 0.6 moves the shipped KDF to
  `block-buffer` 0.12.1 (GHSA-qwgh-2vcv-g2f7). The older crate remains only in
  Flutter Rust Bridge's compile-time MD5 chain; a CI path guard confines the
  time-limited OSV exception to that chain, and exact-version `cargo-deny`
  entries permit only the unavoidable upstream major-version splits.

## [1.8.0] - 2026-10 (tag `1.8.0`, versionCode 31)

Release sentinel (`tool/release_build.sh --sentinel`): `Announcements & Events`.

AAB sha256: `f7b7025cabc69f761c28a06f07d1e836eb429d0048b63bc145410dd0b78ef428`.
The delivered 216-second clean rebuild (after explicit `build/` + `.dart_tool/`
removal) passed upload-signature, package/version, Bundletool/ZIP-integrity,
fresh-timestamp, all-ABI Dart-sentinel, 64-bit ELF-alignment and
`PAGE_ALIGNMENT_16K` verification.

### Added
- **Native Announcements & Events (ADR 0016):** Events publishing now writes an
  independent, versioned `events.json` beside the unchanged HTML page and
  posters in the same atomic commit. The saved-library viewer reads it through
  the same bounded same-site policy and displays native read-only posters.
  Existing sites need one Events republish; a missing file stays quiet, while
  real failures are retryable and never block the catalogue.

### Changed
- **Library Bookmarks and drawer actions:** the main drawer now opens a
  standalone Library Bookmarks page owning Add Bookmark and the shared saved
  library list; Library network retains Add member. Settings and Share Apps
  share the pinned bottom row, with Share Apps on the right.
- **Discoverable viewer image consent:** when covers or event posters are
  present but the default-off remote-image setting is disabled, the viewer
  explains the choice and offers Load covers. This persists the existing
  opt-in; same-site and third-party gates, memory-only caching and disposal
  rules are unchanged.

## [1.7.0] - 2026-10 (tag `1.7.0`, versionCode 30)

Linux golden images came from run `40270124772`; the complete release CI
matrix passed in run `40272137572`.

Release sentinel (`tool/release_build.sh --sentinel`): `Share Apps`.

AAB sha256: `25e9fa8012d636f387ee9ad7251fc70f6117b45111bc10e6ef7b08fd51b94f26`.
The clean 231-second build from `1c58a8a` passed upload-signature,
package/version, ZIP-integrity, fresh-timestamp, all-ABI Dart-sentinel,
64-bit ELF-alignment and `PAGE_ALIGNMENT_16K` verification.

### Added
- **Share Apps:** a drawer entry above Settings opens a scrollable panel that
  starts with Pitak only — its real icon and a native OS share of the Play
  Store listing. Future apps need one validated catalog entry each; there are
  no placeholder rows and no new dependency.
- **Native published-catalogue viewer** (ADR 0015, plan `appViewer_plan.md`):
  tapping any saved Library-network row (bookmark, card or discovered) opens
  that library's published `books.json` in a read-only Flutter page instead of
  the browser. A defensive schema-1 reader (`PublishedCatalogueCodec`,
  `PublishedItemReader`) treats every byte as hostile: byte/depth/row caps,
  exact kind and age tokens, sparse `other`/unknown projections, last-wins
  duplicate series handling with visible counts. Origin + directory policy
  (`PublishedSiteUrlPolicy`) applies to the catalogue and same-site covers on
  every redirect hop; a viewer-owned, caller-abortable HTTP client (64 MiB
  typed cap inside a 66 MiB outer guard) fetches once per explicit open; JSON
  decode and the filter/sort/group pass run in worker isolates. UI: search
  (120 ms debounce), kind/language facets, three stable sorts (published order
  is the default — never "Recently added"), series grouping, read-only detail,
  persistent newer-schema and identity-conflict warnings, and an explicit
  **Open in browser** fallback. Covers are memory-only (100 entries / 16 MiB
  LRU), consent-gated for BOTH origin classes, downscaled off the UI isolate,
  and discarded on reload/exit. No new dependency, no schema/backup/manifest
  change, no WebView, no import. `NetworkMapPage`'s "Open site" stays external.

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
