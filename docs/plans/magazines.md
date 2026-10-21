# Catalogue item kinds, magazines & issues — session-based implementation plan

- **Branch:** `magazines`
- **Status:** Plan, revision 5 (2026-10-21). Structured as **discrete
  sessions** (Part C): each one can be executed by an LLM or a human in
  isolation, ends in a green, committed state, and hands off through
  `docs/plans/magazines-progress.md` (Part B).
- **Promise protected (ARCHITECTURE §1.1):** P1 (every format change is
  versioned, migrated and tested), P5 (one blessed way: one lendable unit,
  one identity, one list, one search index — for every kind of item).
- Mockup: `docs/mockups/periodicals_mockup.html` (predates the resolved
  decisions: chips row, bound-volume input and "missing issue" row differ —
  Part A is authoritative).

Pitak is a general library app. The catalogue is designed for **several kinds
of item** from the start — three ship in this work: **books**, **magazines**
(issues grouped under a periodical, lendable individually) and **others** (a
built-in catch-all — a DVD, a board game, a map — described in the free-text
notes field every item already has, which becomes searchable). The rule is
**design the seams, not the rooms**: identity, the lendable unit, the kind
discriminator and the wire formats are generic now; anything a kind that does
not exist yet would need is deferred with a written trigger.

---

# Part A — Decisions and target model (reference)

Sessions cite these by id (F1, D4, W2, …). Do not re-decide inside a session;
if a session finds a decision unworkable, stop, record it in the progress
file under *Deviations*, and let the next planning step resolve it.

## A.1 Foundation — catalogue item kinds (ADR 0013)

| # | Decision | Why |
|---|----------|-----|
| F1 | **One base row per physical thing, of any kind** — the existing `books` table / entity *is* the base row (renamed `CatalogueItem`, F7). It carries the fields every kind shares (title, transliteration, cover, language, age group, copies, location, notes, source, removed, uid, added…). Book-only fields (author, ISBN, publisher, year, genre, pages) are already nullable; a non-book row leaves them null. | No table split, no migration of 25 columns, no second list/search/publish/backup path. |
| F2 | **The base row is the lendable unit.** The vault's `loans.book_id` (`rust/src/vault.rs:68`) is the base row id — for every present and future kind. Standing decision (ARCHITECTURE §6): *a new kind never touches the vault.* | The encrypted, Kotlin-compatible store is the most expensive thing in the app to change. |
| F3 | **`kind` discriminator** on the base row: `ItemKind` enum (`book`, `magazineIssue`, `other` — chips *Books · Magazines · Others*), persisted as a stable token (`'book'` default), tolerant `fromToken` like `AgeGroup`. **Kinds are defined by the app**, never created by users at runtime. | One column makes every list, facet, export and viewer kind-aware. |
| F4 | **Kind-specific data lives in a per-kind detail table**, 1:1 with the base row (`<kind>.item_id → books.id ON DELETE CASCADE`). The base table never widens for a new kind. | Class-table inheritance: adding a kind = adding a table. |
| F5 | **Domain shape:** `CatalogueItem.details: ItemDetails?` — a **sealed union** (`IssueOf` with fields; `OtherItemOf` as a field-less marker); `null` ⇒ book. `kind` is **derived** from `details`, so kind and details cannot disagree. Each member validates itself inside `CatalogueItem.validate`. | Exhaustive `switch (item.details)`; the marker is where fields go if "Others" ever needs any. |
| F6 | **`kind` in every wire format from day one**: Pitaka-JSON v4, `books.json` (additive), `.pitabak` (`item_kinds.json`, W2). Absent ⇒ `book`. **Unknown kind token ⇒ that row is skipped and reported**, never mis-catalogued as a book. | Old files stay readable; future kinds are additive; fail closed on the unknown. |
| F7 | **Rename first:** `Book` → `CatalogueItem` and every name that means "an item of any kind" (Part C, S1–S4). Persisted and wire names (`books` table, `book_uid`, `loans.book_id`, `books.db`, `books.json`, JSON keys `books`/`bookUid`) **do not change** — contracts. Names that genuinely mean *book* (`AddBookPage`, `DuplicateIsbnFailure`, ISBN scan) keep their names. | Code must read correctly from day one; the diff is large but has zero behaviour. |
| F8 | **Periodicals stay a specific concept** (ISSN, frequency, subscription). No generic "collections". Trigger: a kind that needs grouping (DVD box set, book series) — decide then, with an ADR. | A box set and a subscription are different things. |

## A.2 Magazines & issues

| # | Decision | Why |
|---|----------|-----|
| D1 | **An issue is a base row with `details = IssueOf`** (`periodicalUid`, `volume?`, `issueNumber?`, `issueDate?`, `boundUntil?`, `label?`) and a `magazine_issues` detail row. | F1–F5. |
| D2 | **A `Periodical` entity + `periodicals` table**: title, ISSN, publisher, language, cover, frequency, optional subscription window, private fields. Identity `periodicalUid` (UUID), same pattern as `itemUid`. | The series is the single writer of everything an issue inherits. |
| D3 | **Derived fields are projected, not read through.** `IssueProjection` writes the base row's `title`, `titleTransliteration`, `publisher`, `language`, `publishedYear`, `ageGroup` from (periodical, issue). Editing the series re-projects every issue in one transaction. No per-issue age-group override. | Every existing consumer reads plain base columns. |
| D4 | **Bound volume = one issue row with a date range**: `issueDate` (first issue) + `boundUntil` (last issue). One required input: "issues from X to Y". Volume/issue number optional; a range may span volume numbers. One physical item, one `copyCount`, one loan. A bound volume the user does not want grouped under the magazine is simply added as an ordinary item. | Dates are always known even when numbers are not. |
| D5 | **Subscription tracking is optional and derived.** `subscriptionEnd == null` ⇒ untracked. `SubscriptionStatus.of(periodical, now)` ∈ {untracked, active, expiringSoon (≤ **30 days**), lapsed}. No status column, no notifications, no plugin. | A stored status can drift; a derived one cannot. |
| D6 | **Issue identity for dedup/merge:** `itemUid` → numbered issue (`periodicalUid`, `volume ?? 0`, `issueNumber`) / bound volume (`periodicalUid`, `issueDate`, `boundUntil`) → fuzzy title. Date-only single issues have no uniqueness guarantee — like books without an ISBN. A same-uid row whose `kind` differs is a **conflict**. | Mirrors uid → ISBN → fuzzy (ARCHITECTURE §6). |
| D7 | **ISSN lives on the periodical only**, canonical `NNNN-NNNC`, mod-11 check digit, unique among non-null. Never in `books.isbn`. | An ISSN identifies the title, not the issue. |
| D8 | **Hard delete of a periodical fails closed** while issues reference it (`PeriodicalHasIssuesFailure`). Soft-remove leaves issues untouched. Changing a row's `kind` after creation is **not** supported. | No orphan links; no cross-kind rewrites. |
| D9 | **No "missing issue" gap rows.** | With date-range bound volumes, number gaps cannot be computed honestly. |
| D10 | **FTS gains `notes`** (the description field): the v5 migration drops the FTS table + triggers; `beforeOpen` recreates them with the new column list and rebuilds. `issue_label` is **not** indexed (detail table; FTS external content is one table). | Search is on-device, so indexing private notes leaks nothing (P2). |
| D11 | **Scanning a magazine barcode** (EAN-13 prefix `977`, ISSN-derived, passes the ISBN-13 checksum today) routes to the add-issue flow. | Today it would store a bogus "ISBN". |

## A.3 Others

| # | Decision | Why |
|---|----------|-----|
| O1 | **`ItemKind.other` has no kind-specific fields and no detail table.** What the item *is* goes in the existing `notes` field (labelled "Description" on the Others form, "Notes" elsewhere — same column), searchable per D10. `OtherItemOf` is a field-less marker. | A description is enough. |
| O2 | **Honest limit:** `notes` is private (stripped at publish), so an Other item publishes title, cover, language and age group only. Trigger for a public `description` on the base row: a library asks for descriptions on its site. | Reuses the existing privacy rule. |
| O3 | **Generic use cases suffice:** `AddCatalogueItemUseCase` / `UpdateCatalogueItemUseCase` validate any `details`; only issues need a dedicated use case. | Nothing kind-specific to orchestrate. |
| O4 | Merge identity for others: `itemUid` → fuzzy (title). | Same as ISBN-less books. |

## A.4 Interchange, backup, publish, UI

| # | Decision | Why |
|---|----------|-----|
| W1 | **Pitaka-JSON `schemaVersion` 3 → 4**: per row `kind` + nested `issue{}` for issues (`other` has no object); top-level `periodicals[]`. Older builds refuse a v4 file with the existing "update the app" message. | Silent import would drop kinds — data loss (P1). |
| W2 | **`.pitabak`:** `books.db` stays byte-for-byte Room-shaped and holds the base rows of **every** kind. Kinds are **explicit** in `item_kinds.json` (`hasItemKinds`): `{ "schemaVersion": 1, "kinds": [{ "bookUid", "kind" }] }` for every non-book row; kind-specific data rides in its own `hasX` entry (`periodicals.json`/`hasPeriodicals`). A uid listed nowhere ⇒ `book`; a detail entry whose uid's kind disagrees ⇒ dropped + counted. | Room shape is a contract; `hasX` is the blessed extension point; explicit beats implied. |
| W3 | **Publish:** `books.json` stays schema 1 (additive): every entry gains `kind` (+ `issue{}`); top-level `periodicals[]` (public fields only). Viewer gets a kind facet; issues group under their title. | Additive keys are ignored by older viewers. |
| W4 | **Covers:** an issue may have its own; `IssueCover.resolve(issue, periodical)` falls back to the series cover. The janitor counts periodical covers as live references. | Otherwise the startup sweep deletes series covers (M11 bug class). |
| U1 | **Library kind chips:** a fixed row from `ItemKind.values` — *Books · Magazines · Others*. Tap filters; tap again clears (none = all). No "All" chip. `LibraryQuery.kind: ItemKind?`. | User decision. |
| U2 | **Magazine titles page** is reached from the drawer ("Magazines"), from an issue's detail page ("Open series") and from the "+" sheet. The series page lists its issues via `CatalogueItemRepository.page` with `periodicalUid` set. | One paged query per list (N10-d). |

## A.5 Target domain model

```dart
// library/domain/value_objects/item_kind.dart
enum ItemKind { book('book'), magazineIssue('magazine-issue'), other('other');
  final String token; static ItemKind? fromToken(String? raw); String get label; }

// library/domain/value_objects/item_details.dart
sealed class ItemDetails { ItemKind get kind; List<FieldError> validate(); }
final class IssueOf extends ItemDetails {   // D1, D4
  periodicalUid, volume?, issueNumber?, issueDate?, boundUntil?, label?;  bool get isBound;
}
final class OtherItemOf extends ItemDetails { const OtherItemOf(); }     // O1

// library/domain/entities/catalogue_item.dart (renamed from book.dart)
class CatalogueItem { ...existing fields..., ItemDetails? details;
  ItemKind get kind => details?.kind ?? ItemKind.book;  IssueOf? get issue; }
```

`IssueOf` rules: `periodicalUid` non-blank ≤ `maxFieldChars`; `volume`/`issueNumber`
`isValidCount`; bound ⇒ `issueDate` required and `boundUntil ≥ issueDate`; not
bound ⇒ at least one of `issueNumber`/`issueDate`; dates
`isValidOptionalDateMillis`; `label` `isValidFieldText`. `OtherItemOf.validate()`
→ `[]`.

`features/periodicals/domain/`: `Periodical` (+ static `validate` gate),
`Issn` (`normalize`, `fromEan13`), `PeriodicalFrequency` (weekly, fortnightly,
monthly, bimonthly, quarterly, annual, irregular), `SubscriptionStatus`,
`IssueCadence` (next date/number prefill), `IssueTitle.compose` (single
`"<Series> — Vol 249 No 10 (Oct 2026)"`, bound `"<Series> — Vol 248, Jul 2025 – Jun 2026"`,
null parts omitted, const English months), `IssueProjection.apply`,
`IssueCover.resolve`, `IssueSorter` (`issueDate desc, volume desc, issueNumber desc, id desc`),
`PeriodicalRepository` (listAll summaries, getById, findByUid, findByIssn,
insert, update, markRemoved, restoreRemoved, delete, countIssues, findIssue,
findBoundVolume, issuesOf, insertAll, replaceAll).

New failures: `DuplicateIssnFailure`, `DuplicateIssueFailure`,
`PeriodicalHasIssuesFailure`, `UnsupportedItemKindFailure`.
`CatalogueRules`: `isValidDateOrder`; `FieldError.userMessage` labels for
`issn`, `frequency`, `subscriptionStart/End`, `issue.*`.

## A.6 Target persistence model (schema v5)

```
books            + kind TEXT NOT NULL DEFAULT 'book'                  (base row, Room-shaped)
magazine_issues  item_id PK → books(id) ON DELETE CASCADE, periodical_uid TEXT NOT NULL (soft link),
                 volume, issue_number, issue_date, bound_until, issue_label
periodicals      id, periodical_uid (UNIQUE non-null), title, title_transliteration, title_sort,
                 issn (UNIQUE non-null), publisher, language, cover_url, frequency,
                 subscription_start, subscription_end, notes, location, source_type,
                 source_detail, age_group, added_date, removed, removed_at, added_by
```

Raw-SQL invariants (`_createIndexesAndFts`, `IF NOT EXISTS`, listed in
`migration_test._rawSqlObjects`): `index_books_kind`;
`index_magazine_issues_periodical_uid`;
`UNIQUE index_magazine_issues_number_key (periodical_uid, COALESCE(volume, 0), issue_number) WHERE issue_number IS NOT NULL AND bound_until IS NULL`;
`UNIQUE index_magazine_issues_bound_key (periodical_uid, issue_date, bound_until) WHERE bound_until IS NOT NULL`;
`UNIQUE index_periodicals_periodical_uid`; `UNIQUE index_periodicals_issn`.

FTS (D10): `_ftsColumns` = `title, title_transliteration, author, isbn, location, genre, notes`
(trigger bodies add `new.notes`/`old.notes`). v5 `onUpgrade` runs
`DROP TRIGGER IF EXISTS books_fts_ai/ad/au; DROP TABLE IF EXISTS books_fts`;
`beforeOpen` recreates and, finding no FTS table, calls `rebuildFts()`.

Foreign keys: `magazine_issues.item_id` is a real FK with cascade
(`references(Books, #id, onDelete: KeyAction.cascade)`), requiring
`PRAGMA foreign_keys = ON` in `beforeOpen`. Verified 2026-10-21: no existing
table declares a FK and the pragma is set nowhere. `periodical_uid` stays a
soft link (D8).

Migration (`from < 5`, a **separate** `if`, not chained to the network
`else if`): `createTable(periodicals)`, `createTable(magazineIssues)`,
`addColumn(books, books.kind)`, then the FTS drop.

## A.7 Rename map (F7) — executed in S1–S4

| Renamed | Kept |
|---|---|
| `Book` → `CatalogueItem`; `entities/book.dart` → `entities/catalogue_item.dart` | table `books`, `books_fts`, `books.db`, `books.json`, JSON keys `books`/`bookUid`, vault `book_id` |
| `Book.bookUid` → `CatalogueItem.itemUid` (column `book_uid` + JSON key `bookUid` unchanged; mappers/codecs translate with a comment) | `WishlistBook` (wishlist is books-only) |
| `BookSourceType` → `ItemSourceType`; `BookSort` → `LibrarySort` (tokens unchanged) | `AddBookPage`, `AddBookController`, `FindByIsbnUseCase`, `DuplicateIsbnFailure`, ISBN scan, lookup feature |
| `BookRepository` → `CatalogueItemRepository`; `DriftBookRepository` → `DriftCatalogueItemRepository`; `book_mapper.dart` → `catalogue_item_mapper.dart`; `bookRepositoryProvider` → `catalogueItemRepositoryProvider`; `bookById` → `catalogueItemById` | Drift data class `BookRow` (it is the row of the `books` table) |
| `AddBookUseCase` / `UpdateBookUseCase` / `DeleteBookUseCase` → `Add/Update/DeleteCatalogueItemUseCase` | |
| `BookPage` → `CatalogueItemPage` (doc: a page of the paged read, not a screen); `BookSorter` → `CatalogueItemSorter` | |
| `BookRow` widget → `CatalogueItemRow`; `BookGridCard` → `CatalogueItemGridCard`; `BookCover` → `ItemCover`; `BookDetailPage` → `CatalogueItemDetailPage` | |
| `LendDecision.forBook` → `forItem`; domain `Loan.bookId` → `Loan.itemId` (`vault/domain/entities/borrower.dart`; the FRB-generated `bookId` is mapped at the boundary) | Rust + FRB bindings (F2) |
| `PublishBook` → `PublishItem`; `ImportPayload.books` → `items`; `LegacyRows.books` → `items` | |
| `book_validation_gate_test` → `catalogue_item_validation_gate_test`; ratchet entries re-keyed | ADR 0004/0011 get a one-line "renamed 2026-10" note |

---

# Part B — Session protocol (read before every session)

## B.1 What a session is

A session is a unit of work sized so one focused run can finish it: one
goal, a known set of files, a verification command list, one commit. A
session **never** spans two of the numbered items in Part C. Sessions are
ordered; *Depends on* lists the hard prerequisites — anything else may be
done in any order.

## B.2 Start-of-session checklist

1. `git switch magazines && git status --short` — the tree must be clean.
   If it is not, stop and read the progress file: a previous session may
   have left a `wip` commit or notes.
2. Read `docs/plans/magazines-progress.md` (**State**, **Deviations**, **Next
   session**). The *Next session* entry is the one to run unless the human
   says otherwise.
3. Read `AGENTS.md`, Part A of this plan, and the session's **Read first**
   list. Do not read the whole codebase; the list is sufficient by design.
4. Run the session's **Baseline** command and confirm it is green *before*
   changing anything. If it is red, stop: record it under *Open issues* —
   the previous session's handoff was wrong.

## B.3 End-of-session checklist (the handoff)

A session ends in exactly one of these states:

- **Done** — every **Done when** command passes; one commit with the given
  message (plus any `fixup` squashed in); progress file updated; tree clean.
- **Partial** — allowed only if `dart analyze` is clean *and* every test that
  passed at baseline still passes. Commit as
  `wip(magazines): S<n> partial — <what works>`; list what is unfinished
  under *Next session* notes. The next run finishes S<n> first.
- **Blocked** — the tree is restored to the last commit (`git restore . &&
  git clean -fd` on files you created); the exact failing command and its
  output go under *Open issues*; *Next session* stays S<n>.

Always update `docs/plans/magazines-progress.md` as the **last** action
(it is committed with the session). Then stop. Do not start the next session
in the same run.

## B.4 Gates

| Name | Command(s) |
|---|---|
| `gen` | `dart run build_runner build --delete-conflicting-outputs` — run whenever `@riverpod`/`freezed`/drift-annotated code changed; the result must leave no uncommitted generated diff after commit |
| `analyze` | `dart analyze` (zero issues) and `dart format --set-exit-if-changed lib test` |
| `arch` | `flutter test test/architecture test/core/database/migration_test.dart` |
| `lite` | `analyze` + `arch` + the session's own tests |
| `full` | `lite` + `flutter test` |

Golden tests are Linux-pinned (CHANGELOG 1.5.2): on macOS, run the suite
with `--exclude-tags golden` if the project defines that tag, otherwise
record golden failures under *Open issues* as "platform goldens, verify in
CI" — they are not a blocker for a Done state unless the session changed the
widget under test.

## B.5 Rules that apply to every session

- Follow AGENTS.md; the plan never overrides it. If a step would violate a
  rule, stop and record a *Deviation* instead of complying.
- Never touch `rust/`, `lib/src/rust/`, the vault schema, or any persisted
  column/wire key name (F2, F7).
- Zero-behaviour sessions (S1–S4, S8) must not change any test expectation
  except names/paths.
- Keep every new file under 500 lines; split before extending a capped file
  (`layer_boundaries_test` allow-list).
- Every new `CatalogueItem(` / `Periodical(` construction site must be added
  to the gate test allow-list in the same session, with a reason.
- Write doc comments for public APIs; explain non-obvious choices for a
  beginner in a short comment.

---

# Part C — Sessions

Format: **Goal · Depends on · Read first · Baseline · Steps · Done when ·
Commit · Handoff notes to write.**

## S0 — Baseline and progress log

- **Goal:** record the green baseline and create the handoff file.
- **Depends on:** nothing.
- **Read first:** `docs/plans/magazines-progress.md` template (Part B).
- **Baseline:** `gen`, then `full`.
- **Steps:** (1) run `gen`; confirm no diff. (2) run `full`; note test
  count, duration, and any platform-golden failures. (3) fill the progress
  file **State** with the baseline numbers and commit hash.
- **Done when:** `full` green (goldens excepted per B.4).
- **Commit:** `chore(magazines): record baseline for the session plan`.
- **Handoff:** baseline numbers; `Next session: S1`.

## S1 — Rename `Book` → `CatalogueItem`

- **Goal:** the entity class and file are renamed; nothing else changes.
- **Depends on:** S0.
- **Read first:** `lib/features/library/domain/entities/book.dart`,
  `test/architecture/book_validation_gate_test.dart` (allow-list + scanned
  set), `test/architecture/layer_boundaries_test.dart` (ratchet map),
  `docs/adr/0004-book-validate-ingress-gate.md`.
- **Baseline:** `lite` (library + architecture tests).
- **Steps:**
  1. `git mv lib/features/library/domain/entities/book.dart lib/features/library/domain/entities/catalogue_item.dart`;
     `git mv test/architecture/book_validation_gate_test.dart test/architecture/catalogue_item_validation_gate_test.dart`.
  2. Across `lib/ test/ integration_test/` replace the **identifier** `Book`
     only: regex `\bBook\b` → `CatalogueItem` in `.dart` files (this does not
     touch `WishlistBook`, `BookRepository`, `AddBookPage`, …). Then replace
     the import path `entities/book.dart` → `entities/catalogue_item.dart`.
  3. Review prose: `grep -rn "CatalogueItem" lib test --include=*.dart | grep "///"`
     and restore sentence uses of "Book" that meant the *concept book* (e.g.
     "a Book is…" in docs about ISBNs) to "book"; keep type references.
  4. Entity doc comment: "The catalogue item row (any kind) — ADR 0013
     (pending). Originally ported from Kotlin `Book`." Gate test: scan
     `CatalogueItem(`; update its own file-path strings; the allow-list keeps
     the same entries (paths updated).
  5. Ratchet map: no paths change in this session (the entity is not listed).
  6. ADR 0004: append "- 2026-10: `Book` renamed `CatalogueItem`; the gate is
     unchanged." (do not rewrite the ADR).
  7. `gen` (generated files reference the type), then `lite`.
- **Done when:** `full` green; `git grep -n "\bBook\b" -- lib test` returns
  only prose and the wishlist/lookup names you deliberately kept (record the
  count).
- **Commit:** `refactor(catalogue): rename Book to CatalogueItem (F7, no behaviour change)`.
- **Handoff:** the remaining `\bBook\b` prose count; `Next session: S2`.

## S2 — Rename `bookUid` → `itemUid`, `BookSourceType`, `BookSort`

- **Goal:** field and enum names mean "item"; stored tokens, columns and JSON
  keys unchanged.
- **Depends on:** S1.
- **Read first:** `lib/core/database/tables.dart`,
  `lib/features/library/infrastructure/book_mapper.dart`,
  `lib/features/import_export/infrastructure/pitaka_json_{importer,exporter}.dart`,
  `lib/features/settings/domain/app_settings.dart`.
- **Baseline:** `lite`.
- **Steps:**
  1. `\bbookUid\b` → `itemUid` in `.dart` under `lib test`. Then **restore
     every string literal** `'itemUid'` / `"itemUid"` back to `'bookUid'`
     (JSON keys, CSV headers, test fixtures): `grep -rn "'itemUid'\|\"itemUid\"" lib test`.
     Add a one-line comment at each codec site: "JSON key stays `bookUid`
     (wire contract, ADR 0014)". The Drift column getter becomes
     `itemUid` while `.named('book_uid')` stays.
  2. `\bBookSourceType\b` → `ItemSourceType` and `BookSourceTypeX` →
     `ItemSourceTypeX`; tokens untouched.
  3. `\bBookSort\b` → `LibrarySort`, `BookSortX` → `LibrarySortX`; persisted
     tokens untouched (check `app_settings` tests still pass unchanged).
  4. `gen`, `lite`.
- **Done when:** `full` green; `git grep -n "book_uid" -- lib` shows only
  the column name sites; `git grep -c "'bookUid'" -- lib` is unchanged from
  baseline (record it).
- **Commit:** `refactor(catalogue): itemUid, ItemSourceType, LibrarySort (F7, no behaviour change)`.
- **Handoff:** the two grep counts; `Next session: S3`.

## S3 — Rename repository, mapper, use cases, providers

- **Goal:** repository/use-case/provider names mean "item".
- **Depends on:** S2.
- **Read first:** `lib/core/di/src/library_providers.dart`,
  `lib/features/library/domain/repositories/book_repository.dart`,
  `lib/features/library/infrastructure/drift_book_repository.dart` (header
  only), `test/architecture/layer_boundaries_test.dart` (ratchet map),
  `docs/adr/0011-book-repository-isp-deferred.md`.
- **Baseline:** `lite`.
- **Steps:**
  1. `git mv` → `domain/repositories/catalogue_item_repository.dart`,
     `infrastructure/drift_catalogue_item_repository.dart`,
     `infrastructure/catalogue_item_mapper.dart`,
     `application/{add,update,delete}_catalogue_item_use_case.dart`; the
     matching test files likewise.
  2. Identifiers: `BookRepository` → `CatalogueItemRepository`,
     `DriftBookRepository` → `DriftCatalogueItemRepository`,
     `BookRowMapper` → `CatalogueItemRowMapper` (the Drift `BookRow` data
     class name is **kept** — it is the row of the `books` table),
     `AddBookUseCase`/`UpdateBookUseCase`/`DeleteBookUseCase` →
     `…CatalogueItemUseCase`, provider functions `bookRepository` →
     `catalogueItemRepository`, `bookById` → `catalogueItemById` (generated
     `…Provider` names follow after `gen`).
  3. Ratchet map: re-key `drift_book_repository.dart` →
     `drift_catalogue_item_repository.dart` with the **same** recorded size.
  4. ADR 0011: append the one-line rename note.
  5. `gen`, `lite`.
- **Done when:** `full` green.
- **Commit:** `refactor(catalogue): rename repository, mapper, use cases, providers (F7)`.
- **Handoff:** `Next session: S4`.

## S4 — Rename domain helpers, widgets, pages, vault/publish/import names

- **Goal:** finish the rename map (A.7); docs mention the new names.
- **Depends on:** S3.
- **Read first:** A.7; `lib/features/vault/domain/entities/borrower.dart`
  (`Loan`), `lib/features/vault/domain/lending_policy.dart`,
  `lib/features/publish/domain/publish_export.dart`,
  `lib/features/import_export/domain/import_payload.dart`,
  `lib/features/backup/infrastructure/legacy_db_reader.dart`,
  `lib/core/widgets/book_cover.dart`, `AGENTS.md` §3.3, `docs/ARCHITECTURE.md` §2.1/§3.
- **Baseline:** `lite`.
- **Steps:**
  1. `git mv` + identifier renames: `book_page.dart` → `catalogue_item_page.dart`
     (`BookPage` → `CatalogueItemPage`), `book_sorter.dart` →
     `catalogue_item_sorter.dart`, widgets `book_row.dart` →
     `catalogue_item_row.dart`, `book_grid_card.dart` →
     `catalogue_item_grid_card.dart`, `core/widgets/book_cover.dart` →
     `item_cover.dart` (`BookCover` → `ItemCover`), page
     `book_detail_page.dart` → `catalogue_item_detail_page.dart`
     (`BookDetailPage` → `CatalogueItemDetailPage`); tests likewise.
  2. `LendDecision.forBook` → `forItem`; `Loan.bookId` → `Loan.itemId` in the
     domain class only; the vault infrastructure/mapper translates from the
     FRB `bookId` (comment: "vault column stays `book_id`, F2").
  3. `PublishBook` → `PublishItem`; `ImportPayload.books` → `items`;
     `LegacyRows.books` → `items` (JSON key `books` unchanged — comment).
  4. Ratchet map: re-key `book_detail_page.dart` →
     `catalogue_item_detail_page.dart`, same size.
  5. Docs: `AGENTS.md` §3.3 (`Book.validate` → `CatalogueItem.validate`);
     `ARCHITECTURE.md` §2.1 gate name, §3 module map line for `library/`.
  6. `gen`, `lite`.
- **Done when:** `full` green; `git grep -n "\bBook\b\|BookRepository\|BookPage\|BookSorter\|BookRow\b\|BookCover\|BookDetailPage\|PublishBook\|forBook" -- lib test`
  returns only the kept names (A.7 right column) and prose.
- **Commit:** `refactor(catalogue): complete the Book → CatalogueItem rename map (F7)`.
- **Handoff:** list any A.7 entry deliberately not renamed and why;
  `Next session: S5`.

## S5 — Records: ADR 0013, ADR 0014, docs, changelog

- **Goal:** the decisions are on record before feature code lands.
- **Depends on:** S4 (names in the ADRs must be the real ones).
- **Read first:** `docs/adr/0000-template.md`, `docs/adr/README.md`,
  `docs/ARCHITECTURE.md` §3, §5, §6, `AGENTS.md` §3.3, `CHANGELOG.md` head.
- **Baseline:** none (docs only) — still run `analyze` at the end.
- **Steps:**
  1. `docs/adr/0013-catalogue-item-kinds.md`: context (general library app;
     vault coupling), decision (F1–F8, D1–D11, O1–O4), consequences
     (recipe Part D.1, rename done in S1–S4, standing rule "a new kind never
     touches the vault"), resolved decisions log (Part D.3).
  2. `docs/adr/0014-catalogue-interchange-and-backup.md`: W1–W4 with the
     exact JSON shapes (A.4, S18, S21).
  3. `ARCHITECTURE.md`: §3 module map (`features/periodicals/`), §5 JSON v4 +
     `books.json` `kind`, §5.4 schema history v5 (pending), §5.5 rows for
     `item_kinds.json` / `periodicals.json`, §6 standing decisions.
  4. `AGENTS.md` §3.3: `Periodical.validate` beside `CatalogueItem.validate`.
  5. `CHANGELOG.md` `[Unreleased]`: Added (magazines, others, kinds), Changed
     (schema v5, JSON v4, FTS indexes notes, backup entries, rename).
  6. `docs/adr/README.md` index lines for 0013/0014.
- **Done when:** `analyze` green (no Dart changes expected).
- **Commit:** `docs(catalogue): ADR 0013 item kinds, ADR 0014 interchange/backup`.
- **Handoff:** `Next session: S6`.

## S6 — Domain: `ItemKind`, `ItemDetails`, `CatalogueItem.details`, failures, `LibraryQuery`

- **Goal:** the kind seam exists in the domain, fully tested; nothing
  persists it yet.
- **Depends on:** S4 (S5 recommended).
- **Read first:** A.5; `catalogue_item.dart`, `catalogue_rules.dart`,
  `core/error/failure.dart`, `library/domain/library_query.dart`,
  `test/features/library/domain/*`.
- **Baseline:** `lite`.
- **Steps:**
  1. `value_objects/item_kind.dart`, `value_objects/item_details.dart`
     (`IssueOf`, `OtherItemOf`, rules in A.5).
  2. `CatalogueItem.details` + derived `kind`, `issue` getter; `validate`
     appends `details?.validate()`; `copyWith(details:)`.
  3. `CatalogueRules.isValidDateOrder`; `FieldError.userMessage` labels.
  4. Failures: `DuplicateIssnFailure`, `DuplicateIssueFailure`,
     `PeriodicalHasIssuesFailure`, `UnsupportedItemKindFailure` (+ the UI
     message mapping where other failures are mapped — find it with
     `grep -rn "DuplicateIsbnFailure" lib/features/library/presentation`).
  5. `LibraryQuery`: `ItemKind? kind`, `String? periodicalUid`
     (blank → null), `sameIntentAs`, `toString`.
  6. Tests: `item_kind_test`, `item_details_test` (every rule at its
     boundary), `catalogue_item_validated_test` additions, `library_query_test`.
- **Done when:** `lite` green; domain purity test green.
- **Commit:** `feat(catalogue): ItemKind and ItemDetails seam in the domain (F3, F5)`.
- **Handoff:** `Next session: S7`.

## S7 — Domain: periodicals feature

- **Goal:** every pure periodical rule exists and is tested.
- **Depends on:** S6.
- **Read first:** A.5; `lib/features/lookup/domain/isbn_format.dart` (style
  for `Issn`), `AgeGroup` in `catalogue_item.dart` (enum style),
  `lib/features/library/domain/catalogue_item_sorter.dart` (oracle style),
  `lib/features/network/domain/entities/network_library.dart` (entity style).
- **Baseline:** `lite`.
- **Steps:** create `lib/features/periodicals/domain/` with
  `entities/periodical.dart` (+ `validate`, `copyWith`),
  `value_objects/issn.dart`, `value_objects/periodical_frequency.dart`,
  `subscription_status.dart`, `issue_cadence.dart`, `issue_title.dart`,
  `issue_projection.dart`, `issue_cover.dart`, `issue_sorter.dart`,
  `repositories/periodical_repository.dart` (+ `PeriodicalSummary`). Tests in
  `test/features/periodicals/domain/` (one file per unit; cases listed in
  A.5 — include month-end clamping, the 30/31-day boundary, every title
  omission combination, projection idempotence). Extend the gate test to scan
  `Periodical(` with the entity file as the only allowed site.
- **Done when:** `lite` green.
- **Commit:** `feat(periodicals): domain model, value objects and rules (D2–D7)`.
- **Handoff:** `Next session: S8`.

## S8 — Make room in the item repository (pure refactor)

- **Goal:** `drift_catalogue_item_repository.dart` drops well under its
  ratchet cap so S10 can extend it.
- **Depends on:** S3.
- **Read first:** the repository file; `test/features/library/drift_book_repository_test.dart`
  (renamed in S3); ratchet map.
- **Baseline:** `lite`.
- **Steps:** move `_LanguageResolver`, `_RollbackWith`, `_ftsQuery` and the
  raw `ORDER BY` builder into `library/infrastructure/drift_catalogue_sql.dart`
  (library-private helpers, doc-commented); lower the ratchet entry to the
  new size (or delete it if < 500). No test expectation changes.
- **Done when:** `full` green; repository ≤ 450 lines.
- **Commit:** `refactor(library): extract SQL helpers from the item repository (ratchet)`.
- **Handoff:** new line counts; `Next session: S9`.

## S9 — Schema v5

- **Goal:** tables, migration, FK pragma, indexes, FTS rebuild, snapshot,
  generated helpers, data-matrix row — all proven.
- **Depends on:** S6 (for tokens), S8.
- **Read first:** A.6; `lib/core/database/tables.dart`,
  `lib/core/database/app_database.dart`,
  `test/core/database/migration_test.dart` (matrix rows for v3/v4 and
  `_rawSqlObjects`), `docs/ARCHITECTURE.md` §5.4.
- **Baseline:** `arch`.
- **Steps:**
  1. `tables.dart`: `Books.kind`; `MagazineIssues`; `Periodicals`.
  2. `app_database.dart`: `schemaVersion => 5`; history comment; migration
     per A.6 (separate `if (from < 5)`), FTS drop; `_ftsColumns` + trigger
     bodies with `notes`; `PRAGMA foreign_keys = ON` in `beforeOpen`
     (comment: why safe); new indexes.
  3. `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/app_database/`
     then `dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database test/core/database/generated/`.
  4. `migration_test.dart`: v5 matrix row (populated v4 → v5: book, issue,
     bound volume, other, periodical rows round-trip; `kind` back-filled;
     notes-only word found by FTS; cascade delete proven; FTS column list
     asserted); `_rawSqlObjects` extended; a 5 000-row FTS rebuild timing
     test with a generous bound.
  5. `gen`, `arch`.
- **Done when:** `full` green; `git status` shows the new snapshot + helper
  committed.
- **Commit:** `feat(database): schema v5 — kind, magazine_issues, periodicals, FTS notes (A.6)`.
- **Handoff:** migration timing numbers; `Next session: S10`.

## S10 — Item details seam, mapper, repository

- **Goal:** the item repository reads/writes kinds and issue details; the
  list query supports kind and series facets.
- **Depends on:** S9.
- **Read first:** repository + `drift_catalogue_sql.dart` + mapper;
  `library_query.dart`; `issue_sorter.dart`;
  `test/features/library/drift_catalogue_item_repository_test.dart`.
- **Baseline:** `lite`.
- **Steps:**
  1. `library/infrastructure/drift_item_details.dart`: `readDetails(kindToken, issueRow)`,
     `writeDetails(id, details)`, `deleteDetails(id)`; exhaustive `switch`.
  2. Mapper: joined row → entity (unknown kind token → `book` + one
     `app_log` line); entity → base companion (+ detail companion).
  3. Repository: LEFT JOIN `magazine_issues` in `_listRows`/`_searchRows`;
     `kind` predicate; `periodical_uid` predicate + `IssueSorter` order;
     two-table transactional writes in `insert/update/insertAll/replaceAll`;
     `update` refuses a row whose stored kind token is unknown
     (`UnsupportedItemKindFailure`); UNIQUE violations on the issue keys →
     `DuplicateIssueFailure`.
  4. Tests: kind facet; series facet + order == `IssueSorter`; both issue
     keys race → typed failure; detail written/updated/cascaded; an Other
     item round-trips with `kind` only; plain-item edit leaves no detail row;
     unknown-kind write refused; search by notes.
- **Done when:** `full` green; repository still under its ratchet entry.
- **Commit:** `feat(library): item details seam and kind-aware repository (F4, F6)`.
- **Handoff:** `Next session: S11`.

## S11 — Periodical repository, DI, janitor

- **Goal:** periodicals persist; covers of periodicals are protected.
- **Depends on:** S10.
- **Read first:** `periodical_repository.dart`; the item repository (patterns);
  `lib/core/di/src/library_providers.dart`, `providers.dart`;
  `lib/features/library/application/cover_file_janitor.dart` + its test.
- **Baseline:** `lite`.
- **Steps:**
  1. `periodicals/infrastructure/drift_periodical_repository.dart` +
     `periodical_mapper.dart` (uid minting; `listAll` one
     `LEFT JOIN … GROUP BY`; ISSN race → `DuplicateIssnFailure`;
     `findIssue`/`findBoundVolume`/`issuesOf` via the item mapper).
  2. `core/di/src/periodical_providers.dart` (`periodicalRepository`) + part
     registration.
  3. Janitor counts periodical covers (W4).
  4. Tests: repository CRUD/uid/ISSN race/counts/order; janitor "series
     cover survives a sweep".
- **Done when:** `full` green.
- **Commit:** `feat(periodicals): drift repository, DI, cover janitor rule (W4)`.
- **Handoff:** `Next session: S12`.

## S12 — Use cases: periodicals and issues

- **Goal:** every write path for series and issues, fail-closed.
- **Depends on:** S11.
- **Read first:** `add_catalogue_item_use_case.dart` (pattern),
  `update_catalogue_item_use_case.dart`, `delete_catalogue_item_use_case.dart`,
  `issue_projection.dart`, `issue_title.dart`.
- **Baseline:** `lite`.
- **Steps:** `periodicals/application/`: `add_periodical_use_case.dart`,
  `update_periodical_use_case.dart` (one transaction; re-projects every
  issue), `delete_periodical_use_case.dart` (`countIssues > 0` ⇒ refuse;
  release cover via janitor), `add_issue_use_case.dart`
  (series lookup → `CatalogueItem(details: IssueOf)` → projection →
  validate → `findIssue`/`findBoundVolume` pre-check → insert),
  `update_issue_use_case.dart` (refuses kind change). Providers in
  `periodical_providers.dart`. Tests with fakes: every success and failure
  path, rollback on mid-way failure.
- **Done when:** `full` green; gate allow-list updated for the use-case
  construction sites.
- **Commit:** `feat(periodicals): add/update/delete series and issue use cases (D3, D8)`.
- **Handoff:** `Next session: S13`.

## S13 — Controllers, read providers, scan routing

- **Goal:** screen state and the 977 barcode route.
- **Depends on:** S12.
- **Read first:** `library_controller.dart`, `library_window.dart`,
  `library_filter_controller.dart`, `core/di/src/platform_providers.dart`
  (`clockProvider`, `nowTickProvider`), the scan routing file
  (`grep -rn "routeScannedIsbn" lib`), `catalogueItemById` provider.
- **Baseline:** `lite`.
- **Steps:** `periodicals_controller.dart` (summaries + `SubscriptionStatus`
  via `clockProvider`), `issue_list_controller.dart` (family by
  `periodicalUid`, reuses `LibraryWindow` + `page(LibraryQuery(periodicalUid:))`),
  `add_issue_controller.dart`, `periodical_form_controller.dart`;
  `periodicalById`/`periodicalByUid` read providers watching both mutation
  signals; `LibraryFilterController` gains the kind facet; scan routing:
  `977…` → `Issn.fromEan13` → `findByIssn` → add-issue or "new title"
  decision (returned as a sealed route value, UI decides in S14). Tests with
  `ProviderContainer` overrides.
- **Done when:** `full` green.
- **Commit:** `feat(periodicals): controllers, read providers, magazine barcode routing (D11, U1)`.
- **Handoff:** `Next session: S14`.

## S14 — Library screen: make room, kind chips, add sheet, row badges

- **Goal:** the Library list is kind-aware.
- **Depends on:** S13.
- **Read first:** `library_page.dart`, `library_controls_row.dart`,
  `catalogue_item_row.dart`, `catalogue_item_detail_page.dart` (to split),
  ratchet map, `test/features/library/library_page_test.dart`,
  `library_controls_row_test.dart`, `catalogue_item_row_test.dart`.
- **Baseline:** `lite`.
- **Steps:**
  1. Split: detail page → `widgets/catalogue_item_actions.dart`
     (remove/restore + lend section); `library_page.dart` → `widgets/library_menu_button.dart`.
     Lower the detail page's ratchet entry.
  2. Kind chips (U1) from `ItemKind.values`, toggle semantics; search hint
     "Search title, author, ISBN, notes…".
  3. `widgets/add_sheet.dart`: FAB → *Add book / Add magazine issue / Add
     other item / New magazine title* (the latter three push pages created in
     S15–S17; until then they push a placeholder `Scaffold` with the page
     name — replaced in those sessions).
  4. Row badges `Issue` / `Bound volume` / `Other`; cover via
     `IssueCover.resolve` with a `periodicalCoversProvider` map.
  5. Tests: chips toggle; sheet entries; badges.
- **Done when:** `full` green; no file over its cap.
- **Commit:** `feat(library): kind chips, add sheet, kind badges (U1)`.
- **Handoff:** which sheet entries are placeholders; `Next session: S15`.

## S15 — Periodicals list page and series detail page

- **Goal:** series are visible, with subscription badges and their issues.
- **Depends on:** S14.
- **Read first:** `library_page.dart` (list/paging idiom), `catalogue_item_row.dart`,
  `core/widgets/app_drawer.dart`, `periodicals_controller.dart`,
  `issue_list_controller.dart`.
- **Baseline:** `lite`.
- **Steps:** `periodicals/presentation/pages/periodicals_page.dart` (rows,
  `SubscriptionBadge` widget, empty state, FAB "New magazine title"),
  `pages/periodical_detail_page.dart` (hero, subscription card, "+ Add
  issue", paged issues newest-first, edit, overflow with the typed delete
  refusal); drawer entry "Magazines"; replace the S14 placeholders that
  these pages satisfy. Widget tests for badge states and the refusal.
- **Done when:** `full` green.
- **Commit:** `feat(periodicals): magazine titles page and series detail page (U2)`.
- **Handoff:** `Next session: S16`.

## S16 — Periodical form and add-issue form

- **Goal:** series and issues can be created and edited from the UI.
- **Depends on:** S15.
- **Read first:** `add_book_page.dart` (form idiom, cover capture through
  `BookCoverController`), `add_book_page_test.dart`, `issue_cadence.dart`,
  `issue_title.dart`, gate test allow-list.
- **Baseline:** `lite`.
- **Steps:** `pages/periodical_form_page.dart` (fields per A.2; "Track
  subscription" switch; ISSN inline validation; language picker reusing the
  facet values; cover capture via the `CoverFiles` port flow),
  `pages/add_issue_page.dart` (series picker; "Bound volume" switch swapping
  the single date for "Issues from / to"; optional volume/issue number;
  label; own cover; copies, pages, location prefilled from series; notes;
  generated-title preview). Add both `CatalogueItem(`/`Periodical(` sites to
  the gate allow-list with reasons. Replace the remaining S14 placeholders.
  Widget tests (switch behaviour, preview, save passes a projected item).
- **Done when:** `full` green; each new page < 500 lines (split widgets if
  needed).
- **Commit:** `feat(periodicals): series form and add-issue form (D4)`.
- **Handoff:** `Next session: S17`.

## S17 — Others form, item details section, goldens

- **Goal:** Others can be added; detail pages show kind-specific blocks.
- **Depends on:** S16.
- **Read first:** `add_book_page.dart`, `catalogue_item_detail_page.dart`,
  `catalogue_item_actions.dart`, golden test examples
  (`grep -rln "matchesGoldenFile" test | head`).
- **Baseline:** `lite`.
- **Steps:** `library/presentation/pages/other_item_form_page.dart`
  (title, transliteration, cover, **Description** = `notes`, language, age
  group, copies, location, source, date added; `details: const OtherItemOf()`;
  gate allow-list entry); `widgets/item_details_section.dart` with
  `switch (item.details)` (issue block incl. "Open series"; nothing for
  others/books) inserted into the detail page; goldens for the series row +
  badge; tests.
- **Done when:** `full` green (goldens per B.4).
- **Commit:** `feat(catalogue): Others form and item details section (O1, O3)`.
- **Handoff:** `Next session: S18`.

## S18 — Pitaka-JSON v4 and CSV

- **Goal:** export/import carry kinds, issues and periodicals; v3 still imports.
- **Depends on:** S12 (use cases) — independent of S14–S17.
- **Read first:** `pitaka_json_exporter.dart`, `pitaka_json_importer.dart`,
  `import_payload.dart`, `import_limits.dart`, `import_library_use_case.dart`,
  `export_library_use_case.dart` (CSV columns), existing v3 fixtures under
  `test/`.
- **Baseline:** `lite`.
- **Steps:** per W1 — `kPitakaSchemaVersion = 4`; per-row `kind` + nested
  `issue{}`; top-level `periodicals[]`; importer rules (unknown kind skipped +
  counted; `magazine-issue` without `issue{}` rejected; orphan issue imported
  as a book + warning); `ImportPayload` fields; use case imports periodicals
  first inside the existing transaction; CSV columns `Kind`, `Series`,
  `Volume`, `Issue`, `Issue date`, `Bound until`, `Issue label`. Tests: v4
  round-trip for all three kinds; v3 fixture unchanged; each rejection/skip
  path; truncation.
- **Done when:** `full` green.
- **Commit:** `feat(import_export): Pitaka-JSON v4 with item kinds and periodicals (W1)`.
- **Handoff:** `Next session: S19`.

## S19 — Merge

- **Goal:** merge understands periodicals and issue identity.
- **Depends on:** S18.
- **Read first:** `library_merge_engine.dart` (split target `_FuzzyIndex`),
  `merge_library_use_case.dart`, `background_merge_planner.dart`,
  `merge_page.dart`, ratchet map, `library_merge_engine_test.dart`,
  `merge_engine_properties_test.dart`.
- **Baseline:** `lite`.
- **Steps:** extract `_FuzzyIndex` → `fuzzy_index.dart` (pure refactor,
  lower the ratchet entry, properties test unchanged); `periodical_merge.dart`
  (uid → ISSN → exact title; add-only, removal-as-conflict);
  `issue_identity.dart` (D6 keys); same-uid kind mismatch ⇒ conflict; use
  case applies periodicals first and re-projects issues of merged series;
  planner I/O stays plain Dart; merge page shows periodical counts. Tests
  incl. isolate round-trip.
- **Done when:** `full` green.
- **Commit:** `feat(merge): periodicals and issue identity in the merge plan (D6)`.
- **Handoff:** `Next session: S20`.

## S20 — Publish

- **Goal:** the published site shows kinds and groups issues.
- **Depends on:** S12 — independent of S14–S19.
- **Read first:** `publish_export.dart`, `publish_redaction.dart`,
  `publish_library_use_case.dart`, `publish_cover_ids.dart`,
  `cover_url_allow_list.dart`, `assets/publish/index.html`, their tests.
- **Baseline:** `lite`.
- **Steps:** `PublishItem.kind` + nested `issue{}`; `PublishExport.periodicals[]`
  (public fields only; private fields stripped — add to the redaction test);
  periodical covers through the cover-id + allow-list pipeline; issue
  entries publish `IssueCover.resolve`; viewer: kind facet (Books · Magazines
  · Others), issues grouped under their title with the bound badge, unknown
  kinds as plain items; `schemaVersion` stays 1. Tests.
- **Done when:** `full` green.
- **Commit:** `feat(publish): item kinds and periodicals on the published site (W3)`.
- **Handoff:** `Next session: S21`.

## S21 — Backup and restore

- **Goal:** `.pitabak` carries kinds, issue details and periodicals; old
  archives restore unchanged.
- **Depends on:** S12 — independent of S14–S20.
- **Read first:** `backup_archive_writer.dart`, `backup_manifest.dart`,
  `backup_extras_reader.dart`, `restore_backup.dart` (phase structure; at
  cap), `legacy_db_reader.dart`, `restore_summary.dart`, ratchet map,
  backup tests + fixtures under `test/fixtures`.
- **Baseline:** `lite`.
- **Steps:** per W2 — writer emits `item_kinds.json` (`hasItemKinds`) and
  `periodicals.json` (`hasPeriodicals`), manifest defaults false; extras
  reader parses both with caps and re-validation; new
  `restore_item_details.dart` applies kinds and joins issue entries by
  `bookUid` before the catalogue write, detaches unmatched links; summary
  fields `kindsApplied / periodicalsRestored / issuesLinked / issuesDetached /
  rowsSkippedUnknownKind`; `restore_backup.dart` stays under its cap. Tests:
  writer entries + flags; reader drops + counts; restore links/detaches;
  flag-less fixture restores exactly as before.
- **Done when:** `full` green.
- **Commit:** `feat(backup): item kinds and periodicals in .pitabak (W2)`.
- **Handoff:** `Next session: S22`.

## S22 — Release hygiene and final verification

- **Goal:** everything a release needs; the whole branch verified end to end.
- **Depends on:** S17, S19, S20, S21.
- **Read first:** `docs/RELEASING.md`, `fastlane/metadata/android/en-US/changelogs/`,
  `lib/features/guides/domain/guide_catalog.dart` + its test,
  `integration_test/`, `CHANGELOG.md`.
- **Baseline:** `full`.
- **Steps:** fastlane blurb for the next versionCode; `GuideId.catalogue`
  guide ("Books, magazines and other items") within the pinned invariants;
  integration smoke (add series → add issue → add other item → lend → backup
  → restore); CHANGELOG `[Unreleased]` reconciled against what shipped;
  ARCHITECTURE §5.4 history line finalised; run the F-Droid purity check
  command from `docs/RELEASING.md` §2 (no plugin was added — record the
  output).
- **Done when:** `gen` no diff; `full` green; `cargo` gates untouched
  (confirm `git diff --stat main -- rust/` is empty).
- **Commit:** `chore(catalogue): release hygiene for item kinds and magazines`.
- **Handoff:** mark the plan complete; `Next session: none — ready for review/merge`.

---

# Part D — Appendices

## D.1 Recipe: adding a future kind (goes into ADR 0013)

1. `ItemKind.<kind>('<token>')` + `final class <Kind>Of extends ItemDetails`
   with `validate()` (a field-less marker if no fields, like `OtherItemOf`).
   The compiler now flags every non-exhaustive `switch`.
2. If it has fields: detail table `<kind>_items(item_id PK → books.id
   CASCADE, …)`; schema bump; snapshot + helpers + matrix row.
3. `drift_item_details.dart`: read/write/delete branch; mapper branch.
   Nothing else in the repository changes.
4. Wire formats: the `kind` token is already carried everywhere; add a
   nested `"<kind>": {…}` object in Pitaka-JSON and `books.json` and a
   `has<Kind>` `.pitabak` entry only if the kind has fields.
5. Add-sheet entry, a form page (gate allow-list), a block in
   `item_details_section.dart`; the kind chip appears automatically (U1).
6. Grouping needed? That is the F8 trigger — decide with an ADR.
7. **The vault is not touched** (F2).

## D.2 Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Rename sessions break something silently | zero-behaviour rule (B.5); `full` before/after; prose review step; wire/table names grep-verified |
| Enabling `PRAGMA foreign_keys` surprises an existing path | no existing FK (verified); matrix + cascade test; `replaceAll`/restore rely on cascade (tested) |
| FTS rebuild on upgrade is slow on a large catalogue | one-time, inside the migration; same statement as the self-heal path; timed in the matrix test |
| Re-projection on rename touches N issue rows | one transaction; `issuesOf` bounded; failure rolls back the rename |
| Startup cover sweep deletes series covers | janitor rule (S11) + test |
| Old build receives a v4 JSON file | refuses with the existing message (W1) |
| Old build restores a new `.pitabak` | ignores the new entries; issues/others restore as books — documented in ARCHITECTURE §5.5 |
| Row written by a newer build with an unknown kind | read maps to `book` + logged once; write back refused (S10) |
| Merge conflict storm after a rename on one device | periodicals merge first; issues re-projected after apply (S19) |
| A session overruns its context | the Partial state (B.3) exists for this; prefer committing a green subset over pushing on |

## D.3 Resolved decisions log (user answers, 2026-10-21)

| Q | Answer | Effect |
|---|--------|--------|
| 1 | "Expiring soon" window = **30 days** | D5 |
| 2 | Bound volume = **"issues from date X to date Y"**; user may instead catalogue it as its own item | D4; D9; two partial unique keys (D6) |
| 3 | **No** per-issue age-group override | D3 |
| 4 | **Fixed kind chips** (Books, Magazines, future kinds), tap filters, tap again shows all | U1; U2 |
| 5 | **Rename now** | F7 → S1–S4 |
| 6 | Kinds are **app-defined**; add a built-in **"Others"** kind | F3, O1–O4 |
| 7 | Others have **no type label** — the existing description/notes field says what the item is, and **notes become searchable** | O1–O2, D10, W2 (explicit `item_kinds.json`) |
| 8 | Plan written as **discrete, independently runnable sessions** with a handoff file | Part B, Part C, `magazines-progress.md` |
