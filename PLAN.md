# PLAN.md — Session 33 — One spelling per language (dropdown + canonicalise + migrate)

User request: typing `English` and `english` records two languages; the
catalogue filter then shows two chips. Fix it for new AND existing users.
Agreed direction (this session): **A + dropdown**. Plain dropdown of the
library's own languages + "Other…" (free text, becomes a dropdown entry once
saved). Google Books ISO codes (`en`, `hi`, …) are converted to names in-app.
A book whose language is not in the list shows as "Other" with the value
editable. An empty library starts with `English` + `Other…`.

## Understanding (verified from source this session)

- Root cause: free-text field, only `trim()` applied
  (`lib/features/library/presentation/pages/add_book_page.dart:232,375`).
  Nothing downstream is case-aware:
  - `drift_book_repository.dart:198-211` `SELECT DISTINCT language` is
    case-sensitive → two chips.
  - `drift_book_repository.dart:97-104,424` filter is deliberate EXACT match
    on the stored string (D1-a, because SQLite `lower()` is ASCII-only and
    broke `Ελληνικά`). Locked by `test/features/library/add_edit_book_test.dart:113-127`.
    **Kept as-is** — once data is canonical, exact match is correct.
  - `book_sorter.dart:51-53` / `drift_book_repository.dart:180-183` sort is
    binary code-unit → `English < Hindi < english`. Unchanged; data fix suffices.
  - `library_merge_engine.dart:574` `a.language == b.language` → false
    conflict between `English` and `english`.
  - `google_books_lookup_service.dart:116` stores the raw BCP-47/ISO code
    (`en`) → a third spelling for lookup-filled books.
- Write chokepoint: ALL ingress ends in `DriftBookRepository.insert/update/
  insertAll/replaceAll` (`:229,:242,:302,:323`). Callers: add/update use
  cases, `import_library_use_case.dart:209,242`,
  `merge_library_use_case.dart:356,458,466,523`, legacy restore (via
  import). `Book.validate` (`book.dart:227`) is the static field gate but has
  no access to existing languages, so it cannot resolve spellings alone.
- `AppDatabase` (`lib/core/database/app_database.dart:26`) is at
  `schemaVersion 1`, `onCreate` only; `core/database` imports nothing from
  `features/` today. `Books.language` is `text().nullable()`
  (`tables.dart:62`). Wishlist has no language column.
- Form dropdown precedent: `DropdownButtonFormField` with a `Not set` null
  item (`add_book_page.dart:390-416`). Lookup fills the field via
  `fillIfEmpty(_language, m.language)` (`:193`).
- Facet list: `libraryLanguagesProvider` (`lib/core/di/providers.dart:235`)
  re-runs on every `libraryControllerProvider` mutation → a newly saved
  "Other" language appears in the dropdown immediately (no restart).
- Cross-feature domain import precedent: `wishlist_use_cases.dart:218` uses
  `Book.validate` → lookup may import a library-domain value object.
- No `LanguageName` value object exists; `domain/value_objects/` has only
  `library_id.dart`, `library_qr_payload.dart`.
- Drift version per in-repo comment: 2.28.2 (`drift_book_repository.dart:107`).
  `MigrationStrategy.onUpgrade(m, from, to)` — from memory; verify in pub
  cache before Step 4.

## Privacy & threat notes

- No new data collected; no network; language is not PII. Local-only.
- Migration REWRITES rows (`english` → `English`). Irreversible loss of the
  case variant only; content preserved. Runs once inside one transaction.
- Hostile input: "Other…" text still passes `Book.validate` length cap
  (`CatalogueRules.maxFieldChars`). Canonicalisation only ever returns a
  string that was already stored or the trimmed input — it cannot mint new
  content. ISO table is `const`. Dropdown items come from the local DB only.
- Migration false-positive risk: a genuinely 2-letter user-typed language
  name that collides with an ISO code (e.g. `Ga`, `Wu`) would be renamed.
  Accepted — vanishingly rare in this app's audience; noted here.

## Proposed approach

Plain English: a book's language gets snapped to the spelling your library
already uses (ignoring case/whitespace) or converted from a Google Books
code; the form offers a dropdown of those spellings plus "Other…". A
one-time, one-transaction migration collapses existing duplicate spellings.

1. **`LanguageName` (domain value object)** —
   `lib/features/library/domain/value_objects/language_name.dart`. Pure Dart.
   - `LanguageName.key(String) → String`: trim, collapse whitespace, Dart
     `toLowerCase()` (Unicode-aware; SQLite's is ASCII-only — this is WHY it
     lives in Dart). Unit-tested on Latin + Greek + Devanagari.
   - `LanguageName.canonicalise(String? raw, Iterable<String> existing) →
     String?`: blank → null; ISO code → name (§3); else the FIRST `existing`
     whose key matches; else `trimmed`. Deterministic.
   - `LanguageName.defaults = ['English']` — seed shown when the library is empty.
   - Contains `_isoNames`: `const` map, ISO 639-1 two-letter code → English
     name. Full 184-code list adapted from the public ISO 639-1 table
     (credit: Wikipedia "List of ISO 639-1 codes"; also cross-checked
     against Dart `intl` locale names). Only the 2-letter primary subtag
     is matched (`en-GB` → `en`); anything ≥3 chars is treated as a name.
2. **Repository-level enforcement** — `DriftBookRepository.insert/update/
   insertAll/replaceAll` canonicalise `language` against the current
   distinct set inside the same transaction, so EVERY ingress (form,
   import, merge, restore) obeys one rule. `insertAll`/`replaceAll`
   canonicalise within the batch too (first spelling wins), so an imported
   file with mixed case yields one spelling.
   Why the repo and not `Book.validate`: only the repo can see what is
   already stored. `Book.validate` stays the static field gate.
3. **ISO → name at the lookup boundary** —
   `google_books_lookup_service.dart:116` maps via `LanguageName`, so
   `BookMetadata.language` is already `English`; the form never sees `en`.
   Idempotent: `English` → `English`.
4. **Schema v2 migration** — `AppDatabase.schemaVersion => 2`,
   `onUpgrade(from < 2)`: read distinct languages, group by
   `LanguageName.key` in Dart, resolve ISO codes, pick winner per group =
   most books → tie: not-an-ISO-code → NOCASE first; `UPDATE books SET
   language = ? WHERE language = ?` for every loser. Single transaction.
   Idempotent (re-run finds no groups). `core/database` gains one import
   from `features/library/domain` (pure Dart; no layering violation —
   `core` is the cross-cutting root and the VO has no Flutter/Riverpod).
   Existing tests build DBs fresh via `onCreate`; a dedicated migration test
   opens a v1 fixture, inserts variants, upgrades, asserts one spelling.
5. **Dropdown UI** — replace `_field(_language, 'Language')` with
   `DropdownButtonFormField<String?>`: `Not set` (null), each item from
   `libraryLanguagesProvider` (seeded with `LanguageName.defaults` when
   empty), then `Other…` sentinel. Choosing `Other…` reveals a `TextField`
   (the existing `_language` controller) for free text. Edit mode: if the
   book's language is not in the list (old backup, or the list hasn't
   refreshed yet), pre-select `Other…` and fill the box with the value —
   editable, as requested. Lookup `fillIfEmpty` sets the dropdown when the
   mapped name is in the list, else `Other…` + text.
   Presentation-only; the repo still canonicalises whatever arrives.

Borrowed patterns: dropdown mirrors `add_book_page.dart:390-416`
(`DropdownButtonFormField` + null "Not set" item); repo-side normalisation
mirrors the existing `isbn` normalisation in `library_merge_engine.dart:669`.

## Decision points

- **D1** Repo canonicalises inside the transaction vs a use-case wrapper:
  repo (chosen) — merge/import/restore call the repo directly, a wrapper
  would be bypassable.
- **D2** Winner rule in migration: most-used spelling; tie → non-code →
  NOCASE first. Confirm or override.
- **D3** ISO codes: 2-letter primary subtag only (`en`, `en-GB`→`en`).
  3-letter (639-2) codes NOT mapped (Google Books emits 639-1). Confirm.
- **D4** `Other…` text stays visible after save? No — the form closes on
  save; next open shows the new language as a dropdown item.
- **D5** Search FTS path (`drift_book_repository.dart:400-440`) untouched —
  language is not an FTS column.

## Steps

- [x] 1 `LanguageName` VO + ISO table + tests (`test/features/library/language_name_test.dart`).
- [x] 2 Repo canonicalisation in `insert/update/insertAll/replaceAll` + tests in `add_edit_book_test.dart` (mixed-case insert → one `distinctLanguages` entry; batch with `english`,`English`,`en` → one spelling; non-Latin round-trip).
- [x] 3 Lookup: map ISO code → name; unit test `en`→`English`, `hi`→`Hindi`, `xx`→`xx`, `English`→`English`.
- [x] 4 Verify drift `onUpgrade` signature in pub cache; `schemaVersion 2` + migration + test (v1 fixture → upgrade → one spelling, counts preserved, idempotent re-run).
- [x] 5 Dropdown UI in `add_book_page.dart` + widget tests (`add_book_page_test.dart`: empty library shows `English`+`Other…`; pick existing; `Other…` reveals text; edit with unknown language → `Other…` prefilled; lookup `en` → `English` selected).
- [x] 6 Merge engine: compare language via `LanguageName.key` (user decision (b), this session) so `English` vs `english` across two devices is not a conflict; test added.
- [x] 7 `dart run build_runner build --delete-conflicting-outputs`, `dart analyze`, `dart format`, `flutter test`. Update README test count if it lists one.

## Out-of-scope observations

- `distinctLanguages()` orders `COLLATE NOCASE` while sort-by-language is
  BINARY — chips and list can disagree in order for mixed-case non-ASCII.
  Harmless after this change for ASCII; noted, not touched.
- Wishlist has no language field; Goodreads CSV importer does not set one.
- `README.md:187` says 1651 tests; suite is 1733 after this session (and
  was already stale before it). Update in the `docs:` commit, not here.
- Prior PLAN.md (Session 32, share card) reported "implemented; not
  committed"; `git log` shows commit `66fe5df` landed it. Superseded.

## Result

**All 7 steps implemented, verified and committed: `e6bca1a`
(`feat(library): one spelling per language — dropdown, canonicalise on
write, schema v2 clean-up`). Not pushed.**

Plain English: the Language field is now a dropdown of your library's own
languages + "Other…"; whatever you type under "Other…" is snapped to an
existing spelling if there is one, and otherwise becomes a new dropdown
entry immediately after save. Google Books codes (`en`, `hi`) arrive as
names. On first launch after the update a one-time clean-up collapses
`English`/`english`/`en` into the spelling most of your books already use.

Verification:
- `flutter test`: **1733 passed** (43 new: 1 merge-engine test, 14 `language_name_test`, 9
  `language_merge_plan_test`, 8 repo tests in `add_edit_book_test`, 3
  migration tests in `app_database_test`, 7 widget tests in
  `add_book_page_test`, 1 lookup test). The pre-existing D1-a exact-match
  test still passes unchanged.
- `dart analyze lib test`: no issues. `dart format`: clean.
- `build_runner`: no `.g.dart` diffs. It re-resolved `pubspec.lock`
  (matcher/test_api, transitive); reverted with `git checkout -- pubspec.lock`.

Files:
- NEW `lib/features/library/domain/value_objects/language_name.dart` (VO +
  184-entry ISO 639-1 table, credit: Wikipedia list of ISO 639-1 codes).
- NEW `lib/features/library/domain/value_objects/language_merge_plan.dart`
  (pure migration planner; `LanguageRename` is a record, per the N14
  no-`@immutable`-in-domain precedent).
- `drift_book_repository.dart`: `_LanguageResolver`; `insert`/`update`/
  `insertAll` now run in a transaction (read spellings + write atomically);
  `replaceAll` resolves within the file.
- `app_database.dart`: `schemaVersion 2`, `onUpgrade` →
  `_collapseLanguageSpellings()`.
- `google_books_lookup_service.dart`: ISO code → name at the boundary.
- `add_book_page.dart`: `_languageField()` dropdown; `_field` gained an
  optional `onChanged`.

Deviations from plan (recorded):
- D2 amended: a bare ISO code ALWAYS loses to a real name in the migration,
  even with more books — the app never stores codes, so a lookup leftover
  must not out-vote a name the user typed. Tested.
- Step 6 changed from "leave `==`" to a `LanguageName.key` compare after
  the assumption below broke; user chose (b).

### Step 6 finding (resolved: option b)
Assumption "merge conflicts vanish once data is canonical" was only true
when BOTH libraries already shared a spelling; two internally-consistent
devices could still differ (`English` vs `english`) and
`library_merge_engine.dart` compared with `==`. Now `_languagesEqual`
compares `LanguageName.key`s (blank == null == "none"). Test:
`library_merge_engine_test.dart` "treats language spellings that differ
only by case/spacing as the same language". Remaining raw compares
checked: `library_query.dart:63` compares two filter INTENTS (exact chip
value) — correct as-is; `publish_export.dart:108` is a null check.

