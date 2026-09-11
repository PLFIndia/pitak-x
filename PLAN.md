# PLAN.md — Session 16: N03 (detail page observes the book by ID)

Roadmap: `fix-schedule.md` §3 row N03. Review source: `astra-review.md` N03.

## Understanding

`BookDetailPage` (`lib/features/library/presentation/pages/book_detail_page.dart:55–59`)
is a `ConsumerWidget` handed a `Book` snapshot from the list
(`library_page.dart:204`). Everything on the page renders `book.*` from that
snapshot, and the Edit action (`:80–92`) pushes `AddBookPage(book: book)` with
the same snapshot. Two things mutate the row while the page is open:

1. `_EditableCover` → `BookCoverController.replaceCover(widget.book, raw)`
   (`book_cover_controller.dart:38–68`) — writes `coverUrl = covers/<new>.jpg`
   to the DB, then `janitor.releaseReference(book.coverUrl)` deletes the OLD
   file. Only `_EditableCoverState._coverUrl` is updated; the page's `book`
   still says `coverUrl = covers/<old>.jpg`.
2. `RemoteCoverMaterializer` (M09) may rewrite `coverUrl` from an `https://`
   URL to a local file at any time while the page is open (asked from
   `BookCover`, which already takes `bookId`).

The bug: **capture cover → tap Edit → change the title → Save.**
`AddBookPage._buildBook()` (`add_book_page.dart:202–237`) copies
`base?.coverUrl` (the stale snapshot) into the saved `Book`, and
`UpdateBookUseCase` → `DriftBookRepository.update` writes it verbatim. The
row now points at `covers/<old>.jpg`, whose file the janitor already deleted
→ placeholder; and `covers/<new>.jpg` becomes an orphan the janitor will
sweep on next startup. The user's photo is lost.

Secondary (same root cause): a second `replaceCover` in the same visit passes
the ORIGINAL snapshot's `coverUrl` to `releaseReference`, so the intermediate
file is not released until the startup sweep (review note); and all detail
rows show pre-edit values after Edit, which is why the page currently pops
itself after Edit (`:87–91`) instead of showing the fresh row.

Verified live on HEAD `1cf334b` by reading every file above; the review's
line numbers are stale but the shapes are intact.

## Privacy & threat notes

No new data, no network, no new permission. All changes are in-process reads
of the local Drift row already displayed. Threat model unchanged: the cover
file lives under app-private storage; the fix only stops a stale reference
from being persisted. No secrets touched. No logging added.

## Investigation notes

- `BookRepository.getById(int)` exists (`book_repository.dart:27`) and returns
  `Either<Failure, Book?>`. Drift 2.28.2 is present; there is no stream API on
  the repository (N04 territory — NOT added here).
- Existing single-row read-model precedent: `bookTitleProvider`
  (`providers.dart:586–591`) — a `@riverpod` family over `getById`. Same shape
  is the natural home for a `bookByIdProvider`.
- Every mutation path already signals via `libraryControllerProvider`
  (`invalidate`/`refresh` in `book_cover_controller.dart:66`,
  `remote_cover_materializer.dart:86`, `add_book_page.dart:258`,
  `library_controller.dart` remove/restore). A `bookById` family that
  `ref.watch`es `libraryControllerProvider` is rebuilt by all of them with
  zero new plumbing — the "consistent mutation-version signal" the review's
  N04 direction names, reused rather than invented.
- `AddBookPage` is `ConsumerStatefulWidget`; `_buildBook()` uses
  `widget.book` as `base`. In edit mode it needs the FRESH row at save time
  for the fields it does not edit (`coverUrl`, `removed`, `removedAt`,
  `addedBy`, `bookUid`), while form fields stay the user's typed values.
- 29 `implements BookRepository` fakes exist — adding a repository method is
  a 29-file change; adding a provider is not. Provider route chosen.
- `WishlistDetailPage` has the same snapshot shape but NO in-page mutation
  that changes the row while it is open (purchase pops on success, edit pops
  after). The lost-write bug cannot occur there today — the decision below
  asks whether to touch it anyway.

## Proposed approach (OSS references)

Riverpod's own documented pattern for "one entity by id that stays fresh":
a family provider the page watches (Riverpod docs, "Passing arguments to your
requests"; same as this repo's `bookTitleProvider` / `borrowerProfileProvider`).

1. **`bookByIdProvider(int id)`** in `core/di/providers.dart` (`@riverpod`
   family, autoDispose): `ref.watch(libraryControllerProvider)` for the
   invalidation signal (value ignored), then `repo.getById(id)`; Left → throw
   the `Failure` (Riverpod → `AsyncError`, same idiom as `library_controller.dart`).
   Null → the book is gone.
2. **`BookDetailPage(bookId:)`** replaces `BookDetailPage(book:)`. The page
   `ref.watch(bookByIdProvider(bookId))` and renders loading / safe error /
   "no longer exists" / data. The data branch is the existing body, unchanged
   except that `book` comes from the provider. `_EditableCover` drops its
   `_coverUrl` copy and renders the observed book's `coverUrl`; `replaceCover`
   gets the observed (fresh) book, so the second-replace janitor case is fixed
   too. The post-Edit `pop()` is removed: the page now shows truth.
   Keep the initial `Book` as an optional `initialBook` so the first frame is
   not a spinner when pushed from the list (render it until the provider has
   data). Decision D2 below.
3. **`AddBookPage` edit mode uses a fresh snapshot at save.** In `_save()`,
   when `_isEdit`, re-read `getById(widget.book!.id)` and pass THAT as the
   base for the non-form fields. If the row is gone → `NotFoundFailure`
   surfaced through the existing `AddBookController` error path. Cheapest
   robust form: give `_buildBook` a `Book base` parameter. This alone closes
   the lost-cover bug even if some other caller passes a stale snapshot.
4. **Tests (regression first, prove red on HEAD):**
   - `test/features/library/book_detail_page_test.dart` (new): (A) row
     changes (`coverUrl` rewritten in the repo + `libraryController`
     invalidated) → page re-renders with the new value without re-entry;
     (B) capture-then-edit: after the repo's cover changed, tapping Edit
     opens `AddBookPage` and Save keeps the NEW cover — red on HEAD;
     (C) book deleted while open → safe "no longer exists" state, no crash;
     (D) repo Left → safe error text, no raw exception.
   - `test/features/library/add_book_page_test.dart`: (E) edit mode with a
     stale `book:` whose `coverUrl` differs from the repo row → saved row
     keeps the repo's cover — red on HEAD.
   - `book_cover_controller_test.dart`: unchanged contract; add (F) only if
     the controller signature changes (it does not).

## Decision points

- **D1 (asked first, per fix-schedule §3 row):** scope — library detail page
  only, or also `WishlistDetailPage`? → **(b) both pages** (user, S16).
  Wishlist gets the same shape: `wishlistBookByIdProvider(id)` family
  watching `wishlistControllerProvider` as its signal; `WishlistDetailPage`
  observes by id; `AddWishlistPage` edit mode re-reads the row at save.
- **D2:** first-frame behaviour — (a) accept `initialBook` and render it until
  the provider resolves (no spinner flash); (b) `bookId` only, spinner on
  first frame. Proposed: (a). → **(a)** taken as the proposed default under
  the end-to-end go-ahead (user did not object).
- **D3:** execute end-to-end or pause at each decision point? →
  **end-to-end** (user, S16); pause only if an assumption breaks.

## Steps

- [x] 1. D1/D2/D3 answered (b / a / end-to-end).
- [x] 2. Regression tests written; run on HEAD. Red: `add_book_page_test`
      N03 → `Expected 'covers/new.jpg' / Actual 'covers/old.jpg'`;
      `add_wishlist_page_edit_test` N03 → same. `book_detail_page_test` and
      the N03 cases in `wishlist_detail_page_test` do not compile on HEAD
      (`bookId` parameter absent) — API-change red. Test-harness note: a
      focused `TextField` scrolls itself back into view after a fling settles,
      unbuilding the lazily built save button — helpers unfocus first.
- [x] 3. `bookByIdProvider` + `wishlistBookByIdProvider` families in
      `core/di/providers.dart`; build_runner rerun (`.fvmrc`/`.gitignore`
      untouched).
- [x] 4. `BookDetailPage(bookId, initialBook?)` observes by id; body split into
      `_BookDetailBody` + gone/failed/loading scaffolds; `_EditableCover`
      dropped its `_coverUrl` copy; post-Edit `pop()` removed.
      `WishlistDetailPage` same shape (`_WishlistDetailBody` keeps the M13
      busy flag).
- [x] 5. Call sites: `library_page.dart` `openDetail`, `wishlist_page.dart`
      `_row`.
- [x] 6. `AddBookController.saveEdit(id, applyEdits)` /
      `AddWishlistController.saveEdit` re-read the row and build on it;
      `save()` now refuses a persisted id. Forms pass `_buildBook(base)` /
      `_build(base)` as the callback; maintainer stamp read before any await.
- [x] 7. Gates green (see Result); coverage of touched files checked.
- [x] 8. fix-schedule.md §1/§3/§5 updated; commit approval requested.

## Out-of-scope observations

- Repository has no reactive streams (N04) — this session reuses the existing
  invalidation signal; N04 may later replace `bookById`'s dependency with a
  real stream without touching the page.
- `WishlistDetailPage` snapshot shape (see D1).

## Result

**Root cause fixed, not patched.** Both detail pages now observe their row by
id and both edit forms save on top of a freshly re-read row. The stale
snapshot that resurrected a deleted cover file no longer exists anywhere in
the flow: the list row is used for the first frame only and never reaches an
action.

What changed (plain English):
- Two tiny read-model providers (`bookById`, `wishlistBookById`) that re-read
  one row whenever the list controller is invalidated — the signal every
  mutation already fires. No repository interface change (29 fakes untouched).
- The detail pages render whatever those providers say: current row, "no
  longer exists", or a safe error. A row rewritten underneath swaps in without
  a spinner (Riverpod keeps the previous value during a reload). A failed
  re-read AFTER data was shown keeps the last-known row on screen by design
  (actions surface their own failures); a failed FIRST read shows the error
  page.
- The edit controllers gained `saveEdit(id, applyEdits)`: read the row now,
  let the form overlay its fields, write. `save()` refuses a persisted id so
  nobody can bypass this by accident.
- `_EditableCover` no longer keeps its own copy of the cover reference; the
  janitor now receives the row's real current reference (fixes the review's
  second-capture-in-one-visit note too).

Tests: 13 new (6 `book_detail_page_test`, 2 `add_book_page_test`, 3 new N03
cases in `wishlist_detail_page_test`, 2 `add_wishlist_page_edit_test`). Red
on HEAD: the two `add_*_page` N03 saves (`covers/old.jpg` written back), and
every detail-page N03 case (constructor change → compile red). Existing
`library_page_test` fake given distinct ids + a real `getById` (its rows all
shared `emptyId`, which the by-id page cannot distinguish).

Gates (pinned SDK 3.44.2): analyze 0; format 391 files / 0 changed; flutter
test `--coverage` **1335 passed / 0 failed** (`/tmp/pitak-s16-flutter-final3.txt`,
0 `[E]`); cargo 32 passed / 2 expected ignored; `git diff --check` clean;
build_runner → expected `.g.dart` diffs only; lib-diff scan: no
print/log/http/Uri/Platform added. Coverage: `add_book_controller` 19/22,
`add_wishlist_controller` 20/23, `book_detail_page` 118/233 (misses are the
camera/crop plugin path, remove/restore dialogs, lend — all pre-existing and
untestable without plugins), `wishlist_detail_page` 98/125; project 69.66%
(+0.40).

Test-harness lesson (recorded for later sessions): a focused `TextField`
scrolls itself back into view after a fling settles, which unbuilds the lazily
built save button. Save helpers now unfocus, scroll, settle, tap. Also: the
full suite must be launched fully detached (`nohup script &` inside a
subshell) — the tool's own timeout kills child `flutter_tester` processes.

Not done: no device verification (static finding; reproduced deterministically
in widget tests). Remote CI not checked.
