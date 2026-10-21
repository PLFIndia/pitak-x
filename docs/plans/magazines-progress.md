# Magazines / item kinds — progress log (session handoff)

Plan: `docs/plans/magazines.md` (revision 5). Protocol: Part B of the plan.
**Read this file first in every session; update it as the last action of
every session; commit it with the session's commit.**

## State

- Last completed session: **S3** (repository, mapper, use cases, providers)
- Branch: `magazines` — working tree clean: **yes**
- Last commit: S3's commit (S2 was `2959034`, S1 `e216e6b`, S0 `8899cc0`)
- Full suite last green at: **S3, 2026-10-21** — 2426 tests, 57 s
  (`flutter test --exclude-tags golden`)
- Baseline numbers (from S0): tests = **2426 passed, 0 failed**
  (goldens excluded), duration = **86 s**, platform-golden failures = **7**
  (all in `test/golden/key_screens_test.dart`, pixel diffs ≤ 2.4 % — the
  Linux-pinned goldens of CHANGELOG 1.5.2; verify in CI, not a blocker).
- `gen` at baseline: `Built with build_runner in 25s; wrote 1136 outputs`,
  no diff.

### How the gates are run on this machine (S0 findings)

- **Use the FVM-pinned SDK.** `pubspec.lock` pins Flutter **3.44.2**
  (`.fvmrc`); the `flutter` on `PATH` is 3.41.1 and `build_runner` refuses
  to resolve with it. Prefix every command with
  `export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"` (or use `fvm flutter` /
  `fvm dart`).
- **`analyze` is CI-scoped:** `flutter analyze lib test integration_test`
  (exactly what `.github/workflows/ci.yml` runs). A bare `dart analyze` from
  the repo root reports 43 pre-existing errors inside the vendored
  `rust_builder/cargokit/build_tool/` (its own pub deps are not fetched) plus
  3 `sort_pub_dependencies` infos in `pubspec.yaml` — none of them ours.
  Format gate: `dart format --set-exit-if-changed lib test integration_test`.
- **Goldens:** the project defines the `golden` tag (`dart_test.yaml`), so
  `full` on macOS is `flutter test --exclude-tags golden`; the golden-only run
  writes diffs to the git-ignored `test/golden/failures/`.

## Next session

**S4 — Rename domain helpers, widgets, pages, vault/publish/import names.**
Nothing in flight. Follow the plan's S4 steps verbatim.

Notes for it:

- `docs/ARCHITECTURE.md` still says `BookRepository.page` at §3 (module map
  line for `library/`) and §5-ish line 343 — S4 step 5 owns both; fix them
  together with the §2.1 gate name.
- S3 also renamed the use-case PROVIDER functions (`addBookUseCase` →
  `addCatalogueItemUseCase`, update/delete likewise, with their generated
  `…Provider`/`…Ref` names) and the sibling mapper extension
  `BookCompanionMapper` → `CatalogueItemCompanionMapper`; A.7 did not list
  them, but they name "an item of any kind" (F7). Not renamed on purpose:
  `lend_book_use_case.dart` / `LendBookUseCase` (vault — S4 decides via
  `LendDecision.forItem`), `_bookRepo` private fields, `bookId` parameters
  (vault column `book_id`, F2).
- The `test/features/library/add_edit_book_test.dart` groups were renamed to
  `AddCatalogueItemUseCase` / `UpdateCatalogueItemUseCase` (descriptions
  only).

Rename technique (learned in S1–S3):

- `git grep` on this macOS build does not support `\b`; use
  `git grep -P '\bBookRepository\b'` (PCRE). The system `grep` has no `-P`.
- Do identifier replacement with a lexer that skips string literals (JSON
  keys, UI text, fixtures) and handles `//`, `/* */`, `'…'`, `"…"`, `r'…'`,
  triple quotes and `${}` interpolation; rename inside comments too, then
  review the comment diff for references to Kotlin class names (restore
  those: e.g. "Kotlin `BookSort`" stayed). A blind regex breaks raw-string
  prefixes and fixtures. Treat `.g.dart` like any other file, then run `gen`
  and confirm it only re-emits what the script already wrote (hash lines and
  copied doc comments change — expected).
- `git ls-files -- 'lib/*.dart'` (single star) matches everything under
  `lib/`; `'lib/**/*.dart'` misses top-level files. Exclude `lib/src/rust/`
  and `test/core/database/generated/` (version-pinned helpers) explicitly.
- After the rename: `dart format`, then fix `lines_longer_than_80_chars` in
  comments by reflowing the paragraph (S1 used a textwrap script), then
  re-check the file-size ratchet (`layer_boundaries_test.dart`); S4 re-keys
  `book_detail_page.dart` → `catalogue_item_detail_page.dart` (recorded 677
  after S3's bump, see Deviations).
- Generated riverpod provider names follow the function names after `gen`
  (`bookRepositoryProvider` → `catalogueItemRepositoryProvider`); rename the
  provider functions and let `gen` produce the `…Provider` identifiers, but
  the lexer must rename the `…Provider` references in hand-written code too.

## Deviations from plan

- `S1`/`S3` — plan said the ratchet map only changes KEYS in the rename
  sessions (and B.5: no test-expectation changes) — four ratchet SIZES were
  bumped by the mechanical growth of longer identifiers (`dart format`
  wrapping signatures/expression bodies; the 80-column lint forcing
  doc-comment reflows): `add_book_page.dart` 638 → 640 (S1),
  `merge_library_use_case.dart` 543 → 544 (S1) → 545 (S3),
  `drift_catalogue_item_repository.dart` 597 → 599 (S3),
  `book_detail_page.dart` 676 → 677 (S3). No logic was added; comment
  paragraphs with slack were reflowed first wherever one existed. The bump
  carries a comment in `layer_boundaries_test.dart`; S8 and S14 shrink these
  files anyway.

## Open issues / blocked

_(None yet. Record the exact failing command and the first lines of its
output. Platform-golden failures go here tagged "verify in CI".)_

## Session log

| Session | State | Commit | Date | Notes |
|---------|-------|--------|------|-------|
| — | — | `9ca2dba` | 2026-10-21 | plan committed; no sessions run |
| S0 | Done | `8899cc0` | 2026-10-21 | baseline: 2426 tests green in 86 s, 7 platform goldens (verify in CI); gen no diff |
| S1 | Done | `e216e6b` | 2026-10-21 | `Book` → `CatalogueItem`, 130 files; remaining `\bBook\b` in lib+test = 87, all prose/UI strings/fixtures; full green 2426 |
| S2 | Done | `2959034` | 2026-10-21 | `itemUid`/`ItemSourceType`/`LibrarySort`, 83 files. `git grep -n book_uid -- lib` (non-generated) = 18 lines, all column-name sites; `git grep -c "'bookUid'" -- lib` hand-written = 3 (unchanged: exporter, importer, `validate` field label); generated `app_database.g.dart` went 3 → 0 because the Drift row data-class JSON serializer (used nowhere in the app) now keys on the getter `itemUid`. The v1–v4 `test/core/database/generated/` helpers keep `bookUid` (version-pinned). Full green 2426 |
| S3 | Done | _(this commit)_ | 2026-10-21 | `CatalogueItemRepository`, `DriftCatalogueItemRepository`, `CatalogueItemRowMapper`, `Add/Update/DeleteCatalogueItemUseCase`, `catalogueItemRepositoryProvider`, `catalogueItemByIdProvider` (+ use-case providers); 6 lib + 2 test files moved; ratchet re-keyed (597 → 599, see Deviations); ADR 0011 note; full green 2426 |
