# Magazines / item kinds — progress log (session handoff)

Plan: `docs/plans/magazines.md` (revision 5). Protocol: Part B of the plan.
**Read this file first in every session; update it as the last action of
every session; commit it with the session's commit.**

## State

- Last completed session: **S1** (`Book` → `CatalogueItem`)
- Branch: `magazines` — working tree clean: **yes**
- Last commit: S1's commit (S0 was `8899cc0`)
- Full suite last green at: **S1, 2026-10-21** — 2426 tests, 63 s
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

**S2 — Rename `bookUid` → `itemUid`, `BookSourceType`, `BookSort`.** Nothing
in flight. Follow the plan's S2 steps verbatim.

Notes for it:

- `git grep` on this macOS build does not support `\b`; use
  `git grep -P '\bbookUid\b'` (PCRE). The system `grep` has no `-P` either.
- Do the identifier replacement with a lexer that skips string literals and
  comments (S1 used `/tmp/rename_book.py`-style tokenising: `//`, `/* */`,
  `'…'`, `"…"`, `r'…'`, triple quotes, `${}` interpolation). A blind regex
  would rewrite JSON keys and test fixtures — exactly what step 1's
  "restore every string literal" clause warns about. Treat the `.g.dart`
  files like any other file, then run `gen` and confirm it only re-emits what
  the script already wrote.
- `git ls-files -- 'lib/**/*.dart'` does NOT match top-level files
  (`lib/main.dart`, `test/widget_test.dart`, `test/app_lock_navigator_test.dart`,
  `integration_test/vault_smoke_test.dart`); include them explicitly.
- Expect `dart format` to wrap lines where the identifier got longer and the
  `lines_longer_than_80_chars` lint to flag comment lines — reflow those
  paragraphs (S1 did this with a small textwrap script). Re-check the file-size
  ratchet afterwards (see Deviations).

## Deviations from plan

- `S1` — plan step 5 said "Ratchet map: no paths change in this session"
  (and B.5: no test-expectation changes) — two ratchet SIZES were bumped:
  `add_book_page.dart` 638 → 640 and `merge_library_use_case.dart` 543 → 544
  — the longer identifier made `dart format` wrap a method signature and an
  expression body; no logic was added. Comment paragraphs with slack were
  reflowed first (`library_merge_engine.dart` came back to exactly 721). The
  bump carries a comment in `layer_boundaries_test.dart`. S8 and S14 lower
  these files anyway.

## Open issues / blocked

_(None yet. Record the exact failing command and the first lines of its
output. Platform-golden failures go here tagged "verify in CI".)_

## Session log

| Session | State | Commit | Date | Notes |
|---------|-------|--------|------|-------|
| — | — | `9ca2dba` | 2026-10-21 | plan committed; no sessions run |
| S0 | Done | `8899cc0` | 2026-10-21 | baseline: 2426 tests green in 86 s, 7 platform goldens (verify in CI); gen no diff |
| S1 | Done | _(this commit)_ | 2026-10-21 | `Book` → `CatalogueItem`, 130 files; remaining `\bBook\b` in lib+test = 87, all prose/UI strings/fixtures; full green 2426 |
