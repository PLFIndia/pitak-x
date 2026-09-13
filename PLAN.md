# PLAN.md — Session 30 — N10-d part 2: paged reads + windowed library list

Roadmap: `fix-schedule.md` §1 (NEXT = N10-d part 2 of 2). Finding:
`astra-review.md` N10 ("Large-library operations run unbounded work on the UI
isolate" — "lists load the whole catalogue"), sub-item d of the S26 breakdown.
Part 1 (S29, `2ef9381`) made both list reads FINAL in SQL with a TOTAL order
(`…, added_date DESC, id ASC`). Part 2 puts the page boundary on those same
statements and makes the Library screen load rows in windows.

## Understanding

Today (`library_controller.dart:127-159`) `_load` calls `repo.query(...)` or
`repo.search(...)` and the controller's state is `AsyncValue<List<Book>>` —
the WHOLE catalogue, every time, on every keystroke (debounced), sort or chip
change. `library_page.dart:157-179` renders `_BookList(books)` with
`ListView.separated` / `GridView.builder` over the full list. The widgets are
lazy; the READ is not. With the accepted 100,000-row import limit that is up
to 100k `Book` objects materialised through Drift on the UI isolate per load.

What part 1 bought us: because ORDER BY is total, "the first N rows SQLite
returns" IS "the first N rows the user should see", and the (N+1)th page is
well-defined. Nothing needs re-sorting in Dart.

Verified this session (from source, not memory):

- **Value readers of the controller's list:** only `library_page.dart:55`
  (`ref.watch(libraryControllerProvider)` → `.when(data: books)`). Grep
  `libraryControllerProvider).(value|valueOrNull|requireValue|when|…)` and
  `.future` in `lib/` → nothing else. The derived providers
  (`libraryLanguages` `providers.dart:233`, `bookTitle` `:644`, `bookById`
  `:671`, `pendingSnapshot` `:763`) watch it ONLY as the N04 mutation
  signal and read the REPOSITORY (`distinctLanguages`/`getById`/`getAll`).
  So a windowed state does not starve any of them. 12 other sites only
  `invalidate`/`refresh` it or read `.notifier`.
- **Mutation semantics to preserve:** every write path invalidates or
  refreshes the controller (N03/N04). After a refresh the FIRST window must
  reload (a removed row disappears, a rename shows) — but the user's scroll
  position should not be thrown away wholesale. Decision D2 below.
- **N05 revision guard** (`_revision`) must cover `loadMore` too: a
  late "page 2 of the OLD query" must never be appended to the NEW query's
  list.
- **Test fakes:** 32 test files implement `BookRepository` (18 explicit
  full implementations, 14 via `noSuchMethod`). Adding a page parameter to
  `query`/`search` (rather than new methods) means touching the explicit
  ones again (S29 did 22 files for a signature change — recorded cost).
  Adding NEW methods with `noSuchMethod`-free fakes is the same cost.
  Decision D3.
- **Drift page API (2.28.2, pub-cache):** `SimpleSelectStatement.limit(int
  limit, {int? offset})`; `customSelect` takes raw SQL so `LIMIT ?n OFFSET
  ?m` bound as `Variable<int>`. Keyset needs a `WHERE (key, added_date, id)
  < (?, ?, ?)`-style predicate expressed per sort — SQLite supports row-value
  comparisons since 3.15 (bundled 3.51.0), and the sort key is an
  EXPRESSION for two of the three sorts (`_ageRank`, `_languageBlank` +
  `_languageKey`), so the cursor would carry (rank/blank, key, addedDate,
  id). Both are implementable; they differ in what happens when rows change
  between pages.
- **`_LimitBooksSelects`** (`drift_book_repository_test.dart:25-46`) is the
  S29 seed: it proved SQLite's own first-3 are right. Part 2 replaces the
  interceptor trick with a real page call.
- Baseline gates: analyze 0; format 408/0; Flutter **1611 passed / 0
  failed** (`/tmp/pitak-s30-flutter-baseline.txt`, EXIT=0, 0 `[E]`); cargo
  **32 passed**, 2 expected ignored — identical to the S29 handoff. HEAD =
  `origin/main` = `c5c4ea5`, tracked tree clean.

## Privacy & threat notes

No user data leaves the device; no new fields, no logging, no isolates. New
inputs reaching SQL: a page size and an offset/cursor — both produced by the
controller, never by the user. They are still bound as `Variable`s (never
interpolated) and clamped (page size `1..maxPageSize`, offset `>= 0`) at the
repository boundary so a hostile caller cannot ask SQLite for a negative or
astronomically large window. A keyset cursor would carry a row's sort key
(language string / age token) — same data already in the list; it never
persists. Threat model otherwise unchanged from S29.

## Investigation notes

- Re-read in full: `drift_book_repository.dart` (`query` `:53-75`,
  `_orderingTerms` `:120-139`, `_orderSql` `:147-158`, `search` `:335-368`),
  `book_repository.dart`, `library_controller.dart`, `library_page.dart`,
  `library_filter_controller.dart`, `providers.dart:226-238, 636-680,
  754-776`, `book_sorter.dart` header.
- Tests read: `drift_book_repository_test.dart` (S29 group + fixture +
  oracle + interceptor), `library_controller_test.dart` (8 tests; the fake
  records `sortsSeen`/`searchesSeen`), `library_page_test.dart` (6 widget
  tests over a fake repo), `library_adaptive_layout_test.dart` (2).
- Not yet read (read before touching): `book_row.dart`, `book_grid_card.dart`,
  `empty_library_state.dart` — presentation only, probably untouched.

## Concrete design (after D1–D5)

**Domain** (`library/domain/`, pure Dart):
- `library_query.dart`: `LibraryQuery({text = '', sort, language})` — the
  triple the controller already carries. `text`/`language` are normalised
  (trimmed; blank → `''` / `null`) in the constructor so every consumer
  sees ONE canonical form. `==`/`hashCode` for the controller's "did the
  list change" check. `libraryPageSize = 60`, `maxLibraryPageSize = 500`
  (a hard clamp: nothing in the app asks for more than the reload-to-depth
  path, which is bounded by what the user actually scrolled).
- `book_page.dart`: `BookPage({items, hasMore})` immutable. `hasMore` is
  computed by the repository by asking SQLite for `limit + 1` rows and
  trimming (one statement, no COUNT(*) — a COUNT over an FTS join would
  cost a second full walk). D1-a: OFFSET semantics documented on the port.

**Port** (`book_repository.dart`): `query`/`search` REMOVED (D3-c). New:
`Future<Either<Failure, BookPage>> page(LibraryQuery query, {required int
limit, int offset = 0})`. Doc: same order/filter contract as before; the
LIMIT/OFFSET lives on the SAME statement as the ORDER BY; blank `text` →
typed select, otherwise FTS; `limit` clamped to `1..maxLibraryPageSize`,
`offset` clamped to `>= 0`; the OFFSET seam caveat.

**Infrastructure** (`drift_book_repository.dart`): `page` dispatches to the
two private statements S29 already has (`_pageTyped` / `_pageFts`), each
with `LIMIT ?(limit+1) OFFSET ?offset` as bound `Variable<int>`s (FTS) or
Drift's `..limit(limit + 1, offset: offset)` (typed — Drift writes the
literals itself; ints, not user strings). The `_orderingTerms`/`_orderSql`
twins are untouched.

**Application** (`library_controller.dart`): state `AsyncValue<LibraryWindow>`.
`LibraryWindow({books, hasMore, isLoadingMore})` immutable, in
`application/library_window.dart` (same file style as `MergeUiState`).
- `build()`: watches sort + facet as today, builds a `LibraryQuery`; if it
  differs from the last one (sort/chip changed = different list) the depth
  resets to one page; if it is the SAME (invalidate after a mutation = same
  list) it reloads `max(loadedCount, pageSize)` rows in ONE statement
  (D2-b). The depth survives the rebuild because Riverpod keeps the SAME
  notifier instance across `invalidate` (verified: `_notifierNotifier.result
  ??=` in `async_notifier/base.dart:534`; only a full dispose recreates it).
- `refresh()`: same depth rule as an invalidate (D2-b).
- `onQueryChanged()`: new text = new list → depth resets to one page.
- `loadMore()`: no-op unless `hasMore && !isLoadingMore` and the state has
  data; sets `isLoadingMore`, fetches `offset = books.length`, appends under
  the SAME `_revision` (N05 extension: a late page from an older revision is
  dropped, and `isLoadingMore` is only cleared for the current revision). A
  `Left` from the page fetch keeps the loaded rows and clears
  `isLoadingMore` — the user keeps what they have and can scroll again to
  retry; it is NOT promoted to `AsyncError` (which would blank a list the
  user is looking at).
- `remove`/`restoreRemoved`: unchanged (fail closed → `AsyncError`).

**Presentation** (`library_page.dart`): `_BookList(window, onLoadMore)`;
`CustomScrollView` with `SliverList.separated` / `SliverGrid.builder` +
a trailing `SliverToBoxAdapter` loader row when `isLoadingMore`; a
`NotificationListener<ScrollNotification>` fires `onLoadMore` when
`metrics.extentAfter < 600` px (~1.5 screens ahead). Also fires when the
first page does not fill the viewport (no scroll notification would come)
— handled by triggering from the itemBuilder when the LAST item is built
and `hasMore` (cheap; the controller de-dupes concurrent calls).

**Tests (red first):**
1. `drift_book_repository_test.dart`: page group — pages concatenated ==
   S29 oracle for every sort × facet, typed AND FTS (compile-red); `hasMore`
   false only at the end; clamp; the OFFSET seam documented by a test that
   inserts between pages and asserts the duplicate (D1-a evidence, not
   hidden). `_LimitBooksSelects` RETIRED (replaced by real pages).
2. `library_controller_test.dart`: fake gains `pagesSeen` (offset, limit);
   new: `loadMore` appends + forwards offset; a stale `loadMore` completion
   is dropped; `refresh` after two pages reloads 120 in ONE call (D2-b);
   sort change resets depth to one page; `loadMore` failure keeps rows.
3. `library_page_test.dart`: scrolling to the end shows more rows; footer
   loader visible while the second page is pending.

## Proposed approach (draft — D1–D3 decide the shape)

OSS reference: Android Paging 3's `PagingSource.load(LoadParams) →
LoadResult.Page(data, prevKey, nextKey)` is the model for "repository returns
a page + a token for the next one, controller appends" (the Kotlin sibling
app almost certainly used Room + Paging). Riverpod's own docs show
"infinite scroll" as an `AsyncNotifier` holding `List<T>` + `hasMore` with a
`fetchNext()` that guards against concurrent loads. No new dependency.

1. **Domain (pure Dart):** a small immutable `BookPage` value in
   `library/domain/` — `items`, `hasMore`, and (keyset only) an opaque
   `next` cursor. `pageSize` constant (`libraryPageSize`, tentatively 60 —
   roughly 3 phone screens of rows / 2 tablet grids; D4 if the user cares).
2. **Port:** `BookRepository` gains the page read(s) (shape per D3). Doc
   states: same order/filter contract as `query`/`search`, the LIMIT lives
   on the SAME statement (`_orderingTerms` / `_orderSql`), never two
   statements.
3. **Infrastructure:** `DriftBookRepository` implements it on top of the
   S29 statements: `..limit(size, offset: off)` on the typed select; `LIMIT
   ?n OFFSET ?m` bound variables on the FTS raw SQL. (Keyset: a per-sort
   WHERE predicate mirroring `_orderingTerms`/`_orderSql`, third twin →
   more surface to keep equivalent; see D1 trade-off.)
4. **Controller:** state becomes `AsyncValue<LibraryWindow>` where
   `LibraryWindow` = `{ books, hasMore, isLoadingMore }` (immutable, in
   `application/` next to the controller, matching the `MergeUiState`
   style). `_load` fetches page 1; new `loadMore()` fetches the next page
   under the SAME `_revision` and appends; concurrent `loadMore` calls
   collapse into one. `refresh()`/rebuild reload page 1 (D2 decides whether
   they reload up to the previously loaded depth).
5. **Presentation:** `_BookList` gets `hasMore` + `onLoadMore`; a
   `NotificationListener<ScrollNotification>` (or a sentinel last item)
   triggers `loadMore` near the end; a trailing progress row while
   `isLoadingMore`. Grid and list both.
6. **Tests (red first):**
   - repository: page N+1 never repeats/skips a row for every sort × facet on
     the S29 seeded fixture (pages concatenated == the S29 oracle) — red on
     HEAD (compile: no page API); `hasMore` false exactly at the end; page
     size clamp; FTS path identical; an insert between pages — offset:
     document the duplicate/skip window; keyset: prove no duplicate.
   - controller: `loadMore` appends under the same revision; a late
     `loadMore` result from an old query is dropped (N05 extension);
     `refresh` reloads the head; existing 8 tests adapted to the window
     state.
   - page: scrolling to the end calls `loadMore`; the trailing loader shows.
   - `_LimitBooksSelects` retired (the direct page test replaces it) or kept
     as an independent guard — decide while writing.

## Decision points

- **D1 — OFFSET or keyset?** Both are correct on a static table (order is
  total). They differ when rows change between page loads:
  - (a) **OFFSET/LIMIT.** Simplest; one extra `limit(size, offset:)` on the
    existing statements; no third SQL twin. Cost: an insert/removal between
    page 1 and page 2 shifts rows by one → one duplicate or one skipped row
    at the seam. In THIS app every write path already invalidates/refreshes
    the controller (N03/N04), which reloads from page 1 — so the seam
    problem only appears for writes the controller is not told about (none
    in `lib/` today) or for the brief window between a write and its
    refresh. SQLite still walks and discards the first `offset` rows, but
    with the ORDER BY it already sorts the full set either way — the saving
    is materialisation (Dart objects), which is the actual N10 cost.
  - (b) **Keyset (`(sortKey, addedDate, id)` cursor).** Immune to the seam
    problem and cheaper for deep pages. Cost: a per-sort WHERE predicate in
    BOTH the typed and raw-SQL paths (a third and fourth twin of
    `BookSorter`), a cursor type crossing the domain port, and the language
    key must be `TRIM(COALESCE(...))` on both sides (S29 lesson). Roughly
    double the code and equivalence-test surface of (a).
  - Recommendation: **(a)**, because every mutation already restarts the
    list from page 1 and the seam case is unreachable from the UI; record
    the limitation in the port doc and pin it with a test that documents
    (not hides) the behaviour.
  - **ANSWER: (a) OFFSET/LIMIT.**
- **D2 — after `refresh()`/rebuild (sort, chip, invalidate), reload just
  page 1 or up to the previously loaded depth?** (a) page 1 only — simple,
  scroll jumps to the top after any mutation (today the whole list reloads
  too, but the scroll offset survives because the widget keeps its
  `ScrollController` and the list is the same length). (b) reload
  `loadedCount` rows in ONE statement (`LIMIT loadedCount OFFSET 0`) so a
  remove/rename/cover change keeps the user where they were; sort/chip
  changes (a genuinely new list) go back to page 1. Recommendation: **(b)**
  for `refresh()`/invalidate, **page 1** for `build` when the sort or
  facet changed — it is the difference between "I deleted a book and the
  list jumped to the top" (a regression against today) and today's
  behaviour.
  - **ANSWER: (b) reload to the previously loaded depth on refresh /
    invalidate; page 1 when sort or facet changed.**
- **D3 — port shape:** (a) a `page` parameter on the existing
  `query`/`search` (`{required int limit, int offset = 0}`) → same two
  methods, 18 fakes edited again (scripted regex as in S29); the no-page
  callers (none in production after this) disappear. (b) two new methods
  `queryPage`/`searchPage` returning `BookPage`, leaving `query`/`search`
  for tests/other callers → 18 fakes ALSO need the new methods (they
  `implements`), same edit count, plus two redundant whole-list methods
  kept alive only for tests. (c) ONE new method `page(LibraryQuery intent,
  {required int limit, int offset})` where `LibraryQuery` = `{text, sort,
  language}` — the controller already carries exactly this triple; one
  method to fake, one to test, `query`/`search` REMOVED. Recommendation:
  **(c)** if the user accepts a slightly larger diff now for one blessed
  read; otherwise **(a)**.
  - **ANSWER: (c) one `page(LibraryQuery, {limit, offset})` method;
    `query`/`search` removed.**
- **D4 — page size:** 60 (recommendation) unless the user has a number.
  - **ANSWER: 60 accepted.**
- **D5 — execute end-to-end or pause at each decision point?**
  - **ANSWER: (a) end-to-end** (pause on broken assumption / new decision /
    privacy trade-off / before commit).

## Steps

- [x] 1. State check, baseline gates (done — see Investigation notes).
- [x] 2. Ask D1–D5 (one at a time) — answered a / b / c / 60 / a.
- [x] 3. Red tests: repository page group (compile-red on HEAD: `page`
      undefined, 8 sites), controller part-2 group (compile-red:
      `LibraryWindow`/`loadMore` undefined, 20+ sites), page widget tests
      (compile-red: fake missing `page`). Behaviour-red proved via a
      HEAD-shaped graft (`test/_tmp_red/`, removed): "build asks for one
      page" → `Expected: <60> Actual: <1073741824>`; "window shows one page
      of rows" → 150 ≠ 60.
- [x] 4. Domain: `library_query.dart` (`LibraryQuery`, `libraryPageSize`,
      `maxLibraryPageSize`, `sameIntentAs`), `book_page.dart` (`BookPage`).
- [x] 5. Port `page(LibraryQuery, {limit, offset})` replaces `query`/`search`;
      Drift impl `_listRows` (`..limit(size+1, offset:)`) / `_searchRows`
      (`LIMIT ?n OFFSET ?m` bound) on the S29 ordered statements; clamps.
- [x] 6. Controller: `AsyncValue<LibraryWindow>`, `_loadHead` (D2-b depth
      rule via `sameIntentAs`), `loadMore` (de-duped, revision-guarded,
      failure keeps rows), `_supersede`.
- [x] 7. Presentation: `CustomScrollView` + `SliverList.separated` /
      `SliverGrid.builder` + footer sliver (`library-load-more` key),
      `NotificationListener` → `loadMore` at `extentAfter < 600`.
- [x] 8. Fakes: 20 sites rewritten by `/tmp/migrate_fakes.py` (every site
      printed + counted), 2 by hand (`library_controls_row_test.dart`
      filtering fake, `wishlist_use_cases_test.dart` delegating decorator);
      `add_edit_book_test.dart` 6 direct calls → `firstPage` helper;
      `remote_cover_materializer_test.dart` `_LibraryRebuilds.build` type;
      unused `app_settings.dart` imports dropped where `BookSort` vanished.
- [x] 9. Gates green; `build_runner` LAST → 1 hash-only `.g.dart` diff.
- [ ] 10. Commit (approval) — explicit paths only.

## Out-of-scope observations

- (carried from S29) `getAll()` has no `id` tie-break; `distinctLanguages()`
  orders `COLLATE NOCASE` while `languageAsc` orders BINARY.
- **Fake sprawl, third time paid:** 22 files hand-roll `BookRepository`. S29
  touched every one for a signature; S30 touched every one again for the
  `query`/`search` → `page` replacement (scripted, but the script needed a
  regex fix and two hand edits). A `test/support/fake_book_repository.dart`
  base class would make the next port change a one-file edit. Not done here
  (scope), strongly recommended as its own small session.
- `library_page.dart` uncovered lines are the pre-existing grid branch
  (`library_adaptive_layout_test.dart` covers it but its coverage run is
  separate) and the availability badge path — unchanged by this session.
- The OFFSET seam (D1-a) is documented and pinned; if a write path is ever
  added that does NOT invalidate/refresh `libraryControllerProvider`, the
  seam becomes user-visible. The N04 pattern (every mutation signals the
  controller) is what keeps it unreachable.
- `pendingSnapshot` still calls `repo.getAll()` for the needs-metadata
  count — a whole-catalogue read on the vault-unlocked reminders path. Not in
  the N10 sub-item list; a `COUNT`/filtered read would close it (note for a
  future N10-f if the user wants it).

## Result

**Done (uncommitted, awaiting approval).** The Library screen reads the
catalogue in 60-row windows; SQLite orders, filters AND cuts the window in
one statement for both the plain listing and the FTS search; the controller
appends pages on scroll, reloads to the user's depth after a write, and
starts over on a new intent; a late page from a superseded intent is dropped.

Gates (S30 end): analyzer **0**; format **411 files / 0 changed**; Flutter
**1628 passed / 0 failed** (`/tmp/pitak-s30-flutter-final.txt`, EXIT=0, 0
`[E]`) = 1611 baseline + 17 (repo +4 net after retiring the interceptor
test, controller +8, page +3, domain +6, minus 4 folded); cargo **32
passed** (Rust untouched); `git diff --check` clean; `build_runner` run LAST
→ only `library_controller.g.dart` (hash + state type), `.fvmrc`/`.gitignore`
untouched. Coverage **72.90%** (+0.14); `library_controller.dart` 77/78,
`drift_book_repository.dart` 156/165 (misses = pre-existing `on Object
catch` branches), `library_query.dart` 13/13, `library_window.dart` 10/10,
`book_page.dart` 3/3 (after `library_query_test.dart`). Lib-diff privacy
scan: no print/log/http/Uri/Platform/isolate/io added; the window ints are
clamped and bound, never interpolated.

Mid-session corrections (recorded, no design change):
1. `_FakeBookRepo` migration regex missed `query({` (brace on the signature
   line) → 0 sites on the first run; pattern widened to `\(\{?\n`, second
   run rewrote 20 and reported the 2 non-trivial bodies for hand edits.
2. `library_page_test` drags used `find.byType(Scrollable).first`, which is
   the HORIZONTAL chips row — the vertical list never moved (`pagesSeen`
   stayed `[(0,60)]`). Probe printed the three scrollables' axes; tests now
   target the `CustomScrollView`'s descendant scrollable.
3. `LibraryQuery` `==`/`hashCode` tripped `avoid_equals_and_hash_code_on_
   mutable_classes` (no `@immutable` without `meta`, which the N14 domain
   allowlist forbids) → replaced by an explicit `sameIntentAs`; the one
   controller test that compared queries with `equals` now asserts fields.

Not device-verified (deterministic in tests). Optional sandbox pass on
`dev.khoj.pitaka.fdroid`: import > 60 books, scroll, watch the footer
spinner and that a delete keeps the scroll position.

## Commit paths (explicit — never `git add -A`)

lib/features/library/application/library_controller.dart
lib/features/library/application/library_controller.g.dart
lib/features/library/application/library_window.dart
lib/features/library/domain/book_page.dart
lib/features/library/domain/library_query.dart
lib/features/library/domain/repositories/book_repository.dart
lib/features/library/infrastructure/drift_book_repository.dart
lib/features/library/presentation/pages/library_page.dart
test/app_lock_navigator_test.dart
test/core/di/derived_providers_test.dart
test/core/widgets/app_gate_test.dart
test/features/import_export/export_controller_test.dart
test/features/import_export/export_page_share_test.dart
test/features/import_export/export_roundtrip_test.dart
test/features/import_export/import_controller_test.dart
test/features/import_export/import_library_use_case_test.dart
test/features/import_export/import_page_test.dart
test/features/import_export/merge_controller_test.dart
test/features/import_export/merge_library_use_case_test.dart
test/features/library/add_book_page_test.dart
test/features/library/add_edit_book_test.dart
test/features/library/book_cover_controller_test.dart
test/features/library/book_detail_page_test.dart
test/features/library/domain/library_query_test.dart
test/features/library/drift_book_repository_test.dart
test/features/library/library_adaptive_layout_test.dart
test/features/library/library_controller_test.dart
test/features/library/library_controls_row_test.dart
test/features/library/library_page_test.dart
test/features/library/remote_cover_materializer_test.dart
test/features/vault/lend_book_use_case_test.dart
test/features/wishlist/wishlist_detail_page_test.dart
test/features/wishlist/wishlist_use_cases_test.dart
test/widget_test.dart
PLAN.md
