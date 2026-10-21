# ADR 0013: Catalogue item kinds — one base row, per-kind detail tables

- **Status:** Accepted
- **Date:** 2026-10-21 (plan `docs/plans/magazines.md` rev 5; decisions
  resolved with the maintainer the same day)

## Context

Pitak is a general library app, but its catalogue knows only books: the
`books` table (25 Room-shaped columns), one `CatalogueItem` entity (named
`Book` until this work), one paged list, one FTS index, one publish payload,
one backup shape. Users also keep **magazines** (issues of a periodical,
lent individually) and **other things** — a DVD, a board game, a map.

Two promises (docs/ARCHITECTURE.md §1.1) constrain the design:

- **P1 — zero data loss.** Every persisted and wire format is read by older
  builds and other phones; a change must be versioned, migrated and tested.
- **P5 — one blessed way.** A beginner maintains this. Two list paths, two
  identities or two search indexes would double every future change.

The most expensive thing in the app to change is the **vault**: the
SQLCipher store in Rust whose `loans.book_id` (`rust/src/vault.rs`) points at
a library row by its per-device id, with a Kotlin-compatible layout. A second
lendable table would mean a second loan shape, a second migration matrix and
a second FRB surface.

The alternative designs considered:

1. **A table per kind** (`books`, `magazine_issues`, `other_items`), each a
   full copy of the shared columns. Rejected: N list/search/publish/backup
   paths and a vault that must know N id spaces.
2. **One wide table** that gains columns for every kind. Rejected: the base
   row widens forever; `kind`-specific uniqueness rules (an issue key) cannot
   be expressed; a 25-column migration for every new kind.
3. **Generic "collections"** grouping any items. Rejected (for now): a
   subscription and a DVD box set are different things; a periodical needs
   an ISSN, a frequency and a subscription window, none of which a generic
   collection has. Trigger for revisiting: a kind that needs grouping (a
   series, a box set) — decide then with an ADR.

## Decision

**One base row per physical thing, of any kind; kind-specific data in a
per-kind detail table; the base row is the lendable unit.**

Foundation (F1–F8 in the plan):

- **F1** The existing `books` table / `CatalogueItem` entity *is* the base
  row. It carries what every kind shares (title, transliteration, cover,
  language, age group, copies, location, notes, source, removed, uid,
  added…). Book-only columns (author, ISBN, publisher, year, genre, pages)
  are already nullable; a non-book row leaves them null.
- **F2** `loans.book_id` in the vault is the base row id for every present
  and future kind. **Standing rule: a new kind never touches the vault.**
- **F3** A `kind` discriminator on the base row: `ItemKind` enum —
  `book('book')`, `magazineIssue('magazine-issue')`, `other('other')` —
  persisted as the stable token (`'book'` default), parsed tolerantly like
  `AgeGroup.fromToken`. Kinds are **defined by the app**, never created by
  users at runtime.
- **F4** Kind-specific data lives in a per-kind detail table, 1:1 with the
  base row (`<kind>.item_id → books.id ON DELETE CASCADE`). The base table
  never widens for a new kind (class-table inheritance).
- **F5** In the domain, `CatalogueItem.details: ItemDetails?` is a **sealed
  union** — `IssueOf` (with fields) and `OtherItemOf` (a field-less marker);
  `null` ⇒ book. `kind` is *derived* from `details`, so the two can never
  disagree, and `switch (item.details)` is exhaustive by construction.
- **F6** `kind` travels in every wire format from day one (ADR 0014). Absent
  ⇒ `book`. An **unknown kind token is skipped and reported** — never
  mis-catalogued as a book.
- **F7** The rename `Book` → `CatalogueItem` (and every name meaning "an
  item of any kind") was done first, as four zero-behaviour commits (plan
  sessions S1–S4). **Persisted and wire names do not change**: table
  `books`, column `book_uid`, JSON keys `books` / `bookUid`, vault
  `book_id`, files `books.db` / `books.json`. Names that genuinely mean
  *book* keep their names (`AddBookPage`, `DuplicateIsbnFailure`, ISBN scan,
  `WishlistBook`, the Drift data class `BookRow`).
- **F8** Periodicals stay a specific concept (ISSN, frequency,
  subscription). No generic collections.

Magazines and issues (D1–D11):

- **D1** An issue is a base row with `details = IssueOf(periodicalUid,
  volume?, issueNumber?, issueDate?, boundUntil?, label?)` and a
  `magazine_issues` detail row.
- **D2** A `Periodical` entity + `periodicals` table (title, ISSN, publisher,
  language, cover, frequency, optional subscription window, private fields).
  Identity `periodicalUid` (UUID), minted like `itemUid`.
- **D3** Derived fields are **projected, not read through**: the base row's
  title, transliteration, publisher, language, year and age group are
  written from (periodical, issue) by `IssueProjection`; editing the series
  re-projects every issue in one transaction. No per-issue age-group
  override. Every existing consumer keeps reading plain base columns.
- **D4** A **bound volume** is one issue row with a date range (`issueDate`
  = first issue, `boundUntil` = last). One physical item, one `copyCount`,
  one loan. Volume/issue number optional; a range may span volume numbers.
- **D5** Subscription status is **derived**, never stored:
  `SubscriptionStatus.of(periodical, now)` ∈ {untracked, active,
  expiringSoon (≤ 30 days), lapsed}. No notifications.
- **D6** Issue identity for dedup/merge: `itemUid` → numbered issue
  (`periodicalUid`, `volume ?? 0`, `issueNumber`) / bound volume
  (`periodicalUid`, `issueDate`, `boundUntil`) → fuzzy title. A same-uid row
  whose `kind` differs is a **conflict**.
- **D7** ISSN lives on the periodical only (canonical `NNNN-NNNC`, mod-11
  check digit, unique among non-null). Never in `books.isbn`.
- **D8** Hard delete of a periodical **fails closed** while issues reference
  it (`PeriodicalHasIssuesFailure`); soft-remove leaves issues untouched.
  Changing a row's `kind` after creation is not supported.
- **D9** No "missing issue" gap rows (date-range bound volumes make number
  gaps uncomputable).
- **D10** FTS gains `notes`; the detail table's `issue_label` is not indexed.
- **D11** A magazine barcode (EAN-13 prefix `977`) routes to the add-issue
  flow instead of being stored as a bogus ISBN.

Others (O1–O4): `ItemKind.other` has **no fields and no detail table**; what
the item *is* goes in the existing `notes` field (labelled "Description" on
the Others form), which becomes searchable (D10). `notes` stays private, so
an Other item publishes title, cover, language and age group only (trigger
for a public description: a library asks for one on its site). The generic
add/update use cases validate any `details`; merge identity is
`itemUid` → fuzzy title.

## Consequences

- **Easier:** every list, facet, export, viewer and backup is kind-aware
  through one column; adding a kind is a recipe, not a redesign (below).
  The vault, the paged list, FTS, merge identity and publish stay single.
- **Harder / new rules:**
  - Schema v5 (`books.kind`, `magazine_issues`, `periodicals`, FTS rebuild
    with `notes`) is a migration with a data-matrix row and a 5 000-row FTS
    rebuild timing test; `PRAGMA foreign_keys = ON` is turned on for the
    cascade (verified: no existing table declares a FK).
  - Every `CatalogueItem(` / `Periodical(` construction site is gated
    (`test/architecture/catalogue_item_validation_gate_test.dart`).
  - A row written by a newer build with an unknown `kind` reads as a book
    (logged once) and is **refused on write-back** — the app never
    silently rewrites a kind it does not understand.
  - The startup cover sweep must count periodical covers as live
    references (the M11 bug class) — enforced by a janitor test.
- **Forbidden:** per-kind tables for shared columns; a second lendable unit;
  user-defined kinds; storing a subscription status; an ISSN on a base row.

### Recipe: adding a future kind

1. `ItemKind.<kind>('<token>')` + `final class <Kind>Of extends ItemDetails`
   with `validate()` (a field-less marker if it has no fields, like
   `OtherItemOf`). The compiler now flags every non-exhaustive `switch`.
2. If it has fields: detail table `<kind>_items(item_id PK → books.id
   CASCADE, …)`; schema bump; snapshot + generated helpers + matrix row.
3. `drift_item_details.dart`: read/write/delete branch; mapper branch.
   Nothing else in the repository changes.
4. Wire formats: the `kind` token is already carried everywhere; add a
   nested `"<kind>": {…}` object in Pitaka-JSON and `books.json` and a
   `has<Kind>` `.pitabak` entry only if the kind has fields (ADR 0014).
5. Add-sheet entry, a form page (gate allow-list entry), a block in
   `item_details_section.dart`; the kind chip appears automatically.
6. Grouping needed? That is the F8 trigger — decide with an ADR.
7. **The vault is not touched** (F2).

### Resolved decisions log (maintainer answers, 2026-10-21)

| Q | Answer | Effect |
|---|--------|--------|
| 1 | "Expiring soon" window = 30 days | D5 |
| 2 | Bound volume = "issues from date X to date Y"; the user may instead catalogue it as its own item | D4, D9, two partial unique keys (D6) |
| 3 | No per-issue age-group override | D3 |
| 4 | Fixed kind chips (Books · Magazines · Others); tap filters, tap again shows all | UI decisions U1/U2 in the plan |
| 5 | Rename now | F7 (plan sessions S1–S4) |
| 6 | Kinds are app-defined; add a built-in "Others" kind | F3, O1–O4 |
| 7 | Others have no type label — the description/notes field says what the item is, and notes become searchable | O1–O2, D10, explicit `item_kinds.json` (ADR 0014) |
| 8 | Plan written as discrete, independently runnable sessions with a handoff file | `docs/plans/magazines.md` Part B/C, `magazines-progress.md` |
