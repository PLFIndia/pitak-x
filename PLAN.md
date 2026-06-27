# Task: Adaptive library grid (#1) + overflow hardening (#3)

## Understanding
- #1: On wide windows (tablet/foldable/desktop) the library is a single skinny
  `ListView` in a sea of whitespace. Switch to a multi-column cover grid above a
  width breakpoint; keep the list on phones.
- #3: No responsive code exists today. Long titles + multiple status badges in a
  `Row`, and the two-button empty-state `Row`, can overflow on narrow widths or
  large system font scales. Harden the known offenders.

## Privacy & threat notes
- Pure presentation change. No new data collected, stored, or transmitted.
- Covers reuse the existing `BookCover` widget, which already gates remote
  `https://` fetches behind the opt-in setting. No new network egress.

## Investigation notes
- `library_page.dart:172` `_BookList` = flat `ListView.separated` (only list).
- `book_row.dart` Row: title is `Expanded`; trailing badges are fixed-width and
  NOT wrap/flex — overflow risk with several badges on a narrow row.
- `empty_library_state.dart` two-button `Row(mainAxisSize.min)` — overflow risk
  at large text scale / very narrow width.
- `library_controls_row.dart` already in a horizontal `SingleChildScrollView`
  (scroll-safe) — out of scope.
- `BookCover` takes `width`/`height`; safe to render large/expanded.
- No `LayoutBuilder`/`MediaQuery`/breakpoint helper anywhere yet.
- Default flutter_test surface is 800x600 → existing `library_page_test` will
  now hit the grid path; grid card must still expose title / `×N` / `Removed`.

## Proposed approach
- New `core/layout/breakpoints.dart`: single source of truth for the
  `largeScreenMinWidth = 600` breakpoint (skill: adaptive-layout workflow).
- `_BookList` wrapped in `LayoutBuilder`: `maxWidth >= breakpoint` → grid via
  `GridView.builder` + `SliverGridDelegateWithMaxCrossAxisExtent`
  (`mainAxisExtent` fixed so cells can't overflow vertically); else the existing
  `ListView` (BookRow), unchanged.
- New `BookGridCard`: `Column[ Expanded(Stack: cover + corner status pills),
  title(2 lines, ellipsis), author(1 line, ellipsis) ]`. Cover is `Expanded`
  (absorbs slack) so text never overflows the fixed-height cell. Status shown as
  overlay pills (Removed / Not available / Needs info, and `×N`).
- #3: `book_row.dart` — group trailing badges into a `Flexible`→`Wrap` so they
  wrap instead of overflowing. `empty_library_state.dart` — `Row` → `Wrap`.

## Decision points
- None outstanding; user approved #1 + #3, end-to-end.

## Steps
- [x] Add `core/layout/breakpoints.dart`.
- [x] Add `BookGridCard` widget.
- [x] Make `_BookList` adaptive (LayoutBuilder + grid).
- [x] Harden `book_row.dart` trailing badges (Flexible + Wrap).
- [x] Harden `empty_library_state.dart` button Row → Wrap.
- [x] Tests: adaptive grid/list + overflow regression; full suite + analyze.

## Out-of-scope observations
- `library_controls_row.dart` is already horizontal-scroll-safe; left untouched.
- Centralized routing (`go_router`, prior suggestion #2) deferred per user.

## Result
**#1 Adaptive grid:**
- `lib/core/layout/breakpoints.dart` — `largeScreenMinWidth = 600` (SSOT).
- `lib/features/library/presentation/widgets/book_grid_card.dart` — new
  cover-forward card; cover is `Expanded` + status as overlay `Wrap` pills, so
  a fixed-height grid cell can never overflow.
- `library_page.dart` `_BookList` now wraps in `LayoutBuilder`: `>= 600px` →
  `GridView.builder` + `SliverGridDelegateWithMaxCrossAxisExtent`
  (`mainAxisExtent: 280`); below it the original `ListView`/`BookRow` path,
  unchanged. Shared `unavailableOf`/`openDetail` helpers avoid duplication.

**#3 Overflow hardening:**
- `book_row.dart` — trailing badges moved into a `Flexible`+`Wrap` (badge inner
  padding removed; spacing now owned by the Wrap) so badges wrap instead of
  pushing the row off-screen on narrow widths / large text scales.
- `empty_library_state.dart` — two-button `Row` → `Wrap`.

**Tests:** +3 files (`book_grid_card_test`, `library_adaptive_layout_test`,
plus a narrow-row overflow case in `book_row_test`). Adaptive switch verified
by forcing 400px (list) vs 1000px (grid). Full suite: **407 passing**.
`dart analyze` clean on all touched files; `dart format` applied.

**Notes / verification:**
- Existing `library_page_test` (default 800px surface) now exercises the grid
  path and still passes — `find.text` resolves on grid cards too.
- Pre-existing repo-wide analyzer infos (pubspec dependency sort order, etc.)
  are unrelated to this change and were left untouched (§2 stay-in-scope).
- No new dependency; no privacy surface change (covers reuse the opt-in-gated
  `BookCover`).
- Inspiration: Material 3 window-size-class 600px breakpoint + the
  adaptive-layout skill (`LayoutBuilder` on available width, not device type).
