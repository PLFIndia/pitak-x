# Magazines / item kinds — progress log (session handoff)

Plan: `docs/plans/magazines.md` (revision 5). Protocol: Part B of the plan.
**Read this file first in every session; update it as the last action of
every session; commit it with the session's commit.**

## State

- Last completed session: **S15** (Magazines list page + series detail page,
  drawer entry, subscription badges, typed delete refusal)
- Branch: `magazines` — working tree clean: **yes**
- Last commit: S15's commit (S14 `526b9da`, S13 `bba12b2`, S12 was `02f3f99`,
  S11 `5ce4ec0`, S10 `b657c8c`, S9 `b9109f2`, S8 `d3ee18b`, S7 `118bc1f`, S6
  `0517263`, S5 `415adfd`, S4 `29689f8`, S3 `34a7045`, S2 `2959034`, S1
  `e216e6b`, S0 `8899cc0`)
- Full suite last green at: **S15, 2026-10-23** — 2728 tests, ~90 s
  (`flutter test --exclude-tags golden`)
- Run stopped here (one session per run, B.3): the next run starts at S16.
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

**S16 — Periodical form and add-issue form.** Nothing in flight. Follow the
plan's S16 steps verbatim.

Notes for it (what S15 built, and the surfaces S16 plugs into):

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

## Open issues / blocked

_(None yet. Record the exact failing command and the first lines of its
output. Platform-golden failures go here tagged "verify in CI".)_

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
| S15 | Done | `4da57f9` | 2026-10-23 | `periodicals_page.dart` (281: rows with cover/publisher/"N issues · latest YYYY-MM", `SubscriptionBadge` per status, empty + safe error states, FAB → "New magazine title" placeholder), `periodical_detail_page.dart` (403: observes `periodicalByIdProvider` N03, hero, `SeriesSubscriptionCard` on the injected clock, "Add issue", issues via `IssueListController` paged newest-first in ONE outer scroll view with footer spinner, rows reuse `CatalogueItemRow` → item detail), overflow hard delete with the typed `PeriodicalHasIssuesFailure` refusal shown in place; sections split to `widgets/periodical_detail_sections.dart` (592 → 403, S14 precedent); removed title visible-but-actionless (edit/add hidden, D8); drawer entry "Magazines" between Wishlist and Library network; ZERO S14 placeholders replaced (all four are S16/S17 form destinations — see Deviations), S15 added its own pushes for S16 to swap; gate allow-list unchanged (no construction site); 17 new tests (2728 total), full green ~86 s |
