# PLAN.md — current task

Roadmap: `fix-schedule.md`. Session 4, **M01 COMPLETE, uncommitted**.
User approved end-to-end execution and clarified that the app creates repos.
Use the existing auto_init setup flow; do not add another initialization path.

## Understanding
- Prevent GitHub publication from deleting unrelated branch files after a failed
  head/commit lookup. An existing head must always supply a known `base_tree`.
- Start/current HEAD: `3b44f4f`. Resume state matched the checkpoint (PLAN.md
  only); astra-review.md and fix-schedule.md stay intentionally untracked.
- Scope: commitFiles head/base-tree resolution, its tests and contract comments.
  M10, M14 and manifest-cache policy are not part of this task.

## Privacy & threat notes
- A failed read must cause no blob/tree/commit/ref writes, not an orphan tree
  committed over existing content. Validate response shape before using SHAs.
- No new data collection, logging, permissions, credentials or persistence.
- Existing callers map HTTP errors and GitHubApiException to fixed UI messages;
  never expose response bodies or tokens in new diagnostics.
- Tests use mock HTTP only. No live GitHub mutations are authorized.

## Investigation notes
- Before changes, M01 evidence matched http_github_api.dart:266–269, :295 and
  :371–381: null commit lookup could omit base_tree but retain the existing
  parent and advance the ref. Malformed 200 ref responses could bootstrap too.
- Original tests covered success, ambiguous 404 bootstrap, and blob 403, but not
  failed commit lookup. Library/events callers already handle typed failures.
- CORRECTION to the first plan: the GitHub REST reference docs list 404 as
  Resource not found and 409 as Conflict. Neither status alone proves emptiness.
  They also explicitly prohibit creating references in empty repositories,
  even with an existing commit SHA. The previous plan's claim that 404/409 were
  documented positive empty-repo signals was incorrect; do not implement it.
- Source verified from the documentation fetched earlier in this session:
  https://docs.github.com/en/rest/git/refs?apiVersion=2022-11-28
  Cached document: /tmp/gh_refs.html, sections Get/Create a reference.
- createUserRepo already sends auto_init: true (http_github_api.dart:162).
  Re-read SetupGitHubRepo: creation precedes Pages setup and target persistence.
  User confirmed this existing workflow; no additional bootstrap is needed.

## Proposed approach (implemented; supersedes first plan)
- Require an existing, readable branch and its commit tree before all writes.
  Return HTTP failures for every non-200 preflight response, including 404/409;
  reject malformed response bodies and missing/invalid SHAs safely.
- Remove the ambiguous no-head/bootstrap path. Tree always has base_tree,
  commit always has the verified parent, ref update always uses force: false.
- Keep the implementation explicit; no _EmptyRepo type or speculative bootstrap
  abstraction is needed if only verified existing heads are supported.
- Preserve the existing domain error contract; use the established guarded HTTP
  pattern for transport errors. Manifest rebuilding remains separate.
- Canonical reference: GitHub REST Git references documentation above. No OSS
  algorithm or cryptography needed for this bounded control-flow fix; no deps.

## Decision points
- End-to-end execution: APPROVED.
- Resolved by user clarification: the app already lets users create the repo.
  Preserve that auto_init flow; require a readable existing branch at publish.
  No new initialization UX/API workflow. Commit approval remains separate.

## Steps
- [x] Verify repository state, evidence, callers and baseline gates.
- [x] Correct unsupported bootstrap assumption; record checkpoint before coding.
- [x] Resolve bootstrap question using the existing app repo-creation flow.
- [x] Write failing mock regressions first: ref and commit HTTP errors, malformed
  bodies, transport failures; assert no writes and no ref movement.
- [x] Implement approved preflight invariant; test preservation of unrelated
  files via base_tree, parent and non-forced ref update assertions.
- [x] Run focused/full tests, analyzer, formatter and Rust gates.
- [x] Update tracker/result; present explicit-path commit approval request.

## Out-of-scope observations
- headTreeShas and its caller treat manifest-rebuild failure as empty cache.
  This can lose cover-reuse information, not just cause redundant uploads.
- defaultBranch failures still fall back to main. M01 now rejects a missing
  branch rather than creating an orphan; broader branch/Pages resolution remains
  N09. The initial plan overstated the old behavior's safety.

## Result
- M01 implemented in http_github_api.dart:247–370; contract documented in
  github_api.dart:213–220. No setup/UI/cache-policy changes.
- New http_github_publish_preflight_test.dart contains 65 tests. Original 500
  reproduction FAILED before fixing: blob/tree/commit/ref writes occurred.
  Initial 58-test matrix: 12 passed / 46 failed before the fix. Existing API
  tests updated for real SHA-shaped fixtures and fail-closed missing-ref behavior.
- End gates: analyzer 0 issues; format 337 files/0 changed; full Flutter with
  coverage 945 passed/0 failed (65 new); Rust 30 passed/0 failed, 2 expected ignored.
  Baseline: 880 Flutter, 30 Rust, analyzer clean, format 336 files/0 changed.
- Coverage: preflight 13/13 lines; SHA parser 6/6; commitFiles 48/50 (96%).
  No annotated edits or generated diffs. Manual diff/security review: no new
  logging, secrets, permissions, persistence, or endpoints; boundary validation
  strengthened. Four overlong-line analyzer findings corrected and rechecked.
- No pending failed checks. No commit, installation, destructive command or live
  API write. Mock verification only, not a live GitHub publication. Commit approval
  is the remaining optional action; next remediation task is M10.
