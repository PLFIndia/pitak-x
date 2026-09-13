# PLAN.md — Session 27 — N10-b: fuzzy-token cache in `planMerge`

Roadmap: `fix-schedule.md` §1 (NEXT = N10-b). Finding: `astra-review.md` N10
("Large-library operations run unbounded work on the UI isolate"), sub-item b
of the S26 breakdown (a→b→c→d→e). Pure domain; no API used by callers changes.

## Understanding

`planMerge` (`lib/features/library/domain/merge/library_merge_engine.dart`)
routes every incoming no-ISBN book that found no exact match into
`_bestFuzzyMatch` (`:316-339`). That function calls `tokenSet(c)` for EVERY
local no-ISBN candidate on EVERY call — the local pool's tokens never change
inside one plan, so a plan over I incoming and L local no-ISBN rows performs
I·L tokenisations (regex replace + lowercase + split + set build each) plus
I·L Jaccard set intersections. With the accepted 100,000-row import cap
(`import_limits.dart`) that is up to 10^10 of each, on whichever isolate runs
the plan (today the UI isolate — N10-c moves it; N10-b makes it cheap).

Re-verified this session (S26's line numbers still exact): `tokenSet(c)` at
`library_merge_engine.dart:327` inside the candidate loop; `localNoIsbn`
built once at `:185`; the only production caller is
`merge_library_use_case.dart:512` (`planMerge(local, incoming)`, no optional
args). `jaccard` (`:619-624`) and `tokenSet` (`:602-616`) are public and
tested directly (`library_merge_engine_test.dart:412-425`).

Semantics that MUST be preserved (the existing 40 engine tests pin them):
- best = the candidate with the highest Jaccard; among equal scores the
  EARLIEST candidate in `localNoIsbn` order wins (`score > bestScore`);
- candidates already in `claimedLocalIds` (by `id`) are skipped;
- an incoming row with an empty token set never matches;
- a hit requires `bestScore >= threshold`.

## Privacy & threat notes

- Pure domain: no IO, no network, no logging. Nothing new leaves the device.
- Untrusted input is the INCOMING file (M15-validated rows, ≤ 8000 chars per
  field). The index is built from LOCAL rows only; incoming tokens are used
  for lookups. Worst case per incoming row (every token hits a posting that
  lists every local book) is O(|tokens|·L) — never worse than today's
  O(L·|tokens|) scan, so a hostile file cannot make the new path slower than
  the old one.
- Memory: postings hold one `int` per (local candidate, distinct token) pair
  — bounded by the field caps × L, the same order as the token sets
  themselves.
- Threat model unchanged from N07: who can read the plan = the local user.

## Investigation notes

- Any candidate with a NON-ZERO Jaccard score shares ≥ 1 token with the
  incoming set, so scoring only the candidates reachable through an inverted
  index (token → candidate indices) is exact, not approximate: candidates it
  skips would have scored 0 and can never be `best` (`0 > 0.0` is false; the
  threshold is > 0 anyway). Tie-break is preserved by comparing
  `(score, -index)`: highest score, then lowest `localNoIsbn` index.
- `|A∩B|` falls straight out of the postings walk (count hits per candidate),
  so `jaccard` never needs the candidate's set at query time; the Jaccard
  formula moves into one private helper shared by the public `jaccard` and the
  index (single source of truth for the score).
- Lazy build: today a plan whose incoming rows ALL carry ISBNs performs zero
  tokenisations; the index is therefore built on the FIRST fuzzy query, not
  eagerly, so no plan does more work than before.
- Test seam: proving "each local candidate is tokenised once" needs to observe
  `tokenSet` calls. The codebase's pure-DI shape for this is an optional
  function parameter (`int Function()? clock` in the lookup/publish use cases,
  `DownscaleFn` in `FileEventsRepository`). `planMerge` gains
  `Tokenizer tokenizer = tokenSet` (a top-level function is a valid constant
  default). Production callers are untouched.
- Purity gate (`test/architecture/domain_purity_test.dart`): no new imports
  needed (`dart:core` only). `Random` in the equivalence TEST is the seeded
  non-secure one — test fixture determinism, not security randomness
  (AGENTS.md §6.4 applies to production code).
- OSS reference: the token → postings + per-candidate intersection count is
  the standard inverted-index set-similarity join (as in Lucene's
  `MinShouldMatch`/`MoreLikeThis` scoring and the `SetSimilaritySearch`
  literature); no external package needed, ~60 lines.

## Proposed approach

One private class inside the engine file, one optional parameter on
`planMerge`:

```
typedef Tokenizer = Set<String> Function(Book book);

MergePlan planMerge(List<Book> local, List<Book> incoming,
    {double fuzzyThreshold = kDefaultFuzzyThreshold,
     Tokenizer tokenizer = tokenSet});

class _FuzzyIndex {
  _FuzzyIndex(this._candidates, this._tokenizer);   // nothing computed yet
  late final List<Set<String>> _tokens = ...;        // tokenSet ONCE per candidate
  late final Map<String, List<int>> _postings = ...; // token → candidate indices
  _FuzzyHit? best(Set<String> incTokens, Set<int> claimed, double threshold);
}
```

`best()` walks the incoming tokens, accumulates `hits[candidateIndex]++`
from the postings, then for each touched candidate (skipping claimed ids)
computes `inter / (|inc| + |cand| - inter)` and keeps the highest score with
the lowest index on ties. `_bestFuzzyMatch` is deleted; `planMerge` holds one
`_FuzzyIndex` for the whole plan. `jaccard(a, b)` stays public and calls the
same `_jaccardFromIntersection(inter, |a|, |b|)` helper.

## Decision points

- **D1 — Inverted index or plain cache?** (a) cache + inverted index (the
  S26 table's "optional" part included): each incoming row scores only
  candidates sharing ≥ 1 token — exact, O(I·k) instead of O(I·L) comparisons;
  ~40 extra lines. (b) cache only: `tokenSet` once per candidate, still
  compares every candidate (I·L Jaccard). **Proposed (a)** — same
  correctness, covers the 100k×100k case the review cites.
- **D2 — Test seam.** (a) optional `tokenizer` parameter on `planMerge`
  (matches the repo's `clock`/`DownscaleFn` DI shape). (b) count via a global
  test hook. **Proposed (a).**
- **D3 — Execution mode.** (a) end-to-end; (b) pause at each decision point.

## Steps

- [x] 1. Baseline gates recorded (analyzer 0, format 405/0, Flutter 1589, cargo 32).
- [x] 2. PLAN.md written; D1–D3 asked.
- [x] 3. Regression tests (red on HEAD): tokeniser call counter (each local
      no-ISBN candidate tokenised ≤ 1× across many incoming rows; ISBN-only
      candidates never tokenised; all-ISBN incoming → zero tokenisations),
      randomised equivalence vs a brute-force reference (score + tie-break +
      claimed skipping), zero-overlap candidates never chosen, wall-clock
      guard on a synthetic 3k×3k no-ISBN plan.
- [x] 4. Implement `_FuzzyIndex`, `Tokenizer`, shared Jaccard helper; delete
      `_bestFuzzyMatch`.
- [x] 5. Gates: analyzer, format, full Flutter suite (detached), cargo
      (untouched → 32 stands), `build_runner` not needed (no annotated code).
- [x] 6. Result written; commit approval requested (paths listed below).

## Out-of-scope observations

1. `_bruteForceFuzzy` in the test file is a second copy of the OLD algorithm,
   kept deliberately as the oracle. If the engine's fuzzy semantics ever
   change on purpose (e.g. a different tie rule), the oracle must change with
   it — the equivalence test will say so loudly.
2. The postings walk allocates one `Map<int,int>` per incoming row. Fine at
   100k (~µs each); a reusable `List<int>` counter + touched-list would shave
   the allocation if profiling on a low-memory device ever shows it. Not done
   — no measurement says it matters.
3. `planMerge` still runs on the caller's isolate (the use case → UI isolate).
   N10-c moves it; N10-b makes the work it moves small.
4. `tokenSet` is still called once per INCOMING row (unavoidable — each row
   is seen once) and the JSON importer has already lower-cased/trimmed
   nothing for us; a shared normalised-title column would let the tokens be
   computed at import time instead. Speculative, not scheduled.
5. `jaccard(a, b)` remains public and is used only by the tests and the
   oracle; production scoring goes through `_jaccardFromIntersection`.

## Result

**N10-b DONE — committed `e79fca7`, pushed (`aa6a7b0..e79fca7 main`, fast-forward).**
Pre-commit codegen gate passed; CI run `34754461782` queued at push time
(result recorded in `fix-schedule.md` S27 log). Housekeeping commit follows
(README test count, this record).

- Red evidence: the two `tokenizer`-seam tests were **compile-red** on HEAD
  (`undefined_named_parameter` × 2); the wall-clock test was
  **behaviour-red** on HEAD — 3000 × 3000 no-ISBN plan took **22,126 ms**
  against a 5 s budget (probe file under `test/_tmp_red/`, removed). The
  fixed engine runs the same fixture in **66–87 ms** (3 timing probe runs,
  probe removed) — ~300×. Tie-break, claimed-skip, zero-overlap and the
  25-round seeded brute-force equivalence tests pass on both (they guard
  semantics, not speed).
- Gates at end: analyzer **0**; format **405 / 0 changed**; Flutter
  `--coverage` **1596 passed / 0 failed** (`/tmp/pitak-s27-flutter-final.txt`,
  EXIT=0, 0 `[E]`) — +7; cargo **32 passed** (Rust untouched, baseline
  stands); `git diff --check` clean; no `@riverpod`/`freezed` code touched →
  no `build_runner`, no `.g.dart` diff. Coverage **72.68%** (+0.03);
  `library_merge_engine.dart` 185/188.
- Privacy scan of the lib diff: no print/log/http/Uri/Platform/isolate
  added; the engine's imports are unchanged (two domain files), purity gate
  green.
- Decisions: D1 **(a)** inverted index; D2 **(a)** `tokenizer` parameter;
  D3 **(a)** end-to-end. No pause trigger fired. One tool slip corrected
  mid-session: `timeout` is not on macOS (exit 127) — the red-proof run was
  relaunched detached per the S16 pattern; no test result was inferred from
  the failed call.

### Commit paths

- `lib/features/library/domain/merge/library_merge_engine.dart`
- `test/features/library/library_merge_engine_test.dart`
- `PLAN.md`
