# PLAN.md — Session 15: M13 — wishlist purchase is not transactional

## Understanding

`fix-schedule.md` §1 NEXT = **M13** (astra-review.md, Major). "Purchased — add
to library" on a wishlist entry does three writes with no shared transaction:

1. mark the wishlist row `purchased = true` + stamp `purchasedDate`;
2. look up the ISBN in the library (D2 duplicate check);
3. insert a fresh library book.

If step 3 fails the row is already purchased but no book exists, the detail
page pops as if it worked, and — because the purchase buttons are hidden for
purchased rows — there is no way to retry. If step 2 fails (storage error) the
error is swallowed and the insert runs anyway, so a real duplicate can be
created. Two quick taps both read `purchased: false` and both insert.

Fix the foundation: the whole purchase/move is ONE database transaction that
either fully happens or leaves the row untouched; a lookup failure aborts it;
an already-purchased row is refused (idempotent); the UI stays on screen and
tells the user when it failed.

## Privacy & threat notes

- **Data touched:** wishlist rows and library rows in the local Drift DB
  (unencrypted by user decision M06b). No secrets, nothing leaves the device,
  no new permissions, no new dependencies.
- **Who is affected:** the device user only — silent data inconsistency, not
  an attacker path. Current failure direction is "report success, persist a
  half-state" (fail-open on integrity); fix makes it fail-closed (rollback).
- **Cover URL hand-off:** `_toLibraryBook` already copies `coverUrl`; a remote
  https ref becomes a normal library cover request that M09's consent gate
  governs. No new fetch is introduced here.
- **Threat model:** ordinary double-tap or a disk-full / constraint error
  during the insert. Not remotely triggerable.

## Investigation notes (verified this session, HEAD `26553d2`)

- `lib/features/wishlist/application/wishlist_use_cases.dart:130–160`
  (`MarkWishlistPurchasedUseCase.call`): `getById` → `update(purchased)` →
  `findByIsbn` → `insert`. No transaction. Lookup Left falls through
  (`existing.isRight() && hit != null` is simply false). Confirmed live.
- `lib/features/wishlist/presentation/pages/wishlist_detail_page.dart:117–131`
  buttons only when `!book.purchased`; `:136–157` `_markPurchased` folds the
  Left to `false` and always pops; no busy flag → re-tap possible. Confirmed.
- `lib/features/wishlist/application/wishlist_controller.dart:57–70`
  `markPurchased` returns the Either and refreshes/invalidates unconditionally.
- `lib/features/library/domain/repositories/book_repository.dart:64–72` +
  `lib/features/library/infrastructure/drift_book_repository.dart:282–301`:
  `runInTransaction` is zone-scoped over the shared `AppDatabase`; a Left
  inside becomes `_RollbackWith` → rollback → the Left is returned unchanged.
  Used already by `import_library_use_case.dart:133` and
  `merge_library_use_case.dart:236`. The wishlist repo is constructed on the
  SAME `AppDatabase` (`providers.dart:167–169`, `:267–269`).
- Drift 2.28.2 (`pubspec.lock`) `engines.dart:12–16, 55`: statements issued
  outside an active transaction wait for it → a re-read inside the transaction
  sees the previous purchase's commit. To be PROVEN by the concurrency test.
- `WishlistRepository` has no transaction API; none is needed because the
  book repo's transaction covers both (documented at
  `drift_book_repository.dart:282–284`).
- Existing tests: `test/features/wishlist/wishlist_use_cases_test.dart`
  (real in-memory Drift for the wishlist, `_MemBookRepo` fake for books —
  pass-through transaction, so it CANNOT prove rollback; M04 lesson). No
  `WishlistDetailPage` widget test exists.
- UI failure convention to follow: `book_detail_page.dart:485–503` (busy
  flag, `_snack`, stay on page on Left); message mapping shape from
  `add_wishlist_page.dart:360–366`.

## Proposed approach

Borrowed from this repo's own M04 (`ImportLibraryUseCase`) pattern — the
transaction lives in the use case via `BookRepository.runInTransaction`, and
"read → validate → write" all happen inside it (same shape as SQLite's
canonical "check-then-insert inside BEGIN…COMMIT").

1. **Use case** (`wishlist_use_cases.dart`):
   - `call()` wraps the entire move in `_books.runInTransaction` when a
     `BookRepository` is present. Inside: re-read the row (guard), D2 lookup,
     library insert, THEN the wishlist update. Any Left → rollback → Left.
   - `findByIsbn` Left is returned as-is (propagated; nothing written).
   - Idempotency guard: if the re-read row is already `purchased`, return a
     new typed outcome `MarkPurchasedAlreadyPurchased` without writing (D1).
   - The no-move path (`moveToLibrary == false` or no book repo) is a single
     row update — already atomic; keep, plus the same already-purchased guard.
2. **Controller** (`wishlist_controller.dart`): refresh the wishlist always
   (truth re-read); invalidate the library only when the outcome is a
   `MarkPurchasedSuccess` with a move (nothing changed otherwise).
3. **Detail page** (`wishlist_detail_page.dart`): busy flag disables both
   buttons while a purchase is in flight; on Left → stay on the page and show
   a snackbar with a typed, safe message; on Right → existing behaviour (pop,
   D2 message). Follows `book_detail_page.dart`'s `_busy` + `_snack` shape.
4. **Tests** — regression first, red on HEAD:
   - `wishlist_use_cases_test.dart`: (A) rollback with REAL Drift for both
     repos and a decorator that fails only `insert` → wishlist row still
     `purchased == false`; (B) `findByIsbn` Left → Left returned, no insert,
     row untouched; (C) two concurrent moves on a no-ISBN row → exactly one
     library book, one is `AlreadyPurchased`; (D) already-purchased row →
     `AlreadyPurchased`, no insert, `purchasedDate` unchanged.
   - New `test/features/wishlist/wishlist_detail_page_test.dart`: failure →
     page still mounted + snackbar; success → popped; buttons disabled while
     in flight.

## Decision points (one at a time)

- **D1 — already-purchased semantics.** When "Purchased — add to library" hits
  a row that is already `purchased` (second concurrent tap, or a row the user
  earlier marked "purchased only"): (a) refuse with a typed no-op outcome
  (`AlreadyPurchased`); (b) still try to move it to the library (D2 check,
  insert if ISBN absent — but a no-ISBN row cannot be checked, so a retry
  duplicates). Recommend **(a)**: safe by construction; after this fix a
  failure rolls back so the buttons stay visible and retry is natural.
  Adding an "Add to library" action for purchased-only rows is a separate
  feature (recorded out of scope).
- **D2 — execution mode:** end-to-end, or pause at each decision point?

**Answers (2026-09-10):** D1 = **(a)** refuse with a typed `AlreadyPurchased`
outcome, no write. D2 = **end-to-end**; pause only on a broken assumption,
unforeseen decision, or security trade-off; stop before commit for approval.

## Steps

- [x] 0. Baseline gates (done: analyze 0, format 388/0, Flutter 1312, Rust 32).
- [x] 1. Ask D1, then D2. Do not implement before D1 is answered.
- [x] 2. Write regression tests A–D in `wishlist_use_cases_test.dart`; run;
      record which are red on HEAD. → A, B, C, D all **red on HEAD** (A:
      `purchased` true after failed insert; B: Right instead of Left; C: two
      `MarkPurchasedSuccess`; D: `Success` instead of `AlreadyPurchased`).
      Happy-path E green on HEAD by design (guards the move).
- [x] 3. Implement the transactional use case + `AlreadyPurchased` outcome.
- [x] 4. Tests A–E green (+ a "vanished row inside the move" test, F).
- [x] 5. Controller: invalidate library only on a successful move.
- [x] 6. Detail page: busy guard, stay-on-failure, typed message.
- [x] 7. Widget test `wishlist_detail_page_test.dart` (failure / busy /
      success / already-purchased). Failure, busy and already-purchased were
      **red on HEAD** (proved by swapping the HEAD page back in); success
      passes on HEAD by design.
- [x] 8. Gates: analyze 0; format 389/0; `flutter test --coverage` **1322
      passed / 0 failed** (`/tmp/pitak-s15-flutter-final.txt`); cargo 32.
- [ ] 9. Ask approval to commit (fix code + tests + PLAN.md only).
- [ ] 10. Update `fix-schedule.md` §1, §3, §3.1, §5.

## Out-of-scope observations

- `WishlistDetailPage` renders a `widget.book` snapshot (same class as N03 for
  the library detail page) — a successful purchase must pop to show truth.
- No "Add to library" action exists for rows marked "purchased only"; users
  who took that path (or hold pre-fix half-state rows) have no in-app route to
  the library except re-adding manually. Candidate follow-up feature.
- Wishlist `coverUrl` reaches the library book unsanitised on move; ingress
  validation of that field is M15's territory.

## Result

**M13 fixed.** The wishlist purchase/move is now one Drift transaction; a
failed lookup or insert rolls the purchase back and the user is told, on the
same screen, that nothing changed.

What changed (plain English):

- `lib/features/wishlist/application/wishlist_use_cases.dart` —
  `MarkWishlistPurchasedUseCase.call` splits into `_markOnly` (flag only, one
  row write) and `_markAndMove`, which runs inside
  `BookRepository.runInTransaction` (same pattern as M04's import). Inside
  the transaction the row is re-read; an already-purchased row returns the
  new `MarkPurchasedAlreadyPurchased` outcome without writing (D1 = a); a
  `findByIsbn` Left is propagated instead of being treated as "no match";
  the library insert happens BEFORE the wishlist update so the failure path
  never even issues the wishlist write. Any Left → rollback → Left returned.
- `lib/features/wishlist/application/wishlist_controller.dart` —
  `markPurchased` still refreshes the wishlist on every outcome, but only
  invalidates the library list when a book was actually inserted.
  `.g.dart` hash only.
- `lib/features/wishlist/presentation/pages/wishlist_detail_page.dart` —
  now a `ConsumerStatefulWidget` so a `_purchasing` flag can disable both
  purchase buttons during a write (no double-tap); on a Left the page stays
  put and shows a plain-language snackbar (`NotFound` / `Validation` /
  generic — never raw exception text); on a Right it pops as before, with
  the D2 and the new already-purchased notices.
- Tests: `test/features/wishlist/wishlist_use_cases_test.dart` +6 (real
  Drift for both repos; `_DelegatingBookRepo` decorators sabotage only
  `insert` / `findByIsbn`); new
  `test/features/wishlist/wishlist_detail_page_test.dart` (4 widget tests,
  scriptable/gated book repo).

Verification: analyze 0; format 389/0; Flutter **1322 passed** (was 1312);
Rust 32; coverage `wishlist_use_cases.dart` 74/76 (the 2 misses are the
untouched `UpdateWishlistBookUseCase` storage branch), controller 22/23,
detail page 70/95 (misses are the edit/delete actions, out of scope);
project 69.26% (+0.70). Lib diff adds no print/log/http/Uri/Platform.

OSS credit: transaction shape is this repo's own `ImportLibraryUseCase`
(M04); the underlying "check-then-write inside BEGIN…COMMIT" is SQLite's
canonical idiom, relying on Drift 2.28.2 serialising statements around an
open transaction (`engines.dart:55`, read this session) — proven by test C.

Not done: commit (awaiting approval); no device run (static finding,
reproduced deterministically in tests).
