# PLAN.md — Session 25 — N09: publish setup (existing-repo adoption, sign-out, pagination, one Pages URL resolver)

Roadmap: `fix-schedule.md` §1 (NEXT). Finding: `astra-review.md` N09
("Existing-repository setup and published URL handling are incomplete").

## Understanding

Four separate gaps, all in the publish feature:

1. **Advanced picker stores blindly.** `publish_page.dart:395-399` `_pickRepo`
   writes `setTargetRepo(fullName)` and nothing else — no ownership check, no
   Pages check. `SetupGitHubRepo` (the one-tap path) does verify+enable Pages,
   so the two ways of getting a target disagree: "connected" may not mean
   "ready to publish" (the review's "pushed publish without a working site").
2. **Sign-out keeps the target.** `_signOut` (`:367-375`) clears only the token.
   Sign in with a different account → the old `owner/repo` is still the target;
   a publish then fails late (or, with push rights to that repo, succeeds
   against another account's site).
3. **Repo list stops at 100.** `http_github_api.dart:131-137` sends
   `per_page=100` once and ignores the `Link` header.
4. **Two URL builders.** `publish_events_use_case.dart:202` hand-builds
   `https://$owner.github.io/$repo/events.html`; the library path and the
   drawer use `githubPagesUrlFor`. Neither handles a user-site repo
   (`owner/owner.github.io` → root URL `https://owner.github.io/`, from memory
   of GitHub Pages docs — verified behaviour, not a design choice), so the
   review's "helper handles account-root sites" is NOT true today either.

Root cause behind 1 and the S4 `defaultBranch` note: the branch we commit to is
the repo's `default_branch`, but the branch a Pages site serves is its
`source.branch`. They usually coincide (we enable Pages on the default branch)
but nothing guarantees it for an adopted repo.

## Privacy & threat notes

- Data leaving the device: the GitHub token, only to `api.github.com`
  (unchanged). New calls: `GET /repos/{o}/{r}`, `GET /repos/{o}/{r}/pages`,
  paginated `GET /user/repos`. No new hosts.
- Data minimisation: with D1-a the repo list is requested with
  `affiliation=owner` — the app never receives the user's collaborator/org
  repositories at all.
- Hostile input: every field parsed from GitHub responses is treated as
  untrusted. The Pages `html_url` (could be a custom domain, arbitrary text) is
  deliberately NOT used; the site URL stays derived by the pure resolver from
  `owner/repo`, which is validated (`[A-Za-z0-9._-]`) before it is stored.
  Branch names from the API are used only as URL path segments in later API
  calls → validated against a conservative charset before use.
- Failure copy: fixed sentences only; no response text reaches the UI (§5).
- Threat model: who can reach the target repo setting? Only this device's
  user (secure storage). What stops a token for account B publishing to
  account A's repo? D3-a (sign-out clears the target) + the adopt-time
  ownership check (owner == signed-in login).

## Investigation notes (verified this session, file:line current)

- `publish_page.dart:367-375` `_signOut`; `:377-393` `_loadRepos`; `:395-399`
  `_pickRepo`; `:135-141` post-sign-in only runs setup when no target stored.
- `setup_github_repo.dart:74-121`: create → 422 adopt → `defaultBranch ?? 'main'`
  → `enablePages` → store. Adopt path never reads the existing Pages config.
- `http_github_api.dart:131-149` `userRepos` single page; `:200-212`
  `defaultBranch` returns the repo's `default_branch`.
- `publish_library_use_case.dart:172-174` and `publish_events_use_case.dart:115-117`
  both `defaultBranch(...) ?? 'main'`; `:288-289` library uses the resolver;
  `:202` events hand-builds the URL.
- `github_pages_url.dart:10-15`: no root-site rule.
- `publish_credential_store.dart`: no `clearTargetRepo` on the port.
- GitHub OpenAPI (fetched 2026-09-12, then deleted from /tmp):
  `GET /repos/{o}/{r}/pages` → 200 `page{status: built|building|errored|null,
  source{branch, path}, build_type: legacy|workflow, html_url}` or 404;
  `POST` same path body `{source:{branch, path:'/'|'/docs'}}` → 201/409/422;
  `GET /repos/{o}/{r}` → `full-repository{owner.login, private, archived,
  default_branch, permissions{admin, push, pull}}` (permissions present for
  authenticated calls); `GET /user/repos` params `affiliation`, `per_page`
  (max 100), `page`; response header `Link` with `rel="next"`.
- OSS reference for pagination: `github` 9.17.0 (MIT, DirectCode)
  `lib/src/common/util/pagination.dart` `PaginationHelper.fetchStreamed` —
  follows `Link: rel="next"`, stops when absent. Adapted (bounded) below.
- Existing `GitHubApi` fakes: 6 in `test/` + 1 impl — any port change touches
  all six (mechanical).

## Proposed approach

**Domain (`github_api.dart`, `github_models.dart`, `github_pages_url.dart`)**
- `GitHubRepoDetails{fullName, ownerLogin, isPrivate, isArchived,
  defaultBranch, canPush, canAdmin}` + `GitHubApi.repository(owner, repo, token)`.
- `PagesSite{sourceBranch, sourcePath, isWorkflowBuild}` +
  `GitHubApi.pagesSite(owner, repo, token)` → null on 404.
- `defaultBranch()` REMOVED from the port: setup reads it from
  `RepoCreated`/`repository()`; publish paths use the Pages source branch.
- `githubPagesUrlFor`: root-site rule (`repo.toLowerCase() ==
  '${owner.toLowerCase()}.github.io'` → `https://owner.github.io/`) +
  `githubPagesFileUrl(ownerRepo, relativePath)` for `events.html`.
- `PublishCredentialStore.clearTargetRepo()`.

**Application**
- `SetupGitHubRepo`: shared `_verifyPages(owner, repo, defaultBranch)` —
  `pagesSite` null → `enablePages(defaultBranch)`; present → accept only
  legacy build with path `/`; else typed `ValidationFailure` with plain copy.
  New `adopt(token, fullName)`: `currentUserLogin` → `repository()` → owner
  must equal login (D1), `canPush`, not archived → `_verifyPages` → store LAST.
  The 422 path of `call()` goes through the same helper.
- `PublishLibraryUseCase` / `PublishEventsUseCase`: branch =
  `pagesSite.sourceBranch`; null → typed failure "GitHub Pages is turned off
  for this repository — set it up again in Connection." (closes the S4
  missing-branch note for good). Events URL via `githubPagesFileUrl`.

**Infrastructure (`http_github_api.dart`)**
- `userRepos`: `affiliation=owner` (D1-a), `per_page=100`, follow `Link
  rel="next"` up to `maxRepoPages` (D4); returns `RepoListing{repos,
  truncated}` so the page can say "showing the first 1000".
- `repository`, `pagesSite` parsers with strict types; branch-name charset gate.

**Presentation (`publish_page.dart`)**
- `_pickRepo` → `setupGitHubRepoProvider.adopt(...)` with busy state and the
  same `.match` shape as `_setUpNewRepo`; success copy "Connected to
  owner/repo — ready to publish!"; refusal copy from `ValidationFailure`.
- `_signOut` → `clearToken` + `clearTargetRepo`; `_targetRepo = null`.
- Truncation notice under the list when `truncated`.

## Decision points

- **D1 — Which existing repos may be picked?** (a) only repos OWNED by the
  signed-in account (`affiliation=owner`; adopt refuses others) — matches the
  one-tap path, URL is always `you.github.io/...`, fewer repos fetched;
  (b) any repo where the user has push+admin (org repos allowed).
  Recommend (a).
- **D2 — Pages verification depth.** (a) as proposed (enable if missing;
  require legacy build + path `/`; publish commits to the Pages source branch;
  `defaultBranch` port removed); (b) enable-if-missing only, keep committing to
  the default branch. Recommend (a) — (b) leaves the "pushed but not served"
  case open.
- **D3 — Sign-out semantics.** (a) clears token AND target (manifest kept:
  the last published site still exists publicly and the drawer link stays
  correct); (b) keep the target, re-check owner on next sign-in.
  Recommend (a) — explicit, fail-closed, one rule.
- **D4 — Pagination bound.** (a) at most 10 pages (1000 repos), list marked
  truncated; (b) unbounded until no `next`. Recommend (a) (§6.5 DoS bound).
- **D5** — execute end-to-end, or pause at each decision point?

**Answers (2026-09-12):** D1 → **(a)** owned repos only; D2 → **(a)** full
Pages check, publish to the Pages source branch, `defaultBranch` port removed;
D3 → **(a)** sign-out clears token + target, manifest kept; D4 → **(a)** ≤ 10
pages, `truncated` flag; D5 → **end-to-end**.

## Steps

- [x] 1. Baseline gates (analyze 0, format 404/0, Flutter 1516, cargo 32).
- [x] 2. Regression tests RED first (see Result for the red evidence).
- [x] 3. Domain: resolver (user-site rule, charset gate, `githubPagesFileUrl`),
      `RepoListing`/`GitHubRepoDetails`/`PagesSite`, `repository()`/`pagesSite()`
      on the port, `defaultBranch()` removed, `clearTargetRepo()` on the store,
      `gitHubPagesNotServingMessage`.
- [x] 4. Infrastructure: paginated `userRepos` (`affiliation=owner`, `Link`
      `rel="next"` page NUMBER only, `maxRepoPages = 10`), `repository`,
      `pagesSite`, branch-name charset gate, `_decodeMapSafe`.
- [x] 5. Application: `SetupGitHubRepo.adopt` + shared `_adoptOwned` /
      `_verifiedPagesBranch` (422 path uses the same rules); both publish use
      cases read the Pages source branch and refuse when Pages is off/re-pointed;
      events URL via the resolver.
- [x] 6. Presentation: `_pickRepo` → `adopt` with busy + typed copy; `_signOut`
      clears the target; truncation notice; list tiles disabled while busy.
- [x] 7. All 6 `GitHubApi` fakes + 2 `PublishCredentialStore` fakes updated.
- [x] 8. Gates (no `@riverpod` code touched → no `build_runner` needed; verified
      `git diff` shows no `.g.dart`/`providers.dart` change).
- [ ] 9. `fix-schedule.md` §1/§3/§5; commit approval (explicit paths).

## Out-of-scope observations

- Custom Pages domains (`cname`) are not surfaced — the derived URL is shown
  even when GitHub serves a custom domain. Bookmarks only accept
  github.io/pages.dev anyway.
- Manifest rebuild still degrades to an empty cache on read failure (S4/S5).
- `SecureStoragePublishCredentialStore` has 0/21 coverage (pre-existing; a
  `FlutterSecureStorage` fake test would close it — hygiene).
- Every publish now costs one extra `GET /repos/{o}/{r}/pages` round-trip
  (~200 ms). Acceptable for correctness; caching the source branch in the
  manifest would be a later optimisation if anyone notices.
- `_excerpt` (S22 obs.) still embeds ≤200 chars of GitHub body text in
  `PublishCommitHttpError.body` — unchanged, never shown to users.
- 7 `GitHubApi` fakes now live across test files; the S14–S24 shared
  `test/support/` fake note keeps growing (this session touched all of them).
- The `_pickRepo` "Checking …" status is briefly visible then replaced;
  a per-tile spinner would be nicer than disabling the whole list (N12-class
  polish).

## Result

**Regression tests — red evidence**
- `test/features/publish/github_pages_url_test.dart` +10: `githubPagesFileUrl`
  compile-red; user-site rule and owner-charset rule **behaviour-red on HEAD**
  (probe: `me/me.github.io` → `https://booklover.github.io/booklover.github.io/`;
  `evil.example/repo` → `https://evil.example.github.io/repo/`).
- `test/features/publish/http_github_api_test.dart` +22 (pagination 7,
  `repository` 6, `pagesSite` 9) — compile-red (`RepoListing`, new methods).
- `test/features/publish/setup_github_repo_test.dart` rewritten: 33 (was 18) —
  `adopt` group 14 + 422-path group 3 compile-red; the old "unknown branch
  falls back to main" case deleted (the fallback WAS the S4 bug).
- `test/features/publish/publish_library_use_case_test.dart` +5,
  `publish_events_use_case_test.dart` +3 — compile-red (fakes implement the
  new port); the user-site URL assertions would be behaviour-red on HEAD's
  resolver (same probe as above).
- `test/features/publish/publish_page_test.dart` +7 — **5 behaviour-red against
  a HEAD-shaped graft** of the page (pick stores without adopt; sign-out keeps
  the target; no truncation notice; not-owned and `/docs` repos stored), 2
  green-by-design guards (complete list → no notice; list failure → safe copy).

**Gates at end:** analyze **0**; format **404 / 0 changed**; Flutter
`--coverage` **1576 passed / 0 failed** (`/tmp/pitak-s25-flutter-final.txt`,
EXIT=0, 0 `[E]`); cargo **32 passed**, 2 expected ignored; `git diff --check`
clean; no `.g.dart` / `providers.dart` diff (no annotated code touched).
Coverage **72.60%** (+0.71); `github_pages_url.dart` 21/21,
`setup_github_repo.dart` 57/57, `http_github_api.dart` 208/246,
`publish_events_use_case.dart` 55/58, `publish_library_use_case.dart` 98/115,
`publish_page.dart` 316/348. Lib-diff privacy scan: no print/log/Platform/
`Uri.parse`; the only new URL literals are the resolver's `https://<host>/`
builders over a charset-validated owner/repo.

**What changed, in plain words**
1. The advanced picker now goes through the SAME checks as one-tap setup:
   the repo must be yours, pushable, public, not archived; Pages is turned on
   if off, and refused (with instructions) if it serves `/docs` or a workflow.
   The target is stored only after every check passes.
2. Sign-out forgets the target with the token. The manifest is kept so the
   drawer's share link keeps pointing at the site that still exists.
3. The repo list fetches only OWNED repos, follows GitHub's pagination up to
   10 pages, and tells the user when it stopped early.
4. One resolver builds every published address; user sites
   (`owner/owner.github.io`) resolve to the account root; events reuse it.
5. Both publish paths commit to the branch Pages ACTUALLY serves (read live)
   and refuse with a fixed message when Pages is off — closing the S4
   "defaultBranch fallback can select a missing branch" note.

**OSS credit:** pagination adapted from `github` 9.17.0 (MIT, DirectCode)
`PaginationHelper.fetchStreamed`; deliberately narrowed to take only the page
NUMBER from the `Link` header and re-issue against our own API base. Pages
response shapes verified against GitHub's official OpenAPI description
(2026-09-12), not memory.

**Assumptions flagged:** (1) GitHub's user-site rule (`<login>.github.io`
repo → root URL) is from the Pages docs, not re-fetched this session — it is
long-standing and low-risk, but a device pass on a real user-site repo would
confirm. (2) A `build_type` missing from `GET /pages` is treated as `legacy`
(older API shape); a `PagesSite` with an unknown `build_type` string throws.

### Commit paths (explicit, never `-A`)

```
lib/features/publish/application/publish_events_use_case.dart
lib/features/publish/application/publish_library_use_case.dart
lib/features/publish/application/setup_github_repo.dart
lib/features/publish/domain/github_api.dart
lib/features/publish/domain/github_error_messages.dart
lib/features/publish/domain/github_models.dart
lib/features/publish/domain/github_pages_url.dart
lib/features/publish/domain/publish_credential_store.dart
lib/features/publish/infrastructure/http_github_api.dart
lib/features/publish/infrastructure/secure_storage_publish_credential_store.dart
lib/features/publish/presentation/pages/publish_page.dart
test/features/publish/github_device_flow_test.dart
test/features/publish/github_pages_url_test.dart
test/features/publish/http_github_api_test.dart
test/features/publish/publish_controller_test.dart
test/features/publish/publish_events_use_case_test.dart
test/features/publish/publish_library_use_case_test.dart
test/features/publish/publish_page_test.dart
test/features/publish/setup_github_repo_test.dart
PLAN.md
```
