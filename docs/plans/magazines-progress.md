# Magazines / item kinds — progress log (session handoff)

Plan: `docs/plans/magazines.md` (revision 5). Protocol: Part B of the plan.
**Read this file first in every session; update it as the last action of
every session; commit it with the session's commit.**

## State

- Last completed session: **S11** (periodical repository, DI, janitor W4)
- Branch: `magazines` — working tree clean: **yes**
- Last commit: S11's commit (S10 was `b657c8c`, S9 `b9109f2`, S8 `d3ee18b`,
  S7 `118bc1f`, S6 `0517263`, S5 `415adfd`, S4 `29689f8`, S3 `34a7045`,
  S2 `2959034`, S1 `e216e6b`, S0 `8899cc0`)
- Full suite last green at: **S11, 2026-10-22** — 2588 tests, 82 s
  (`flutter test --exclude-tags golden`)
- Run stopped here (one session per run, B.3): the next run starts at S12.
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

**S12 — Use cases: periodicals and issues.** Nothing in flight. Follow the
plan's S12 steps verbatim.

Notes for it (what S11 built, and the hooks S12 should reuse):

- **Where the repository binding is:** `periodicalRepositoryProvider` lives
  in `core/di/src/database_providers.dart` (next to `wishlistRepository`),
  NOT in a `periodical_providers.dart` — see Deviations. S12 creates
  `core/di/src/periodical_providers.dart` for the use-case providers (and
  registers it in `core/di/providers.dart`); that module may import
  `database_providers.dart` and `library_providers.dart`
  (`catalogueItemRepositoryProvider`, `coverFileJanitorProvider`) with no
  cycle, because nothing in `library_providers.dart` will need it.
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
    the use case (S12) still pre-checks for a friendlier message but the
    repository is the last line of defence.
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
    snapped by the item repository on write. If the series page ever shows
    the periodical's own language next to its issues', S12's add/update
    periodical use cases are the place to canonicalise (or generalise the
    resolver) — not needed by the plan today.
- **Janitor (W4) done:** `CoverFileJanitor` has a required `periodicals:
  PeriodicalRepository` and reads `listAll()`; fakes in four test files
  implement `listAll` only (`_NoPeriodicals` / `_Periodicals`). S12's
  `delete_periodical_use_case` gets `janitor.releaseReference` exactly like
  `DeleteCatalogueItemUseCase` does (`library_providers.dart`).
- **Gate test:** `periodical_mapper.dart` is on the `Periodical(`
  allow-list ("DB mapper (rows validated on write)"). S12's
  `add_issue_use_case` constructs `CatalogueItem(details: IssueOf(...))` —
  it calls `CatalogueItem.validate` on the projected row, so it needs no
  allow-list entry; a periodical use case that builds a `Periodical(` must
  reference `Periodical.validate` (B.5).
- **Transactions:** `update_periodical_use_case` (one transaction;
  re-projects every issue) should wrap its work in
  `CatalogueItemRepository.runInTransaction` — Drift transactions are
  zone-scoped, so the periodical repository's `update` and the item
  repository's `update` calls inside the callback join it, and a `Left`
  rolls everything back (`RollbackWith`).

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
  NOT (yet) refuse a kind change — the plan puts that in S12's
  `update_issue_use_case` (D8).
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
  base module"). No `periodical_providers.dart` exists yet; S12 creates it
  with the use-case providers. AGENTS §0 "one blessed way" over the plan's
  literal file name.
- `S11` — `CatalogueSql.issueIdentityKey` was extracted from S10's
  `CatalogueCollisions.issue` (pure move, no behaviour change, S10's tests
  unchanged) so the collision lookup and the new `findIssue` /
  `findBoundVolume` share the one D6 predicate. The `drift_catalogue_sql.dart`
  header no longer says "nothing outside `library/infrastructure` imports
  this file": the periodical repository does, on purpose.

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
| S11 | Done | _(this commit)_ | 2026-10-22 | `periodicals/infrastructure/`: `periodical_mapper.dart` (tolerant read; blank ISSN → NULL; fail-closed `StateError` without a uid), `drift_periodical_repository.dart` (441 lines: every `PeriodicalRepository` method; `listAll` one LEFT JOIN + GROUP BY ordered title/id; uid minted on insert, stored uid wins on update; ISSN race → `DuplicateIssnFailure`; `delete` fails closed in one transaction; `findIssue`/`findBoundVolume` via `CatalogueSql.issueIdentityKey`, `issuesOf` in `IssueSorter` order through the item mapper); `periodicalRepositoryProvider` in `database_providers.dart` (see Deviations); `CoverFileJanitor.periodicals` (W4) + 4 test fakes; gate allow-list + mapper; 32 new tests (2588 total), full green 82 s |
