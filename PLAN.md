# PLAN.md — Session 21: stop stale-codegen CI failures at the source (tracked pre-commit gate)

## Understanding

CI runs `34607276360` and `34617757083` (2026-09-11) both failed on the same
step, `build_runner (no uncommitted diff)`. Commit `8ec79b0` unblocked `main`
by regenerating three `.g.dart` files. This session removes the CLASS of
failure, not just the instance.

**What actually happens (verified in pub-cache source, not memory):**

- `riverpod_generator` 2.6.4 (pubspec.lock:1043) emits one line per provider:
  `String _$xHash() => r'<sha1>';`
  (`riverpod_generator-2.6.4/lib/src/riverpod_generator.dart:24`).
- The sha1 is `sha1(utf8(node.toSource()))` — the analyzer AST re-serialised
  as source for the WHOLE annotated class/function
  (`riverpod_analyzer_utils-0.5.10/lib/src/riverpod_ast/generator_provider_declaration.dart:85-92`).
  `toSource()` drops comments and normalises whitespace (verified in step 3b:
  a comment-only edit left the hash unchanged; adding one private field
  changed it). So any CODE edit inside the class body — a new field, a
  renamed private member, a changed statement — changes the hash. Nothing
  else in the `.g.dart` changes.
- Riverpod uses the hash for hot-reload provider-identity checks only; it is
  `null` in product builds (`riverpod_generator.dart:32-33`). Functionally
  harmless when stale — but the CI gate (correctly) treats any diff as stale.
- `BuildYamlOptions` (`riverpod_generator-2.6.4/lib/src/models.dart`) offers
  only name prefix/suffix options. **There is no switch to disable the hash.**
  So the fix cannot be a config flag; it must be a gate that runs before the
  commit is created.

**Why it slipped twice:** the Session 20 workflow ran `build_runner` at step 11,
then kept editing the annotated controllers (steps 12–13, red-proof
iterations) without re-running it. The Session 20 note calling this
"cache-state-sensitive" drift (fix-schedule.md:358) is **superseded**: the
inputs are deterministic source text; the "cold vs warm" observation was a
symptom of edits made after the last generation, not of build cache state.

**Repo state today:** no active git hooks (`.git/hooks` has only `.sample`
files, `core.hooksPath` unset), no `.githooks/`, no `Makefile`/`justfile`,
`tool/` holds two Python asset generators only. README §"Quality gates"
documents the CI commands by hand.

## Privacy & threat notes

No user data, no network, no secrets. The hook runs local read-only tooling
(`dart run build_runner build`, `git diff`) inside the working tree. It does
not phone home, install anything, or touch files outside the repo. A hook is
executable code that runs on every commit, so it is committed, reviewed, and
opt-in (a one-time `git config core.hooksPath .githooks`) — git never
auto-activates tracked hooks, by design. `.fvm/` stays untracked.

## Investigation notes

- CI gate: `.github/workflows/ci.yml:57-64` — `dart run build_runner build
  --delete-conflicting-outputs` then `git diff --quiet -- '*.g.dart'
  '*.freezed.dart'`. Flutter pinned via `.fvmrc` (3.44.2); local `fvm`
  resolves the same SDK (`.fvm/flutter_sdk -> ~/fvm/versions/3.44.2`,
  Dart 3.12.2). Global `dart` on PATH is 3.11.0 — a DIFFERENT SDK, so the
  hook must use the pinned one, not whatever `dart` resolves to.
- Warm `build_runner build` on a clean tree: **~3 s, 0 outputs written**,
  tree stays clean → the hook cost is acceptable for every commit.
- Generated part files tracked: 24 `.g.dart`, 1 `.freezed.dart` (`git
  ls-files`); `part` directives agree. The CI glob already covers both.
- OSS reference for the pattern (tracked `.githooks/pre-commit` +
  `core.hooksPath`): Suwayomi/Suwayomi-Tsumiru `.githooks/pre-commit`
  (Flutter; stashes unstaged work, regenerates, re-stages). We adopt the
  tracked-hook + `core.hooksPath` wiring but **not** the auto-stash /
  auto-`git add .` behaviour — silently modifying the commit is the kind of
  magic AGENTS.md §0 forbids; we fail closed and tell the developer exactly
  what to run.
- `actions/checkout` latest is v7.0.1; v5.0.0's only change is Node 24
  (the exact deprecation CI annotates), v6 moved credential persistence to a
  separate file, v7 blocks fork-PR checkout on `pull_request_target`/
  `workflow_run` (we use neither). Verified via `gh api` release bodies.

## Proposed approach

Two small, independent changes plus documentation. No new dependencies.

1. **`.githooks/pre-commit`** (new, tracked, executable). Fails closed when:
   - an annotated source file is staged but its generated part is stale, or
   - a generated part is stale for any other reason.
   Logic: if any staged path is under `lib/` or `test/` and ends in `.dart`,
   run the pinned `dart run build_runner build --delete-conflicting-outputs`,
   then `git diff --quiet -- '*.g.dart' '*.freezed.dart'` — the SAME check
   CI runs, so local and CI can't disagree. On drift: print the changed
   files and the two commands to fix it (`git add <files>` then re-commit),
   exit 1. It never stages or stashes anything itself.
   Dart resolution order: `.fvm/flutter_sdk/bin/dart` (the pinned SDK) →
   `fvm dart` → `dart` on PATH with a loud warning that the SDK may differ
   from `.fvmrc`. Skips with a notice when no Dart is found rather than
   blocking commits on a non-Flutter machine (docs-only contributors).
   Escape hatch for emergencies: `git commit --no-verify` (standard git,
   nothing to invent).
2. **`.github/workflows/ci.yml`**: bump `actions/checkout@v4 → @v5` in both
   jobs. v5 is the minimum that clears the Node 20 deprecation annotation
   and is a one-line, behaviour-neutral change (verified release notes).
   Not jumping to v7: v6/v7 change credential-file and fork-checkout
   behaviour; neither is needed here and each is a separate review.
3. **README.md** §"Getting started": one-time
   `git config core.hooksPath .githooks` with a plain-English sentence on
   what the hook does and why. §"Quality gates": add the build_runner
   check so the documented local gates match CI 1:1.
4. **fix-schedule.md** §5: Session 21 entry; supersede the S20 "cold vs
   warm" observation with the verified root cause.

**Not doing (and why):** an auto-fix hook that stages regenerated files
(hidden mutation of the commit); a `Makefile`/`justfile` (new tooling for one
command; README + hook suffice); `lefthook`/`pre-commit` framework (new
dependency, AGENTS.md §9); changing the CI gate (it is correct — it caught
the bug).

## Decision points

- **D1 — hook activation:** git cannot auto-enable tracked hooks. Options:
  (a) opt-in via a documented one-time `git config core.hooksPath .githooks`
  (explicit, reviewable, standard); (b) a script that sets it (still needs a
  manual run; more surface). **Recommend (a)** — and I will run the `git
  config` on this clone only with your approval (§6: it mutates repo
  config).
- **D2 — hook strictness when no Dart SDK is found:** (a) skip with a notice
  (docs-only commits still work; CI remains the hard gate); (b) block.
  **Recommend (a)** — CI is the authoritative gate, the hook is the early
  warning.
- **D3 — checkout bump:** (a) `@v5` minimal; (b) `@v7` latest.
  **Recommend (a)**.
- **D4 — execution:** end-to-end, or pause at each decision point?

## Steps

- [x] 1. Baseline: `git status` clean tracked tree; HEAD = `origin/main` =
  `8ec79b0`; warm build_runner leaves no diff.
- [x] 2. Write `.githooks/pre-commit`; `chmod +x` (approved).
- [x] 3. Test the hook: (a) content edit in a non-annotated file → runs,
  passes; (b) comment-only edit inside `ImportController` → PASSES (hash
  unchanged — `toSource()` drops comments; assumption corrected, see
  Understanding); (b') one new private field inside `ImportController` →
  REFUSED, names `import_controller.g.dart`, prints the fix; (c) stage the
  regenerated file → passes; (d) only `PLAN.md` staged → exits 0 without
  build_runner; (e) `--no-verify` is core git. All edits reverted, hash
  `1794281c…` confirmed restored.
- [x] 4. `ci.yml`: `checkout@v4 → @v5` (2 places) + cross-reference comment.
- [x] 5. README: hook setup + why + quality-gate parity.
- [x] 6. fix-schedule.md Session 21 entry + §1 state block + §1.2 env fact.
- [x] 7. Gates: format 401/0; analyze 0; build_runner + generated-diff
  check clean; `git diff --check` clean; ci.yml parses. (`actionlint`,
  `shellcheck` not installed — `bash -n` only.)
- [x] 8. Commit `0a7cb84` (approved), pushed `8ec79b0..0a7cb84`. CI run
  `34627965432`: both jobs green, all 8 Flutter steps + 6 Rust steps ✓,
  coverage 70.91% (unchanged), **zero annotations** (Node 20 notice gone).
- [x] 9. `git config core.hooksPath .githooks` (approved) — repo-local
  only, global unset; hook found executable at that path.

## Out-of-scope observations

- `ExportController` has no keepAlive link (S20 obs. 2) — unchanged.
- `subosito/flutter-action@v2`, `dtolnay/rust-toolchain`, `Swatinem/rust-
  cache@v2` — not annotated by CI; left alone.
- `build_runner` warns `SDK language version 3.12.0 is newer than analyzer
  language version 3.9.0` — informational; a `flutter pub upgrade` decision
  for a future session, not this one.

## Result

**Decisions:** D1 (a) opt-in `core.hooksPath` · D2 (a) skip-with-notice
when no SDK · D3 (a) `checkout@v5` · D4 end-to-end.

**Assumption corrected mid-session:** I planned test 3(b) as "a comment
edit changes the hash". It does not — `toSource()` re-serialises the AST
without comments. A one-field addition does. Hook, README and this plan were
reworded before anything was committed. The hook's LOGIC was never wrong
(it diffs the generator's actual output); only my description of the
trigger was.

**Changes:** `.githooks/pre-commit` (new, executable) · `ci.yml` (checkout
@v5, step comment) · `README.md` (hook setup + gate parity) · `PLAN.md`.
Untracked, not committed: `fix-schedule.md` (S21 entry, §1 state, §1.2
env fact).

**Gates:** format 401/0 · analyze 0 · codegen diff clean · `git diff
--check` clean. Flutter/cargo suites not re-run (no Dart/Rust source
changed); CI on the push is the confirmation.

**Landed:** commit `0a7cb84` on `main` = `origin/main`; CI `34627965432`
green with zero annotations; hook active on this clone. Nothing pending.
