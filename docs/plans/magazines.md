# Catalogue item kinds, magazines & issues — implementation plan

- **Branch:** `magazines`
- **Status:** Plan, revision 2 (2026-10-21). No code yet. Mockup:
  `docs/mockups/periodicals_mockup.html`.
- **Promise protected (ARCHITECTURE §1.1):** P1 (every format change is
  versioned, migrated and tested), P5 (one blessed way: one lendable unit,
  one identity, one list, one search index — for every kind of item).

Revision 2 changes the foundation: Pitak is a general library app, so the
catalogue is designed for **several kinds of item** (books today, magazine
issues now, DVDs / games / equipment later) *without* building anything for
kinds that do not exist yet. The rule is **design the seams, not the rooms**:
what is expensive to retrofit (identity, the lendable unit, the discriminator,
the wire formats) is made generic now; what is cheap to add later (a sealed
details union, kind-specific forms, a generic "collections" concept, the
class rename) is deferred with a written trigger.

Each phase is one reviewable PR; every step names the file it touches, the
rule it satisfies (AGENTS.md / ARCHITECTURE §2.1 fitness functions) and the
test that proves it.

---

## 0. Decisions (details in ADR 0013 / ADR 0014)

### 0.1 Foundation — catalogue item kinds (ADR 0013)

| # | Decision | Why |
|---|----------|-----|
| F1 | **One base row per physical thing, of any kind** — the existing `books` table / `Book` entity *is* the base row. It carries the fields every kind shares (title, transliteration, cover, language, age group, copies, location, notes, source, removed, uid, added…). Book-only fields (author, ISBN, publisher, year, genre, pages) are already nullable; a non-book row leaves them null. | No table split, no data migration of 25 columns, no second list/search/publish/backup path. |
| F2 | **The base row is the lendable unit.** The vault's `loans.book_id` (`rust/src/vault.rs:68`) is the base row id — for every present and future kind. Standing decision (ARCHITECTURE §6): *a new kind never touches the vault.* | The encrypted, Kotlin-compatible store is the most expensive thing in the app to change. |
| F3 | **`kind` discriminator** on the base row: `ItemKind` enum (`book`, `magazineIssue`), persisted as a stable token (`'book'` default), tolerant `fromToken` like `AgeGroup`. | One column makes every list, facet, export and viewer kind-aware. |
| F4 | **Kind-specific data lives in a per-kind detail table**, 1:1 with the base row (`magazine_issues.item_id → books.id`, `ON DELETE CASCADE`). The base table never widens for a new kind. | Class-table inheritance: adding a kind = adding a table, not touching `books`. |
| F5 | **Domain shape:** `Book.kind` + one optional value object per kind (`Book.issue: IssueOf?` now). Invariant, enforced by `Book.validate`: `kind == magazineIssue ⇔ issue != null`. The sealed `ItemDetails` union is introduced **with the second kind** (one member is not a union). | Typed domain code (`book.isIssue`, `book.issue!.volume`), nothing speculative. |
| F6 | **`kind` in every wire format from day one**: Pitaka-JSON v4, `books.json` (additive), `.pitabak` (implied by which detail entry lists the uid — §5.6). Absent ⇒ `book`. **Unknown kind token ⇒ that row is skipped and reported** (never mis-catalogued as a book). | Old files stay readable; future kinds are additive; fail closed on the unknown. |
| F7 | **`Book` keeps its class name for now.** The base row of a DVD being a `Book` is the one wart; the rename to `CatalogueItem` is logic-free and safe at any time, so it ships as a rename-only PR **immediately before the PR that introduces the second kind**. Until then `Book`'s doc comment says "the catalogue item row (any kind)". | Hundreds of files, zero behaviour; churn now buys nothing. Recorded in ADR 0013 with the trigger. |
| F8 | **Periodicals stay a specific concept** (ISSN, frequency, subscription). No generic "collections"/"series" table. Trigger to generalise: a second kind that needs grouping (DVD box set, book series). | A box set and a subscription are different things; a generic model now is speculation. |

### 0.2 Magazines & issues (first application of the foundation)

| # | Decision | Why |
|---|----------|-----|
| D1 | **An issue is a base row with `kind = magazineIssue`** and a `magazine_issues` detail row (`periodicalUid`, `volume`, `issueNumber`, `issueNumberEnd`, `issueDate`, `label`). | F1–F5. |
| D2 | **A `Periodical` entity + `periodicals` table** holds series-level data: title, ISSN, publisher, language, cover, frequency, optional subscription window, private fields. Identity `periodicalUid` (UUID), same pattern as `bookUid`. | The series is the single writer of everything an issue inherits. |
| D3 | **Derived fields are projected, not read through.** `IssueProjection` writes the base row's `title`, `titleTransliteration`, `publisher`, `language`, `publishedYear`, `ageGroup` from (periodical, issue). Editing the series re-projects every issue in one transaction. | Every existing consumer (facet SQL, sort, publish, exports, merge) reads plain base columns. Zero joins there. |
| D4 | **Bound volume = one issue row with a range** (`issueNumber..issueNumberEnd`, one `volume`). One physical item, one `copyCount`, one loan. Spanning two volumes is **not** supported in v1 (record two rows). | A library that binds a year's issues lends the volume as one thing. |
| D5 | **Subscription tracking is optional and derived.** `subscriptionEnd == null` ⇒ untracked. `SubscriptionStatus.of(periodical, now)` ∈ {untracked, active, expiringSoon (≤ 30 days), lapsed}. No status column, no notifications, no plugin. | A stored status can drift; a derived one cannot. No Google deps (P3). |
| D6 | **Issue identity for dedup/merge:** `bookUid` → (`periodicalUid`, `volume ?? 0`, `issueNumber`) → fuzzy title. Date-only issues (no number) have no uniqueness guarantee — exactly like books without an ISBN. A same-uid row whose `kind` differs is a **conflict**, never auto-merged. | Mirrors the existing uid → ISBN → fuzzy order (ARCHITECTURE §6). |
| D7 | **ISSN lives on the periodical only**, canonical `NNNN-NNNC`, mod-11 check digit, unique among non-null. Never in `books.isbn`. | An ISSN identifies the title, not the issue. |
| D8 | **Hard delete of a periodical fails closed** while issues reference it (`PeriodicalHasIssuesFailure`). Soft-remove leaves issues untouched. Changing a row's `kind` after creation is **not** supported (delete and re-add). | No orphan links; a kind change would have to rewrite the detail row and every consumer's assumptions. |
| D9 | **Interchange:** Pitaka-JSON `schemaVersion` **3 → 4** (adds `kind`, nested `issue{}` per row, top-level `periodicals[]`). Older builds refuse a v4 file with the existing "update the app" message. | An old build importing silently would drop kinds and links — data loss (P1). |
| D10 | **Backup:** `.pitabak` gains a plain `periodicals.json` entry announced by `hasPeriodicals` (the `hasX` pattern); `books.db` stays byte-for-byte Room-shaped and holds the base rows of **every** kind. | ARCHITECTURE §5.5: the Room shape is a contract; `hasX` is the blessed extension point. |
| D11 | **Publish:** `books.json` stays schema 1 (additive): every entry gains `kind`; issue entries gain `issue{}`; a top-level `periodicals[]` (public fields only). Viewer gets a kind facet and groups issues under their title. | Additive keys are ignored by older viewers. |
| D12 | **Covers:** an issue may have its own; `IssueCover.resolve(issue, periodical)` falls back to the series cover. The janitor counts periodical covers as live references. | Otherwise the startup sweep deletes every series cover (M11 bug class). |
| D13 | **FTS unchanged.** The composed title is indexed; `issue_label` is not. Trigger: a user asks to search by label. | Changing `_ftsColumns` means dropping/rebuilding FTS + triggers in a migration. |
| D14 | **Library screen:** kind facet chips (`All · Books · Magazine issues`) in the same paged query + an assist chip `Magazines ↗` that opens the series list. The series page lists its issues through the same `BookRepository.page` read with `periodicalUid` set. | One paged query per list (N10-d). |
| D15 | **Scanning a magazine barcode** (EAN-13 prefix `977`, ISSN-derived, passes the ISBN-13 checksum today) routes to the add-issue flow. | Today it would store a bogus "ISBN". |

---

## 1. Architecture compliance map

| Rule | How the plan satisfies it |
|------|---------------------------|
| Layering (AGENTS §3, ARCHITECTURE §2) | New feature `lib/features/periodicals/{domain,application,infrastructure,presentation}`. `library/domain` gains `ItemKind`, `IssueOf`, `Book.kind/issue`. Cross-feature imports: domain→domain, presentation→application/domain only. `domain_purity_test`, `layer_boundaries_test` green. |
| Validation at the boundary (AGENTS §3.3, ADR 0004) | `IssueOf.validate` runs inside `Book.validate` (plus the kind⇔details invariant); `Periodical.validate` is a static ingress gate. The gate test scans `Periodical(` too; new construction sites are allow-listed deliberately (§6). |
| Riverpod codegen only (AGENTS §4) | Every provider `@riverpod`; generated `AsyncNotifier`s; DI in `core/di/src/periodical_providers.dart`; autoDispose default; mutation-signal pattern reused; clock via existing `clockProvider` / `nowTickProvider`. |
| `Either<Failure, T>` (AGENTS §5) | New sealed members: `DuplicateIssnFailure`, `DuplicateIssueFailure`, `PeriodicalHasIssuesFailure`, `UnsupportedItemKindFailure`. No exceptions across layers. |
| Fail closed (AGENTS §2.7) | Delete with issues refuses; failed pre-check read refuses the insert; unknown kind rows skipped + reported; orphan issue links detached + reported; kind mismatch on merge = conflict. |
| Secrets | None involved. |
| File-size ratchet (ARCHITECTURE §2.1) | Files at cap that this touches — `drift_book_repository.dart` (597), `book_detail_page.dart` (676), `library_merge_engine.dart` (721), `restore_backup.dart` (553) — are **split before being extended**; entries are lowered, never added. |
| Schema bump protocol (ARCHITECTURE §5.4) | v5: snapshot, generated helpers, data-matrix row, raw-SQL object list. |
| Wire contracts (ARCHITECTURE §5) | JSON v4, backup `hasPeriodicals`, publish additive — each tested + CHANGELOG. |
| Decisions get records (AGENTS §0) | ADR 0013 (item kinds + magazines), ADR 0014 (interchange + backup). |
| Idempotent edits (AGENTS §2.5) | `from < 5` guard; `IF NOT EXISTS` indexes; exact gate allow-lists. |

---

## 2. Domain model (pure Dart)

### 2.1 `library/domain/value_objects/item_kind.dart` (new)

```dart
/// Which kind of catalogue item a base row is (F3). Persisted as [token];
/// never the ordinal. Unknown token → null (caller decides: skip + report).
enum ItemKind {
  book('book'),
  magazineIssue('magazine-issue');
  const ItemKind(this.token);
  final String token;
  static ItemKind? fromToken(String? raw);
}
```

### 2.2 `library/domain/value_objects/issue_of.dart` (new)

```dart
/// Value Object: the magazine-issue details of a base row (F4/F5).
final class IssueOf {
  const IssueOf({
    required this.periodicalUid,
    this.volume, this.issueNumber, this.issueNumberEnd,  // end ⇒ bound (D4)
    this.issueDate,                                       // epoch millis
    this.label,
  });
  bool get isBound => issueNumberEnd != null;
  static List<FieldError> validate(IssueOf issue);
}
```

Rules (one test each): `periodicalUid` non-blank ≤ `maxFieldChars`; numbers
`isValidCount` (null or ≥ 1); `issueNumberEnd` requires `issueNumber` and
`≥` it; at least one of `issueNumber`/`issueDate`; `issueDate`
`isValidOptionalDateMillis`; `label` `isValidFieldText`.

### 2.3 `Book` changes (`library/domain/entities/book.dart`)

- `final ItemKind kind;` (default `ItemKind.book`) and `final IssueOf? issue;`
  `bool get isIssue => kind == ItemKind.magazineIssue;`
- Doc comment: "the catalogue item row (any kind) — see ADR 0013; the class
  name is legacy (F7)".
- `Book.validate`: invariant `kind == magazineIssue ⇔ issue != null`
  (`FieldError('kind', 'does not match the item details')`), then
  `IssueOf.validate` errors prefixed `issue.*`. `copyWith(kind:, issue:)`
  can set, not clear (D8).
- Grows ≈ 30 lines (377 → ~410; ratchet 500).

### 2.4 `features/periodicals/domain/` (new feature)

| File | Content |
|------|---------|
| `entities/periodical.dart` | `Periodical` (`id`, `periodicalUid`, `title`, `titleTransliteration`, `issn`, `publisher`, `language`, `coverUrl`, `frequency`, `subscriptionStart`, `subscriptionEnd`, `notes`, `location`, `sourceType`, `sourceDetail`, `ageGroup`, `addedDate`, `removed`, `removedAt`, `addedBy`) + `static Either<List<FieldError>, Periodical> validate(...)` (title required/trimmed, text caps, dates representable, `subscriptionEnd ≥ subscriptionStart`, cover normalised not rejected, ISSN canonical) + `copyWith`. |
| `value_objects/issn.dart` | `Issn.normalize(String?) → String?` (strip spaces/hyphens, upper-case X, 8 chars, mod-11 weights 8..2, returns `NNNN-NNNC`); `Issn.fromEan13(String) → String?` (prefix `977`, digits 4–10 + computed check digit). |
| `value_objects/periodical_frequency.dart` | enum `weekly, fortnightly, monthly, bimonthly, quarterly, annual, irregular` + token + tolerant `fromToken`. |
| `subscription_status.dart` | `SubscriptionStatus.of(Periodical, int nowMillis)` → sealed `Untracked \| Active(daysLeft) \| ExpiringSoon(daysLeft) \| Lapsed(since)`; `expiringSoonWindowDays = 30`. |
| `issue_cadence.dart` | `nextIssueDate(frequency, lastDateMillis) → int?` (+7 d, +14 d, +1 mo day-clamped, +2 mo, +3 mo, +1 y, `irregular` → null); `nextIssueNumber(last)`. Form prefill only. |
| `issue_title.dart` | `IssueTitle.compose(Periodical, IssueOf) → String`: `"<Series> — Vol 249 No 10 (Oct 2026)"`; parts omitted when null; bound: `"<Series> — Vol 248 (Nos 1–12, 2025)"`. Const English month list (chrome is English, ARCHITECTURE §1.2). |
| `issue_projection.dart` | `IssueProjection.apply(Periodical, Book) → Book` (D3) via `copyWith` only; idempotent. |
| `issue_cover.dart` | `IssueCover.resolve(Book issue, Periodical? series) → String?`. |
| `issue_run.dart` | `IssueRun.gaps(List<Book>)` — missing numbers per volume (bound ranges count as present). |
| `issue_sorter.dart` | Domain oracle for order within a series: `issueDate desc, volume desc, issueNumber desc, id desc`. SQL is tested against it (same as `BookSorter`). |
| `repositories/periodical_repository.dart` | Interface below. |

```dart
abstract interface class PeriodicalRepository {
  Future<Either<Failure, List<PeriodicalSummary>>> listAll();          // + issueCount, boundCount, latestIssueDate (one GROUP BY)
  Future<Either<Failure, Periodical?>> getById(int id);
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid);
  Future<Either<Failure, Periodical?>> findByIssn(String issn);
  Future<Either<Failure, Periodical>> insert(Periodical p);             // mints periodicalUid
  Future<Either<Failure, Periodical>> update(Periodical p);
  Future<Either<Failure, Unit>> markRemoved(int id, int at);
  Future<Either<Failure, Unit>> restoreRemoved(int id);
  Future<Either<Failure, Unit>> delete(int id);                          // use case guarantees no issues
  Future<Either<Failure, int>> countIssues(String periodicalUid);
  Future<Either<Failure, Book?>> findIssue(String periodicalUid, int? volume, int issueNumber);
  Future<Either<Failure, List<Book>>> issuesOf(String periodicalUid);   // bounded by maxLibraryPageSize
  Future<Either<Failure, int>> insertAll(List<Periodical> rows);        // atomic
  Future<Either<Failure, int>> replaceAll(List<Periodical> rows);       // merge OVERWRITE
}
```

`BookRepository` gains **no** methods (ADR 0011 stays deferred): `kind` and
the detail row flow through `insert/update/delete/insertAll/replaceAll/page`
inside the implementation. `LibraryQuery` gains `ItemKind? kind` (null = all)
and `String? periodicalUid` (set ⇒ that series, `IssueSorter` order).

### 2.5 `CatalogueRules` + failures

- `CatalogueRules.isValidIssueRange(start, end)`, `isValidDateOrder(start, end)`.
- `FieldError.userMessage` labels: `kind`, `issn`, `frequency`,
  `subscriptionStart`, `subscriptionEnd`, `issue.periodicalUid`,
  `issue.volume`, `issue.issueNumber`, `issue.issueNumberEnd`,
  `issue.issueDate`, `issue.label`.
- `core/error/failure.dart`: `DuplicateIssnFailure{existingTitle, existingPeriodicalId}`,
  `DuplicateIssueFailure{existingTitle, existingBookId}`,
  `PeriodicalHasIssuesFailure{issueCount}`,
  `UnsupportedItemKindFailure{token}` (an import/restore row with a kind this
  build does not know).

---

## 3. Persistence model (schema v5)

```
books            (base row, every kind; Room-shaped + kind)      ← existing table
  + kind TEXT NOT NULL DEFAULT 'book'

magazine_issues  (detail, 1:1)                                   ← new
  item_id            INTEGER PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE
  periodical_uid     TEXT NOT NULL          -- soft link (no FK), like loans→books
  volume             INTEGER NULL
  issue_number       INTEGER NULL
  issue_number_end   INTEGER NULL
  issue_date         INTEGER NULL
  issue_label        TEXT NULL

periodicals                                                       ← new
  id, periodical_uid (UNIQUE non-null), title, title_transliteration, title_sort,
  issn (UNIQUE non-null), publisher, language, cover_url, frequency,
  subscription_start, subscription_end, notes, location, source_type,
  source_detail, age_group, added_date, removed, removed_at, added_by
```

Raw-SQL invariants added to `_createIndexesAndFts` (`IF NOT EXISTS`, listed in
`migration_test._rawSqlObjects`):

- `index_books_kind ON books (kind)`
- `index_magazine_issues_periodical_uid ON magazine_issues (periodical_uid)`
- `UNIQUE index_magazine_issues_key ON magazine_issues (periodical_uid, COALESCE(volume, 0), issue_number) WHERE issue_number IS NOT NULL` (D6)
- `UNIQUE index_periodicals_periodical_uid`, `UNIQUE index_periodicals_issn`

Foreign keys: `magazine_issues.item_id` is a real FK with cascade (drift
`references(Books, #id, onDelete: KeyAction.cascade)`), which needs
`PRAGMA foreign_keys = ON` in `beforeOpen`. No existing table declares a FK,
so enabling it changes nothing for them; the migration matrix proves it, and
a test proves that deleting a base row removes its detail row.
`periodical_uid` stays a soft link by design (D8 enforces integrity in the
use case; import/restore detach + report).

Migration (`from < 5`, a **separate** `if`, not chained to the network
`else if`): `createTable(periodicals)`, `createTable(magazineIssues)`,
`addColumn(books, books.kind)` — the `DEFAULT 'book'` back-fills every
existing row.

---

## 4. Phases (one PR each; Conventional Commits)

### Phase 0 — records (docs only)

0.1 `docs/adr/0013-catalogue-item-kinds.md` — F1–F8 and D1–D8, D12–D15,
    including the **recipe for adding a kind** (§7 below) and the rename
    trigger (F7).
0.2 `docs/adr/0014-periodical-interchange-and-backup.md` — D9–D11, F6.
0.3 `docs/ARCHITECTURE.md`: §3 module map (`features/periodicals/`), §5
    JSON v4 + `books.json` `kind`, §5.4 schema history v5, §5.5 table row
    (`periodicals.json` / `hasPeriodicals`), §6 standing decisions ("the base
    row is the lendable unit; a new kind never touches the vault").
0.4 `AGENTS.md` §3.3 accepted deviations: `Periodical.validate` beside
    `Book.validate` (same ADR 0004 mechanism).
0.5 `CHANGELOG.md` `[Unreleased]`: schema v5, JSON v4, backup
    `hasPeriodicals`, publish additive keys, item kinds.

### Phase 1 — domain (`feat(catalogue): item kinds + periodicals domain`)

1.1 Everything in §2.
1.2 `LibraryQuery`: `kind`, `periodicalUid`; `sameIntentAs`/`toString` updated.
1.3 Tests (`test/features/library/domain/`, `test/features/periodicals/domain/`):
    `item_kind_test` (tokens, unknown → null); `issue_of_test` (every §2.2
    rule at its boundary); `book_validated_test` (kind⇔details invariant both
    ways; `issue.*` errors; plain book unaffected); `periodical_test`;
    `issn_test` (check digit, `X`, spacing, `fromEan13` happy/wrong
    prefix/bad length); `subscription_status_test` (untracked; 31 d active;
    30 d expiringSoon; 0 d; lapsed); `issue_cadence_test` (month-end clamp,
    year rollover, irregular); `issue_title_test` (every omission combination,
    bound, Indic title untouched); `issue_projection_test` (fields, own cover
    kept, idempotent); `issue_run_test`; `issue_sorter_test`;
    `library_query_test`.
1.4 Gates: `domain_purity_test`; `book_validation_gate_test` extended to
    scan `Periodical(` (initial allow-list: the entity file).

### Phase 2 — persistence, schema v5 (`feat(catalogue): schema v5`)

2.0 **Make room first** (ratchet): move `_LanguageResolver`, `_RollbackWith`,
    `_ftsQuery` and the raw `ORDER BY` builder from `drift_book_repository.dart`
    into `library/infrastructure/drift_book_sql.dart` (pure refactor; tests
    unchanged); lower its ratchet entry.
2.1 `core/database/tables.dart`: `Books.kind`; `MagazineIssues`
    (`@DataClassName('MagazineIssueRow')`); `Periodicals`
    (`@DataClassName('PeriodicalRow')`).
2.2 `app_database.dart`: `schemaVersion => 5`, history line, migration (§3),
    `PRAGMA foreign_keys = ON` in `beforeOpen`, new raw-SQL objects.
2.3 Snapshot protocol: `drift_dev schema dump` → `drift_schema_v5.json`;
    `schema generate` → `test/core/database/generated/schema_v5.dart`;
    `migration_test.dart` data-matrix row (a populated v4 DB upgrades; book,
    issue, periodical rows round-trip; `kind` back-filled to `book`; FTS
    search works; cascade proven), `_rawSqlObjects` updated.
2.4 `library/infrastructure/drift_item_details.dart` (new, **the seam for
    future kinds**): `readDetails(BookRow) → (IssueOf?)`, `writeDetails(id,
    Book)`, `deleteDetails(id)`; today it knows `magazine_issues` only.
2.5 `book_mapper.dart`: `(BookRow, MagazineIssueRow?) → Book` and
    `Book → BooksCompanion + MagazineIssuesCompanion?`; unknown stored kind
    token → the row maps to `book` **and** is logged once via `app_log` (a
    newer build wrote it; reading must not crash, writing back is refused by
    `update` with `UnsupportedItemKindFailure`).
2.6 `drift_book_repository.dart`: `_listRows`/`_searchRows` LEFT JOIN
    `magazine_issues` (badges + mapper), `kind` predicate, `periodical_uid`
    predicate + `IssueSorter` ORDER BY; `insert/update/insertAll/replaceAll`
    write base + detail in one transaction through `drift_item_details.dart`;
    UNIQUE violation on the issue key → `DuplicateIssueFailure` (same idiom
    as `_isbnCollision`).
2.7 `periodicals/infrastructure/drift_periodical_repository.dart` +
    `periodical_mapper.dart`: §2.4 interface; uid minting; `listAll` is one
    `LEFT JOIN … GROUP BY`; ISSN race → `DuplicateIssnFailure`.
2.8 DI: `core/di/src/periodical_providers.dart` + part in `providers.dart`.
2.9 `cover_file_janitor.dart`: periodical covers are live references (D12).
2.10 Tests: `drift_periodical_repository_test` (CRUD, uid, ISSN race,
     `countIssues`, `findIssue` ± volume, `issuesOf` order == `IssueSorter`);
     `drift_book_repository_test` additions (kind facet, series facet + order,
     issue-key race → typed failure, detail row written/updated/cascaded, a
     plain-book edit leaves no detail row); `cover_file_janitor_test` (series
     cover survives a sweep); `migration_test` v1..v4 → v5.

### Phase 3 — application (`feat(periodicals): use cases + controllers`)

| File (`periodicals/application/`) | Responsibility | Tests |
|---|---|---|
| `add_periodical_use_case.dart` | `Periodical.validate` → `findByIssn` pre-check (fail closed on read error) → insert | success / validation / duplicate ISSN / repo failure |
| `update_periodical_use_case.dart` | validate → ISSN pre-check excluding self → **one transaction**: update series, `issuesOf`, `IssueProjection.apply` each, `BookRepository.update` each (D3) | rename re-titles every issue; mid-way failure rolls back all |
| `delete_periodical_use_case.dart` | `countIssues > 0` ⇒ `PeriodicalHasIssuesFailure`; else delete + release cover via janitor | fails closed; deletes when empty |
| `add_issue_use_case.dart` | load series (`NotFoundFailure` if missing/removed) → `Book(kind: magazineIssue, issue: …)` → `IssueProjection.apply` → `Book.validate` → `findIssue` pre-check ⇒ `DuplicateIssueFailure` → insert | each path; bound; date-only skips pre-check |
| `update_issue_use_case.dart` | as add, `update`, pre-check excludes self; refuses a kind change (D8) | |
| `periodicals_controller.dart` | `@riverpod class PeriodicalsController` (AsyncNotifier of summaries + `SubscriptionStatus` from `clockProvider`); `refresh()` | |
| `issue_list_controller.dart` | `@riverpod` family by `periodicalUid`, reusing `LibraryWindow` + `BookRepository.page(LibraryQuery(periodicalUid: …))`, plus `IssueRun.gaps` | paging, gaps |
| `add_issue_controller.dart`, `periodical_form_controller.dart` | thin `AsyncNotifier<void>` wrappers like `AddBookController`; prefill via `IssueCadence` | |
| `library/application/scan_routing` | `routeScannedCode`: EAN-13 `977…` → `Issn.fromEan13` → `findByIssn` → add-issue prefilled, or offer "New magazine title" (D15) | 977 routes to issues; ISBN path unchanged |

`periodicalById(int)` / `periodicalByUid(String)` read providers watch
`periodicalsControllerProvider` **and** `libraryControllerProvider` as
mutation signals (pattern of `bookById`). Every issue write calls
`LibraryController.refresh()`. Screens with a subscription badge watch
`nowTickProvider` so an open screen rolls over (N04 idiom). No
`DateTime.now()` in domain; none added in application.

### Phase 4 — presentation (`feat(periodicals): screens`)

4.0 **Make room first**: `book_detail_page.dart` (676, at cap) — extract the
    remove/restore confirmation + lend section into
    `widgets/book_detail_actions.dart`; `library_page.dart` (416) — extract
    the "more" popup menu into `widgets/library_menu_button.dart`.
    `add_book_page.dart` (638) is deliberately untouched — issues get their
    own page.
4.1 `library_controls_row.dart`: kind facet chips (`All · Books · Magazine
    issues`, state on `LibraryFilterController` like the language facet) +
    assist chip `Magazines ↗` → `PeriodicalsPage`. Chips for kinds are built
    from `ItemKind.values` (a future kind appears automatically).
4.2 `widgets/add_sheet.dart`: FAB → *Add book / Add magazine issue / New
    magazine title*.
4.3 `book_row.dart`: `Issue` / `Bound volume` badges from `book.issue`; cover
    via `IssueCover.resolve` (series covers from a one-query
    `periodicalCoversProvider` map).
4.4 `periodicals/presentation/pages/periodicals_page.dart`: series rows
    (cover, title, ISSN · frequency · N issues, `SubscriptionBadge`), empty
    state, FAB.
4.5 `pages/periodical_detail_page.dart`: hero, subscription card, "+ Add
    issue", issues newest-first (`IssueListController`), gap rows, edit,
    overflow (remove/restore/delete with the typed refusal).
4.6 `pages/periodical_form_page.dart`: per mockup; "Track subscription"
    switch; ISSN inline validation; language picker reuses the facet values;
    cover capture through the existing `CoverFiles` port flow.
4.7 `pages/add_issue_page.dart`: series picker (preselected from a series),
    "Bound volume" switch, date, label, own cover, copies, pages, location
    (prefilled from series), notes, generated-title preview. Builds `Book(` →
    **gate allow-list entry** (the use case re-validates).
4.8 `library/presentation/widgets/issue_detail_section.dart`: "Issue" and
    "From the series" blocks shown by `BookDetailPage` when `book.isIssue`
    (one `switch (book.kind)` — the seam where a future kind adds its own
    section). Lend button unchanged.
4.9 Drawer entry "Magazines" → `PeriodicalsPage`.
4.10 Widget tests: `periodicals_page_test`, `periodical_detail_page_test`
     (badge states, gap row, refusal message), `periodical_form_page_test`,
     `add_issue_page_test` (bound toggle, preview, save passes a projected
     `Book`), `book_row_test` (badges), `library_controls_row_test` (kind
     chips), goldens for the series row + badge (Linux goldens, see CHANGELOG
     1.5.2).

### Phase 5 — interchange, merge, publish, backup (`feat(catalogue): formats`)

5.1 **Pitaka-JSON v4** (`kPitakaSchemaVersion = 4`). Per book row:
    `"kind": "magazine-issue"` (absent ⇒ `book`) and a nested
    `"issue": { "periodicalUid", "volume", "issueNumber", "issueNumberEnd", "issueDate", "label" }`;
    top-level `"periodicals": [...]`. Importer: periodicals through
    `Periodical.validate`, capped by `ImportLimits.maxRows`; unknown `kind`
    ⇒ row skipped + counted (`UnsupportedItemKindFailure` → warning text);
    kind⇔details mismatch ⇒ row rejected (parse error); an issue whose series
    is in neither the file nor the local library ⇒ imported as a **book**
    with a warning "N issues were detached: series not found".
    `ImportPayload` gains `periodicals`, `issuesDetached`, `rowsSkippedUnknownKind`.
    v3 files import unchanged (fixture kept).
5.2 `import_library_use_case.dart`: in the existing single transaction —
    periodicals first (upsert by uid; ISSN dedup like ISBN), then rows.
5.3 **CSV export**: additive columns `Kind`, `Series`, `Volume`, `Issue`,
    `Last issue`, `Issue date`, `Issue label`. PDF export unchanged (composed
    title carries the information; renderer at cap).
5.4 **Merge**: `library_merge_engine.dart` is at cap (721) — extract
    `_FuzzyIndex` to `fuzzy_index.dart` first. Then `periodical_merge.dart`
    (uid → ISSN → exact title key; add-only, removal-as-conflict) and the
    issue second key (D6) in `issue_identity.dart`; same-uid kind mismatch ⇒
    conflict. `merge_library_use_case.dart` applies periodicals before rows
    and re-projects issues of merged series. Planner input/output stay plain
    Dart (isolate-safe). Merge page shows periodical counts.
5.5 **Publish**: `PublishBook` gains `kind` + nested `issue{}` (public);
    `PublishExport` gains `periodicals[]` (`periodicalUid, title,
    titleTransliteration, issn, publisher, language, coverUrl, frequency,
    ageGroup`; subscription dates, notes, location, source*, addedBy
    **stripped**). Periodical covers go through the same cover-id +
    allow-list pipeline; issue entries publish `IssueCover.resolve`.
    `assets/publish/index.html`: kind facet, issues grouped under their
    title with the bound badge; unknown kinds render as plain items.
    `schemaVersion` stays 1.
5.6 **Backup**: writer emits `periodicals.json`
    `{ "schemaVersion": 1, "periodicals": [...], "issues": [{ "bookUid", "periodicalUid", "volume", "issueNumber", "issueNumberEnd", "issueDate", "label" }] }`
    and sets `hasPeriodicals` (`BackupManifest` default **false**).
    **Kind rule for `.pitabak`:** `books.db` holds every base row in Room
    shape (no `kind` column); a base row's kind is *implied by the detail
    entry that lists its uid* (`issues[]` ⇒ `magazine-issue`; listed nowhere
    ⇒ `book`). A future kind adds its own `hasX` entry with the same rule.
    `backup_extras_reader.dart` reads it (4 MiB cap, rows re-validated,
    invalid dropped + counted); new `restore_periodicals.dart` joins issues
    to the restored rows by `bookUid` *before* the catalogue write (restore
    phase 5, no device writes yet), detaches unmatched links, and reports
    `periodicalsRestored / issuesLinked / issuesDetached` in `RestoreSummary`.
    Kotlin-era archives: flag absent ⇒ nothing to do. `restore_backup.dart`
    stays under its cap because the join lives in the new file.
5.7 Tests: JSON v4 round-trip, v3 fixture, unknown-kind skip, mismatch
    rejection, detached warning, oversized `periodicals` truncation; CSV
    columns; merge identity (uid/ISSN, issue second key, kind-mismatch
    conflict, re-projection after apply, isolate round-trip); publish
    redaction, cover fallback, viewer tolerance; backup writer entry + flag,
    reader drops + counts, restore links/detaches, flag-less archive restores
    exactly as before (fixture).

### Phase 6 — release hygiene

6.1 `fastlane/metadata/android/en-US/changelogs/<next versionCode>.txt`.
6.2 Guides: no catalogue guide exists (`GuideId` = publish, map, backup,
    vault, network). Add `GuideId.magazines` (series → issues → lending →
    backup) respecting the pinned invariants (order, 2–7 steps, ≤ 3 "Good to
    know", 1:1 destination → `PeriodicalsPage`); `guide_catalog_test`
    expectations updated deliberately.
6.3 `integration_test/` smoke: add series → add issue → lend → backup → restore.

---

## 5. Order of work and PR boundaries

```
PR 1  docs:  ADR 0013, ADR 0014, ARCHITECTURE/AGENTS/CHANGELOG   (phase 0)
PR 2  feat:  domain (ItemKind, IssueOf, Book.kind, periodicals)  (phase 1)
PR 3  feat:  schema v5 + repositories + DI + janitor             (phase 2)   ← PR 2
PR 4  feat:  use cases + controllers + scan routing              (phase 3)   ← PR 3
PR 5  feat:  screens                                             (phase 4)   ← PR 4
PR 6  feat:  JSON v4 + CSV + merge                               (5.1–5.4)   ← PR 4
PR 7  feat:  publish + viewer                                    (5.5)       ← PR 4
PR 8  feat:  backup/restore                                      (5.6)       ← PR 4
PR 9  chore: release hygiene                                     (phase 6)
```

PRs 5–8 are independent of each other. Every PR description states what
changed, why, security impact ("no secrets; hostile-input bounds unchanged or
tightened"), and coverage.

---

## 6. Gate allow-lists that change (deliberate, reviewed)

| Gate | Entry | Reason |
|------|-------|--------|
| `book_validation_gate_test` | `periodicals/presentation/pages/add_issue_page.dart` | the form builds the `Book`; `AddIssueUseCase` re-validates |
| `book_validation_gate_test` (`Periodical(` scan) | `periodical_mapper.dart`, `pitaka_json_importer.dart`, `restore_periodicals.dart`, `add/update_periodical_use_case.dart` | sites that pass through `Periodical.validate` |
| `layer_boundaries_test` ratchet | lower `drift_book_repository.dart`, `book_detail_page.dart`, `library_merge_engine.dart` to post-split sizes | entries shrink; none added |
| `migration_test._rawSqlObjects` | five new indexes | raw-SQL invariants are proven after every upgrade path |

---

## 7. Recipe: adding a future kind (what the seams buy — goes into ADR 0013)

1. `ItemKind.<kind>('<token>')` + a value object `<Kind>Of` with `validate`.
2. `Book.<kind>: <Kind>Of?` and the kind⇔details invariant in `Book.validate`
   (second kind: replace the optional fields with the sealed `ItemDetails`).
3. Detail table `<kind>_details(item_id PK → books.id CASCADE, …)`; schema
   bump; snapshot + helpers + matrix row.
4. `drift_item_details.dart`: read/write/delete for the new table; mapper
   branch. Nothing else in the repository changes.
5. Wire formats: nested `"<kind>": {…}` object in Pitaka-JSON and
   `books.json`; a `has<Kind>` entry in `.pitabak` listing uids (kind implied).
6. Add-sheet entry, form page, `issue_detail_section`-style section in the
   `switch (book.kind)`; kind chip appears automatically.
7. If the kind needs grouping, that is the trigger for a generic collections
   concept (F8) — decide then, with an ADR.
8. **The vault is not touched** (F2). Lending, availability, loan screens work
   on the base row as they do today.

Before step 1 of the first such PR: the rename-only PR `Book → CatalogueItem`
(F7).

---

## 8. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Enabling `PRAGMA foreign_keys` surprises an existing path | no existing table declares a FK; migration matrix + a cascade test; `replaceAll`/restore delete base rows and rely on cascade (tested) |
| Re-projection on rename touches N issue rows | one transaction; `issuesOf` bounded; failure rolls back the rename |
| Startup cover sweep deletes series covers | janitor counts periodical covers (2.9) + test |
| Old build receives a v4 JSON file | refuses with the existing message (D9) |
| Old build restores a new `.pitabak` | ignores `periodicals.json`; issues restore as books with composed titles — honest limit documented in §5.5 |
| Row written by a newer build with an unknown kind | read maps to `book` + logged once; write back refused with a typed failure (2.5) |
| Merge conflict storm after a rename on one device | periodicals merge first; issues re-projected after apply (5.4) |
| Ratchet violations | every capped file is split *before* being extended |
| Partial/expression index support | SQLite ≥ 3.9; `sqlite3_flutter_libs` bundles a current SQLite; proven by the migration matrix |

---

## 9. Open questions (answer before PR 4)

1. "Expiring soon" window: 30 days — confirm.
2. Bound volume spanning two volumes: **no** in v1 (two rows) — confirm.
3. Per-issue age-group override: **no** (projected from series) — confirm.
4. Drawer entry "Magazines" in addition to the Library assist chip — keep both?
5. `Book → CatalogueItem` rename: deferred to the second kind (F7) — confirm,
   or pull it forward as PR 0.
