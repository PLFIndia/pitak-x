# PLAN.md — Session 29 — N10-d part 1: library ORDER BY / filter fully in SQL

Roadmap: `fix-schedule.md` §1 (NEXT = N10-d part 1 of 2). Finding:
`astra-review.md` N10 ("Large-library operations run unbounded work on the UI
isolate"), sub-item d of the S26 breakdown (a→b→c→d→e). Part 1 is a
prerequisite, not pagination itself: make every list read produce its FINAL
order and filter inside SQLite, so part 2 can put `LIMIT/OFFSET` (or keyset)
on the same statement and get a correct page.

## Understanding

Two reads feed the Library screen (`library_controller.dart:127-159`):

1. **Blank query → `BookRepository.query(sort, language)`**
   (`drift_book_repository.dart:38-88`). Language filter and two of the three
   sorts are SQL. `BookSort.ageGroupAsc` is NOT: SQL orders by the raw
   `age_group` TEXT token (alphabetical: `above-10 < above-15 < above-3 …`),
   then `_byAgeRank` (`:92-101`) re-sorts the WHOLE list in Dart by
   `AgeGroup.sortRank`. A `LIMIT` on this statement would page the wrong
   order.
2. **Non-blank query → `BookRepository.search(query)`**
   (`drift_book_repository.dart:319-341`): FTS5 join, hardcoded
   `ORDER BY added_date DESC`, no language predicate. The controller then
   filters by language in Dart and re-sorts with `BookSorter.sort`
   (`library_controller.dart:143-158`). Same problem: a `LIMIT` here pages
   the unfiltered, wrongly-ordered set.

The review's "lists load the whole catalogue" is the symptom; the Dart-side
post-processing is what makes a simple SQL page IMPOSSIBLE. This session
removes the post-processing while keeping the visible order byte-identical.

Verified facts (this session, from source — not memory):

- Only one production caller of `query`/`search`/`BookSorter`:
  `library_controller.dart:132,143,157`. 22 test fakes implement both
  methods; 14 more use `noSuchMethod`.
- `AgeGroup` has 5 bands (`book.dart:52-66`); `sortRank` order is
  `above-3(0) < above-6(1) < above-10(2) < above-15(3) < advanced(4)` — NOT
  token alphabetical. `fromToken` (`:83-114`) is tolerant (trim/lower/legacy
  names), BUT every Drift write goes through `Book.toCompanion()`
  (`book_mapper.dart:72`, `ageGroup: Value(ageGroup?.token)`), including
  restore (`restore_backup.dart:413`) and `insertAll`/`replaceAll`. No raw
  `INSERT INTO books` exists in `lib/` other than the backup WRITER's own
  scratch Room DB (`backup_archive_writer.dart:249`, not our table). So the
  `age_group` column holds exactly one of the 5 canonical tokens or NULL —
  a 5-branch SQL `CASE` over the token is EXACTLY `sortRank`, with
  `ELSE <big>` covering NULL (and any hypothetical foreign token, which
  `fromToken` would ALSO map to null → same "last" bucket).
- Language filter today: `t.language.lower().equals(lang.toLowerCase())`
  (`:45-47`). SQLite `lower()` is ASCII-only (probe: `lower('Ελληνικά')` is
  unchanged, `sqlite_version() = 3.51.0`), while Dart `toLowerCase()` folds
  Unicode → **the SQL path and the Dart search-path filter already
  disagree** for non-ASCII languages (probe: `query(language: 'Ελληνικά')`
  returned 0 rows for a row whose language is exactly `Ελληνικά`, because
  `lower(col) = 'ελληνικά'` never matches). The chip value comes from
  `distinctLanguages()` (the stored string verbatim), so equality with the
  STORED value is what the user expects. See D1.
- `BookSorter` (domain, N05) is the single Dart source of ordering truth and
  has its own tests (`book_sorter_test.dart`). Its language rule is
  "blank/null LAST, then `compareTo` (code-unit) A→Z" — the SQL path's
  `CaseWhenExpression` + `OrderingTerm.asc(t.language)` under SQLite BINARY
  collation is the same order. Tie-break is `added_date DESC` everywhere.
- Drift 2.28.2 (pub-cache): `CaseWhenExpression`/`CaseWhen`
  (`case_when.dart:9-53`), `Expression.caseMatch` (`expression.dart:228`),
  `Constant<T>` writes a literal, `Variable` binds `?`; `customSelect`
  returns `Selectable<QueryRow>` (`connection_user.dart:391`); the FTS
  `search` already maps rows via `_db.books.map(r.data)`.
- Existing tests that pin the current order: `add_edit_book_test.dart:85-110`
  (`languageAsc`, filtered `recentlyAdded`, `ageGroupAsc` 3 rows),
  `library_controller_test.dart:271-300` (N05: search honours sort, via a
  FAKE repo — the fake sorts nothing, so this test asserts the controller's
  Dart sort; it will need to move to the repository level).

## Privacy & threat notes

No user data leaves the device; no new fields, no logging. The one new
untrusted input reaching SQL is unchanged: the user's search text (already
tokenised + quoted by `_ftsQuery`) and the language chip (bound as a
`Variable`, never interpolated). The age-rank `CASE` is built from the
enum's own tokens (compile-time constants), not from input. Threat model:
identical to today — a local SQLite DB an attacker already holds is game
over regardless of ORDER BY.

## Investigation notes

- `drift_book_repository.dart` re-read in full (`query` `:38-88`,
  `_byAgeRank` `:92-101`, `search` `:319-341`, `_ftsQuery` `:345-351`).
- `library_controller.dart` re-read in full (`_load` `:127-159`).
- `tables.dart` (books: `language` TEXT nullable, `age_group` TEXT nullable,
  `added_date` INT), `app_database.dart` (FTS5 external-content
  `books_fts`, `content_rowid=id`, triggers), `book_sorter.dart`,
  `book.dart:47-114` (`AgeGroup`), `book_mapper.dart`, `app_settings.dart`
  (`BookSort` 3 values), `library_filter_controller.dart` (chip value
  trimmed, never blank).
- Probe (deleted): SQLite `lower()` ASCII-only; `trim()` does not strip
  NBSP; `sqlite_version() 3.51.0`.
- Baseline gates: analyze 0; format 408/0; Flutter **1604 passed / 0 failed**
  (`/tmp/pitak-s29-flutter-baseline.txt`, EXIT=0, 0 `[E]`); cargo **32
  passed**, 2 expected ignored — identical to the S28 handoff.

## Proposed approach

OSS reference: SQLite's own "ORDER BY CASE" idiom (documented in the SQLite
`SELECT` docs, "ordering by an expression") and Drift's
`CaseWhenExpression` API (pub-cache `case_when.dart`). No new dependency.

1. **Age-rank in SQL.** A private `Expression<int> _ageRank(Books t)` =
   `t.ageGroup.caseMatch<int>({Constant(above3.token): Constant(0), …},
   orElse: Constant(AgeGroup.values.length))` built by iterating
   `AgeGroup.values` (so a future band is picked up automatically; the enum
   stays the single source of the rank). `query(ageGroupAsc)` orders by
   `[asc(_ageRank), desc(addedDate)]`; `_byAgeRank` DELETED. Also an
   `asc(id)` final tie-break on every sort so the order is total and stable
   (needed for a correct page in part 2; today ties are "SQLite scan order",
   which for `ORDER BY added_date DESC` over an index is deterministic but
   unspecified).
2. **One ordering builder for both paths.** A private
   `List<OrderingTerm> _orderFor(BookSort sort, Books t)` used by `query`.
   The FTS `search` is a `customSelect` string; give it the SAME order by
   rendering the three `ORDER BY` variants as SQL text next to the Drift
   terms — or (preferred, one truth) rewrite `search` as a Drift `select`
   over `books` with `t.id.isInQuery(<customSelect of FTS rowids>)`… Drift's
   `isInQuery` requires a `BaseSelectStatement`; `customSelect` is a
   `CustomSelectStatement` (NOT a `BaseSelectStatement`, verified
   `custom_select.dart:5`). So: keep `search` as raw SQL and add the
   `language` predicate + an `ORDER BY` fragment produced by a private
   `_orderSql(BookSort)` that is the textual twin of `_orderFor`. Equivalence
   between the two is then a TEST obligation (step 4), not a code-sharing
   guarantee. See D2.
3. **Port change.** `BookRepository.search(query)` →
   `search(query, {required BookSort sort, String? language})` so the
   repository returns the FINAL list. Controller's search branch becomes a
   plain unwrap; `BookSorter` import and the Dart filter go away from the
   controller. `BookSorter` itself STAYS in domain (its tests define the
   contract the SQL must match — that is exactly what the equivalence test
   uses it for). 22 fakes updated mechanically (signature only).
4. **Regression tests (red first).**
   - `drift_book_repository_test.dart` new group "N10-d — order and filter
     are final in SQL": a seeded fixture (5 bands + null, 4 languages incl.
     blank/null AND one non-ASCII, addedDate ties, ~40 rows from a seeded
     `Random`); for EVERY `BookSort` × {no language, ASCII language,
     non-ASCII language}: `query(...)` id-order == `BookSorter.sort(all)`
     filtered id-order — **red on HEAD for `ageGroupAsc`** only via the new
     assert that NO Dart re-sort happens? No: `_byAgeRank` makes the result
     correct today, so the ORDER equivalence is green on HEAD. The red test
     is the SQL-shape one: "`query(ageGroupAsc)` returns rows already in
     band order from SQLite" — provable by running the repository's
     statement with `LIMIT 2` … which needs the page API (part 2). Honest
     red evidence for part 1 therefore = (a) the **search** path:
     `search('x', sort: languageAsc, language: 'Hindi')` — compile-red
     (no such parameters) and behaviour-red against a HEAD graft that
     ignores them; (b) a **Drift `QueryInterceptor`** test that captures
     the SQL text of `query(ageGroupAsc)` and asserts it contains `CASE`
     and does NOT need a Dart re-sort — asserting on generated SQL is
     brittle; instead assert the observable: install an interceptor that
     appends ` LIMIT 3` to the intercepted `runSelect` for the books
     statement and check the 3 rows ARE the first 3 of the expected band
     order — **behaviour-red on HEAD** (HEAD's SQL would return the first 3
     alphabetical tokens `above-10, above-15, above-3`, then Dart re-sorts
     only those 3). This is the exact bug part 2 would hit, stated as a
     test. See D3 for whether this interceptor trick is acceptable.
   - `library_controller_test.dart`: N05 "search results honor the
     persisted sort" → becomes "controller forwards sort + language to
     `search`" (recording fake); the ordering assertion moves to the
     repository equivalence test.
   - `add_edit_book_test.dart` existing 3 `query` tests: unchanged, must
     stay green.
   - Language-filter parity test: a `Ελληνικά` row is found by
     `query(language: 'Ελληνικά')` and by `search(…, language:
     'Ελληνικά')` — **behaviour-red on HEAD** for `query` (probe: 0 rows).
5. Docs: `book_sorter.dart` header (it is now the TEST oracle + the
   controller no longer calls it), `book_repository.dart` contract,
   repository class doc.

## Decision points

- **D1 — language equality semantics.** Today `query` uses SQL `lower()`
  (ASCII-only) and the search path uses Dart `toLowerCase()` (Unicode).
  Both compare against a chip value that is a STORED string verbatim.
  Options: (a) **exact match on the stored string** (`t.language.equals
  (lang)`) — simplest, matches what the chip shows, fixes the non-ASCII
  miss, but `hindi` typed by hand would no longer match `Hindi` (no UI
  types a language filter; the only writer is the chip); (b) keep
  case-insensitive via SQLite `COLLATE NOCASE` (still ASCII-only — same
  non-ASCII miss as today); (c) store a Unicode-lowercased `language_sort`
  shadow column (schema change; `title_sort`/`author_sort` precedent).
  **Proposal: (a).**
- **D2 — search statement shape.** (a) keep raw SQL with a textual
  `ORDER BY` twin of the Drift terms (equivalence guaranteed by test);
  (b) rewrite as Drift `select(books).join(...)`/subquery — `books_fts` is
  not a Drift table (virtual table created by `customStatement`), so a
  typed join would need a hand-written `ResultSetImplementation`; more
  code, no user-visible gain. **Proposal: (a).**
- **D3 — red-evidence technique for the age-rank change.** The order
  equivalence is green on HEAD (Dart re-sort hides the SQL bug); the
  honest red is "the SQL statement's own order is wrong", observable
  only through a page. (a) A test-only `QueryInterceptor` that appends
  `LIMIT 3` to the books select — proves the exact part-2 bug without
  adding production API early; (b) skip red for this sub-step and rely
  on part 2's page tests. **Proposal: (a).**
- **D4 — execute end-to-end, or pause at each decision point?**

**Answers (2026-09-13):** D1 → **(a)** exact match on the stored string;
D2 → **(a)** raw-SQL `ORDER BY` twin + equivalence test; D3 → **(a)**
test-only `QueryInterceptor` appending `LIMIT`; D4 → **(a)** end-to-end
(pause only if an assumption breaks).

## Steps

- [x] 1. State check, baseline gates (done — see Investigation notes).
- [x] 2. Ask D1–D4 (one at a time) — all answered (a).
- [x] 3. Red tests written and proved red (evidence in Result).
- [x] 4. `drift_book_repository.dart`: `_ageRank` (Drift `caseMatch` over
      `AgeGroup.values`), `_languageBlank`, `_languageKey`,
      `_orderingTerms`, `_orderSql`/`_ageRankSql`, `_languageFacet`;
      `query` uses them + `id ASC`; `_byAgeRank` deleted;
      `search(query, {sort, language})`.
- [x] 5. `book_repository.dart`: port signature + doc.
- [x] 6. `library_controller.dart`: one unwrap for both paths; `BookSorter`
      import + Dart filter gone; doc.
- [x] 7. 22 fakes (23 sites) `search` signature — scripted regex, every
      site printed and counted; the wishlist decorator forwards the args.
- [x] 8. `book_sorter.dart` header: role = contract / test oracle.
- [x] 9. Gates green; `build_runner` LAST → 1 hash-only `.g.dart` diff.
- [x] 10. Commit + push approved ("commit and push and do housekeeping"):
      commit `2ef9381` perf(library) N10-d part 1, 31 paths staged
      explicitly, pre-commit hook "generated code is current"; push
      `2e14b67..2ef9381 main -> main` (no force); CI run `34766651432`
      **success** (Flutter analyze/format/test + Rust). Housekeeping:
      README test count 1604 → 1611; `appDetails.md` (local) §3/§5/§9/§10/§11
      updated with the N10-d facts.

## Out-of-scope observations

1. **Pre-existing user-visible bug fixed as a side effect of D1-a**: the
   language chip never matched a non-Latin language name (`lower()` is
   ASCII-only in SQLite). Not in the review; recorded here because the
   behaviour change (case-INsensitive `hindi` no longer matches `Hindi`)
   is deliberate and the chip is the only writer of that value.
2. `distinctLanguages()` still orders `COLLATE NOCASE` while the list's
   `languageAsc` orders BINARY — chips and list can disagree on `english`
   vs `Hindi` casing order. Cosmetic; untouched.
3. `_orderSql` is a textual twin of `_orderingTerms` by design (D2-a). If
   a future Drift version exposes a typed way to join a virtual table, the
   twin can go. Until then the equivalence test is the guard.
4. `_LimitBooksSelects` (test interceptor) is the seed of part 2's real
   `LIMIT`: when `queryPage`/`searchPage` exist, the interceptor test can
   be replaced by a direct page test.
5. `getAll()` (`ORDER BY added_date DESC`, no `id` tie-break) is used by
   export/publish/merge, not the list — left alone; a tie-break there would
   be a separate, export-affecting change.
6. 22 test files hand-roll `BookRepository` fakes (the S14–S28 shared-fake
   hygiene note): this session touched every one of them for a one-line
   signature change. A `test/support/` base fake would have made this a
   one-file edit.
7. `drift_book_repository.dart` 148/158: the 10 uncovered lines are the
   pre-existing `on Object catch` branches (no test drives a SQLite
   failure).

## Result

**Red evidence (before the fix, HEAD `2e14b67`):**

- **Age rank in SQL** — HEAD-shaped probe (`test/_tmp_red/`, removed) with
  the `LIMIT 3` interceptor: HEAD's statement was
  `SELECT * FROM "books" ORDER BY "age_group" ASC, "added_date" DESC LIMIT 3`
  and returned ids `[1, 2, 6]` = `above-10, above-15, above-3` (alphabetical
  tokens; Dart then re-sorted only those 3); expected `[3, 4, 1]` =
  `above-3, above-6, above-10`. **Behaviour-red: yes.**
- **Non-ASCII language filter** — same probe: `query(language:
  'Ελληνικά')` on a row whose language IS `Ελληνικά` → `Expected:
  ['probe greek'] / Actual: []`. **Behaviour-red: yes.**
- **`search(query, {sort, language})`** — 3 repository tests + the
  controller forwarding test: `undefined_named_parameter 'sort'`/`'language'`
  on HEAD. **Compile-red.**
- The `LIMIT` interceptor's first version appended after Drift's trailing
  `;` (SQLite error, not a failed assertion) — corrected to insert before
  it; the red result above is from the corrected probe.

**One assumption broke mid-implementation (fixed, not a pause trigger):**
the `languageAsc` twin first ordered by `b.language ASC` inside the blank
bucket, so SQLite placed NULL rows before `''` rows while `BookSorter`
treats both as the same key `''` (falls through to `added_date DESC`).
The equivalence test caught it at row 25 of the 40-row fixture; the key is
now `TRIM(COALESCE(language, ''))` on both paths. This is exactly the kind
of drift the oracle test exists for.

**Tests:** `drift_book_repository_test.dart` +6 (N10-d group: `LIMIT 3`
band-order page; `query` 3 sorts × 3 facets == `BookSorter`; `search`
same 9 combos; FTS match still narrows before filter/order; non-ASCII
language found by both reads; exact ties id ASC on both reads) +
`_LimitBooksSelects` interceptor + seeded 40-row fixture + `_expectedIds`
oracle. `library_controller_test.dart`: N05 sort test rewritten as
"forwards sort + facet, shows the list verbatim" (fake now records
`(query, sort, language)`; result deliberately NOT in sort order and NOT
all in the facet). `add_edit_book_test.dart`: `'hindi'` → `'Hindi'` +
asserts the other-case miss (D1-a made explicit). `book_test.dart` +1
(tokens SQL-literal-safe `^[a-z0-9-]+$`, ranks distinct — guards the raw
SQL `CASE`). 2 existing `search` callers updated.

**Gates:** analyze **0**; format **408 / 0 changed**; flutter test
`--coverage` **1610 passed / 0 failed** (`/tmp/pitak-s29-flutter-final.txt`,
EXIT=0, 0 `[E]`; the `book_test.dart` guard added after that run passes
standalone → **1611** total); cargo **32 passed** (Rust untouched);
`git diff --check` clean; `build_runner` run LAST → 1 hash-only diff
(`library_controller.g.dart`), `.fvmrc`/`.gitignore` untouched. Coverage
**72.76%** (+0.02); `drift_book_repository.dart` 148/158,
`library_controller.dart` 48/49, `book_sorter.dart` 22/22. Lib-diff privacy
scan: no print/log/http/Uri/Platform/isolate added; the language facet is a
bound `Variable`, the ORDER BY text is enum constants only.

**Committed `2ef9381`, pushed, CI `34766651432` green.** N10-d part 2
(`queryPage`/`searchPage` + windowed controller state) and N10-e remain. No device verification (a
static ordering change, deterministic in tests).

## Commit paths (explicit — never `git add -A`)

```
lib/features/library/application/library_controller.dart
lib/features/library/application/library_controller.g.dart
lib/features/library/domain/book_sorter.dart
lib/features/library/domain/repositories/book_repository.dart
lib/features/library/infrastructure/drift_book_repository.dart
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
test/features/library/domain/book_test.dart
test/features/library/drift_book_repository_test.dart
test/features/library/library_adaptive_layout_test.dart
test/features/library/library_controller_test.dart
test/features/library/library_controls_row_test.dart
test/features/library/library_page_test.dart
test/features/vault/lend_book_use_case_test.dart
test/features/wishlist/wishlist_detail_page_test.dart
test/features/wishlist/wishlist_use_cases_test.dart
test/widget_test.dart
PLAN.md
```
