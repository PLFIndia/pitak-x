# Magazines / item kinds — progress log (session handoff)

Plan: `docs/plans/magazines.md` (revision 5). Protocol: Part B of the plan.
**Read this file first in every session; update it as the last action of
every session; commit it with the session's commit.**

## State

- Last completed session: **S22** (Release hygiene and final verification)
  — **the plan is complete**; every session S0–S22 is Done.
- Branch: `magazines` — working tree clean: **yes**
- Last commit: S22's commit (S21 `98508ad`, S20 `9faab2c`, S19 `61f9a04`,
  S18 `9b9b72d`, S17 `52843fa`, S16 `6c116fa`, S15 `322f3ed`, S14
  `526b9da`, S13 `bba12b2` (+ handoff docs `83cd3b4`), S12 was `02f3f99`,
  S11 `5ce4ec0`, S10 `b657c8c`, S9 `b9109f2`, S8 `d3ee18b`, S7 `118bc1f`,
  S6 `0517263`, S5 `415adfd`, S4 `29689f8`, S3 `34a7045`, S2 `2959034`, S1
  `e216e6b`, S0 `8899cc0`)
- Full suite last green at: **S22, 2026-10-24** — 2880 tests, 121 s
  (`flutter test --exclude-tags golden`; 96 s at the S22 baseline — the
  spread is machine load, not tests); `gen` no diff; `git diff --stat main
  -- rust/` empty.
- Run stopped here: **no next session** — the branch is ready for review
  and merge (see *Next session* for what the release commit still owes).
- Baseline numbers (from S0): tests = **2426 passed, 0 failed**
  (goldens excluded), duration = **86 s**, platform-golden failures = **7**
  (all in `test/golden/key_screens_test.dart`, pixel diffs ≤ 2.4 % — the
  Linux-pinned goldens of CHANGELOG 1.5.2; verify in CI, not a blocker).
- `gen` at baseline: `Built with build_runner in 25s; wrote 1136 outputs`,
  no diff.

### How the gates are run on this machine (S0 findings)

- **Use the FVM-pinned SDK.** `pubspec.lock` pins Flutter **3.44.2**
  (`.fvmrc`); the `flutter` on `PATH` is 3.41.1 and `build_runner` refuses
  to resolve with it. Prefix every command with
  `export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"` (or use `fvm flutter` /
  `fvm dart`).
- **`analyze` is CI-scoped:** `flutter analyze lib test integration_test`
  (exactly what `.github/workflows/ci.yml` runs). A bare `dart analyze` from
  the repo root reports 43 pre-existing errors inside the vendored
  `rust_builder/cargokit/build_tool/` (its own pub deps are not fetched) plus
  3 `sort_pub_dependencies` infos in `pubspec.yaml` — none of them ours.
  Format gate: `dart format --set-exit-if-changed lib test integration_test`.
- **Goldens:** the project defines the `golden` tag (`dart_test.yaml`), so
  `full` on macOS is `flutter test --exclude-tags golden`; the golden-only run
  writes diffs to the git-ignored `test/golden/failures/`.

## Next session

**None — ready for review/merge.** The plan is complete (S0–S22 Done). What
the reviewer / the `chore(release): x.y.z+29` commit still owes, in order
(docs/RELEASING.md §6.1 — none of it is a session):

1. **Goldens (Linux reference renderer):** Actions → "Update goldens" on
   `magazines`, download the artefact, then ONE commit with the S17
   series-row golden test + its `kGoldenNames` entry + the regenerated PNGs
   (recipe under *Open issues*). The golden CI step is red until then;
   every other gate is green.
2. **On-device smoke (RELEASING §6.1 step 7):** cleared install, then
   `fvm flutter test integration_test --flavor fdroid -d <device>` — runs
   BOTH journeys (`vault_smoke_test.dart`, `catalogue_kinds_smoke_test.dart`)
   over `smoke_support.dart`. Neither has been executed on a device in this
   run: there is no Android device/emulator on this machine, and the macOS
   desktop target has no `pitak_crypto.framework` (cargokit is not wired for
   macOS — `RustLib.init()` fails at launch; the attempt's SwiftPM edits
   under `macos/` were reverted). Both files compile under the CI analyzer
   scope. The old vault smoke could not have passed as written (see
   Deviations) — expect to fix finders on first contact, not logic.
3. **Release commit:** bump `pubspec.yaml` to `+29` (the fastlane blurbs
   `29.txt` / `291–293.txt` already exist — 495 chars), move the CHANGELOG
   `[Unreleased]` block under `## [x.y.z] - 2026-10 (tag x.y.z, versionCode
   29)`, README status note, purity check (the classpath check was run in
   S22 — output below; the APK dex scan needs the release build), sentinel
   for `tool/release_build.sh` — an ASCII string new in this release, e.g.
   `New magazine title`.

What S22 did (for the reviewer):

- **Guide:** `GuideId.catalogue` ("Books, magazines and other items") is the
  FIRST card (adding items is the first job) with `GuideDestination.
  magazines` → `PeriodicalsPage` ("Open Magazines"). Copy record:
  `docs/mockups/how-pitak-works.md` §3.6 + "facts behind the copy" rows;
  the backup guide's "what is inside" sentence now names magazine titles
  and other items (W2). Every pinned invariant holds (49 guide tests); the
  guide was trimmed twice to fit the 3000 dp render budget of
  `guide_page_test.dart` (the scan-route bullet was dropped, documented in
  §3.6). The index order and the destination are the two one-line choices a
  reviewer may want to flip.
- **Integration smoke:** `integration_test/catalogue_kinds_smoke_test.dart`
  (magazine title → issue from the series page → other item → vault →
  lend the ISSUE → backup → restore → series/issue/other/loan survived) and
  `smoke_support.dart` (`reveal` scrolls lazy forms, `openVaultUnlocked`
  creates-or-unlocks, `backupAndRestore` via the providers, `smokeStamp`
  for unique titles). `vault_smoke_test.dart` was rewritten onto the same
  helpers (its finders could never have matched — Deviations).
- **F-Droid purity (RELEASING §2, check 1), 2026-10-24:** `( cd android &&
  ./gradlew -q :app:dependencies --configuration
  fdroidReleaseRuntimeClasspath ) | grep -E 'com\.google\.android\.(play|
  gms)|firebase|mlkit'` → **prints nothing** (703 classpath lines resolved;
  grep exit 1). Self-test on `playReleaseRuntimeClasspath` matches
  (`com.google.android.play:app-update:2.1.0`, `play-services-basement`,
  `play-services-tasks`) — the check works. `pubspec.yaml`/`pubspec.lock`
  are byte-identical to `main`: no plugin was added by S0–S22. Gradle's
  only stderr is the known KGP deprecation warning (RELEASING §7).
- **CHANGELOG `[Unreleased]`** rewritten against what shipped (S1–S22,
  with Fixed/Removed sections and the two pre-tag obligations in its lead
  note). **ARCHITECTURE:** §5.4 was already final since S9 (verified, no
  edit); the stale lines were §3's module map ("in progress" on
  `periodicals/`), the drawer list (no "Magazines") and the
  `integration_test/` line — fixed.
- **Fastlane:** `29.txt` + `291/292/293.txt` (identical, the `28`/`281`
  convention), 495 chars.

Notes from S21 (what S21 built, and the seams S22 plugged into):

- **`.pitabak` carries kinds now (W2):** the writer emits `item_kinds.json`
  (`hasItemKinds`: every non-book row's `{bookUid, kind}`) and
  `periodicals.json` (`hasPeriodicals`: the W1 periodical objects + `issues[]`
  keyed by `bookUid`) whenever there is something to say; both flags default
  false, so a flag-less archive restores exactly as before — except that the
  restore now also CLEARS the v5 tables (`periodicals`, `magazine_issues`)
  on any restore: the overwrite is authoritative, and a flag-less archive
  honestly carries no kinds (see Deviations). The S22 integration smoke (add
  series → add issue → add other → lend → backup → restore) can assert the
  round-trip end to end; a loaned row restored as an issue keeps its id and
  its loan (pinned in `catalogue_replacement_restore_test.dart`).
- **The periodical/issue JSON object shape has ONE home:**
  `periodicals/infrastructure/periodical_json_codec.dart`
  (`PeriodicalJsonCodec`); the W1 exporter delegates to it. The two READERS
  differ by policy on purpose (documented in the codec header): the
  Pitaka-JSON importer clamps+reports, the backup codec drops+counts.
- **RestoreSummary** gained `kindsApplied / periodicalsRestored /
  issuesLinked / issuesDetached / rowsSkippedUnknownKind /
  periodicalsDropped` and the invalid flags `itemKindsInvalid /
  periodicalsInvalid` (see Deviations for why the plan's five counts are not
  all of it); `hasAdjustments` now also covers the W2 counts, and the
  restore page has one plain sentence per condition (widget-tested).
- **`restore_backup.dart` left the ratchet list** (553 → 482): the manifest
  parse moved to `parseBackupManifest` in `backup_extras_reader.dart`, the
  legacy-DB read phase to `restore_legacy_read.dart` (`LegacyCatalogueRows`,
  `LegacyDbOpener`, `stageArchiveEntry`, `readLegacyCatalogue`), and the W2
  apply + write helpers live in `restore_item_details.dart`
  (`applyRestoredItemDetails`, `insertRestoredItems`,
  `writeRestoredPeriodicals`). The ratchet entry was DELETED with a comment
  in `layer_boundaries_test.dart`.
- **The restore's periodicals write is `DriftPeriodicalRepository.
  replaceAll`** — constructed on the BUILDER generation's database inside
  the outer `db.transaction` (zone-scoped join), NOT the DI repository (that
  one is bound to the LIVE database; M02 forbids touching it). A Left rolls
  the whole catalogue write back (`_ReplacementRefused`).
- **`CreateBackupUseCase` requires a `PeriodicalRepository`** and reads
  `listAll()` (removed titles included — their issues may still exist, D8);
  a Left FAILS the backup (S18/S20's no-partial-snapshot rule). DI:
  `createBackupUseCaseProvider` watches `periodicalRepositoryProvider`; the
  `.g.dart` hash changed, committed with the session.
- **Gate test unchanged:** no new `CatalogueItem(`/`Periodical(` site —
  restore applies details via `copyWith`, the codec's `Periodical(` is
  gated by its own `Periodical.validate` call (importer pattern), and the
  writer derives everything from already-persisted entities.
- **Golden deferral from S17 is still open** (see Open issues) — S22 did
  not touch it either; the PNG commit lands separately (step 1 above).

Notes from S20 (what S20 built, and the seams S21 consumed):

- **The publish payload is kind-aware:** `PublishItem.kind` is REQUIRED
  (no default — no mapping can silently default an issue to a book) with a
  nested `PublishIssue` (the public identity fields, nulls omitted);
  `PublishExport.periodicals` is a `List<PublishPeriodical>` omitted from
  the JSON when empty (the S18 v4 rule). `redactPeriodicalForPublish` is
  the series stripper (subscription window, notes, location, source,
  added* never leave the device — pinned by the redaction test).
  `schemaVersion` stays 1; the viewer (bundled `assets/publish/
  index.html`, v7) has the fixed kind facet and groups issues under their
  series header (unknown kinds render plain).
- **Cover decisions have ONE home:** `publish/application/
  publish_cover_decider.dart` (`PublishCoverDecider` + `CoverDecision` +
  the `LocalCoverReader`/`RemoteCoverFetcher` typedefs, re-exported from
  the use case file — the S19 one-import idiom). Periodical covers are
  keyed by UID: `PublishCoverIds.pathForPeriodical` hashes
  `'periodical:<uid>'` (domain-separated from book ids), and the
  manifest's `coverUrlByBookId` carries `'periodical:<uid>'` keys for the
  remote source-identity skip. `FilePublishManifestStore` needs no
  migration: the map is string→string, old manifests simply lack the keys
  (one redundant cover upload at most).
- **`PublishLibraryUseCase.call` takes REQUIRED `periodicals`** (the S18
  churn pattern); the controller reads `periodicalRepositoryProvider.
  listAll()` and a Left REFUSES the publish with the same safe message as
  the catalogue read (no partial snapshot — issues stripped of their
  series would be a silent downgrade). Issues with no own cover publish
  the series' salted path (`IssueCover.resolve` applied at publish; the
  series cover is decided ONCE and shared). A removed series publishes no
  entry but its issues still publish (D8) and keep the fallback.
- **`PeriodicalRepository.replaceAll`'s OTHER caller is S21's restore**
  (merge was the first, S19). The backup reader/writer shapes are ADR
  0014 W2 (`item_kinds.json` + `periodicals.json`, manifest flags default
  false); `restore_backup.dart` is at its cap (553) — the plan puts the
  kinds/details apply in a NEW `restore_item_details.dart`.
- **Golden deferral from S17 is still open** (see Open issues) — S21 does
  not touch it.

Notes for S20 (what S19 built, and the seams S20 consumed):

- **The merge now consumes a v4 file fully:** `MergeLibraryUseCase` has a
  REQUIRED `PeriodicalRepository periodicalRepo` (S18's churn pattern — ~34
  test sites). `MergeResult` carries `periodicalsAdded` /
  `periodicalsIdentical` / `periodicalConflicts` (the page shows the counts
  + the kept-local titles; series conflicts are informational, add-only —
  no per-row resolution exists for them). `MergeDiffersDecision` carries
  `incomingPeriodicals`; `localIsEmpty` sees books AND series (overwrite
  replaces both — `PeriodicalRepository.replaceAll` finally has its merge
  caller; S21's restore is the other).
- **Engine shape after S19:** `library/domain/merge/` is now
  `library_merge_engine.dart` (490: plan types + `planMerge` orchestration,
  `export`s merge_fields + periodical_merge), `merge_fields.dart` (389:
  `MergeField`/`mergeEquals`/`mergeDifferences`/`tokenSet`/`jaccard`/
  `normIsbn`/`kDefaultFuzzyThreshold`/`Tokenizer` + the `MergeField.kind` /
  `MergeField.issue` pair), `fuzzy_index.dart` (112: public `FuzzyIndex`),
  `issue_identity.dart` (70: D6 keys as a RECORD typedef — structural
  equality without `==` overrides, the N14 convention), and
  `periodical_merge.dart` (~320: `planPeriodicalMerge`,
  `periodicalMergeEquals`, `reattachIncomingIssue`). `planMerge` gained
  NAMED optional `localPeriodicals`/`incomingPeriodicals` (default empty —
  books-only callers behave exactly as before; the properties test was NOT
  touched). The `MergePlanner` typedef and `planMergeInBackground` are
  4-arg positional (periodicals cross the isolate as plain data — pinned by
  the round-trip test).
- **The D.2 storm mitigation is two-layered:** (1) the planner re-anchors
  incoming issues to the winning series (`PeriodicalMergePlan.winners`) and
  re-projects BOTH sides canonically before comparing; (2)
  `_mergeFieldSpecs` skips the six projected base fields (title,
  transliteration, publisher, year, language, age group) when BOTH rows are
  issues — projected data is derived (D3), never a conflict. After the
  apply, the use case re-projects the stored issues of every series in
  `MergePlan.matchedLocalSeries` through the new shared
  `IssueReprojection` (`periodicals/application/issue_reprojection.dart`,
  extracted from `UpdatePeriodicalUseCase` — the S18 import staleness is
  repaired by the next merge), all inside ONE `runInTransaction`.
- **Series merge equality is NOT `Periodical.sameAs`:** an ISSN/title match
  differs in uid BY CONSTRUCTION, and `addedDate`/`addedBy` are per-device
  — `periodicalMergeEquals` excludes those and applies the M09 cover rule +
  the Session-33 language key (item-engine parity).
- **Resolution guards (D6/D8):** take-theirs is refused when the kinds
  differ (use-case belt + `MergeReviewItem.canTakeTheirs` suspender), and
  `_freshCopyOf` (keep-both) now carries `details` — a keep-both no longer
  silently flips an issue into a book (a key collision then fails the
  insert with `DuplicateIssueFailure`, shown on the review row).
- **Fakes:** `FakePeriodicals` gained `insertAll`/`replaceAll` (+
  `…Failure` switches), honouring the atomic/uids-kept contracts.
- **Gate test:** `periodical_merge.dart` is on the `CatalogueItem(`
  allow-list (the merge orphan rule rebuilds the base row — `copyWith`
  cannot null `details`); census 12 → 13.
- **Golden deferral from S17 is still open** (see Open issues) — S20 does
  not touch it.
- **For S20's `PublishExport.periodicals[]`:** the redaction test pattern
  to extend is the private-field stripping (subscription window, notes,
  location stay local — O2/A.4 W3); `IssueCover.resolve` is the cover rule
  the plan's viewer step cites.

Notes from S18 (what S18 built, and the seams S19 consumed):

- **Import is NOT merge:** S18's use case updates a same-uid series in
  place through the REPOSITORY (`periodicals.update`) and does not
  re-project its issues; S19 owned the re-projection seam (merged series
  are repaired after a merge apply — see above).
- **Fakes:** `FakeItems` now answers `findByUid` and `findByIsbn` from its
  rows (with `calls` entries) — the old "`noSuchMethod` proves
  reachability" trick is gone from `periodical_read_providers_test.dart`;
  use the calls log instead. `FakePeriodicals` keeps its per-method
  `…Failure` switches and records `findByUid`/`findByIssn`.

Notes from S17 (what S17 built, and the seams S18 consumed):

- **Others can be created now**, so v3→v4 import/export really will meet
  `kind: 'other'` rows: no detail table, no nested object (W1), `OtherItemOf`
  is the field-less marker — the importer constructs it for `kind: 'other'`
  rows and the exporter writes `kind` from `item.kind` (derived, F5). The
  repository seam (S10) already round-trips the marker (`DriftItemDetails`
  is a no-op for kinds without a detail table).
- **The Others form's save path** is the GENERIC pair
  (`Add/UpdateCatalogueItemUseCase`, O3) via the existing
  `AddBookController` — see the S17 deviation below; nothing S18 does
  changes it. S18's import paths must keep calling `CatalogueItem.validate`
  (the gate census already covers both import files).
- **Two exhaustive switches now pin the kinds** (both fail to COMPILE when a
  future kind arrives): `catalogue_item_actions.dart`'s Edit routing
  (`switch (book.kind)`) and `item_details_section.dart`'s
  `switch (item.details)`. S18 adds no kind, but its importer must keep
  "unknown kind token ⇒ skip + count" (F6) — the tolerant `ItemKind.
  fromToken` is the reader.
- **Edit-mode identity:** the Others form passes `details: const
  OtherItemOf()` on every save, so a same-uid re-import of an `other` row
  and a local edit can never disagree about kind (D6 conflict rule stays
  the importer's guard).
- **No placeholders remain:** `placeholder_page.dart` was deleted with the
  add sheet's last swap (AGENTS §2.4). Nothing references it.
- **The deferred golden (user decision, see Deviations):** when the Linux
  PNGs are regenerated, land the series-row golden in ONE commit (like
  `628d20d`): a widget golden of the periodicals rows across the badge
  states (active / expiring soon / lapsed / untracked + a removed title) in
  `key_screens_test.dart`, its name added to `kGoldenNames`, and the PNG
  from the `update_goldens` artefact. The widget under test is private
  (`_PeriodicalRow`), so render `PeriodicalsPage` over a seeded
  `FakePeriodicals` + pinned `clockProvider`/`nowTickProvider` like
  `periodicals_page_test.dart` does. S18 does not touch this.
- **Widget-test lessons (S17, same override set as S15/S16):** the Others
  form needs only `catalogueItemRepositoryProvider` (FakeItems) +
  `settingsRepositoryProvider` (FakeSettings) + `libraryLanguagesProvider`
  (deterministic list) — no periodical providers, no `nowTickProvider`
  (nothing it builds arms the minute timer). The detail-page section tests
  pin the big surface (`Size(1080, 2400)`, ratio 1) because the block's
  rows sit below the fold of the 800x600 default. `formatFormDate`/
  `pickFormDate` (periodicals' `form_rows.dart`) are the shared date
  helpers the new form uses for "Date added".
- **Ratchet:** `catalogue_item_detail_page.dart` 455 → 429 (the S17 section
  insertion plus the `DetailRow` extraction) — never re-crossed the cap, so
  no ratchet entry; keep it that way (S18 adds nothing to the page).

Notes from S16 (what S16 built, and the seams S17 consumed):

- **The last placeholder:** `periodicals/presentation/pages/
  placeholder_page.dart` has ONE caller left — `add_sheet.dart`'s "Add other
  item". S17 swaps in the Others form there and DELETES
  `placeholder_page.dart` (AGENTS §2.4). Its only remaining ctor param in
  use is `pageName` (`periodical` is now unused — S16's routes all carry the
  real pages).
- **Edit routing (D8) is kind-aware since S16:**
  `catalogue_item_actions.dart`'s Edit pushes `AddIssuePage(issue:)` for an
  issue row and `AddBookPage` otherwise. An `other`-kind row still lands on
  the book form — S17 must route it to the Others form (the book form
  assembles no `details`, so saving an Other there would silently flip its
  kind to book — the same D8 bug class the issue routing fixed).
- **The Others form (O1–O3):** no kind-specific fields; `notes` labelled
  "Description" (same column, searched per D10); saves through the GENERIC
  `Add/UpdateCatalogueItemUseCase` with `details: const OtherItemOf()` —
  the gate allow-list needs the new page's entry with that reason (B.5).
  Reusable parts built in S16: `LanguageField` (the Session-33 dropdown),
  `FormCoverField` + `FormCoverController.storeCapture` (cover for a
  not-yet-saved row; orphans swept per Q12), `coverCropPresets` in
  `core/widgets/cover_crop.dart`.
- **Detail-page details section:** `catalogue_item_detail_page.dart` is 455
  lines (S14 moved actions to `widgets/catalogue_item_actions.dart`, 282);
  S17's kind-specific blocks fit under the cap if kept compact — split to a
  widgets file before crossing 500. An issue's "Open series" resolves via
  `periodicalByUidProvider(item.issue!.periodicalUid)` (S13; watches both
  mutation signals) → push `PeriodicalDetailPage(periodicalId:)` with the
  resolved id.
- **Goldens (plan S17 step):** the Library golden already shows chips,
  badges and the sheet FAB (S14); on this macOS host the 7 platform-golden
  failures stay "verify in CI". Regenerate the Linux PNGs with the
  `update-goldens` workflow AFTER S17's detail-section changes land.
- **Widget-test lessons (S16, add to the S15 override set):** the forms are
  taller than the 800x600 default surface and their ListView only builds
  near-viewport children — both form test files pin
  `tester.view.physicalSize = Size(1080, 2400), devicePixelRatio = 1` in
  their `openForm` helper. `find.widgetWithText` matches BOTH a field's
  EditableText content AND a hint `Text` — a field whose hint equals its
  value double-matches (the ISSN hint was dropped for that reason); prefer
  label finders. Dropdown menus: tap the field, then `find.text(label).last`
  (the menu overlay duplicates the closed value's text). The series picker
  clamps a selected uid that is absent from the list to null (a dropdown
  value outside its items crashes — fail closed).
- **Ratchet:** `add_book_page.dart` shrank 640 → 526 (language field moved
  out) — the ratchet record was lowered to 526 in the same commit; the
  comment in `layer_boundaries_test.dart` says why.

Notes from S15 (what S15 built, and the surfaces S16 consumed):

- **Placeholder inventory after S15** (all in
  `periodicals/presentation/pages/placeholder_page.dart`; delete the file
  when its last caller is gone — AGENTS §2.4): S16 owns FIVE pushes —
  `add_sheet.dart` "Add magazine issue" and "New magazine title";
  `library_page.dart`'s scan routes (`AddIssueOfPeriodical` → "Add magazine
  issue" with the series carried; `AddPeriodicalByIssn` → "New magazine
  title"); `periodicals_page.dart`'s FAB + empty-state button ("New magazine
  title"); `periodical_detail_page.dart`'s Edit ("Edit magazine title") and
  "Add issue" (both carry the observed series). "Add other item"
  (`add_sheet.dart`) is S17's — leave it standing.
- **Save plumbing (S13 contract, still current):** `AddIssueController` /
  `PeriodicalFormController` fire BOTH mutation signals
  (`libraryControllerProvider` + `periodicalsControllerProvider`) themselves
  on success — the form pages must NOT call `refresh()` after a save; pop on
  `state.hasValue && value != null`. Failures render through
  `catalogueSaveMessage(error, noun: 'issue')` / `noun: 'magazine title'`.
  `AddIssueController.save` takes an entity with `details: IssueOf(...)` and
  a blank title (the projection owns the title).
- **Removed series stay unreachable in the forms:** S15's detail page hides
  Edit / "Add issue" on a removed title, so the forms never receive one from
  the S15 UI; the scan route can still land on a removed series — the form
  should treat that as an ordinary prefill (the use cases accept it).
- **Series edit flow:** `periodicalByIdProvider(id)` is the observed-row
  read the form can preload from (N03);
  `PeriodicalFormController.saveEdit(id, applyEdits)` re-reads the CURRENT
  row (N03 again) — do not hand it a form-side snapshot to persist blindly.
- **Widget-test override set (settled in S15):**
  `periodicalRepositoryProvider` + `catalogueItemRepositoryProvider`
  (`FakePeriodicals` / `FakeItems`) + `settingsRepositoryProvider`
  (`FakeSettings`) + `clockProvider` (pinned) + `nowTickProvider` (`0`), and
  `deletePeriodicalUseCaseProvider` over the fakes when the janitor would
  otherwise touch the file system. The series page's tall header needs the
  big test surface (`tester.view.physicalSize = Size(1080, 2400)`,
  `devicePixelRatio = 1`) for row assertions — the lazy sliver does not
  build off-screen rows.
- **Gate test (B.5):** the two form pages are new entity-construction
  sites — add allow-list entries with reasons IN THE SAME COMMIT. The scan
  is textual with a letter look-behind: prose like "a `_addPeriodical(`
  helper" does not trip it, but never write the literal constructor call in
  a doc comment.
- **Ratchet:** S15 split the series page at 592 lines →
  `periodicals/presentation/widgets/periodical_detail_sections.dart`
  (subscription card, overflow delete, removed badge; page now 403). Keep
  each new form page under 500 — split widgets early, `add_book_page.dart`
  is the idiom.

Notes from S14 (what S14 built, and what S15 consumed):

- **Placeholders to replace:** `periodicals/presentation/pages/
  placeholder_page.dart` (`PlaceholderPage(pageName:periodical:)`) is pushed
  from FOUR sites: `add_sheet.dart` ("Add magazine issue", "Add other item",
  "New magazine title" — "Add other item" is S17's, leave its placeholder)
  and `library_page.dart`'s `routeScannedBarcode` (`AddIssueOfPeriodical` →
  "Add magazine issue" with the series carried; `AddPeriodicalByIssn` → "New
  magazine title"). S15 owns the series form placeholder ONLY via the drawer
  entry + periodicals page FAB (plan S15); the form itself is S16 — so after
  S15 the "Add magazine issue"/"New magazine title" placeholders still stand
  until S16. Delete `placeholder_page.dart` only when its last caller is
  gone (S16/S17).
- **Row/cover wiring in place:** rows and grid cards resolve an issue's
  cover through `periodicalCoversProvider` (`{uid: coverUrl}`, both mutation
  signals watched, `Left` → empty map) — the series page can reuse the same
  map for its issue list instead of re-reading per row.
- **Test pattern settled:** any widget test that renders `CatalogueItemRow`
  / `CatalogueItemGridCard` (or a page containing them) must override
  `periodicalRepositoryProvider` AND `nowTickProvider.overrideWith((ref) =>
  0)` — the cover map watches `PeriodicalsController`, whose build arms the
  real 60 s timer, which blocks `pumpAndSettle` (see `library_page_test.dart`
  for the override pair, `catalogue_item_row_test.dart` for the
  cover-fallback assertions).
- **Chip taps scroll first:** the kind chips widened `LibraryControlsRow`
  past the 800 px test surface — `library_controls_row_test.dart`'s
  `tapChip`/`tapClear` helpers scroll the row's SingleChildScrollView until
  the chip is visible before tapping.
- **Goldens:** the Library screen golden now renders the kind chips, the
  sheet FAB (tooltip changed: "Add to library") and kind badges —
  `key_screens_test.dart` gained the same two overrides. Regenerate the
  library PNGs on Linux CI (`update-goldens` workflow) when the series pages
  land; until then the 7 platform-golden failures stay "verify in CI".
- **Ratchet:** `catalogue_item_detail_page.dart` left the allow-list (681 →
  481; actions/lend/delete moved to `widgets/catalogue_item_actions.dart`,
  272 lines). `library_page.dart` is 397 after the menu-button split
  (`widgets/library_menu_button.dart`, 49).
- **Dead code removed:** `FindByIsbnUseCase` + `findByIsbnUseCaseProvider` +
  `routeScannedIsbn` are gone (D11's `RouteScannedBarcodeUseCase` owns the
  ISBN path now); `scan_routing_test.dart` drives the REAL use case over
  fakes instead of a stubbed `findByIsbn` callback — the failed-read
  fall-through cases live in `route_scanned_barcode_use_case_test.dart`.
- **Gate test:** unchanged — S14 adds no `CatalogueItem(`/`Periodical(`
  construction site in `lib/` (the placeholders carry entities through).

Notes for it (what S13 built, and the contracts S14–S16's pages consume):

- **Kind facet (U1):** `libraryKindFilterProvider` (`LibraryKindFilter`,
  keepAlive, in `library/application/library_filter_controller.dart` next
  to the language filter) holds `ItemKind?`; `toggle(kind)` selects or —
  when `kind` is already selected — clears; `clear()`. There is no `set`
  (the lint asked for a setter; toggle + clear are all U1 needs). The chip
  row reads `ref.watch(libraryKindFilterProvider)` for the selected state
  and calls `toggle` on tap; `LibraryController` already watches it and
  passes `LibraryQuery.kind`, so S14 adds NO list plumbing — only the
  chips. The language facet travels alongside, untouched.
- **Scan routing (D11):** `routeScannedBarcodeUseCaseProvider`
  (`library_providers.dart`) → `RouteScannedBarcodeUseCase(items:,
  periodicals:)` in `library/application/route_scanned_barcode_use_case.dart`;
  `call(raw)` takes the RAW scanner string and returns a sealed `ScanRoute`:
  `OpenCataloguedItem(item)`, `AddBookByIsbn(isbn)` (normalised),
  `AddIssueOfPeriodical(periodical)`, `AddPeriodicalByIssn(issn)`
  (canonical `NNNN-NNNC`). A failed repository read falls through to the
  "not catalogued" route of that barcode kind; a 977 code with a bad check
  digit takes the ISBN path unchanged. S14 replaces `routeScannedIsbn` in
  `library_page.dart` with a `switch` over the route (the existing
  "Already in your library" dialog = `OpenCataloguedItem`; the two
  magazine routes push the S14 placeholders until S15/S16 exist) and
  rewrites `test/features/library/scan_routing_test.dart` accordingly
  (`FindByIsbnUseCase` / `findByIsbnUseCaseProvider` then have no caller
  left in `lib/` — delete them in S14, AGENTS §2.4 no dead code).
- **`PeriodicalsController`** (`periodicals/application/`):
  `AsyncValue<List<PeriodicalListEntry>>` — `entry.periodical`,
  `issueCount`, `latestIssueDate`, `status: SubscriptionStatus`
  (`status.badgeLabel` is the S15 badge text, null = no badge). Rows are
  in `listAll` order (title, id). `build` watches `nowTickProvider` and
  reads `clockProvider`, so the list re-reads once a minute while open:
  **S15 must render with `skipLoadingOnReload: true`** (or `valueOrNull`)
  or the page flashes a spinner every minute. Methods: `refresh()`,
  `remove(id)` / `restoreRemoved(id)` (fail closed into `AsyncError`, like
  `LibraryController`), `delete(id)` → `Future<Either<Failure, Unit>>` —
  the series page's overflow shows a Left through
  `catalogueSaveMessage(failure, noun: 'magazine title')` (the
  `PeriodicalHasIssuesFailure` wording already exists); on Right the
  controller has refreshed itself, the page just pops.
- **`IssueListController(periodicalUid)`** (family): `AsyncValue<LibraryWindow>`
  (`books`, `hasMore`, `isLoadingMore`), `loadMore()`, `refresh()` — the
  exact shape `library_page.dart` renders, so S15's series page can copy
  its list/paging idiom (footer spinner while `isLoadingMore`, `loadMore`
  near the end). It watches `libraryControllerProvider` as its mutation
  signal, so the `LibraryController` builds too: **widget tests of the
  series page must override `settingsRepositoryProvider`** (the sort) as
  well as `catalogueItemRepositoryProvider` — `FakeSettings` in
  `periodical_fakes.dart` is enough.
- **`AddIssueController` / `PeriodicalFormController`:** `AddBookController`
  shape — `save(entity)` (refuses a persisted id), `saveEdit(id,
  applyEdits)` (re-reads the CURRENT row, N03), state `AsyncValue<T?>`
  (null = idle). On success they **fire both mutation signals
  themselves** (`libraryControllerProvider` + `periodicalsControllerProvider`),
  so S16's pages must NOT call `refresh()` after a save (the book form
  does; these do not — the page only pops on `state.hasValue && value !=
  null`). Failures: `catalogueSaveMessage(error, noun: 'issue')` /
  `noun: 'magazine title'`. The add-issue form's `save` input is a
  `CatalogueItem` with `details: IssueOf(...)` and a blank title.
- **Read providers** (`periodical_providers.dart`): `periodicalByIdProvider(id)`
  and `periodicalByUidProvider(uid)` → `Future<Periodical?>`, watching
  both signals. The issue detail page's "Open series" and the W4 cover
  fallback resolve through `periodicalByUid(item.issue!.periodicalUid)`.
  S14's `periodicalCoversProvider` map (plan step 4) is NOT built yet —
  add it to `periodical_providers.dart` watching the same two signals
  (`listAll()` → `{uid: coverUrl}`), or derive it from
  `periodicalsControllerProvider`.
- **Test fakes** (`test/features/periodicals/application/periodical_fakes.dart`):
  `FakePeriodicals` now answers `listAll` (ordered title/id, summary
  from the `issues` map), `markRemoved`, `restoreRemoved` (+ `…Failure`
  switches); `FakeItems` answers `page` (series facet → `IssueSorter`
  order; plain listing by id; search → empty; `pagesSeen` log,
  `pageFailure`); `FakeSettings` (defaults only). `findByIsbn` is still
  unimplemented on `FakeItems` — `route_scanned_barcode_use_case_test.dart`
  subclasses it.
- **Gate test:** unchanged — no new `CatalogueItem(` / `Periodical(` site
  (the controllers hand entities through; the route value wraps them).

Notes from S12 (the use-case contracts, still current):

- **Providers (all in `core/di/src/periodical_providers.dart`, exported by
  `core/di/providers.dart`):** `addPeriodicalUseCaseProvider`,
  `updatePeriodicalUseCaseProvider`, `deletePeriodicalUseCaseProvider`,
  `addIssueUseCaseProvider`, `updateIssueUseCaseProvider` — every one a
  `Future<…UseCase>` over `periodicalRepositoryProvider` (+
  `catalogueItemRepositoryProvider` for the issue/update ones, +
  `coverFileJanitorProvider` for delete). The module imports
  `library_providers.dart` one way; nothing imports it back. The
  `periodicalById`/`periodicalByUid` read providers S13 adds belong in this
  module too (mirror `catalogueItemById`; the mutation signal to watch is
  whatever S13's `periodicals_controller.dart` exposes).
- **Use-case contracts (`periodicals/application/`, 7 files, all < 120
  lines):**
  - `AddPeriodicalUseCase(periodicals)(Periodical)` → persisted row (id +
    minted uid). `UpdatePeriodicalUseCase(periodicals:, items:)(Periodical)`
    → stored row; `id == emptyId` → `NotFoundFailure` before any store
    access. Both go through `PeriodicalIngress.prepare` = `Periodical.validate`
    (title trimmed, ISSN canonical, blank ISSN → null) + ISSN pre-check →
    `DuplicateIssnFailure(existingTitle, existingPeriodicalId)` (update
    excludes its own id). A failed pre-check read is propagated (fail closed).
  - `UpdatePeriodicalUseCase` runs `items.runInTransaction` around
    `periodicals.update` + re-projection of `issuesOf(uid)`; rows whose six
    projected fields already match are skipped (editing notes/subscription
    rewrites nothing). Any `Left` — item write, issue read, or a projected
    row failing `CatalogueItem.validate` — rolls the series edit back
    (proven against Drift: a series title at `maxFieldChars` is valid but
    composes an over-cap issue title → `ValidationFailure`, title unchanged).
  - `DeletePeriodicalUseCase(periodicals:, releaseCover:)(int id)` → `Unit`;
    missing id → `right(unit)`; `countIssues > 0` →
    `PeriodicalHasIssuesFailure(n)` (soft-removed issues count); cover
    released via the janitor hook only after a successful delete. No vault
    interaction (F2: loans reference base rows, never the series).
  - `AddIssueUseCase(periodicals:, items:)(CatalogueItem)` — the input is a
    `CatalogueItem` whose `details` is an `IssueOf`; its `title` is ignored
    (projected from the series). Steps = `IssueIngress.prepare` (series
    `findByUid` → `IssueProjection.apply` → `CatalogueItem.validate`) then
    `IssueIngress.ensureIdentityIsFree` (numbered key → `findIssue`, bound →
    `findBoundVolume`, date-only → no lookup) then `items.insert`. Failures:
    unknown series → `ValidationFailure('The magazine title no longer
    exists.')` (worded through `FieldError('issue.periodicalUid', …)`);
    duplicate → `DuplicateIssueFailure(existingTitle, existingItemId)`; a
    non-issue input → `UnexpectedFailure` (caller bug — books/others use the
    generic catalogue use cases, O3).
  - `UpdateIssueUseCase(periodicals:, items:)(CatalogueItem)`: `emptyId` →
    `NotFoundFailure`; stored row missing → `NotFoundFailure`; stored row
    not a `magazineIssue` → `ValidationFailure('This item is not a magazine
    issue. An item cannot change its kind after it is added.')` (D8, checked
    before any series lookup); then the same ingress as add with
    `excludeId: id`. Moving an issue to another series is an ordinary edit
    (re-projected from, and deduplicated within, the new series).
  - A soft-removed series still accepts issues (the use cases do not look
    at `Periodical.removed`): the plan makes a removed title "visible but
    actionless" in the UI, so S15/S16 should hide "Add issue" / the edit
    entry on a removed title rather than expect a refusal here.
- **Messages:** every failure above is already worded by
  `catalogueSaveMessage(error, noun: …)` (S6); use `noun: 'issue'` /
  `'magazine title'` in the S13 controllers.
- **Test fakes to reuse:** `test/features/periodicals/application/
  periodical_fakes.dart` — `FakePeriodicals` (rows by id, `issues` by uid,
  per-method `…Failure` switches, `calls` log) and `FakeItems` (rows by id,
  `failUpdateAt`, a `runInTransaction` that restores its rows on `Left`).
  Both answer `UnimplementedError` for anything else, so a controller test
  that needs `listAll`/`page` must extend them (add the method, keep the
  switch style). `test/core/di/periodical_providers_test.dart` shows the
  override set (`periodicalRepositoryProvider`,
  `catalogueItemRepositoryProvider`, `coverFileJanitorProvider`).
- **Gate test:** unchanged — no new file constructs `CatalogueItem(` or
  `Periodical(` (the projection does, and it was allow-listed in S11), so
  the plan's "allow-list updated for the use-case construction sites" needed
  no entry. Mind doc comments in `lib/`: the scan is textual, so never write
  the literal constructor call in prose.

Notes from S11 (the repository hooks, still current):

- **Where the repository binding is:** `periodicalRepositoryProvider` lives
  in `core/di/src/database_providers.dart` (next to `wishlistRepository`),
  NOT in `periodical_providers.dart` — see Deviations. The use-case module
  (`core/di/src/periodical_providers.dart`, S12) imports
  `database_providers.dart` and `library_providers.dart` one way.
- **Repository contract as implemented** (`DriftPeriodicalRepository`,
  `periodicals/infrastructure/drift_periodical_repository.dart`, 441 lines;
  `periodical_mapper.dart`, 97):
  - `insert` / `insertAll` / `replaceAll` mint a uid when it is null OR
    blank; `update` ALWAYS keeps the STORED uid (an incoming different uid
    is ignored — issues link to the stored one). `update` with
    `id == emptyId` or a missing row → `NotFoundFailure`.
  - ISSN collisions → `DuplicateIssnFailure(existingTitle,
    existingPeriodicalId)` on `insert` and `update` (re-read after the
    failed write, no exception-text parsing); inside `insertAll` /
    `replaceAll` a collision is a plain `StorageFailure` and the whole batch
    rolls back (same as the item repository).
  - `findByIssn` normalises its input (`Issn.normalize`) before querying, so
    the D11 scan route can pass `Issn.fromEan13(...)` or raw text; a
    structurally invalid ISSN answers null without a query.
  - `delete` is one transaction: missing id → `right(unit)`; `countIssues >
    0` → `PeriodicalHasIssuesFailure(count)` (soft-removed issues count);
    the use case (S12) pre-checks the same rule, the repository is the last
    line of defence.
  - `findIssue` / `findBoundVolume` build an `IssueOf` and query
    `CatalogueSql.issueIdentityKey(db, issue)` — the SAME predicate the
    collision lookup uses (moved out of `CatalogueCollisions` in S11), so
    "already catalogued" means one thing. A bound volume never answers the
    numbered key; `volume: null` ≡ `0`.
  - `issuesOf` returns every issue of the series (soft-removed included) in
    `IssueSorter` order, mapped through the item mapper + `DriftItemDetails`
    (entities carry `details`). `listAll` is one LEFT JOIN + GROUP BY
    (`COUNT(item_id)`, `MAX(issue_date)`), ordered `title, id` in BINARY
    collation.
  - The repository does NOT snap `Periodical.language` to a stored spelling
    (`LanguageResolver` is item-specific); the projected issue rows are
    snapped by the item repository on write. Consequence for S12's
    skip-unchanged check: a series whose language differs from the stored
    spelling only by case has its issues rewritten on every series edit (a
    harmless no-op write). If the series page ever shows the periodical's
    own language next to its issues', the add/update periodical use cases
    are the place to canonicalise (or generalise the resolver) — not needed
    by the plan today.
- **Janitor (W4) done:** `CoverFileJanitor` has a required `periodicals:
  PeriodicalRepository` and reads `listAll()`; fakes in five test files
  implement `listAll` only. `DeletePeriodicalUseCase` receives
  `janitor.releaseReference` exactly like `DeleteCatalogueItemUseCase`.
- **Gate test:** `periodical_mapper.dart` is on the `Periodical(`
  allow-list ("DB mapper (rows validated on write)"); S16's periodical form
  and add-issue form will each need an entry (B.5).

Notes from S10 (the item-repository hooks, still current):

- **Reads:** every repository read starts from `CatalogueSql.joined(db)`
  (`books` LEFT JOIN `magazine_issues`) and maps through
  `TypedResult.toCatalogueItem(db, details)` (`catalogue_item_mapper.dart`),
  where `details` is a `DriftItemDetails` instance (`drift_item_details.dart`:
  `read(kindToken, issueRow)` fail-soft → book + one `appLog` per unknown
  token; `write(itemId, details)` upserts an issue's row / deletes a stale
  one; `delete(itemId)`; static `companion(itemId, issue)` and
  `isSupported(token)`). The periodical repository's `findIssue`,
  `findBoundVolume` and `issuesOf` should use exactly that join + mapper
  (construct its own `DriftItemDetails(db)`), and `issuesOf` must order with
  `CatalogueSql.issueOrderingTerms(db)`.
- **Facets:** `CatalogueSql.facetPredicate(db, query)` builds the typed
  WHERE for language / kind / periodicalUid; `CatalogueSql.searchRows(db,
  details, query, …)` is the FTS statement with the same facets and now
  returns entities. A series page (`periodicalUid` set) orders by
  `issueOrderingTerms` / `issueOrderSql` instead of `LibrarySort`; both paths
  are tested against `IssueSorter` across page seams
  (`drift_catalogue_item_kinds_test.dart`).
- **Writes:** `insert`, `update`, `insertAll`, `replaceAll` write the base
  row and then `_details.write(id, details)` inside one transaction;
  `insertAll` is now row-by-row (ids are needed for detail rows) but still
  one transaction. `update` refuses a stored unknown kind token with
  `UnsupportedItemKindFailure(token)` and leaves the row untouched; it does
  NOT refuse a kind change — that rule lives in S12's `UpdateIssueUseCase`
  (D8), because import (S18) updates re-imported rows by uid through the
  same repository method and reports a kind mismatch as a conflict (D6).
- **Collisions:** `CatalogueCollisions(db)` (`drift_catalogue_collisions.dart`)
  holds the best-effort `isbn(...)` and `issue(...)` lookups that turn a
  UNIQUE violation into `DuplicateIsbnFailure` / `DuplicateIssueFailure`
  (names the existing row). S11's ISSN race → `DuplicateIssnFailure` should
  follow the same shape (`findByIssn` after the failed write).
- **Sizes:** repository 446 lines (under 500, no ratchet entry), `CatalogueSql`
  285, collisions 99, details seam 99 — keep the repository under 500 by
  putting new SQL in `CatalogueSql`.
- **Janitor (W4):** `cover_file_janitor.dart` counts `books` + wishlist cover
  references; S11 adds periodical covers via the new repository's
  `listAll()` (or a dedicated cover-refs read) — add the "series cover
  survives a sweep" test next to the existing janitor tests.
- **DI:** `core/di/src/periodical_providers.dart` with a `periodicalRepository`
  provider over `appDatabaseProvider` (mirror `library_providers.dart`) and
  its `part` registration in `core/di/providers.dart`; run `gen`.

What S7 left for S10–S13 (domain contracts now fixed):

- `lib/features/periodicals/domain/`: `entities/periodical.dart`
  (`Periodical`, `validate`, `copyWith`, `sameAs`, `isSubscriptionTracked`),
  `value_objects/issn.dart` (`normalize`, `isValid`, `fromEan13`),
  `value_objects/periodical_frequency.dart` (token, `days`/`months` step,
  `label`, `fromToken`), `subscription_status.dart` (`of(periodical, now)`,
  30-day window, `badgeLabel`), `issue_cadence.dart` (`IssueCadence.next` →
  `IssuePrefill`, `nextDate`, `addMonthsClamped` in LOCAL calendar time),
  `issue_title.dart` (`compose`, `months`, `yearOf`), `issue_projection.dart`
  (`apply` rebuilds the row — allow-listed in the gate test; the issue use
  cases must validate the projected row), `issue_cover.dart` (`resolve`),
  `issue_sorter.dart` (`sort`, `compare`: date/volume/number desc NULLS
  LAST, id desc — the SQL twin in S10 must use `DESC NULLS LAST`),
  `repositories/periodical_repository.dart` (`PeriodicalSummary(periodical,
  issueCount, latestIssueDate)`; `listAll` ordered by title then id;
  `delete` fails closed with `PeriodicalHasIssuesFailure`; `findIssue`
  takes `volume: int?` — the repository must compare `COALESCE(volume, 0)`).
- The gate test now has a second census: `Periodical(` with the entity as
  the only trusted site. S16's periodical form will need an allow-list
  entry (plan B.5).

Notes from S5 for later sessions:

- Real names to use in the ADRs (after S1–S4): `CatalogueItem` /
  `CatalogueItem.validate` / `itemUid`, `ItemSourceType`, `LibrarySort`,
  `CatalogueItemRepository` / `DriftCatalogueItemRepository` /
  `catalogueItemRepositoryProvider` / `catalogueItemByIdProvider`,
  `Add/Update/DeleteCatalogueItemUseCase` (+ `…UseCaseProvider`),
  `CatalogueItemPage`, `CatalogueItemSorter`, widgets `CatalogueItemRow` /
  `CatalogueItemGridCard` / `ItemCover`, `CatalogueItemDetailPage`,
  `LendDecision.forItem`, `Loan.itemId`, `PublishItem`, `ImportPayload.items`,
  `LegacyRows.items`. Kept: `AddBookPage`, `AddBookController`,
  `BookCoverController`, `LendBookPage`/`LendBookUseCase`, `FindByIsbnUseCase`,
  `DuplicateIsbnFailure`, `WishlistBook`, the Drift data class `BookRow`, and
  every persisted/wire name (`books`, `book_uid`, `bookUid`, `book_id`,
  `books.db`, `books.json`).
- S4 extras beyond A.7 (same F7 rule): private helpers inside renamed files
  (`_ItemCoverState`, `_ItemDetailBody`, `_ItemGoneScaffold`,
  `_ItemLoadFailedScaffold`), test files `book_test.dart` →
  `catalogue_item_test.dart` and `book_validated_test.dart` →
  `catalogue_item_validated_test.dart` (S6 adds to the latter), and
  `CatalogueItemPage.toString()` now prints `CatalogueItemPage(…)`.
- `Loan.itemId` was done type-guided: the field was renamed in
  `borrower.dart`, then every analyzer error ("getter 'bookId' isn't defined
  for 'Loan'" / "named parameter 'bookId' isn't defined") was applied as an
  edit. `FfiVaultRepository` translates FRB `bookId` ↔ domain `itemId` with
  F2 comments. Every OTHER `bookId` (page params, `bookTitleProvider`,
  `LendBookPage.bookId`, `lendBook(bookId:)`) is untouched. Same technique
  for `ImportPayload.books` / `LegacyRows.books` → `items`.

Rename technique (learned in S1–S4):

- `git grep` on this macOS build does not support `\b`; use
  `git grep -P '\bBookRepository\b'` (PCRE). The system `grep` has no `-P`.
- Do identifier replacement with a lexer that skips string literals (JSON
  keys, UI text, fixtures) and handles `//`, `/* */`, `'…'`, `"…"`, `r'…'`,
  triple quotes and `${}` interpolation; rename inside comments too, then
  review the comment diff for references to Kotlin class names (restore
  those: e.g. "Kotlin `BookSort`" stayed). A blind regex breaks raw-string
  prefixes and fixtures. Treat `.g.dart` like any other file, then run `gen`
  and confirm it only re-emits what the script already wrote (hash lines and
  copied doc comments change — expected).
- `git ls-files -- 'lib/*.dart'` (single star) matches everything under
  `lib/`; `'lib/**/*.dart'` misses top-level files. Exclude `lib/src/rust/`
  and `test/core/database/generated/` (version-pinned helpers) explicitly.
- After the rename: `dart format`, then fix `lines_longer_than_80_chars` in
  comments by reflowing the paragraph (S1 used a textwrap script), then
  re-check the file-size ratchet (`layer_boundaries_test.dart`); S4 re-keys
  `book_detail_page.dart` → `catalogue_item_detail_page.dart` (recorded 677
  after S3's bump, see Deviations).
- Generated riverpod provider names follow the function names after `gen`
  (`bookRepositoryProvider` → `catalogueItemRepositoryProvider`); rename the
  provider functions and let `gen` produce the `…Provider` identifiers, but
  the lexer must rename the `…Provider` references in hand-written code too.

## Deviations from plan

- `S1`/`S3` — plan said the ratchet map only changes KEYS in the rename
  sessions (and B.5: no test-expectation changes) — four ratchet SIZES were
  bumped by the mechanical growth of longer identifiers (`dart format`
  wrapping signatures/expression bodies; the 80-column lint forcing
  doc-comment reflows): `add_book_page.dart` 638 → 640 (S1),
  `merge_library_use_case.dart` 543 → 544 (S1) → 545 (S3),
  `drift_catalogue_item_repository.dart` 597 → 599 (S3),
  `book_detail_page.dart` 676 → 677 (S3) → `catalogue_item_detail_page.dart`
  681 (S4, the constructor wrapped). No logic was added; comment paragraphs
  with slack were reflowed first wherever one existed. The bump carries a
  comment in `layer_boundaries_test.dart`; S8 and S14 shrink these files
  anyway.
- `S11` step 2 — the plan puts `periodicalRepository` in a new
  `core/di/src/periodical_providers.dart`. It was placed in
  `core/di/src/database_providers.dart` instead (next to
  `wishlistRepository`, whose header documents the identical situation):
  the cover janitor in `library_providers.dart` must watch it (W4), while
  S12's periodical use cases in `periodical_providers.dart` will need
  `library_providers.dart` (`catalogueItemRepositoryProvider` for issue
  writes, `coverFileJanitorProvider` for a deleted series' cover). Keeping
  the plan's placement would have made `library_providers ⇄
  periodical_providers` a cycle, which the DI module rule in
  `core/di/providers.dart` forbids ("a cycle means the binding belongs in a
  base module"). S12 created `periodical_providers.dart` with the use-case
  providers only. AGENTS §0 "one blessed way" over the plan's literal file
  name.
- `S11` — `CatalogueSql.issueIdentityKey` was extracted from S10's
  `CatalogueCollisions.issue` (pure move, no behaviour change, S10's tests
  unchanged) so the collision lookup and the new `findIssue` /
  `findBoundVolume` share the one D6 predicate. The `drift_catalogue_sql.dart`
  header no longer says "nothing outside `library/infrastructure` imports
  this file": the periodical repository does, on purpose.
- `S12` — the plan names five use-case files; two shared helpers were
  added beside them: `periodical_ingress.dart` (`Periodical.validate` +
  ISSN pre-check, used by add AND update) and `issue_ingress.dart` (series
  lookup → `IssueProjection.apply` → `CatalogueItem.validate` → D6 identity
  pre-check, used by add AND update). Without them each rule would exist
  twice (AGENTS §0 "one blessed way"); the use cases themselves stay 36–119
  lines. The plan's "gate allow-list updated for the use-case construction
  sites" needed no entry: no use case constructs a `CatalogueItem(` or
  `Periodical(` — the (already allow-listed) projection does, and the
  ingress helpers reference the gates. `DeletePeriodicalUseCase` reuses the
  `ReleaseCoverFile` hook type from `delete_catalogue_item_use_case.dart`
  (a `show` import of a sibling feature's application file) instead of
  declaring a third identical typedef.
- `S13` — the plan says "`LibraryFilterController` gains the kind facet";
  no class of that name exists (the file `library_filter_controller.dart`
  holds the `LibraryLanguageFilter` notifier), so a sibling
  `LibraryKindFilter` notifier was added to that file — one facet per
  notifier, as the file's header already argued for the language chip.
- `S13` — the plan does not say where the scan router lives. It is
  `library/application/route_scanned_barcode_use_case.dart` (sealed
  `ScanRoute` + `RouteScannedBarcodeUseCase`) with its provider in
  `library_providers.dart`: the quick-add scan is the Library's entry
  point and two of the four routes are book routes; the periodicals side
  is reached through the domain `PeriodicalRepository` (library/application
  already imports periodicals/domain for the W4 janitor). The use case
  returns a `ScanRoute`, not an `Either`: a repository Left is
  deliberately mapped to the "not catalogued yet" route (the S34 rule —
  navigation, not a gate; the save paths re-check), so there is no
  expected failure left for the UI to handle twice.
- `S13` — `AddIssueController` / `PeriodicalFormController` fire the
  mutation signals (`libraryControllerProvider` AND
  `periodicalsControllerProvider`) themselves on a successful save, where
  `AddBookController` leaves the single refresh to `AddBookPage`. Reason:
  each of these writes invalidates TWO lists (an issue changes the series
  summary; a series edit re-projects issues, D3) and a page that must
  remember two invalidations will eventually forget one — the robust
  place is the controller (AGENTS §0 "never patchwork"). The book
  controller was left as is (zero-behaviour rule for files S13 does not
  own); aligning it is a one-line follow-up if a reviewer wants one
  blessed way across the three forms.
- `S13` — `PeriodicalsController.delete(id)` returns the use case's
  `Either` (and refreshes on Right) instead of folding a Left into
  `AsyncError` like `remove`: `PeriodicalHasIssuesFailure` is an expected
  refusal that belongs to the row's action, while the list itself is
  still valid — turning it into a list error would blank a good screen.
- `S14` — the plan's step 4 says "cover via `IssueCover.resolve` with a
  `periodicalCoversProvider` map". `IssueCover.resolve` takes a `Periodical?`,
  but the map (one `listAll` read for the whole list, the point of the map)
  holds only `{uid: coverUrl}`. The rows therefore apply the same rule
  directly (own non-blank cover, else the map's series cover) with a comment
  citing parity; `IssueCover.resolve` remains the single implementation for
  the callers that DO hold a `Periodical` (issue detail page, publish). No
  duplicated *policy* beyond the two-line branch — the alternative (a
  uid→Periodical map) would carry whole entities into every row build.
- `S14` — the plan does not say where the three placeholder destinations
  live. They share one `PlaceholderPage(pageName:periodical:)` in
  `periodicals/presentation/pages/` (the add-issue route already carries the
  scanned series, so the S16 replacement keeps the call shape). The widget
  test asserts the pushed page's name, so S15–S17's swaps are test-visible.
- `S15` — the plan's step 3 says "replace the S14 placeholders that these
  pages satisfy"; the two pages S15 builds (the series list and the series
  detail) satisfy NONE of the four S14 placeholder pushes — those are all
  form destinations (S16/S17). S15 therefore replaced zero existing
  placeholders and ADDED its own pushes (the page FAB + empty-state button,
  the detail page's Edit and "Add issue") that S16 will swap. The Edit push
  uses the page name "Edit magazine title" (the add route's "New magazine
  title" would mislabel an edit) and carries the observed series, keeping
  S16's call shape symmetric with the add-issue route.
- `S15` — the plan's detail-page outline (hero, subscription card, issues)
  landed at 592 lines, over the 500-line cap: the subscription card,
  overflow menu and removed badge moved to
  `periodicals/presentation/widgets/periodical_detail_sections.dart` (403),
  the same split S14 made for `catalogue_item_detail_page.dart` (B.5 wants
  the split BEFORE extending a capped file, so it happened inside the
  session rather than as a follow-up).
- `S16` — the plan's add-issue step says "copies, pages, location prefilled
  from series", but the series entity carries only `location` among those
  three — pages/copies are prefilled from the LATEST ISSUE instead (the only
  honest source; a magazine's page count is a series habit, not a series
  field). Location comes from the series. All prefills fill EMPTY fields
  only (the book lookup's "user-entered wins" rule).
- `S16` — the plan's step list does not mention the item detail page's Edit
  action, but it pushed EVERY kind to `AddBookPage`, whose assembly carries
  no `details` — saving an issue there would have silently flipped its kind
  to book (D8). Edit is now kind-aware: an issue opens `AddIssuePage`;
  books (and, until S17, `other` rows) keep the generic form.
- `S16` — shared extractions beyond the plan's file list (AGENTS §0 "one
  blessed way", all with their prior behaviour pinned by existing tests):
  the Session-33 language dropdown moved from `add_book_page.dart` to
  `library/presentation/widgets/language_field.dart` (640 → 526, ratchet
  record lowered in the same commit); the 2:3 cover-crop presets moved from
  `catalogue_item_detail_page.dart` to `core/widgets/cover_crop.dart`; the
  form-side cover pipeline (downscale + store, no row write — forms have no
  row yet) is `library/application/form_cover_controller.dart` +
  `library/presentation/widgets/form_cover_field.dart`; the two periodical
  forms share `periodicals/presentation/widgets/form_rows.dart`
  (`FormTextRow`, `DatePickerRow`, `pickFormDate` 1900–2100,
  `formatFormDate`) and `series_picker_field.dart`. Orphaned form covers are
  reclaimed by the startup sweep (Q12) rather than per-form bookkeeping.

- `S17` — the plan's step "goldens for the series row + badge" is DEFERRED
  to land atomically with its PNG (user decision, 2026-10-23). The conflict:
  golden PNGs must be rendered by the `update_goldens` workflow on Linux
  ("never commit a Mac-rendered PNG"), this host is not the reference
  renderer, and the untagged `golden_files_exist_test.dart` guard fails the
  normal suite on a listed name without a committed PNG — so no choice
  inside the session could keep both that rule and the `full`-green Done
  gate. The repo's one precedent for ADDING a golden (`628d20d`) committed
  test + name + PNG together after a workflow run; the deferred golden
  follows that. No behaviour coverage is lost meanwhile: every
  `SubscriptionStatus` badge is asserted in `periodicals_page_test.dart`
  and the kind badges in `catalogue_item_row_test.dart`. The exact recipe
  for the follow-up commit is under *Next session*.
- `S17` — the plan names no controller for the Others form. The form reuses
  `AddBookController` (the existing controller over the generic
  Add/UpdateCatalogueItemUseCase pair that O3 assigns to the kind) instead
  of duplicating its 85 lines under a new name — AGENTS §0 "one blessed
  way"; the name is historical (F7 kept it) and the class is generic over
  `CatalogueItem`. The page fires the library refresh after a save, the
  same division of labour as the book form (the S13 note about the two
  signal-firing styles still stands).
- `S17` — shared extraction beyond the plan's file list (the S14/S16
  idiom): the detail page's private label/value row moved to
  `widgets/detail_row.dart` so the page and the new
  `ItemDetailsSection` share one layout (page 455 → 429 lines).
- `S18` — the plan's step "use case imports periodicals first" does not name
  the constructor: both import and export use cases gained a REQUIRED
  `PeriodicalRepository` (an optional one would let a backup silently skip
  periodicals, P1). ~24 test construction sites were updated mechanically
  (`periodicalRepo: FakePeriodicals()`), the same churn pattern as S1–S4.
- `S18` — the plan does not give a periodical dedup rule for import. The
  book rule was mirrored (one blessed way): same `periodicalUid` → update
  in place (stored uid wins, S11); same ISSN under another uid → skip;
  else insert. Without the ISSN skip, a re-import of a file whose series
  was locally recreated would die on `DuplicateIssnFailure` and roll the
  whole import back — the import contract is "you already own it" skips,
  not aborts.
- `S18` — CSV `Kind` cells carry the singular display name (`Book` /
  `Magazine issue` / `Other`), not the storage token or the plural chip
  label (U1): CSV is export-only and read by humans in spreadsheets. Dates
  in the new columns are ISO `YYYY-MM-DD` (the classic CSV exports none, so
  there was no format to mirror).
- `S18` — ADR 0014's Consequences (not the plan's step list) require the
  export page to say that older builds refuse a v4 file; the JSON format
  description now says so. No version number is named — S22 owns release
  numbering.
- `S19` — the plan names `fuzzy_index.dart` as the engine split, but the
  S19 orchestration (periodical plan + issue chain) would have re-grown the
  engine past its 721 record. So the field-spec section moved to
  `merge_fields.dart` too (the S16 "shared extractions beyond the plan's
  file list" idiom): engine 721 → 490, ratchet entry DELETED.
  `merge_page.dart` split its review widgets to
  `widgets/merge_review_section.dart` when the periodical counts landed
  (538 → 345, entry deleted). `merge_library_use_case.dart` moved its
  result/outcome types to `merge_result.dart` (re-exported, so callers keep
  one import) and netted 545 → 511 with the periodical apply — the ratchet
  entry was lowered, not deleted.
- `S19` — the plan does not give a periodical equality rule. `sameAs` is
  wrong for merge (it compares the reconciled uid, `addedDate`, `addedBy`),
  so `periodicalMergeEquals` mirrors the item engine's exclusions and adds
  the M09 cover rule + Session-33 language key (one blessed comparison per
  side). Issue-vs-issue comparisons skip the six projected base fields for
  the same reason (D3: derived data is never a conflict) — this, not the
  planner's re-projection alone, is what makes a series rename surface ONE
  series conflict and zero per-issue ones (risk D.2).
- `S19` — the plan does not mention resolution semantics for kinds.
  Take-theirs across kinds would flip a stored row's kind via the
  repository's deliberately kind-tolerant `update` (S10), violating D8 —
  refused with a `ValidationFailure`, and the review card hides the button
  (`canTakeTheirs`). `_freshCopyOf` (keep-both) now carries `details`: the
  old rebuild dropped it, which would have silently turned a kept-both
  issue into a book (latent — v3 files had no kinds); a resulting D6 key
  collision fails the insert with `DuplicateIssueFailure` instead.
- `S19` — `MergeDiffersDecision.localIsEmpty` also reads the periodicals
  now: overwrite replaces them (`PeriodicalRepository.replaceAll`), so a
  titles-only library is not "empty". The overwrite dialog and result copy
  say "books and magazine titles".
- `S20` — the plan does not say who reads the periodicals for a publish.
  The controller reads `periodicalRepositoryProvider.listAll()` and a Left
  REFUSES the publish with the catalogue read's safe message — S18's "no
  partial backup" rule applied to the site (issues published without their
  series would be a silent downgrade, P1). A removed series publishes no
  `periodicals[]` entry, but its issues still publish (D8: soft-remove
  leaves issues untouched; they show in the Library list, so they publish)
  and keep the series-cover fallback; the viewer groups an issue only when
  its series entry is present, else renders it plain.
- `S20` — the cover pipeline was extracted to `publish_cover_decider.dart`
  (`PublishCoverDecider` + `CoverDecision` + the `LocalCoverReader`/
  `RemoteCoverFetcher` typedefs, re-exported from the use case file): the
  use case (482) plus periodical covers would have crossed the 500-line
  cap (B.5's split-before-capping, the S14/S16/S19 idiom). It nets to 500.
  Periodical covers are keyed by UID, not the per-device id:
  `PublishCoverIds.pathForPeriodical` hashes `'periodical:<uid>'`
  (domain-separated so a series can never collide with a book's path, and
  stable across reinstalls), and the manifest's `coverUrlByBookId` carries
  `'periodical:<uid>'` keys — the store needs no migration (string map;
  an old manifest just lacks the keys → one redundant upload at most).
- `S20` — `periodicals[]` is omitted from books.json when empty (S18's v4
  rule, one blessed way): additive keys are ignored by older viewers, and
  a magazine-less library keeps the payload it always had.
- `S20` — viewer: the meta line now says "items" (the list is no longer
  books-only — F7's spirit), and the stale `viewerVersion: 4` header was
  bumped to 7 (v5/v6 had landed without bumping it; nothing reads the
  number — verified by grep).
- `S21` — the plan names five summary counts (`kindsApplied` …
  `rowsSkippedUnknownKind`); the summary carries three more fields. (1)
  `periodicalsDropped`: ADR 0014 and ARCHITECTURE §5.5 require invalid rows
  to be "dropped AND counted", and no plan count covers a `periodicals[]`
  row that fails `Periodical.validate`. (2)+(3) `itemKindsInvalid` /
  `periodicalsInvalid`: a DECLARED but UNREADABLE entry (corrupt, oversized,
  too-new schema) cannot be counted honestly — the rows it described are
  unknown — so the summary mirrors the §5.10 identity/network pattern
  (`identityInvalid`/`networkInvalid`) and the page says "could not be read".
- `S21` — W2 does not name the case "issue entry whose `periodicalUid` is in
  no `periodicals[]` row" (series absent, or dropped as invalid). Ruled like
  W1's import orphan rule (one blessed way across both formats): the link is
  detached and counted (`issuesDetached`), the row restores as the book its
  base row already is. A dangling soft link would be silent corruption.
- `S21` — "a flag-less fixture restores exactly as before" is honoured for
  books/wishlist/vault/covers AND interpreted for the v5 tables: restore
  CLEARS `periodicals` (and the books wipe cascades `magazine_issues`) even
  when the archive announces nothing. Pre-S21 the snapshot carried stale
  series rows into the new generation next to a catalogue of plain books —
  the mixed-state window M02 forbids. The authoritative overwrite now covers
  the kind tables (pinned by the flag-less test).
- `S21` — splits beyond the plan's named file (the S12/S19 "one blessed
  way" idiom; B.5 split-before-capping): `restore_backup.dart` was AT its
  553 cap, so the manifest parse moved to `backup_extras_reader.dart`
  (`parseBackupManifest`) and the legacy-DB read phase to
  `restore_legacy_read.dart`; the file nets 553 → 482 and its ratchet entry
  was DELETED. The shared periodical/issue JSON shape moved to
  `periodicals/infrastructure/periodical_json_codec.dart` with the W1
  exporter delegating — W2's "same object as Pitaka-JSON" is now structural,
  not by-convention (the importer keeps its own clamp+report reads; the
  policies differ deliberately, documented in the codec header).
- `S22` — the plan's integration-smoke step names one journey; S22 also
  REWROTE `integration_test/vault_smoke_test.dart`. Its finders could not
  match the current app (`Title` / `Save` — the book form says `Title *` /
  `Add book`; after lending it opened the drawer from the item detail page,
  which has none), so RELEASING §6.1 step 7 had a latent red test. Both
  journeys now share `smoke_support.dart`: a second file in the directory
  must coexist with the first in ONE `flutter test integration_test` run
  (app data persists between files), which needs the create-or-unlock vault
  step and per-run unique titles anyway — a shared helper rather than two
  copies (AGENTS §0 "one blessed way"). Behaviour of the vault journey on a
  cleared install is unchanged. Neither journey was executed (no device;
  macOS has no Rust framework — see *Next session*).
- `S22` — "ARCHITECTURE §5.4 history line finalised" needed no edit: S9
  already replaced the "Pending" paragraph with the final v5 text, and the
  `schemaVersion` doc comment (where §5.4 says the history lives) has entry
  5. The stale wording was elsewhere (module map, drawer line,
  `integration_test/` line) and was fixed instead.
- `S22` — the plan does not say where the catalogue guide sits or ends. It is
  the first card (adding items precedes publishing it) and ends on the
  Magazines page (`GuideDestination.magazines`): the Library is the screen
  under the drawer the reader came from, and the test pins destinations
  1:1 with guides, so a new guide needs a new destination. Copy length was
  cut to the render budget of `guide_page_test.dart` (3000 dp surface) —
  the guide is now ≈ 2880 dp under the test font, just above the backup
  guide's ≈ 2800; the test comment says so and calls the budget deliberate.
- `S22` — beyond the plan's step list: the backup guide's "what is inside"
  sentence was updated (it claimed "your books"; the archive now carries
  kinds and magazine titles, W2) and the mockup copy record gained §3.6 +
  facts rows (the catalog header says "edit both together").

## Open issues / blocked

- **Golden PNGs pending the Linux reference renderer (verify in CI):** the
  S14 library goldens (chips / sheet FAB / badges) were never regenerated,
  and S17's series-row golden is deferred (see Deviations). Remediation:
  Actions → "Update goldens" on branch `magazines` (or a PR touching
  `test/golden/**`), download the `goldens` artefact, then ONE commit with
  the series-row golden test + `kGoldenNames` entry + the PNGs. Until then
  the golden step on Linux CI is expected red; every other gate is green.
- **On-device smoke journeys not executed in this run** (S22): no Android
  device/emulator here; macOS desktop fails at `RustLib.init()` because
  the macOS target is not wired for cargokit (`pitak_crypto.framework`
  missing) — a pre-existing platform gap, not a regression. RELEASING §6.1
  step 7 runs both files on a cleared Android install before tagging.
- **Review nit (pre-S22, not fixed — a UI change outside S22's scope):**
  `catalogueSaveMessage` for `PeriodicalHasIssuesFailure` ends "… or mark
  the title as removed instead", but the series page's overflow offers
  only "Delete permanently" — `PeriodicalsController.remove` has no UI
  caller (S13 wrote the message, S15 the menu). Either add a "Remove"
  entry to `SeriesOverflowMenu` or drop the clause; the catalogue guide
  deliberately does not mention it.

## Session log

| Session | State | Commit | Date | Notes |
|---------|-------|--------|------|-------|
| — | — | `9ca2dba` | 2026-10-21 | plan committed; no sessions run |
| S0 | Done | `8899cc0` | 2026-10-21 | baseline: 2426 tests green in 86 s, 7 platform goldens (verify in CI); gen no diff |
| S1 | Done | `e216e6b` | 2026-10-21 | `Book` → `CatalogueItem`, 130 files; remaining `\bBook\b` in lib+test = 87, all prose/UI strings/fixtures; full green 2426 |
| S2 | Done | `2959034` | 2026-10-21 | `itemUid`/`ItemSourceType`/`LibrarySort`, 83 files. `git grep -n book_uid -- lib` (non-generated) = 18 lines, all column-name sites; `git grep -c "'bookUid'" -- lib` hand-written = 3 (unchanged: exporter, importer, `validate` field label); generated `app_database.g.dart` went 3 → 0 because the Drift row data-class JSON serializer (used nowhere in the app) now keys on the getter `itemUid`. The v1–v4 `test/core/database/generated/` helpers keep `bookUid` (version-pinned). Full green 2426 |
| S3 | Done | `34a7045` | 2026-10-21 | `CatalogueItemRepository`, `DriftCatalogueItemRepository`, `CatalogueItemRowMapper`, `Add/Update/DeleteCatalogueItemUseCase`, `catalogueItemRepositoryProvider`, `catalogueItemByIdProvider` (+ use-case providers); 6 lib + 2 test files moved; ratchet re-keyed (597 → 599, see Deviations); ADR 0011 note; full green 2426 |
| S4 | Done | `29689f8` | 2026-10-21 | A.7 complete: `CatalogueItemPage/Sorter/Row/GridCard`, `ItemCover`, `CatalogueItemDetailPage`, `LendDecision.forItem`, `Loan.itemId`, `PublishItem`, `ImportPayload.items`, `LegacyRows.items`; 6 lib + 7 test files moved; AGENTS §3.3 + ARCHITECTURE §2.1/§3 updated; ratchet re-keyed (677 → 681, see Deviations); `git grep` done-when returns only kept names, UI strings, fixtures and prose; full green 2426 |
| S5 | Done | `415adfd` | 2026-10-21 | ADR 0013 (F1–F8, D1–D11, O1–O4, recipe, resolved-decisions log), ADR 0014 (W1–W4 with JSON shapes), ADR index, ARCHITECTURE §3 module map (`periodicals/`), §5.4 v5 pending, §5.5 `item_kinds.json`/`periodicals.json` rows + old-build note, new §5.7 Pitaka-JSON v4 / `books.json` (§5.6 numbering kept — code comments cite it), §6 standing decision; AGENTS §3.3 `Periodical.validate`; CHANGELOG `[Unreleased]` Added/Changed with an in-progress note. No Dart changed; analyze + format green |
| S6 | Done | `0517263` | 2026-10-21 | `ItemKind`, sealed `ItemDetails` (`IssueOf`, `OtherItemOf`), `CatalogueItem.details`/`kind`/`issue`, validate appends `issue.*` errors, `copyWith(details:)`; `CatalogueRules.isValidDateOrder`; 10 new `FieldError` labels; 4 failures + shared `catalogueSaveMessage` (AddBookPage refactored onto it, 640 → 620 lines); `LibraryQuery.kind`/`periodicalUid`; 39 new tests (2465 total), full green |
| S7 | Done | `118bc1f` | 2026-10-22 | `features/periodicals/domain/` (10 files, 979 lines): `Periodical` + gate, `Issn`, `PeriodicalFrequency`, `SubscriptionStatus`, `IssueCadence`, `IssueTitle`, `IssueProjection`, `IssueCover`, `IssueSorter`, `PeriodicalRepository`/`PeriodicalSummary`; gate test scans `Periodical(`; `issue_projection.dart` allow-listed for `CatalogueItem(`; 68 new tests (2533 total), full green |
| S8 | Done | `d3ee18b` | 2026-10-22 | `drift_catalogue_sql.dart` (194 lines) takes `CatalogueSql` (ORDER BY twins, FTS statement, `ftsQuery`), `LanguageResolver`, `RollbackWith`; repository 599 → 437, ratchet entry deleted; no test expectation changed; full green 2533 |
| S9 | Done | `b9109f2` | 2026-10-22 | schema v5: `books.kind`, `magazine_issues` (FK cascade), `periodicals`; `PRAGMA foreign_keys = ON`; FTS dropped + rebuilt with `notes`; 6 raw indexes (2 partial UNIQUE); snapshot v5 + generated helper; matrix row (back-fill, notes FTS, column list, kinds round-trip, unique keys, cascade); `fts_rebuild_timing_test` (5 000 rows: migration 36 ms, rebuild 3 ms on this laptop; bound 20 s); `app_database_test` fixture rebuilt from the real v1 snapshot (26 columns now); ARCHITECTURE §5.4 updated; full green 2536 |
| S10 | Done | `b657c8c` | 2026-10-22 | `DriftItemDetails` seam; mapper reads the joined row and writes `kind`; repository: LEFT JOIN reads, kind + series facets in both list and FTS paths, `IssueSorter` order for a series, two-table transactional writes, `UnsupportedItemKindFailure` on write-back, `DuplicateIssueFailure` via `CatalogueCollisions`; `CatalogueSql.joined/facetPredicate/issueOrderingTerms/issueOrderSql`; 20 new tests (2556 total), full green |
| S11 | Done | `5ce4ec0` | 2026-10-22 | `periodicals/infrastructure/`: `periodical_mapper.dart` (tolerant read; blank ISSN → NULL; fail-closed `StateError` without a uid), `drift_periodical_repository.dart` (441 lines: every `PeriodicalRepository` method; `listAll` one LEFT JOIN + GROUP BY ordered title/id; uid minted on insert, stored uid wins on update; ISSN race → `DuplicateIssnFailure`; `delete` fails closed in one transaction; `findIssue`/`findBoundVolume` via `CatalogueSql.issueIdentityKey`, `issuesOf` in `IssueSorter` order through the item mapper); `periodicalRepositoryProvider` in `database_providers.dart` (see Deviations); `CoverFileJanitor.periodicals` (W4) + 4 test fakes; gate allow-list + mapper; 32 new tests (2588 total), full green 82 s |
| S12 | Done | `02f3f99` | 2026-10-22 | `periodicals/application/` (7 files): `PeriodicalIngress` (gate + ISSN pre-check), `AddPeriodicalUseCase`, `UpdatePeriodicalUseCase` (one `runInTransaction`; re-projects every issue, skips already-projected rows, a `Left` anywhere rolls the series edit back — proven against Drift), `DeletePeriodicalUseCase` (D8 pre-check, janitor release after delete, no vault), `IssueIngress` (series lookup → projection → gate → D6 identity pre-check), `AddIssueUseCase`, `UpdateIssueUseCase` (refuses a kind change, D8); `core/di/src/periodical_providers.dart` (5 providers) + barrel export; shared fakes `periodical_fakes.dart`; gate allow-list unchanged (no new construction site); 64 new tests (2652 total), full green 81 s |
| S13 | Done | `bba12b2` | 2026-10-23 | `LibraryKindFilter` (U1 toggle) watched by `LibraryController` → `LibraryQuery.kind`; `periodicals/application/`: `PeriodicalsController` (`PeriodicalListEntry` = summary + derived `SubscriptionStatus` from `clockProvider`, re-stamped on `nowTick`; `refresh`/`remove`/`restoreRemoved` fail closed; `delete` returns the `Either`), `IssueListController(periodicalUid)` (family; `LibraryWindow` over `page(LibraryQuery(periodicalUid:))`, D2-b depth on the library signal, N05 guard), `AddIssueController`, `PeriodicalFormController` (`AddBookController` shape, N03 re-read, fire both signals); `periodicalById`/`periodicalByUid` read providers (both signals); `RouteScannedBarcodeUseCase` + sealed `ScanRoute` (D11: 977 → `Issn.fromEan13` → `findByIssn`; else the S34 ISBN path) + provider; `library_page.dart` untouched (S14 switches on the route); fakes gained `listAll`/`markRemoved`/`restoreRemoved`/`page`/`FakeSettings`; gate allow-list unchanged; 43 new tests (2695 total), full green 77 s |
| S14 | Done | `526b9da` | 2026-10-23 | Splits: detail-page actions/lend/delete → `catalogue_item_actions.dart` (681 → 481, ratchet entry removed), app-bar menu → `library_menu_button.dart`; kind chips from `ItemKind.values` with toggle semantics + search hint "…ISBN, notes…"; add sheet (4 entries, 3 placeholders) replacing the add-book FAB; row + grid-card kind badges (Issue / Bound volume / Other) and W4 series-cover fallback via `periodicalCoversProvider` ({uid: coverUrl}, one `listAll`, both mutation signals); scan routing switches on `ScanRoute`, `FindByIsbnUseCase`/provider/`routeScannedIsbn` deleted; `scan_routing_test.dart` rewritten over the real use case (+ magazine routes), chip/badge/sheet tests added; widget tests rendering rows now override `periodicalRepositoryProvider` + pin `nowTickProvider`; gate allow-list unchanged; 16 new tests (2711 total), full green 82 s |
| S15 | Done | `322f3ed` | 2026-10-23 | `periodicals_page.dart` (281: rows with cover/publisher/"N issues · latest YYYY-MM", `SubscriptionBadge` per status, empty + safe error states, FAB → "New magazine title" placeholder), `periodical_detail_page.dart` (403: observes `periodicalByIdProvider` N03, hero, `SeriesSubscriptionCard` on the injected clock, "Add issue", issues via `IssueListController` paged newest-first in ONE outer scroll view with footer spinner, rows reuse `CatalogueItemRow` → item detail), overflow hard delete with the typed `PeriodicalHasIssuesFailure` refusal shown in place; sections split to `widgets/periodical_detail_sections.dart` (592 → 403, S14 precedent); removed title visible-but-actionless (edit/add hidden, D8); drawer entry "Magazines" between Wishlist and Library network; ZERO S14 placeholders replaced (all four are S16/S17 form destinations — see Deviations), S15 added its own pushes for S16 to swap; gate allow-list unchanged (no construction site); 17 new tests (2728 total), full green ~86 s |
| S16 | Done | `6c116fa` | 2026-10-23 | `periodical_form_page.dart` (416: fields per D2, ISSN inline validation, `LanguageField`, `FormCoverField`, frequency dropdown, "Track subscription" switch → start/end pickers, N03 saveEdit); `add_issue_page.dart` (496: `SeriesPickerField`, "Bound volume" switch swapping cover date ↔ from/to (D4), optional volume/number, label, own cover, copies/pages prefilled from the LATEST issue + location from the series — see Deviations, `IssueCadence` number/date prefill into empty fields only, live `IssueTitle` preview, blank title — projected by the use case); `catalogue_item_actions.dart` Edit is kind-aware (issue → AddIssuePage, D8); ALL magazine placeholders replaced (add sheet ×2, scan routes ×2, list FAB, detail Edit/Add issue) — only "Add other item" (S17) keeps `placeholder_page.dart` alive; shared: `LanguageField` (from add_book, 640 → 526 ratchet lowered), `cover_crop.dart` presets (from detail page), `FormCoverController.storeCapture` + `FormCoverField` (form-side cover pipeline, gen run), `form_rows.dart`; gate allow-lists +2 (both forms, "form assembly; gate is Add/UpdateIssueUseCase" / "…PeriodicalUseCase") with the censuses updated; 19 new tests (2747 total), full green ~85 s |
| S17 | Done | `52843fa` | 2026-10-23 | `other_item_form_page.dart` (329: title/transliteration/language/cover, **Description** = the shared notes column (O1), age group, copies, location, source, date added; `details: const OtherItemOf()` on every save so the kind can never flip, D8; reuses `AddBookController` over the generic use cases (O3) — see Deviations; page fires the library refresh like the book form); Edit routing in `catalogue_item_actions.dart` is now an exhaustive `switch (book.kind)` (an `other` no longer lands on the book form, D8); `ItemDetailsSection` (exhaustive `switch (item.details)`: issue block — series resolved via `periodicalByUidProvider` + "Open series" → `PeriodicalDetailPage` (U2), volume/number/cover date or bound from/to range (D4), label; nothing for books/others (O1)) inserted into the detail page; `DetailRow` extracted to `widgets/detail_row.dart` (page 455 → 429); add sheet's last placeholder push swapped and `placeholder_page.dart` DELETED — no placeholders remain; gate allow-list +1 ("form assembly; gate is Add/UpdateCatalogueItemUseCase"), census comment now 12; golden step deferred to its PNG commit (user decision — see Deviations/Open issues); 11 new tests (2758 total), full green ~92 s |
| S18 | Done | `9b9b72d` | 2026-10-23 | Pitaka-JSON v4 (W1): `kPitakaSchemaVersion = 4`; every row writes `kind`, issues nest `issue{}`, top-level `periodicals[]` (omitted when empty); importer parses periodicals FIRST (orphan rule needs the file's uid set), unknown kind skipped+counted (F6), `magazine-issue` without `issue{}` rejected, orphan issue → book + warning, over-cap periodical fields truncated+reported; `ImportPayload.periodicals` (+isEmpty); both use cases gained a REQUIRED `PeriodicalRepository` (~24 test sites churned); import applies periodicals before items in the same transaction (uid → update, ISSN → skip, else insert; summary counts + conditional import-page lines) and `_mergeIntoExisting` carries `details` (kind wins on re-import); export reads `listAll` for JSON + CSV (a read failure fails the export — no partial backup); CSV gains `Kind`/`Series`/`Volume`/`Issue`/`Issue date`/`Bound until`/`Issue label` appended after the classic columns (OWASP quoting covers the Series cell); export-page copy notes the v4 refusal on older builds; ARCHITECTURE §5.7 un-pended for W1; `FakeItems` gained `findByUid`/`findByIsbn` (one DI test migrated off the noSuchMethod trick); gate censuses unchanged (both importers reference their gates); 16 new tests (2774 total), full green ~71 s |
| S19 | Done | `61f9a04` | 2026-10-23 | Merge understands periodicals + issue identity (D6): engine split — `fuzzy_index.dart`, `merge_fields.dart` (+`MergeField.kind`/`issue`; the six projected base fields compare equal between two issues, D3), `issue_identity.dart` (record-typed D6 keys, SQL-twin parity), `periodical_merge.dart` (uid → ISSN → exact title, add-only, removal-as-conflict, `winners` remap + `matchedLocalSeries`); `planMerge` gained named periodical params (properties test untouched); use case gained required `periodicalRepo` (~34 sites), applies series first → items → re-projects merged series' issues in ONE transaction (new shared `IssueReprojection`, extracted from `UpdatePeriodicalUseCase`); overwrite replaces series too; take-theirs refused across kinds (D8) + keep-both keeps `details`; `MergePlanner`/`planMergeInBackground` 4-arg, isolate round-trip with periodicals pinned; merge page shows series counts + kept-local titles (review widgets split to `widgets/merge_review_section.dart`, ratchet 538 → deleted; engine 721 → deleted; use case 545 → 511); gate allow-list +1 (merge orphan rule), census 13; 48 new tests (2822 total), full green ~90 s |
| S20 | Done | `9faab2c` | 2026-10-23 | Publish carries kinds + series (W3): `PublishItem.kind` (required) + nested `PublishIssue`, `PublishPeriodical` (public fields only) + `PublishExport.periodicals[]` (omitted when empty, schema stays 1); `redactPeriodicalForPublish` strips the subscription window/notes/location/source (pinned by the redaction test); cover pipeline extracted to `publish_cover_decider.dart` (typedefs re-exported — use case nets to 500) with `pathForPeriodical` (`'periodical:<uid>'` hash domain + manifest keys); issues publish `IssueCover.resolve` (a series cover is ONE upload, shared by its entry and falling-back issues); a removed series has no entry but its issues publish (D8); use case `call` gained required `periodicals` (22 test sites churned); the controller reads `listAll()` and refuses the publish on a Left; viewer v7: fixed kind facet (Books · Magazines · Others), issues grouped under their series header with Issue/Bound volume/Other badges, unknown kinds plain, meta says "items"; ARCHITECTURE §5.7 un-pended; gate censuses unchanged (no new construction site); 20 new tests (2842 total), full green ~83 s |
| S21 | Done | `98508ad` | 2026-10-23 | `.pitabak` carries kinds (W2): writer emits `item_kinds.json` (`hasItemKinds`, every non-book row) + `periodicals.json` (`hasPeriodicals`, W1 periodical objects + `issues[]` by `bookUid`), omitted when empty; `BackupManifest` +2 flags (default false — flag-less archives restore as before AND now clear the v5 kind tables, see Deviations); `ItemDetailsArchiveCodec` (envelopes: 4 MiB cap, row caps via `ImportLimits`, first-wins duplicates, every row re-validated, drops counted); shared `PeriodicalJsonCodec` (W1 exporter delegates — one shape by construction); `applyRestoredItemDetails` joins kinds/details onto legacy rows pre-write (detaches declared-but-undetailed, kind-disagreeing, missing-row and orphan-series links, all counted); restore writes items row-by-row + detail rows + `DriftPeriodicalRepository.replaceAll` on the BUILDER db in the one transaction; duplicate D6 keys refuse the archive (fail closed, pinned); `RestoreSummary` +6 counts +2 invalid flags, page sentences for each; `restore_backup.dart` 553 → 482, ratchet entry DELETED (`parseBackupManifest` → extras reader; `restore_legacy_read.dart` extracted); `CreateBackupUseCase` requires `PeriodicalRepository` (Left ⇒ no backup — no partial snapshot); ARCHITECTURE §5.5 un-pended; gate censuses unchanged; 36 new tests (2878 total), full green ~90 s |
| S22 | Done | (this commit) | 2026-10-24 | Release hygiene: sixth guide `GuideId.catalogue` ("Books, magazines and other items", first card, → `PeriodicalsPage`; mockup §3.6 + facts rows; backup guide names kinds); `integration_test/catalogue_kinds_smoke_test.dart` (title → issue → other → vault → lend the issue → backup → restore) + shared `smoke_support.dart`, `vault_smoke_test.dart` rewritten onto it (its finders could never match — see Deviations); fastlane `29.txt` + `291/292/293.txt` (495 chars); CHANGELOG `[Unreleased]` reconciled (Added/Changed/Fixed/Removed + pre-tag obligations); ARCHITECTURE module map / drawer / integration lines un-staled (§5.4 already final since S9); F-Droid purity classpath check printed nothing (self-test matches on `play`; pubspec identical to main); neither smoke journey executed (no device; macOS lacks the Rust framework); `gen` no diff, rust diff vs main empty; 2 new tests (2880 total), full green ~95 s |
