# Magazines & issues — implementation plan

- **Branch:** `magazines`
- **Status:** Plan (no code yet). Mockup: `docs/mockups/periodicals_mockup.html`.
- **Promise protected (ARCHITECTURE §1.1):** P1 (every format change is
  versioned, migrated and tested), P5 (one blessed way: issues *are* books).

This plan is written so that each phase is one reviewable PR and every step
names the file it touches, the rule it must satisfy (AGENTS.md / ARCHITECTURE
§2.1 fitness functions) and the test that proves it.

---

## 0. Decisions (summary — details in ADR 0013 / ADR 0014)

| # | Decision | Why |
|---|----------|-----|
| D1 | **An issue is a `Book` row** carrying an optional `IssueOf` value object (`periodicalUid`, `volume`, `issueNumber`, `issueNumberEnd`, `issueDate`, `label`). `book.issue == null` ⇒ ordinary book. | The Rust vault's loans reference `book_id` only (`rust/src/vault.rs:68`). Lending, availability, covers, FTS, paging, merge, publish, backup keep working with **no** second item type. |
| D2 | **A new `Periodical` entity + `periodicals` table** holds series-level data: title, ISSN, publisher, language, cover, frequency, optional subscription window, private fields. Identity: `periodicalUid` (UUID), same pattern as `bookUid`. | The series is the single writer of everything an issue inherits. |
| D3 | **Derived fields are projected, not read through.** `IssueProjection` writes the issue row's `title`, `titleTransliteration`, `publisher`, `language`, `publishedYear`, `ageGroup` from (periodical, issue). Editing the series re-projects every issue in one transaction. | Every existing consumer (language facet SQL, sort, publish, CSV/PDF export, merge) reads plain `books` columns. Zero joins; zero new code paths in those features. |
| D4 | **Bound volume = one issue row with an issue range** (`issueNumber`..`issueNumberEnd`, same `volume`). One physical item, one `copyCount`, one loan. | A library that binds a year's issues lends the volume as one thing. |
| D5 | **Subscription tracking is optional and derived.** `subscriptionEnd == null` ⇒ untracked. `SubscriptionStatus.of(periodical, now)` ∈ {untracked, active, expiringSoon (≤ 30 days), lapsed}. No status column, no notifications, no new plugin. | A stored status can drift; a derived one cannot. No Google deps (P3). |
| D6 | **Issue identity for dedup/merge:** `bookUid` → (`periodicalUid`, `volume ?? 0`, `issueNumber`) → fuzzy title. Issues without an issue number (date-only) have no uniqueness guarantee — exactly like books without an ISBN today. | Mirrors the existing uid → ISBN → fuzzy order (ARCHITECTURE §6). |
| D7 | **ISSN lives on the periodical only**, canonical `NNNN-NNNC`, mod-11 check digit, unique among non-null. Never in `books.isbn`. | An ISSN identifies the title, not the issue; the UNIQUE `isbn` index would collide across issues. |
| D8 | **Hard delete of a periodical fails closed** while issues reference it (`PeriodicalHasIssuesFailure`). Soft-remove is allowed and leaves issues untouched. Converting an issue back to a plain book is **not** supported (delete and re-add). | No orphan links; `copyWith` cannot null a field, so "un-issue" would need a new construction site for no user value. |
| D9 | **Interchange:** Pitaka-JSON `schemaVersion` **3 → 4** (adds `periodicals[]` + six optional book keys). Older builds refuse a v4 file with the existing "update the app" message. | An old build importing silently would drop the links — that is data loss (P1). Refusing is honest. |
| D10 | **Backup:** `.pitabak` gains a plain `periodicals.json` entry announced by `hasPeriodicals` (the existing `hasX` forward-compat pattern); `books.db` stays byte-for-byte Room-shaped. | ARCHITECTURE §5.5: the Room shape is a contract; the `hasX` flag pattern is the blessed extension point. No manifest schema bump needed. |
| D11 | **Publish:** `books.json` stays schema 1 (additive): issue entries gain the six issue keys; a top-level `periodicals[]` is added (public fields only). Viewer groups issues under their title. | ARCHITECTURE §5: additive keys are ignored by older viewers. |
| D12 | **Covers:** an issue may have its own cover; when it has none, `IssueCover.resolve(issue, periodical)` falls back to the series cover. The janitor counts periodical covers as live references. | Without the janitor rule the startup sweep would delete every series cover (same bug class as M11 for wishlist). |
| D13 | **FTS is unchanged in this release.** The composed title ("National Geographic — Vol 249 No 10 (Oct 2026)") is indexed; `issue_label` is not. Trigger to add it: a user asks to search by label. | Changing `_ftsColumns` means dropping and rebuilding the FTS table + triggers in a migration — risk without a request behind it. |
| D14 | **Library screen:** chips `All · Books only · Magazines ↗`. "Books only" hides issue rows in the same paged query; "Magazines ↗" opens the series list page. The series detail page lists its issues via the same `BookRepository.page` read with `periodicalUid` set. | One paged query per list (ARCHITECTURE §6, N10-d). The inline grouped view in the mockup would need two queries in one list. |
| D15 | **Scanning a magazine barcode** (EAN-13 prefix `977`, which is ISSN-derived and passes the ISBN-13 checksum today) routes to the add-issue flow, never to the add-book form. | Today such a scan would store a bogus "ISBN". |

---

## 1. Architecture compliance map

| Rule | How this plan satisfies it |
|------|----------------------------|
| Layering (AGENTS §3, ARCHITECTURE §2) | New feature folder `lib/features/periodicals/{domain,application,infrastructure,presentation}`. `library/domain` gains only the `IssueOf` value object. Cross-feature imports go domain→domain, presentation→application/domain only. `domain_purity_test` + `layer_boundaries_test` stay green. |
| Validation at the boundary (AGENTS §3.3, ADR 0004) | `IssueOf.validate` is called from `Book.validate`; `Periodical.validate` is a static ingress gate like `Book.validate`. The gate test is extended to scan `Periodical(` sites; new `Book(`/`Periodical(` construction sites are added to its allow-list deliberately (§5 below lists them). |
| Riverpod codegen only (AGENTS §4) | Every provider is `@riverpod`; list/detail state are generated `AsyncNotifier`s; DI in `lib/core/di/src/periodical_providers.dart`; autoDispose default; the mutation signal pattern (`ref.watch(xControllerProvider)` inside read providers) is reused. |
| `Either<Failure, T>` (AGENTS §5) | New failures are added to the sealed hierarchy in `core/error/failure.dart`: `DuplicateIssnFailure`, `DuplicateIssueFailure`, `PeriodicalHasIssuesFailure`, `PeriodicalNotFoundFailure` (or reuse `NotFoundFailure`). No exceptions cross layers. |
| Fail closed (AGENTS §2.7) | Delete with issues refuses; a failed pre-check read refuses the insert; import/restore drop invalid rows and **report** counts; orphan issues (link to a missing series) are **detached and reported**, never silently kept dangling. |
| No secrets involved | Nothing here is a secret; no `SecretBytes` changes. |
| File-size ratchet (ARCHITECTURE §2.1) | Three files this work would touch are at their recorded cap: `drift_book_repository.dart` (597), `book_detail_page.dart` (676), `add_book_page.dart` (638). **Each is split *before* it is extended** (§3 phase 2.0 / 4.0). New files are designed to stay < 500 lines. |
| Schema bump protocol (ARCHITECTURE §5.4) | v5: snapshot dump, regenerated helpers, data-matrix row, raw-SQL object list updated. |
| Wire contracts (ARCHITECTURE §5) | JSON v4 (D9), backup `hasPeriodicals` (D10), publish additive (D11), each with a test and a CHANGELOG line. |
| Decisions get records (AGENTS §0) | ADR 0013 (model), ADR 0014 (interchange + backup choices). |
| Idempotent edits (AGENTS §2.5) | Migration guarded by `from < 5`; indexes `IF NOT EXISTS`; provider names unique; the gate allow-lists are exact sets. |

---

## 2. Domain model (pure Dart)

### 2.1 `lib/features/library/domain/value_objects/issue_of.dart` (new)

```dart
/// Value Object: what makes a Book an issue of a periodical. Immutable,
/// validated by [IssueOf.validate] (called from Book.validate).
final class IssueOf {
  const IssueOf({
    required this.periodicalUid,
    this.volume,
    this.issueNumber,
    this.issueNumberEnd,   // non-null ⇒ bound volume (D4)
    this.issueDate,        // epoch millis, nullable
    this.label,            // free text, ≤ CatalogueRules.maxFieldChars
  });
  bool get isBound => issueNumberEnd != null;
  static List<FieldError> validate(IssueOf issue);
}
```

Rules (each one a test):
- `periodicalUid` non-blank, ≤ `maxFieldChars`.
- `volume`, `issueNumber`, `issueNumberEnd`: `CatalogueRules.isValidCount` (null or ≥ 1).
- `issueNumberEnd` requires `issueNumber` and `issueNumberEnd >= issueNumber`.
- At least one of `issueNumber`, `issueDate` present (an issue must be identifiable).
- `issueDate`: `isValidOptionalDateMillis`.
- `label`: `isValidFieldText`.

### 2.2 `Book` changes (`lib/features/library/domain/entities/book.dart`)

- One new field: `final IssueOf? issue;` + `bool get isIssue => issue != null;`
- `Book.validate`: appends `IssueOf.validate(issue)` errors (prefixed field
  names `issue.volume`, …); `FieldError.userMessage` gains the labels.
- `copyWith(issue:)` can set, not clear (D8).
- File grows ≈ 25 lines (377 → ~405, under the 500 ratchet).

### 2.3 `lib/features/periodicals/domain/` (new feature)

| File | Content |
|------|---------|
| `entities/periodical.dart` | `Periodical` (fields in §0 D2 + `addedDate`, `removed`, `removedAt`, `addedBy`; `id`/`emptyId`/`periodicalUid` like `Book`). `static Either<List<FieldError>, Periodical> validate(Periodical)` — title required+trimmed, every text field capped, dates representable, `subscriptionEnd >= subscriptionStart` when both set, cover normalised (same rule as `Book.validate`), ISSN canonical or error. `copyWith`. |
| `value_objects/issn.dart` | `Issn.normalize(String?) → String?` (strip spaces/hyphens, uppercase X, 8 chars, mod-11 check with weights 8..2, returns `NNNN-NNNC`), `Issn.fromEan13(String) → String?` (prefix `977`, digits 4–10 + computed check digit). |
| `value_objects/periodical_frequency.dart` | enum `weekly, fortnightly, monthly, bimonthly, quarterly, annual, irregular` with stable `token` + tolerant `fromToken` (same style as `AgeGroup`). |
| `subscription_status.dart` | `SubscriptionStatus.of(Periodical, int nowMillis)` → sealed `Untracked | Active(daysLeft) | ExpiringSoon(daysLeft) | Lapsed(since)`; `const expiringSoonWindowDays = 30`. |
| `issue_cadence.dart` | `IssueCadence.nextIssueDate(frequency, lastIssueDateMillis) → int?` (+7 d, +14 d, +1 mo (day clamped), +2 mo, +3 mo, +1 y, null for irregular) and `nextIssueNumber(lastIssue)`. Form prefill only. |
| `issue_title.dart` | `IssueTitle.compose(Periodical, IssueOf) → String`: `"<Series> — Vol 249 No 10 (Oct 2026)"`; parts omitted when null; bound: `"<Series> — Vol 248 (Nos 1–12, 2025)"`. English month names as a const list (UI chrome is English, ARCHITECTURE §1.2). Deterministic, fully tested. |
| `issue_projection.dart` | `IssueProjection.apply(Periodical, Book) → Book` (D3): sets `title`, `titleTransliteration` (series transliteration + same suffix, or null), `publisher`, `language`, `publishedYear` (from `issueDate`), `ageGroup`, `needsMetadata=false`. Uses `copyWith` only. |
| `issue_cover.dart` | `IssueCover.resolve(Book issue, Periodical? series) → String?` (own cover, else series cover). |
| `issue_run.dart` | `IssueRun.gaps(List<Book> issues) → List<(volume, issueNumber)>` — missing numbers between min and max per volume (bound ranges count as present). Powers the "missing" row. |
| `issue_sorter.dart` | Domain oracle for issue order within a series: `issueDate desc, volume desc, issueNumber desc, id desc` (total order; the SQL is tested against it, same as `BookSorter`). |
| `repositories/periodical_repository.dart` | Interface (below). |

```dart
abstract interface class PeriodicalRepository {
  Future<Either<Failure, List<PeriodicalSummary>>> listAll();   // + issueCount, boundCount, latestIssueDate (one GROUP BY query)
  Future<Either<Failure, Periodical?>> getById(int id);
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid);
  Future<Either<Failure, Periodical?>> findByIssn(String issn);
  Future<Either<Failure, Periodical>> insert(Periodical p);      // mints periodicalUid
  Future<Either<Failure, Periodical>> update(Periodical p);
  Future<Either<Failure, Unit>> markRemoved(int id, int at);
  Future<Either<Failure, Unit>> restoreRemoved(int id);
  Future<Either<Failure, Unit>> delete(int id);                   // caller guarantees no issues (use case)
  Future<Either<Failure, int>> countIssues(String periodicalUid);
  Future<Either<Failure, Book?>> findIssue(String periodicalUid, int? volume, int issueNumber);
  Future<Either<Failure, List<Book>>> issuesOf(String periodicalUid);   // bounded by maxLibraryPageSize; used by re-projection + gaps
  Future<Either<Failure, int>> insertAll(List<Periodical> rows);   // restore/import, atomic
  Future<Either<Failure, int>> replaceAll(List<Periodical> rows);  // merge OVERWRITE
}
```

`BookRepository` itself gains **no** new methods (ADR 0011 stays deferred):
the issue columns flow through `insert/update/page` via the mapper, and
`LibraryQuery` gains `kind` (`all | booksOnly | issuesOnly`) and
`periodicalUid` (when set: narrows to that series and orders by
`IssueSorter`). Transactions that touch both tables use the existing
`BookRepository.runInTransaction` (same database).

### 2.4 `CatalogueRules` additions (`library/domain/catalogue_rules.dart`)

- `isValidIssueRange(int? start, int? end)`.
- `isValidDateOrder(int? start, int? end)` (subscription window).
- `FieldError.userMessage` labels: `issn`, `frequency`, `subscriptionStart`,
  `subscriptionEnd`, `issue.periodicalUid`, `issue.volume`,
  `issue.issueNumber`, `issue.issueNumberEnd`, `issue.issueDate`,
  `issue.label`.

### 2.5 New failures (`core/error/failure.dart`)

```dart
final class DuplicateIssnFailure extends Failure { existingTitle, existingPeriodicalId }
final class DuplicateIssueFailure extends Failure { existingTitle, existingBookId }   // same (series, volume, number)
final class PeriodicalHasIssuesFailure extends Failure { final int issueCount; }
```
Each gets a safe UI message in the one place failures are mapped for forms.

---

## 3. Phases (one PR each; commits are Conventional)

### Phase 0 — records (docs only)

0.1 `docs/adr/0013-periodicals-as-series-plus-issue-rows.md` — D1–D8, D12–D15.
0.2 `docs/adr/0014-periodical-interchange-and-backup.md` — D9–D11.
0.3 `docs/ARCHITECTURE.md`: §3 module map (`features/periodicals/`), §5.4
    schema history (v5), §5.5 table row (`periodicals.json` / `hasPeriodicals`),
    §5 JSON v4 note, §6 standing decision "issues are books".
0.4 `AGENTS.md` §3.3 accepted deviations: add `Periodical.validate` next to
    `Book.validate` (same ADR 0004 mechanism, enforced by the gate test).
0.5 `CHANGELOG.md` → `[Unreleased]` → *Added / Changed* lines for v5 schema,
    JSON v4, backup `hasPeriodicals`, publish additive keys.

### Phase 1 — domain (`feat(periodicals): domain model`)

1.1 Everything in §2 (`IssueOf`, `Book.issue`, `Periodical`, value objects,
    pure helpers, repository interface, `CatalogueRules`, failures).
1.2 `LibraryQuery`: `kind` + `periodicalUid`, normalised; `sameIntentAs`
    compares them; `toString` updated.
1.3 Tests (`test/features/periodicals/domain/`, `test/features/library/domain/`):
    - `issn_test.dart`: valid/invalid check digits, `X` digit, spacing/hyphen
      tolerance, `fromEan13` happy path + wrong prefix + bad length.
    - `issue_of_test.dart`: every rule in §2.1 (boundary values 0/1, end < start,
      end without start, neither number nor date, label length cap).
    - `book_validated_test.dart`: `Book.validate` surfaces `issue.*` errors;
      a plain book is unaffected.
    - `periodical_test.dart`: title trim/required, text caps, date order,
      cover normalisation (not rejection), ISSN canonicalisation.
    - `subscription_status_test.dart`: untracked; active; exactly 30 days →
      expiringSoon; 31 → active; end == now → expiringSoon(0); end < now →
      lapsed.
    - `issue_cadence_test.dart`: month-end clamping (31 Jan → 28/29 Feb),
      year rollover, irregular → null.
    - `issue_title_test.dart`: every omission combination; bound format;
      Indic series title passes through unchanged.
    - `issue_projection_test.dart`: derived fields, own cover untouched,
      idempotent (applying twice == once).
    - `issue_run_test.dart`: gaps across bound ranges; empty; single.
    - `issue_sorter_test.dart`: total order, null dates last.
    - `library_query_test.dart`: new fields normalise and compare.
1.4 Gates: `domain_purity_test` (new domain files import only domain/fpdart);
    `book_validation_gate_test` extended to also scan `Periodical(`; initial
    allow-list = entity file only.

### Phase 2 — persistence, schema v5 (`feat(periodicals): schema v5`)

2.0 **Make room first** (ratchet): move `_LanguageResolver`, `_RollbackWith`,
    `_ftsQuery` and the raw `ORDER BY` builder out of
    `drift_book_repository.dart` into `library/infrastructure/drift_book_sql.dart`
    (pure refactor, existing tests unchanged). The repository drops to ≈ 450
    lines; its ratchet entry is **lowered** to the new size (entries may shrink,
    never grow).
2.1 `core/database/tables.dart`: `Periodicals` table (`@DataClassName('PeriodicalRow')`,
    columns per D2, `periodical_uid` + `issn` nullable text, `subscription_start/end`
    nullable int, `frequency` text token, `removed/removed_at`, `added_by`,
    `title_sort` shadow like books) and six nullable columns on `Books`:
    `periodical_uid`, `volume`, `issue_number`, `issue_number_end`, `issue_date`,
    `issue_label`.
2.2 `app_database.dart`: `schemaVersion => 5`; doc-comment history line;
    migration `if (from < 5) { createTable(periodicals); addColumn ×6 }` — a
    **separate** `if`, not chained to the network `else if` (books existed in
    every version, so the columns are always added; `createTable` builds the
    current definition).
2.3 `_createIndexesAndFts` (raw-SQL invariants, `IF NOT EXISTS`):
    - `UNIQUE index_periodicals_periodical_uid ON periodicals (periodical_uid)`
    - `UNIQUE index_periodicals_issn ON periodicals (issn)`
    - `index_books_periodical_uid ON books (periodical_uid)`
    - `UNIQUE index_books_issue_key ON books (periodical_uid, COALESCE(volume, 0), issue_number) WHERE periodical_uid IS NOT NULL AND issue_number IS NOT NULL` (D6; expression + partial index, SQLite ≥ 3.9).
    - FTS table/triggers unchanged (D13).
    No SQL foreign key: consistent with how loans reference books; integrity is
    enforced by use cases + import/restore re-validation (D8).
2.4 Snapshot protocol (ARCHITECTURE §5.4): `drift_dev schema dump` →
    `drift_schemas/app_database/drift_schema_v5.json`; `schema generate` →
    `test/core/database/generated/schema_v5.dart`; `migration_test.dart`:
    data-matrix row for v5 (a populated v4 database upgrades; a book row,
    an issue row and a periodical row round-trip; search still works), new
    index names in `_rawSqlObjects`.
2.5 `library/infrastructure/book_mapper.dart`: `IssueOf` ↔ six columns, both
    directions; `toCompanion` writes `Value.absent()`-free explicit nulls for
    a plain book so an edit that keeps `issue == null` cannot leave stale
    issue columns.
2.6 `drift_book_repository.dart`: `_listRows` / `_searchRows` add the `kind`
    predicate and the `periodical_uid = ?` predicate; when `periodicalUid` is
    set the ORDER BY is the `IssueSorter` order. Race-path mapping: a UNIQUE
    violation on `index_books_issue_key` → `DuplicateIssueFailure` (same idiom
    as `_isbnCollision`).
2.7 `periodicals/infrastructure/drift_periodical_repository.dart` +
    `periodical_mapper.dart`: every method in §2.3; `insert` mints the uid;
    `listAll` is one `LEFT JOIN … GROUP BY` returning summaries; ISSN race
    path → `DuplicateIssnFailure`.
2.8 DI: `core/di/src/periodical_providers.dart` (`periodicalRepository`,
    later the use cases/controllers) + part registration in `providers.dart`.
2.9 `cover_file_janitor.dart`: periodical covers are live references (D12) —
    test: a series cover survives a sweep with zero issues referencing it.
2.10 Tests: `drift_periodical_repository_test.dart` (CRUD, uid minting,
     ISSN uniqueness race → typed failure, `countIssues`, `findIssue` with and
     without volume, `issuesOf` order == `IssueSorter`), extended
     `drift_book_repository_test.dart` (kind predicate, series predicate +
     order, issue-key uniqueness → typed failure, plain-book edit clears
     nothing), `migration_test.dart` v1..v4 → v5.

### Phase 3 — application (`feat(periodicals): use cases + controllers`)

| File (`periodicals/application/`) | Responsibility | Tests (ProviderContainer overrides, fakes) |
|---|---|---|
| `add_periodical_use_case.dart` | `Periodical.validate` → ISSN pre-check (`findByIssn`, fail closed on read error) → insert | success; validation; duplicate ISSN; repo failure |
| `update_periodical_use_case.dart` | validate → ISSN pre-check excluding self → **one transaction**: update series, load `issuesOf`, `IssueProjection.apply` each, `BookRepository.update` each (D3) | rename re-titles every issue; a mid-way failure rolls back all |
| `delete_periodical_use_case.dart` | `countIssues > 0` ⇒ `PeriodicalHasIssuesFailure` (D8); else delete + release cover via janitor | fails closed; deletes when empty |
| `add_issue_use_case.dart` | load series (`NotFoundFailure` if missing/removed) → build `Book` with `IssueOf` → `IssueProjection.apply` → `Book.validate` → `findIssue` pre-check ⇒ `DuplicateIssueFailure` → `BookRepository.insert` | each path; bound range; date-only issue skips the pre-check |
| `update_issue_use_case.dart` | same as add but `update`, pre-check excludes self | |
| `periodicals_controller.dart` | `@riverpod class PeriodicalsController extends _$PeriodicalsController` (AsyncNotifier of `List<PeriodicalSummary>` + the `SubscriptionStatus` computed once per build with the injected clock) ; `refresh()` | |
| `issue_list_controller.dart` | `@riverpod class IssueListController` **family** by `periodicalUid`, reusing `LibraryWindow` + `BookRepository.page(LibraryQuery(periodicalUid: …))` and `IssueRun.gaps` | paging, gaps |
| `add_issue_controller.dart` / `periodical_form_controller.dart` | thin `AsyncNotifier<void>` wrappers like `AddBookController`; prefill via `IssueCadence` | |
| `scan_routing` extension (library) | `routeScannedCode`: EAN-13 `977…` → `Issn.fromEan13` → `findByIssn` → open add-issue prefilled, or offer "New magazine title" (D15) | 977 routes to issues; ISBN path unchanged |

DI additions in `periodical_providers.dart`; `periodicalById(int)` and
`periodicalByUid(String)` read providers watch `periodicalsControllerProvider`
**and** `libraryControllerProvider` as mutation signals (same pattern as
`bookById`). Every issue write calls `LibraryController.refresh()` (existing
contract: "every write path refreshes the list controller").

Clock: `SubscriptionStatus` takes `nowMillis`; the controller reads it from
the existing `clockProvider` (`core/di/src/platform_providers.dart`) and the
screens that show a badge watch `nowTickProvider` so an open screen rolls over
(the same N04 idiom the vault's overdue badges use). Tests override
`clockProvider`. No `DateTime.now()` in domain; none added in application.

### Phase 4 — presentation (`feat(periodicals): screens`)

4.0 **Make room first** (ratchet):
    - `book_detail_page.dart` (676, at cap): extract the remove/restore
      confirmation + the lend section into
      `library/presentation/widgets/book_detail_actions.dart`; lower its entry.
    - `add_book_page.dart` (638, at cap): no change needed — issues get their
      own page (below). Note in the PR that it was deliberately not touched.
    - `library_page.dart` (416): extract the "more" popup menu into
      `widgets/library_menu_button.dart` before adding the FAB sheet.
4.1 `library/presentation/widgets/library_controls_row.dart`: kind chips
    `All · Books only · Magazines ↗` (state on `LibraryFilterController`,
    like the language facet; "Magazines ↗" pushes `PeriodicalsPage`).
4.2 `library/presentation/widgets/add_sheet.dart`: FAB → bottom sheet
    *Add book / Add magazine issue / New magazine title*.
4.3 `library/presentation/widgets/book_row.dart`: `Issue` and `Bound volume`
    badges (`book.issue`), cover via `IssueCover.resolve` (series passed by
    the list through a small `periodicalCoversProvider` map — one query).
4.4 `periodicals/presentation/pages/periodicals_page.dart`: series list rows
    (cover, title, ISSN · frequency · N issues, `SubscriptionBadge`),
    empty state, FAB "New magazine title".
4.5 `pages/periodical_detail_page.dart`: hero, subscription card
    (`SubscriptionStatus` → colour + text), "+ Add issue", issues
    newest-first via `IssueListController`, gap rows (`IssueRun.gaps`), edit,
    overflow (remove/restore/delete; delete shows the typed refusal).
4.6 `pages/periodical_form_page.dart`: fields per mockup; "Track subscription"
    switch reveals start/end/source; ISSN field with inline validation;
    language picker reuses the existing language facet values; cover capture
    reuses `BookCoverController` flow through the `CoverFiles` port.
4.7 `pages/add_issue_page.dart`: series picker (or preselected when opened
    from a series), "Bound volume" switch (issue no. ↔ first/last), date
    picker, label, own cover (optional), copies, pages, location (prefilled
    from series default), notes, **generated-title preview**
    (`IssueTitle.compose`). Constructs `Book(` → **add to the gate allow-list**
    with reasoning (the use case re-validates).
4.8 `library/presentation/widgets/issue_detail_section.dart`: "Issue" and
    "From the series" blocks inserted into `BookDetailPage` when
    `book.isIssue` (one `if` + one widget; the page stays under its cap after
    4.0). Lend button unchanged.
4.9 Drawer entry "Magazines" (`core/widgets/app_drawer.dart`) → `PeriodicalsPage`.
4.10 Widget tests: `periodicals_page_test`, `periodical_detail_page_test`
     (badge states, gap row, refusal message), `periodical_form_page_test`
     (switch reveals fields, ISSN error), `add_issue_page_test` (bound toggle
     swaps fields, preview updates, save calls the use case with a projected
     `Book`), `book_row_test` (badges), `library_controls_row_test` (kind
     chips), golden for the series row + subscription badge (Linux goldens,
     see CHANGELOG 1.5.2 note).

### Phase 5 — interchange, merge, publish, backup (`feat(periodicals): formats`)

5.1 **Pitaka-JSON v4** (`import_export/infrastructure/pitaka_json_{exporter,importer}.dart`,
    `kPitakaSchemaVersion = 4`): top-level `periodicals[]`; six optional issue
    keys per book. Importer: `periodicals` parsed with `Periodical.validate`,
    capped by `ImportLimits.maxRows`; a book whose `periodicalUid` is not in
    the file **or** in the local library is imported as a plain book with a
    warning "N issues were detached: series not found" (fail closed on
    integrity, never on data). `ImportPayload` gains `periodicals` +
    `issuesDetached`. v3 files import unchanged (test fixture kept).
5.2 `import_library_use_case.dart`: inside the existing single transaction —
    periodicals first (upsert by uid, ISBN-style dedup by ISSN), then books.
5.3 **CSV export**: six additive columns (`Series`, `Volume`, `Issue`,
    `Last issue`, `Issue date`, `Issue label`). PDF export unchanged (composed
    title already carries the information; the renderer is at its cap).
5.4 **Merge** (`library/domain/merge/`): `library_merge_engine.dart` is at its
    cap (721) — extract `_FuzzyIndex` to `fuzzy_index.dart` first (pure
    refactor, property tests unchanged). Then: new `periodical_merge.dart`
    (uid → ISSN → exact title key; add-only, removal-as-conflict like books)
    and an issue identity index (`periodicalUid`, `volume ?? 0`, `issueNumber`)
    added as the second key after uid (D6). `merge_library_use_case.dart`
    applies periodicals before books in the same transaction and re-projects
    issues of merged series. `BackgroundMergePlanner` input/output stay plain
    Dart objects (isolate-safe). Merge page shows periodical counts.
5.5 **Publish** (`publish/domain/publish_export.dart`, `publish_redaction.dart`,
    `publish_library_use_case.dart`): `PublishBook` gains the six issue keys
    (public); `PublishExport` gains `periodicals[]` with `periodicalUid, title,
    titleTransliteration, issn, publisher, language, coverUrl, frequency,
    ageGroup` — subscription dates, notes, location, source*, addedBy are
    **stripped** (private, same rule as books). Periodical covers go through
    the same cover-id + allow-list pipeline (`publish_cover_ids.dart`,
    `CoverUrlAllowList`); issue entries publish `IssueCover.resolve`.
    `assets/publish/index.html`: "Magazines" facet, issues grouped under their
    title with the bound badge; unknown-key tolerance test unchanged
    (`schemaVersion` stays 1 — additive).
5.6 **Backup** (`backup/`): writer adds `periodicals.json`
    `{ "schemaVersion": 1, "periodicals": [...], "issues": [{ "bookUid", "periodicalUid", "volume", "issueNumber", "issueNumberEnd", "issueDate", "issueLabel" }] }`
    and sets `hasPeriodicals` (`BackupManifest` default **false**).
    `backup_extras_reader.dart` reads it (4 MiB cap, every row re-validated,
    invalid dropped + counted); `restore_backup.dart` joins issues to the
    restored books by `bookUid` *before* the catalogue write (phase 5 of the
    restore, still no device writes), detaches unmatched links and reports
    `periodicalsRestored / issuesLinked / issuesDetached` in `RestoreSummary`.
    Kotlin-era archives: flag absent ⇒ nothing to do. `restore_backup.dart`
    is at its cap (553): the join lives in a new
    `backup/infrastructure/restore_periodicals.dart`.
5.7 Tests: JSON v4 round-trip + v3 fixture + detached-issue warning +
    oversized `periodicals` truncation; CSV columns; merge: periodical uid/ISSN
    identity, issue second-key identity, re-projection after apply, isolate
    round-trip; publish: redaction of private periodical fields, cover
    fallback, viewer tolerance; backup: writer emits entry + flag, reader
    drops invalid rows and counts, restore links/detaches, archive without the
    flag restores exactly as before (fixture).

### Phase 6 — release hygiene

6.1 `fastlane/metadata/android/en-US/changelogs/<next versionCode>.txt` blurb.
6.2 Guides: there is no catalogue guide today (`GuideId` = publish, map,
    backup, vault, network). Add a sixth guide `GuideId.magazines` in
    `guides/domain/guide_catalog.dart` (series → issues → lending → backup),
    respecting the pinned invariants (order, 2–7 steps, ≤ 3 "Good to know",
    1:1 destination → `PeriodicalsPage`); `guide_catalog_test.dart`
    expectations (exact item counts) are updated deliberately.
6.3 `integration_test/` smoke: add series → add issue → lend → backup → restore.

---

## 4. Order of work and PR boundaries

```
PR 1  docs:  ADR 0013, ADR 0014, ARCHITECTURE/AGENTS/CHANGELOG   (phase 0)
PR 2  feat:  domain + LibraryQuery                               (phase 1)
PR 3  feat:  schema v5 + repositories + DI + janitor             (phase 2)   ← needs PR 2
PR 4  feat:  use cases + controllers + scan routing              (phase 3)   ← needs PR 3
PR 5  feat:  screens                                             (phase 4)   ← needs PR 4
PR 6  feat:  JSON v4 + CSV + merge                               (phase 5.1–5.4)
PR 7  feat:  publish + viewer                                    (phase 5.5)
PR 8  feat:  backup/restore                                      (phase 5.6)
PR 9  chore: release hygiene                                     (phase 6)
```

PRs 6–8 are independent of each other and of PR 5 (they depend on PR 4).
Each PR description states: what changed, why, security impact (all: "no
secrets; hostile-input bounds unchanged or tightened"), and coverage.

---

## 5. Gate allow-lists that change (deliberate, reviewed)

| Gate | Entry | Reason |
|------|-------|--------|
| `book_validation_gate_test` | `lib/features/periodicals/presentation/pages/add_issue_page.dart` | the form builds the `Book`; `AddIssueUseCase` re-validates |
| `book_validation_gate_test` (scanned set) | `periodical_mapper.dart`, `pitaka_json_importer.dart`, `restore_periodicals.dart`, `add_periodical_use_case.dart`, `update_periodical_use_case.dart` | `Periodical(` construction sites that pass through `Periodical.validate` |
| `layer_boundaries_test` ratchet | lower `drift_book_repository.dart`, `book_detail_page.dart`, `restore_backup.dart`, `library_merge_engine.dart` to their post-split sizes | entries may shrink; no new entry is added |
| `migration_test._rawSqlObjects` | the four new indexes | raw-SQL invariants must be listed to be proven after every upgrade path |

---

## 6. CI gates (every PR)

- `dart run build_runner build --delete-conflicting-outputs` — no diff
- `dart analyze` — zero issues; `dart format --set-exit-if-changed`
- `flutter test --coverage` — domain/application ≥ 90 % on touched code
- architecture tests: domain purity, layer boundaries + ratchet, validation
  gates, migration matrix
- PR 3 only: drift snapshot + generated helpers committed
- No new plugin ⇒ F-Droid purity unaffected (document in PR 5 description)

---

## 7. Risks and how the plan handles them

| Risk | Mitigation |
|------|------------|
| Re-projection on series rename touches N issue rows | one transaction (`runInTransaction`); `issuesOf` bounded; a failure rolls back the rename too |
| Startup cover sweep deletes series covers | janitor counts periodical covers (2.9) + test |
| Old build receives a v4 JSON file | refuses with the existing "update the app" message (D9), no partial import |
| Old build restores a new `.pitabak` | ignores `periodicals.json` (flag unknown ⇒ false) — issues restore as plain books with composed titles; documented honest limit in ARCHITECTURE §5.5 |
| Merge conflicts storm after a rename on one device | periodicals merge first; issues re-projected after apply (5.4) |
| Ratchet violations | every capped file is split *before* it is extended (2.0, 4.0, 5.4, 5.6) |
| Partial-index support | SQLite ≥ 3.9 (Android 7+/`sqlite3_flutter_libs` bundles a current SQLite); migration test proves the index exists after every upgrade path |

---

## 8. Open questions (answer before PR 4)

1. Subscription "expiring soon" window: 30 days (default in this plan) — confirm.
2. Should a bound volume be allowed to span **two volumes** (e.g. Nos 7–12 of
   vol 3 + Nos 1–6 of vol 4)? Plan: **no** in v1 (one `volume` per row);
   record two rows. Confirm.
3. Per-issue age-group override: plan says **no** (projected from series). Confirm.
4. Drawer entry "Magazines" in addition to the Library chip — keep both?
