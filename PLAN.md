# PLAN.md — Session 17: M15 (import field-level validation), part 1 of 2

Roadmap: `fix-schedule.md` §3 row M15. Review source: `astra-review.md` M15.

## Understanding

The catalogue entities `Book` (`lib/features/library/domain/entities/book.dart:113`)
and `WishlistBook` (`lib/features/wishlist/domain/entities/wishlist_book.dart:33`)
accept any value: there is no validated construction anywhere. The only rule
enforced today is "title is not blank", and only in the four form use cases
(`add_book_use_case.dart:27`, `update_book_use_case.dart:27`,
`wishlist_use_cases.dart:26, :49`). Every other ingress **coerces** instead
of validating, and none of them pass through those use cases:

| Ingress | File | What happens today |
|---|---|---|
| Pitaka JSON import / merge / bundle catalogue | `import_export/infrastructure/pitaka_json_importer.dart:135–190` | `_asInt` turns any integer into `addedDate` / `copyCount` / `removedAt` / `priority` / `purchasedDate`; `title` falls back to `''`; `_asDouble` accepts `1e400` → `Infinity` and the strings `NaN`/`Infinity`; `addedBy` is the ONE text field that skips `limits.clampField` (`:168`); any `https://` `coverUrl` passes through (`:136–141`); wishlist local cover refs are kept even in plain-JSON mode (`:182`, S6 note) |
| Goodreads CSV | `import_export/domain/goodreads_csv_importer.dart:72–121` | title checked per row; nothing else can go wrong (year/pages are display-only ints) — but it builds entities by hand, so a future column would bypass the rules |
| Import apply | `import_export/application/import_library_use_case.dart:170–260` | writes `_bookRepo.insert/update` and `_wishlistRepo.insert/upsert` directly — never the add/update use cases |
| Backup restore | `backup/infrastructure/legacy_db_reader.dart:55–98` → `restore_backup.dart:400–410` | reads `books.db`/`wishlist.db` from the (untrusted) archive and batch-inserts into Drift, no rules at all — **session 2** |
| Wishlist → library move | `wishlist/application/wishlist_use_cases.dart:230` | copies `w.coverUrl` unsanitised into the library book (S15 note 3) — **session 2** |
| Forms | `add_book_page.dart:212–247`, `add_wishlist_page.dart:175–192` | `qty < 1 ? 1 : qty` silently coerces; price `double.tryParse` accepts `-5`, `NaN`, `Infinity`; no field length cap |

Consequences, each verified this session (not from memory):

- `DateTime.fromMillisecondsSinceEpoch(8640000000000001)` throws `RangeError`
  (probe run with the pinned SDK). Call sites that would throw on such a row:
  `book_detail_page.dart:361`, `add_book_page.dart:285` (`_pickDate`),
  `export_library_use_case.dart:251, :327` (CSV/PDF export). `showDatePicker`
  additionally asserts `initialDate` within `[1900, now]`
  (`flutter/.../date_picker.dart:235–239`).
- A wishlist `priority` outside {0,1,2} hits the `DropdownButtonFormField`
  assertion "exactly one item with [DropdownButton]'s value"
  (`flutter/.../dropdown.dart:1035`) from `add_wishlist_page.dart:295`.
- `copyCount ≤ 0`: `lending_policy.dart:25` and `availability.dart:32` clamp
  defensively, but `publish_library_use_case.dart:338` (`active >= copyCount`)
  publishes a zero-copy book as "out" with no loans.
- `jsonEncode({'p': double.infinity})` throws `JsonUnsupportedObjectError`
  (probe) → an imported non-finite `priceEstimate` makes the next **export**
  crash (`pitaka_json_exporter.dart:84`).
- `ImportLimits.defaults.maxFieldChars = 8000` (`import_limits.dart:48`) is
  the advertised field cap; `addedBy` evades it.

Root cause: validation was never centralised — the rules live implicitly in
UI widgets (dropdown items, `qty < 1` clamp) and one use-case check, so each
parser re-invented (or skipped) them. This is the "coercion mistaken for
validation" the review names.

## Privacy & threat notes

- **Threat:** a crafted `.json`/`.csv`/`.pitabak`/backup file (shared by
  another library, downloaded, or tampered in transit) plants rows that crash
  the detail page, the edit form, the wishlist editor, or the exporter —
  a data-driven denial of service on the user's own catalogue, persisting
  across restarts. Also seeds arbitrary `https://` cover URLs into the DB
  (M09's fetch path re-checks the allow-list, so they are inert for network,
  but they survive re-export and are how S13's hostile rows were seeded).
- **Who can exploit:** anyone who can hand the user a file. No device access
  needed. Restore path (session 2) has the same shape.
- **What stops it after this fix:** one pure domain rule set applied at every
  ingress before persistence; invalid rows are rejected and reported, never
  coerced. Bundles stay all-or-nothing (M04). Fail closed everywhere.
- No new data collected, no network, no permissions, no logging. Error
  strings shown to the user contain a truncated title and a field name —
  never raw exception text.

## Investigation notes

- Existing validated-construction precedents in this repo: `EventPoster.create`
  (`events/domain/entities/event_poster.dart:29–38`, nullable static factory),
  `LibraryId.normalizeOrNull` (`library/domain/value_objects/library_id.dart`),
  and the Rust FFI guards `validate_text`/`validate_date`
  (`rust/src/api.rs:171–186`: `MAX_DATE_MILLIS = 8_640_000_000_000_000`,
  `value <= 0 || value > MAX` → reject). Dart's `DateTime` accepts exactly the
  same bound (probe: `8640000000000000` ok, `+1` throws).
- `Failure` hierarchy (`core/error/failure.dart`): `ValidationFailure(message)`
  exists; the import page already lists `parseErrors` (`import_page.dart:202`);
  merge turns the first parse error into a `ValidationFailure`
  (`merge_library_use_case.dart:156`); bundle refuses any parse error
  (`import_bundle.dart:23`).
- `ImportLimits` (`import_export/domain/import_limits.dart`) is already the
  single source of caps; `clampField` truncates. The review asks to REJECT
  rather than silently coerce — but truncating an 8 001-char note to 8 000 is
  a loss the user probably wants (M4 decision: "keep what's valid"). Decision
  point D2 below.
- `CoverUrlAllowList` lives in `publish/domain/` and is already imported by
  `library/application`, `wishlist/presentation`, `core/widgets` — a
  cross-feature domain import is allowed by the purity gate
  (`test/architecture/domain_purity_test.dart:70–73`).
- Domain purity gate forbids `dart:convert`, so the rule set must be pure
  Dart with no JSON knowledge — it validates already-typed fields.
- The exporter writes `coverUrl` verbatim (`pitaka_json_exporter.dart:60`) so
  local `covers/<uuid>.jpg` refs appear in plain JSON; the importer drops them
  for books (`:139`) but not for wishlist (`:182`). `ImportBundle.validate`
  (`import_bundle.dart:26–30`) checks wishlist refs too, so bundles are fine;
  plain JSON wishlist rows can carry a dangling local ref → placeholder (no
  traversal: `CoverPaths.leafOf` guards every file access).
- `LegacyDbReader` (`legacy_db_reader.dart:110`) `_int` does `v.toInt()` on
  any double → throws on NaN/Infinity from a REAL column (SQLite can store
  them). Same class of bug; belongs to session 2 with the restore ingress.
- 29 `implements BookRepository` fakes exist (S16 note) — adding a repository
  method is out of the question; the rule set is a pure function called by the
  ingress code, not a repository concern.
- Existing tests that pin current coercion behaviour and will need updating:
  `pitaka_json_importer_test.dart:12–64` expects
  `coverUrl == 'https://example.com/c.jpg'` to pass through (not allow-listed
  → must now be dropped); `:100` "out-of-range numbers never throw" stays
  valid (still must not throw — now reported).

## Proposed approach (OSS references)

Borrowed shape: **"Parse, don't validate"** (Alexis King) as practised by
`freezed`/`dartz`-style Dart codebases and by this repo's own
`EventPoster.create` — a pure domain function that either returns a
normalised entity or a typed list of field errors; the entity's plain
constructor stays for already-trusted values (DB mapper, `copyWith`). The
per-field rule table follows the Rust FFI guards in `rust/src/api.rs` so the
two trusted cores agree on what a valid date/text is.

### Session 1 (this session) — the rule set + text ingresses

1. **`lib/features/library/domain/catalogue_rules.dart`** (pure): shared
   constants + primitive checks used by both entities —
   `maxDateMillis = 8640000000000000`, `maxFieldChars` (taken from a new
   const so `ImportLimits.defaults.maxFieldChars` references it — single
   source), `isValidDateMillis(int)` (`0 < v ≤ max`), `isValidOptionalDate`,
   `isValidYear` (0 < y ≤ 9999 — publishedYear is displayed as text only, but
   a 20-digit year is still junk), `isValidCount` (page/copy ≥ 1),
   `isValidPrice` (finite, ≥ 0). Plain-English doc on each.
2. **`Book.validated({...})` / `WishlistBook.validated({...})`** static
   factories on the existing entities returning
   `Either<List<FieldError>, Book>` where `FieldError(field, problem)` is a
   small pure value (`catalogue_rules.dart`). Rules: title non-blank after
   trim; every text field ≤ cap (D2 decides reject vs truncate); `addedDate`
   0 (unset) or valid millis; `removedAt`/`purchasedDate` null or valid;
   `removed == true ⇒ removedAt` not required (Kotlin legacy rows have
   removed without stamp — keep tolerant); `copyCount ≥ 1`; `pageCount` null
   or ≥ 1; `publishedYear` null or 1..9999; `priority ∈ {0,1,2}`;
   `priceEstimate` null or finite ≥ 0; `coverUrl` null, a safe local ref
   (`CoverPaths.leafOf != null`) or `CoverUrlAllowList.sanitize` non-null.
   `copyWith` is unchanged (it is used on already-valid rows).
3. **`PitakaJsonImporter`**: `_book`/`_wishlistBook` build through
   `.validated(...)`; a `Left` becomes one `parseErrors` line
   `'Book "<title…>" (row N) skipped: <field>: <problem>'` and the row is
   dropped. `coverUrl` for books: local kept/dropped as today, remote via
   the factory (allow-list). Wishlist: apply the same `keepLocalCovers`
   rule as books (fixes the S6 asymmetry). `addedBy` clamped like every
   other field. `_asDouble` rejects non-finite (`double.tryParse('NaN')`
   returns NaN — probe verified).
4. **`GoodreadsCsvImporter`**: build through `.validated(...)` too (one
   blessed way); message shape identical to today's `'Row N: missing title.'`
   for the title case so the existing test stays meaningful.
5. **Form use cases** (`AddBookUseCase`, `UpdateBookUseCase`,
   `AddWishlistBookUseCase`, `UpdateWishlistBookUseCase`): replace the
   hand-written title check with `.validated(...)` re-check → first
   `FieldError` → `ValidationFailure(message)`. Forms already map
   `ValidationFailure.message` to the user (`add_book_page.dart:506`,
   `add_wishlist_page.dart:377`). `add_book_page.dart:239` `qty < 1 ? 1 : qty`
   stays (UI convenience), the use case is now the gate.
6. **`ImportLibraryUseCase._applyInside`**: payload rows are already
   validated by the parsers; add a defensive re-check per row (cheap, pure)
   so a future parser cannot bypass it — a `Left` here is a bug, mapped to
   `ValidationFailure` and rolling the transaction back.
7. Tests (red first): boundary tests per field on both factories; importer
   tests for each hostile row shape (max+1 date, 0/negative copyCount,
   priority 3, `1e400`/`"NaN"` price, 8 001-char `addedBy`, non-allow-listed
   https cover, wishlist local ref in plain mode); use-case tests for one
   representative rejection each; update the two existing pinned tests.

### Session 2 (next) — binary ingresses

Restore (`LegacyDbReader` → validate rows, refuse the archive on a `Left`
with `BackupCorruptFailure`, fix `_int` on NaN), wishlist→library move
(`_toLibraryBook` via `Book.validated`, cover through the allow-list), and a
legacy-fixture migration-matrix test for a hostile `books.db`.

## Decision points

- **D1 — where the rules live.** (a) static `validated` factories on the
  existing entities + one shared `catalogue_rules.dart` (proposed: minimal
  surface, no new types beyond `FieldError`, mirrors `EventPoster.create`);
  (b) separate Value Object classes per field (`Title`, `EpochMillis`,
  `CopyCount`…) as repo AGENTS §3.3 literally says — heavier (29 fakes and
  every `Book(...)` call site would change type) and gains nothing the
  factory doesn't. Proposing (a).
- **D2 — over-long text fields on import: reject the row or truncate.**
  Review says reject; M4 (S4) deliberately truncates so "a partially-valid
  file still imports what it safely can". Proposing: truncate + report one
  warning line per affected row (`'…notes shortened to 8000 characters'`) —
  the row is kept, the user is told. Rejecting would silently lose a whole
  book over a long note. The form use cases REJECT (the user can shorten).
- **D3 — `addedDate == 0`.** Today means "no date recorded" (detail page
  renders nothing, `_mergeIntoExisting` treats 0 as "keep existing"). Keep 0
  as the valid "unset" sentinel; reject only negatives and > max.
- **D4 — execute end-to-end or pause at each decision point?**

**Answers (user, 2026-09-11):** D1 = **(a)** factories + shared `catalogue_rules.dart`;
D2 = **(a)** truncate + report on import, reject in forms; D3 = **(a)** 0 stays the
valid "unset" sentinel; D4 = **(a)** end-to-end (pause on broken assumption /
new decision / privacy trade-off).

## Steps

- [x] 1. Baseline gates (analyze 0 / format 391·0 / flutter 1335 / cargo 32)
- [x] 2. Ask D1–D4; record answers here
- [x] 3. Red tests: `catalogue_rules_test.dart`, `book_validated_test.dart`,
      `wishlist_book_validated_test.dart` (compile-red), 11 importer hostile-row
      tests + 4 use-case tests (behaviour-red: 15 failed on HEAD)
- [x] 4. `catalogue_rules.dart` + `Book.validate` + `WishlistBook.validate`
      (static validators taking the built entity — simpler than 23-param
      factories; same D1(a) approach)
- [x] 5. `ImportLimits.defaults.maxFieldChars` → `CatalogueRules.maxFieldChars`
- [x] 6. `PitakaJsonImporter` through the validators via a `_RowReader`
      context; wishlist local-ref rule aligned with books; `addedBy` capped;
      truncation + dropped covers reported via a new `ImportPayload.warnings`
      channel (kept separate from `parseErrors` so a warning can't sink a
      bundle — `ImportBundle.validate` refuses on ANY parse error)
- [x] 7. `GoodreadsCsvImporter` through the validators
- [x] 8. Four form use cases through the validators (`FieldError.userMessage`
      feeds the existing snackbar mapping)
- [x] 9. `ImportLibraryUseCase` defensive re-check per row (a Left there means
      a parser bug → whole import fails, transaction rolls back)
- [x] 10. Updated the two pinned importer tests (example.com → allow-listed
      host); `ImportSummary.warnings` rendered on the import page
- [x] 10b. Display/export hardening for PRE-M15 rows already in a database:
      `CatalogueRules.dateFromMillisOrNull` used by the detail page, the edit
      form's date picker + label, and the PDF/CSV export date — out-of-range
      legacy values render as no-date instead of throwing (the review's
      "breaks normal screens" impact applies to rows already persisted)
- [x] 11. Gates; build_runner check (no annotated code touched — no `.g.dart`
      diff, confirmed via `git status`)
- [x] 12. Result section; update `fix-schedule.md` §1/§3/§5

## Out-of-scope observations

- `LegacyDbReader._int` throws on NaN/Infinity doubles (session 2).
- `_toLibraryBook` copies wishlist `coverUrl` unsanitised (session 2, S15 note).
- `add_book_page.dart:285` `_pickDate` would still assert if a row somehow
  had `addedDate > now` (future date): not a crash of the page, only of the
  picker; the rule set does not forbid future dates (a device clock can be
  wrong; the Kotlin app never forbade it). Noted, not changed.
- `_mergeIntoExisting` (`import_library_use_case.dart:300`) rebuilds a `Book`
  by hand — after this session it should also go through `.validated` for
  consistency; deferred to keep the diff reviewable (it only combines two
  already-validated rows).

## Result

**Session 17 (2026-09-11) — M15 part 1 of 2 DONE, uncommitted (approval pending).**

Red-first: 15 behaviour-red failures on HEAD across the importer and use-case
tests (out-of-range date kept, copyCount 0 kept, priority 7 kept, Infinity/NaN
price kept, blank title kept, 9 000-char `addedBy` uncapped, evil-host cover
kept, wishlist local ref kept in plain mode); the three new domain test files
were compile-red. All green after the fix.

What shipped:
- `library/domain/catalogue_rules.dart` (new): `CatalogueRules` primitives
  (date bound = Rust `MAX_DATE_MILLIS`, field cap, year/count/price/cover
  checks, `dateFromMillisOrNull` display guard) + `FieldError` with a
  beginner-friendly `userMessage`.
- `Book.validate` / `WishlistBook.validate` static validators on the entities:
  reject (title blank, bad dates, copyCount/pageCount < 1, year outside
  1..9999, priority outside 0..2, non-finite/negative price, over-cap text);
  NORMALISE the cover (trim, blank→null, disallowed→null) so a pre-M15 row
  can never become uneditable.
- `PitakaJsonImporter`: every row through the validators via a `_RowReader`
  context; rejections land in `parseErrors` naming row + fields; truncations
  and dropped covers land in a NEW `ImportPayload.warnings` channel (separate
  so a warning can't sink a bundle — `ImportBundle.validate` refuses on any
  parse error); `addedBy` now capped; wishlist local covers follow the same
  keepLocalCovers rule as books (S6 asymmetry closed); bundle mode rejects an
  unsafe local cover ref outright (tampering evidence, M04 fail-closed).
- `GoodreadsCsvImporter`: rows through the same validators.
- The four form use cases route through the validators; the forms' existing
  `ValidationFailure → message` mapping shows `FieldError.userMessage`.
- `ImportLibraryUseCase` re-validates each row before writing (defence in
  depth; a Left = parser bug → whole import rolls back). `ImportSummary`
  carries `warnings`, rendered as "Adjustments" on the import page.
- Pre-M15 rows already in a database no longer crash normal screens:
  `dateFromMillisOrNull` guards the detail page, the edit form's date
  picker/label, and the PDF/CSV export date.
- `ImportLimits.defaults.maxFieldChars` now references
  `CatalogueRules.maxFieldChars` (single source of truth).

Gates: analyze 0; format 395/0; flutter test **1381 passed / 0 failed**
(1335 baseline + 46); cargo **32 passed** (2 expected ignored); coverage
**70.04%** (+0.38); `git diff --check` clean; no `.g.dart` diffs; lib scan:
no print/log/http/Uri/Platform added.

Carried to session 18 (M15 part 2): backup restore ingress
(`LegacyDbReader` → validate rows, refuse the archive on a Left, fix `_int`
on NaN/Infinity doubles), `_toLibraryBook` cover sanitising on the
wishlist→library move, and a hostile-`books.db` migration-matrix test.
