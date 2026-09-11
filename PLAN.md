# PLAN.md — Session 19: N04 — derived providers watch real inputs + injectable clock

## Understanding

`astra-review.md` N04: derived lists and reminders are not refreshed by their
real inputs. Re-verified against current code (review line numbers stale, the
patterns are intact):

1. **`libraryLanguages`** (`lib/core/di/providers.dart:224-228`) watches only
   `bookRepositoryProvider` (the repo *object*, which never changes) and queries
   `distinctLanguages()` once. Add/edit/delete/import/merge/restore never
   refresh the filter-chip facets.
2. **`bookTitle`** (`providers.dart:590-595`) — same shape: a rename never
   reaches borrower screens ("Book #id" read model, N06). Not explicitly cited
   by the review (added in S7) but the identical bug class; including it is the
   same one-line fix. **Flagged as an assumption.**
3. **`pendingSnapshot`** (`providers.dart:667-677`) watches the session (loans
   OK) but reads `repo.getAll()` once — a `needsMetadata` edit, import, or
   restore never updates the reminders while the screen stays mounted.
4. **No clock invalidation**: `borrowerProfile` (`:649-660`), `pendingSnapshot`
   (`:676`) and `_LoanRow` (`vault_contents_page.dart:82`) call
   `DateTime.now()` once at build. Overdue/due-soon status never rolls over
   while a screen stays open.
5. **Restore refreshes only the library** (`restore_page.dart:140-143`): a
   restore replaces the wishlist too (M15), but `wishlistControllerProvider` is
   never refreshed — the wishlist page shows pre-restore rows until restart.

N03 (S16) established the precedent this fix reuses: `ref.watch(
libraryControllerProvider)` as a mutation signal — every mutation path in the
app already invalidates or refreshes the list controllers (10 call sites
verified in S16). The repository has no row streams; when it gains one, the
watch line is the single line to swap.

## Privacy & threat notes

No new data leaves the device; no new storage. The clock provider exposes only
epoch millis. No secrets involved. Restore-flow change touches only which
providers get refreshed after a restore that already happened.

## Investigation notes

- `LibraryLogo` (`lib/core/widgets/library_logo.dart`) already falls back to
  the default icon when the referenced file is missing (`existsSync` check) —
  the S9 dangling-logo note is cosmetically handled; the stale *setting* is
  what remains (D2 below).
- Injectable-clock precedent exists: `int Function()? clock` constructor param
  in `chained_isbn_lookup.dart:33`, `publish_events_use_case.dart:75`,
  `publish_library_use_case.dart:114`. For providers, a `clockProvider`
  override plays the same role.
- Unlocked-vault test harness exists: `_InMemoryVault` + overrides in
  `vault_session_controller_test.dart:270-296`.
- No cycle risk: `libraryLanguages`/`bookTitle`/`pendingSnapshot` → watch
  `libraryControllerProvider`; the controller watches only settings + the
  language *filter* (selection), never the languages list.
- Due dates are millisecond-precision: a loan due at 15:00 becomes overdue at
  15:00, not at midnight. A midnight-only rollover would miss intra-day due
  times (D1 below).

## Proposed approach

1. **Signal watches** (N03 pattern, one line each + doc):
   - `libraryLanguages`: `ref.watch(libraryControllerProvider)`.
   - `bookTitle`: `ref.watch(libraryControllerProvider)`.
   - `pendingSnapshot`: `ref.watch(libraryControllerProvider)` for the books
     part (session already watched for loans).
2. **Injectable clock + tick**:
   - `clockProvider`: `@riverpod int Function() clock(...)` defaulting to wall
     clock; overridable in tests (matches the existing `int Function()` idiom).
   - `nowTickProvider`: an autoDispose Stream/Notifier provider that emits
     periodically (granularity = D1) while watched; `borrowerProfile`,
     `pendingSnapshot`, and `_LoanRow` watch it so time-based display rolls
     over on mounted screens. Timer cancelled via `ref.onDispose`.
   - `borrowerProfile`/`pendingSnapshot` take `now` from `ref.watch(
     clockProvider)()`; `_LoanRow` reads the same.
3. **Restore refresh**: `restore_page.dart` also refreshes
   `wishlistControllerProvider` on success (with the signal watches in place,
   all derived state then follows automatically).
4. **D2 (if approved)**: after a successful restore, clear the library-logo
   setting when its file is absent from the restored covers.

## Regression tests (prove red on HEAD first)

- `test/core/di/derived_providers_test.dart` (new):
  - languages: mutate repo languages → invalidate/refresh library controller →
    provider serves the new list (red on HEAD: stale).
  - bookTitle: rename → same signal → new title (red on HEAD: stale).
  - pendingSnapshot: unlocked vault + add a `needsMetadata` book → signal →
    snapshot includes it (red on HEAD: stale).
  - clock: override `clockProvider`, loan due at T+1h; at T it is due-soon;
    advance fake clock past T + fire the tick → overdue (compile-red on HEAD:
    no `clockProvider`).
- `test/features/backup/restore_page_test.dart` +1: successful restore
  refreshes the wishlist controller (red on HEAD: only library refreshed).

## Decision points

- **D1 — tick granularity:** (a) 60-second periodic tick [recommended: covers
  intra-day due times and day rollover; a few cheap rebuilds/min, only while a
  watching screen is mounted]; (b) midnight rollover only [review's literal
  wording; misses a 15:00 due time]; (c) self-scheduled invalidation at the
  next due boundary [precise, most complex].
- **D2 — dangling logo setting (S9 note):** (a) include: clear the logo
  setting after a restore whose covers lack the file [closes the note];
  (b) defer: display already falls back to the default icon.
- **D3 — execution:** end-to-end, or pause at each decision point?

## Steps

- [ ] Baseline gates recorded (analyze 0; format 396/0; flutter 1414; cargo 32).
- [ ] Regression tests written; proved red on HEAD.
- [ ] Signal watches on `libraryLanguages`, `bookTitle`, `pendingSnapshot`.
- [ ] `clockProvider` + `nowTickProvider`; wire into `borrowerProfile`,
      `pendingSnapshot`, `_LoanRow`.
- [ ] Restore refreshes the wishlist controller.
- [ ] (D2) Logo-setting cleanup on restore, if approved.
- [ ] build_runner (providers.dart is `@riverpod`); confirm only expected
      `.g.dart` diffs.
- [ ] End gates: analyze / format / flutter test --coverage / cargo test.
- [ ] PLAN.md Result; fix-schedule.md §1/§3/§5 updates.

## Result

DONE (2026-09-11, Session 19). Decisions: D1=(a) 60 s tick, D2=(a) logo
cleanup included, D3=end-to-end.

- Regression tests proved red on HEAD: 3 behaviour-red signal tests
  (languages/bookTitle/pendingSnapshot stale under an active listener), 2
  compile-red clock tests (no `clockProvider`/`nowTickProvider` existed), 1
  behaviour-red restore-page test (`getAllCalls` stayed 1), 1 behaviour-red
  logo test (`logoWrites` stayed empty).
- `providers.dart`: `libraryLanguages`, `bookTitle`, `pendingSnapshot` now
  watch `libraryControllerProvider` (N03 signal pattern); new `clockProvider`
  (injectable `int Function()`, same idiom as the lookup/publish use cases)
  and `nowTickProvider` (self-invalidating 60 s timer; value = epoch millis
  because Riverpod only propagates CHANGED values — a `Stream.periodic` of
  identical events never rebuilds dependents, verified experimentally);
  `borrowerProfile` + `pendingSnapshot` take `now` from the clock and rebuild
  on the tick.
- `vault_contents_page.dart` `_LoanRow`: same clock + tick (overdue badge
  rolls over on an open page).
- `restore_page.dart`: success refreshes the wishlist controller too (restore
  replaces both tables since M15).
- `restore_controller.dart`: `_clearDanglingLogoRef` after a successful
  restore — settings are not in backups, so a logo reference whose file is
  absent from the post-restore covers set is cleared (fail-open: skipped when
  settings are not loaded, write Left ignored — the logo widget already falls
  back to the default icon).
- Found while implementing: (1) `RestoreBackup` is a `final class` — the logo
  tests use the real restorer over the real storage chain instead of a fake;
  (2) `restore_controller_test.dart` ALREADY existed with 6 tests — an
  initial draft overwrote it by mistake; recovered from HEAD and merged (the
  6 originals + 3 new all pass); (3) the tick timer breaks the widget-test
  invariant "no pending timers after tree disposal" for self-managed
  containers — `borrower_profile_page_test` stubs `nowTickProvider` (documented
  inline); (4) `container.invalidate` only SCHEDULES a rebuild — tests flush
  with `await container.pump()`.
- Gates: analyze 0; format 397/0; flutter test 1423 passed (1414 + 9 new);
  cargo 32 passed (2 expected ignored); coverage 70.30% (+0.16);
  `restore_controller.dart` 21/21. Lib-diff scan: no print/log/http/Uri/
  Platform added. build_runner: only the expected `.g.dart` diffs; `.fvmrc`/
  `.gitignore` untouched.
