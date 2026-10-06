# PLAN.md — Session 34 — Clear "already in library" message + locked-vault Lend hint

User request (two UX bugs):
1. Scanning the ISBN of a book that is ALREADY in the library ends in a
   generic "Could not save the book. Please try again." It must clearly say
   the book is already in the library.
2. On the book detail page, when the vault is locked the Lend button silently
   disappears. Correct but confusing: show a grayed-out Lend button with a
   hint telling the user to unlock the vault to use lending.

## Understanding (verified from source this session)

Problem 1 — root-cause chain:
- `books.isbn` carries a UNIQUE index: `lib/core/database/app_database.dart:76`
  (`index_books_isbn`; wishlist has a twin at `:93`).
- Scan flow: `library_page.dart:47 _quickAddByScan` → `ScannerPage` →
  `AddBookPage(initialIsbn: …)` → user taps "Add book" →
  `AddBookController.save` → `AddBookUseCase` → `Book.validate` (pure field
  gate, no duplicate check) → `DriftBookRepository.insert`
  (`drift_book_repository.dart:237`) → SQLite UNIQUE violation throws →
  `on Object catch` → `StorageFailure('insert: $e')` (`:252`).
- `add_book_page.dart:618 _messageFor` maps only `ValidationFailure` /
  `NotFoundFailure`; everything else falls to the generic
  "Could not save the book. Please try again." (`:623`). That is the message
  the user reported.
- `AddBookUseCase` docstring: duplicate-ISBN routing was deliberately deferred
  ("NOT ported … a UI concern that calls `findByIsbn` first").
- `BookRepository.findByIsbn` already exists (`book_repository.dart:76`, impl
  `drift_book_repository.dart:381`, exact match, blank → null).
- In-repo precedent for the pre-check pattern: wishlist
  `MarkWishlistPurchasedUseCase` (`wishlist_use_cases.dart`) calls
  `findByIsbn` before inserting into the library and returns a typed
  `MarkPurchasedAlreadyInLibrary` outcome.
- Editing a book ONTO another row's ISBN (`update`, `:256-289`) hits the same
  unique index and the same generic message.

Problem 2 — current behaviour:
- `book_detail_page.dart:184`: `lendDecision` is computed only when
  `session is VaultUnlocked`; `:273` renders the whole Lend block only
  `if (vaultUnlocked && lendDecision != null)` → locked / uninitialized vault
  ⇒ no button, no explanation.
- Vault session states (`vault_session_state.dart`): `VaultUninitialized`
  (offer "set up"), `VaultLocked` (offer "unlock"), `VaultUnlocked(data)`.
- `VaultPage` (`vault/presentation/pages/vault_page.dart`) already renders the
  setup/unlock UI per state; the drawer pushes it (`app_drawer.dart:76`).
  The detail page WATCHES `vaultSessionControllerProvider` (keepAlive), so
  after unlocking and popping back it rebuilds with a live Lend button — no
  extra plumbing needed.
- `LendDecision` (`lending_policy.dart`) already models allowed/refused +
  plain-language reason for the unlocked case; unchanged.
- Widget-test setup precedent for vault state: `lend_book_page_test.dart`
  (override `vaultStoreProvider` + `vaultRepositoryProvider`, then
  `container.read(vaultSessionControllerProvider.notifier).enable(…)`).
- `book_detail_page_test.dart` currently never overrides vault providers and
  never asserts on Lend — the new always-visible button may change what those
  tests see; suite run will confirm.

## Privacy & threat notes

- No new data collected, no network calls, no new permissions. All local.
- `DuplicateIsbnFailure` carries the EXISTING book's title/id — the user's own
  local data, surfaced only to that user in the UI message. Never logged
  (failure diagnostics stay internal, per §5/§6.2).
- Locked-vault hint reveals only that a lending feature exists (already
  visible in the drawer) — nothing about vault contents, borrowers, or
  whether the vault holds data. The button stays DISABLED: no path into
  lending without an unlocked vault; `LendBookUseCase` remains the enforcing
  gate (fail closed preserved).
- Scan-time duplicate check reads the local DB only.

## Proposed approach

### Fix 1 — typed duplicate-ISBN failure + clear message

1. `lib/core/error/failure.dart`: add `DuplicateIsbnFailure extends Failure`
   with `existingTitle` (String?), `existingBookId` (int?),
   `existingIsRemoved` (bool, default false). Nullable fields so the
   race-path mapping (step 3) can construct it even when the title re-query
   fails.
2. `AddBookUseCase`: after `Book.validate` passes, when the ISBN is non-blank
   call `findByIsbn`; a hit returns `left(DuplicateIsbnFailure(…))` with the
   existing title/id/removed flag. A FAILED pre-check read propagates (fail
   closed — if we cannot read, we do not blind-insert). Update the docstring
   (the "NOT ported" deferral note is now resolved).
3. `DriftBookRepository.insert` + `.update` catch blocks — race safety net
   (TOCTOU between the use-case pre-check and the write; the unique index
   stays the final gate): when a write fails and `book.isbn` is non-blank,
   re-query `findByIsbn`; a colliding row (for `update`: with a DIFFERENT id)
   → `DuplicateIsbnFailure` (best-effort title); otherwise keep
   `StorageFailure`. Deliberately NO exception-string parsing and no new
   dependency: `SqliteException` is not re-exported by `package:drift/drift.dart`
   and `sqlite3` is only a transitive dep (importing it directly would trip
   `depend_on_referenced_packages`). The re-query is robust and honest: if a
   row now holds that ISBN, "already in your library" IS the truth.
4. `add_book_page.dart _messageFor`: `DuplicateIsbnFailure` →
   `"'{title}' is already in your library."` (no title → "This book is already
   in your library."); when `existingIsRemoved`, append "(marked as removed —
   restore it from the library list)". [D2]
5. Scan-time routing in `library_page._quickAddByScan` (completes the deferred
   Kotlin behaviour, catches the duplicate BEFORE the user fills a form):
   - New thin application entry point `FindByIsbnUseCase`
     (`lib/features/library/application/find_by_isbn_use_case.dart`) returning
     `Either<Failure, Book?>` + `@riverpod` provider in `core/di/providers.dart`
     (same pattern as `addBookUseCase`, `:244`) — presentation must not call
     the repository directly (§3.1).
   - After a scan: ISBN found → dialog "This book is already in your library."
     with [View book] → `BookDetailPage(bookId: …, initialBook: …)` and
     [Cancel]; not found → `AddBookPage(initialIsbn: …)` as today.
   - Lookup READ failure → fall through to the add form (navigation choice,
     not a security gate — the save path + unique index still refuse the
     duplicate). [D1]

### Fix 2 — Lend button states on the book detail page

6. `book_detail_page.dart`: replace the `if (vaultUnlocked && lendDecision != null)`
   block with a session-state-driven section:
   - `VaultUnlocked` → unchanged (LendDecision drives enabled/disabled + reason).
   - `VaultLocked` → disabled `FilledButton.icon` (grayed by the theme) +
     hint below in the SAME style as the existing `lendDecision.reason` text:
     "Unlock the borrowers vault to lend this book." + a `TextButton.icon`
     "Unlock the vault" that pushes `VaultPage`. On return after a successful
     unlock the watched provider rebuilds this page with a live button. [D3]
   - `VaultUninitialized` → disabled button + "Set up the borrowers vault to
     start lending." + "Set up the vault" → `VaultPage`.
   - Session still loading / errored (`valueOrNull == null`) → render nothing
     (transient, same as today).
   - Icon on the disabled button stays `Icons.outbox` (consistent identity;
     the hint carries the "why"). [D4]

### Tests (§8/§10)

7. - `drift_book_repository_test.dart`: duplicate-ISBN insert →
     `DuplicateIsbnFailure`; update onto another row's ISBN →
     `DuplicateIsbnFailure`; update keeping its OWN ISBN → still succeeds;
     duplicate `book_uid` → `StorageFailure` (not misreported as ISBN dup).
   - Use-case test (extend `add_edit_book_test.dart` or new
     `add_book_use_case_test.dart`, matching existing layout): duplicate →
     left carrying the existing title; blank ISBN → no pre-check, insert runs;
     `findByIsbn` failure → propagated, insert NOT attempted.
   - `add_book_page_test.dart`: saving a duplicate shows the "already in your
     library" message, not the generic one.
   - `book_detail_page_test.dart` (setup borrowed from `lend_book_page_test.dart`):
     locked → disabled Lend + unlock hint; uninitialized → setup hint;
     unlocked+allowed → enabled Lend; tapping "Unlock the vault" navigates
     (find the VaultPage app bar "Borrowers vault").
   - Quick-add scan-time routing: `ScannerPage` needs a camera, so the full
     tap-through is not widget-testable; extract the post-scan routing into a
     testable helper (or test `FindByIsbnUseCase` + the dialog separately).
     If neither is feasible without contortion, record it and verify manually.
   - Full `flutter test` run — existing detail-page tests may now see the
     disabled-Lend block; adjust only if an expectation actually breaks.

8. Quality gates: `dart run build_runner build --delete-conflicting-outputs`
   (new provider), `dart analyze` (zero issues), `dart format`, full suite.

## Decision points

- **D1** — Scan-time duplicate routing (step 5): RESOLVED — user approved
  end-to-end with recommendations; included.
- **D2** — Wording: RESOLVED — "'{title}' is already in your library."
  (+ "It is marked as removed — open it from the library list to restore it."
  for soft-deleted rows).
- **D3** — Locked hint interactivity: RESOLVED — hint + tappable
  "Unlock the vault" / "Set up the vault" link opening VaultPage.
- **D4** — Disabled-button icon: RESOLVED — kept `Icons.outbox`.

## Steps

- [x] 1. `DuplicateIsbnFailure` in `core/error/failure.dart`
- [x] 2. `AddBookUseCase` pre-check + docstring
- [x] 3. `DriftBookRepository.insert/update` catch → duplicate mapping
- [x] 4. `add_book_page.dart _messageFor` branch
- [x] 5. `FindByIsbnUseCase` + provider + quick-add scan routing [D1]
- [x] 6. `book_detail_page.dart` locked/uninitialized Lend section [D3/D4]
- [x] 7. Tests (repo, use case, both pages, routing helper)
- [x] 8. build_runner + analyze + format + full `flutter test`
- [x] 9. Result section below

## Out-of-scope observations

- Wishlist has the SAME latent bug: unique `wishlist_books.isbn` index
  (`app_database.dart:93`) + `drift_wishlist_repository.insert/upsert` catch →
  `StorageFailure` → generic "Could not save the entry."
  (`add_wishlist_page.dart:381`). Scanning a duplicate ISBN into the wishlist
  gives the same confusing message. Same fix pattern applies; not touched here
  (reported flow is the library).
- ISBN uniqueness is EXACT-string: a hand-typed hyphenated ISBN does not
  collide with the stored normalized form (scanner normalizes, the form does
  not). Normalizing ISBN at form entry would close that gap — separate task.

## Result

DONE — full suite green (1752 tests) on BOTH the system Flutter 3.41.1 and
the fvm-pinned 3.44.2 (after `fvm flutter clean`: 27 failures under 3.44.2
were stale `build/unit_test_assets` shaders compiled by 3.41.1 —
"ink_sparkle.frag … runtime stages format" — not code regressions; they
reproduce on pristine main). `dart analyze lib test` zero issues,
`dart format` clean, build_runner re-run produced no diff.

Code commit: 8ee6d07 `fix(library,vault): name the existing book on
duplicate-ISBN adds; Lend explains a locked vault`.

Changed files:
- `lib/core/error/failure.dart` — new `DuplicateIsbnFailure`
  (`existingTitle` / `existingBookId` / `existingIsRemoved`).
- `lib/features/library/application/add_book_use_case.dart` — `findByIsbn`
  pre-check before insert; a failed pre-check read aborts the add (fail
  closed); docstring deferral note resolved.
- `lib/features/library/application/find_by_isbn_use_case.dart` — NEW thin
  use case so presentation never touches the repository directly (§3.1).
- `lib/core/di/providers.dart` (+`.g.dart`) — `findByIsbnUseCaseProvider`.
- `lib/features/library/infrastructure/drift_book_repository.dart` —
  `insert`/`update` catch blocks map a UNIQUE-isbn collision to
  `DuplicateIsbnFailure` via a best-effort re-query (`_isbnCollision`, no
  exception-text parsing, no new dependency); `book_uid` collisions stay
  `StorageFailure`.
- `lib/features/library/presentation/pages/add_book_page.dart` —
  `_messageFor`: "'{title}' is already in your library." (+ removed note).
- `lib/features/library/presentation/pages/library_page.dart` — quick-add
  scan now routes through top-level `routeScannedIsbn`: duplicate → dialog
  "Already in your library" with [View book] → BookDetailPage; new/unreadable
  ISBN → AddBookPage pre-filled (fail-through is safe: save path + UNIQUE
  index still guard).
- `lib/features/library/presentation/pages/book_detail_page.dart` — Lend
  section renders for every KNOWN vault state: unlocked = policy-driven as
  before; locked = disabled button + "Unlock the borrowers vault to lend this
  book." + "Unlock the vault" link → VaultPage; uninitialized = disabled
  button + set-up hint + link; loading/error = hidden (transient).

Tests added:
- `drift_book_repository_test.dart` — group "S34 — duplicate ISBN maps to
  DuplicateIsbnFailure" (insert collision + title/id, removed flag, update
  onto another row's ISBN, own-ISBN update still succeeds, book_uid collision
  NOT misreported).
- `add_edit_book_test.dart` — AddBookUseCase: duplicate refused with title,
  removed duplicate flagged, blank ISBNs never collide, failed pre-check
  propagates with zero insert attempts (`_FailingFindByIsbnRepo`).
- `add_book_page_test.dart` — `_MemRepo.findByIsbn` now derives from stored
  books (like the real repo); duplicate save shows the named message, removed
  duplicate shows the removed note, nothing inserted, form stays open.
- `book_detail_page_test.dart` — group "S34: the Lend section reflects the
  vault state": locked → disabled + hint, uninitialized → disabled + set-up
  hint, unlocked → enabled + no hint, hint tap opens the vault screen
  (`_StubVault` + VaultStore file fixture, recipe from replacement_harness).
- `scan_routing_test.dart` — NEW: duplicate → dialog naming the book, View
  book → detail page, Cancel → no navigation, unknown ISBN → pre-filled add
  form, failed read → falls through to the add form.

Notes / assumptions:
- `pubspec.lock` matcher/meta drift seen mid-session came from running tests
  with the SYSTEM Flutter 3.41.1; the committed lock matches the fvm-pinned
  3.44.2 (`.fvm/fvm_config.json`), and reverted cleanly. Release built with
  `fvm flutter`.
- Architecture boundary tests (`test/architecture/domain_purity_test.dart`)
  pass with the new use case + page imports.
- Camera scan itself not widget-tested (flutter_zxing needs a device);
  routing after the scan is covered by `scan_routing_test.dart`.
