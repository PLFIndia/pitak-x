# Active plan — optional ISBN lookup after scanning

## Understanding

Add a persisted Settings → Library switch that lets Add book and Add to
wishlist look up a scanned ISBN immediately. Default off preserves the current
behavior: scan fills only the ISBN and the user taps Lookup. Library quick-add
is a different routing flow and stays unchanged.

## Privacy & threat notes

- Immediate mode sends the scanned ISBN to the existing lookup services; the
  switch subtitle says so. Default off and unavailable settings fail closed to
  manual mode, so no new implicit network request occurs.
- Keep the existing ISBN validation, fixed safe lookup messages, empty-field-
  only metadata filling and explicit save. No credentials or new telemetry.
- Tests use fake scanners and lookup services; no camera or live service.

## Proposed approach

1. Add `lookupIsbnAfterScan` to the immutable settings snapshot, prefs
   repository and serialised controller setter; render the switch with the
   existing fixed-failure settings helper.
2. After a successful scan, each form reads the latest setting and calls its
   existing `_lookupIsbn` only when enabled. Reuse the existing scanner test-
   seam style so widget tests can emit synthetic ISBNs.
3. Test default-off, enabled immediate lookup, manual lookup in both modes,
   settings persistence/failure and unchanged quick-add routing.

## Steps

- [x] Baseline focused tests: 77 passed.
- [x] Persist and expose the setting; add the Settings switch.
- [x] Wire both scan flows without changing quick-add.
- [x] Add focused repository, controller and widget tests.
- [x] Run formatting, analysis and affected suites.

## Out of scope

- Changing lookup providers, metadata mapping, quick-add routing or save
  behavior; adding dependencies; live network/camera tests.

## Result

Implemented on `improvements`. `lookupIsbnAfterScan` persists in
SharedPreferences (default false) through the existing serialised settings
controller. Settings → Library has the new switch with explicit online-lookup
copy and fixed save-failure handling. The shared `IsbnLookupField` and
`scanIsbnForForm` keep both forms identical; enabled scans call the existing
lookup, manual Lookup remains available, settings load failure stays manual,
and a re-entrancy guard prevents overlapping automatic/manual lookups.
Quick-add is untouched. The scanner uses the established injectable camera
seam for tests. Guide, privacy policy and Unreleased changelog are updated.

Verification: 84 focused tests, then 1,124 affected tests, and finally the
complete non-golden suite: 5,860 passed. `flutter analyze lib test
integration_test`, formatting, architecture file-size ratchets and
`git diff --check` are clean. No live lookup, camera or production service was
used. Golden tests and device/camera validation were not run.

---

# Historical: `opt-fixes.md` remediation

## Understanding

Continue the `publishOptimisation` remediation from `HANDOFF.md`. Items 1–5 are
committed and green. Finish item 6's eight failing tests without weakening the
spooling invariant, then implement items 7–16 one finding at a time with focused
tests and the final hermetic verification gates.

## Privacy & threat notes

- Use only fake APIs, synthetic secrets, temporary directories and hermetic
  fixtures; never contact production services or open real user archives.
- Preserve fixed safe UI/log messages, complete snapshot proofs, exact owned
  deletions, expected-head compare-and-swap and artifact cleanup on every path.
- Native secret buffers must be wiped on success, validation failure and
  cancellation; tests must never print secret contents.

## Investigation notes

- The baseline focused run reproduces exactly eight failures: seven controller
  tests read cleared `DesiredFile.bytes`, and one use-case test expects a spool
  to exist even though a failed read correctly precedes lazy store creation.
- Item 6 production code and its other focused suites are already present in the
  working tree. `HANDOFF.md` and `opt-fixes.md` are untracked owner documents.

## Proposed approach

1. Resolve committed bodies in the controller fake exactly as the real writer
   does; assert zero disposals for pre-spool read failure and add a post-spool
   typed-failure disposal test.
2. Run the two focused files and then all publish tests; inspect generated and
   formatting diffs before requesting the separate item-6 commit approval.
3. Implement items 7–16 in guide order, keeping item 8 native work isolated and
   regenerating Riverpod output only after provider changes.
4. Run the focused suites after each finding, then the guide's final checks.

## Decision points

- The user's “go ahead” authorizes end-to-end implementation. Git mutations and
  other §6 actions still require their exact-command approval at the point of use.
- Fold the two pre-existing formatting-only diffs into item 6, as the handoff
  explicitly permits; keep `PLAN.md`, `HANDOFF.md` and `opt-fixes.md` out of it.

## Steps

- [x] Item 6: repair test doubles, add post-spool failure coverage, all publish tests green.
- [x] Item 7: lifecycle re-lock after picker suppression.
- [x] Item 8: Rust and Kotlin secret-buffer cleanup with native tests.
- [x] Item 9: web availability status handling and streamed byte cap.
- [x] Item 10: truthful sharing outcomes and unavailable/exception handling.
- [x] Item 11: retain restore terminal result until a new archive is chosen.
- [x] Item 12: gate QR join success on persisted identity.
- [x] Item 13: accessible provider-status contrast in both themes.
- [x] Item 14: await editable-field saves and follow external values safely.
- [x] Item 15: touch published-cover recency only on cache hits.
- [x] Item 16: share GitHub blob pacing across commits.
- [x] Final regeneration, analysis, formatting, focused suites and Rust checks.

## Out of scope

J11–J15, J17 and J19–J23; production-service checks; real credentials/archives;
Linux golden regeneration on macOS; device, TalkBack, biometric-prompt, native
heap-inspection and large-device performance validation.

Pre-existing lint from `e75410b` (item 10):
`lib/features/backup/presentation/pages/create_backup_page.dart:183` exceeded
the 80-character lint limit and failed `flutter analyze`. Fixed as the
one-line string split `e5e0179` (no copy change), because the final gate
required a clean analysis.

## Result

Item 6 is implemented and verified: the fakes resolve spooled upload bodies,
pre-read failure creates no store, post-spool typed failure and exceptions clean
up, and events preserve stored size through the shared artifact writer. The
full publish suite (2,339 tests), architecture suite, analysis, generated-code
regeneration, formatting and `git diff --check` are green; committed as
`ce452f4`.

Item 7 is implemented and verified. The grace-expiry regression failed before
the controller fix, then all 10 app-gate tests passed. Analysis, formatting and
`git diff --check` are clean; committed as `261dad2`.

Item 8 is implemented and verified. Every public Rust secret input now has a
`Zeroizing` owner before validation; Kotlin wipes rejected/cancelled inputs and
returned plaintext. Rust: 36 passed plus 2 ignored real-archive tests. Kotlin:
6 passed. Vault: 271 passed. Clippy, Rust formatting and `git diff --check` are
clean; committed as `e4c8b8d`.

Item 9 is implemented and verified. Only 404 or refused content now restores
inline tags; other HTTP/network failures retain the last accepted file. Actual
streamed bytes and declared length are capped at 1 MiB, over-cap streams are
cancelled before parsing, and no `arrayBuffer()` fallback remains. The real
viewer harness, 61 contract checks and all 2,339 publish tests pass; committed
as `81faa7c`.

Item 10 is implemented and verified. Backup success is described as a hand-off,
not proof of saving. Card/link shares close only on success; dismissed and
unavailable outcomes stay open, exceptions use fixed safe copy, and both
actions reset busy in `finally`. All 23 focused tests and all 2,588
backup-plus-publish tests pass, with clean analysis, formatting and
`git diff --check`; committed as `e75410b`.

Item 12 is implemented and verified (`4c649e0`). `CommunityLibrarySection`
passes `buildScanner` through to `QrScanPage` (existing camera test seam) and
shows "Joined library — now merge their file." only on a `Right` from
`setLibraryId`; a `StorageFailure` shows fixed save-failure/retry copy, keeps
the old identity and starts no merge. Three widget tests cover success,
failure and cancel; settings + architecture + QR suites: 119 passed.

Item 13 is implemented and verified (`b616fc0`). New `ProviderStatusColors`
in `provider_tile.dart` is the single source for success/warning/info/error;
light theme now uses green 800, deepOrange 900, blue 800 and red 800 (dark
shades untouched), used by the GitHub "Signed in" and Cloudflare "Token
verified" rows. Measured on the REAL indigo-scheme card (`#f5f2fa`), not
white: green 800 = 4.63, deepOrange 900 = 5.06, blue 800 = 5.19, red 800 =
5.08; dark pairs 5.74–12.15. `test/support/a11y.dart` gained `contrastRatio`
and `expectMeetsTextContrast`; 39 new tests pin every `ProviderConfig` in both
themes, expanded and collapsed, plus a pumped-card colour check. Reverting the
shades locally reproduced exactly six light-theme failures. Publish +
architecture: 2,422 passed.

Item 14 is implemented and verified (`5cc80bc`). `EditableTextField.onCommitted`
is now `Future<bool>` with a `_saving` guard: it collapses only on true, keeps
failed input in the editor, shows a spinner instead of the check while saving
(text stays editable) and follows external `initial` changes via
`didUpdateWidget` only when neither editing nor saving. `settings_write.dart`
exposes awaitable `saveSettingAndReport`; the fire-and-forget `saveSetting`
delegates to it and both Settings name fields use the awaitable form. Eight
widget tests plus two Settings-page tests; settings + core/widgets +
architecture: 165 passed.

Item 15 is implemented and verified (`c3ddcfe`). A repeat request whose cover
is still cached now updates `_usedAt` before the dedupe return; remembered
failures, queued misses, disabled consent and disposed sessions do not. No
Riverpod state is republished for recency. Two new tests (100-entry LRU with
cover 0 surviving without a refetch, failure-only dedupe not shielding the true
LRU); the LRU test fails on the pre-fix code. Network + architecture: 1,058
passed.

Item 16 is implemented and verified (`a228ec2`). `GitHubBlobPacer` in
`http_github_commit.dart` owns only the last blob-start timestamp and the
capped-backward-clock rule; `HttpGitHubApi` owns one and hands it to every
fresh `GitHubCommitWriter`. `gitHubApiProvider` is keepAlive with the
process-wide pacing justification and regenerated (`Provider<GitHubApi>`).
Tests: second commit waits the remaining second, >1s elapsed and a backward
clock behave, exactly one ref move per commit, and a DI test proves the
provider retains one pacer with no listener between commits. Publish + core/di
+ architecture: 2,473 passed.

Final hermetic gates (all green):
- `build_runner --delete-conflicting-outputs`: no generated drift.
- `flutter analyze lib test integration_test`: no issues.
- `dart format --set-exit-if-changed lib test integration_test`: clean.
- publish + network + architecture: 3,445 passed.
- backup + vault + settings + core/storage + core/widgets: 679 passed.
- viewer availability harness + availability parity contract: 61 passed;
  `node --check` clean on both JavaScript harnesses.
- Touched widget suites (cloudflare tile, QR join, editable fields, name
  fields, app-lock, backup copy truth, published cover/catalogue): 118 passed.
- Rust: `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test --release` → 36 passed, 2 ignored real-archive tests.
- `git diff --check` clean. No production service contacted, no real
  credential/archive/biometric used, no Linux goldens regenerated.

Still unclaimed: the full repository test run, golden tests, `cargo deny`,
device/TalkBack, real biometric prompts, native heap inspection, large-device
performance and the F-Droid runtime-classpath check.

Item 11 is implemented and verified. `RestoreController` is
`@Riverpod(keepAlive: true)` (the per-run `ref.keepAlive()` link is gone);
`clearResult()` returns to idle only while no restore runs; the page calls it
as soon as a new archive is picked. The page regression (pop after completion,
reopen, same failure shown; new pick clears it) failed on the pre-fix code and
passes now. Controller tests cover retained success/failure past the old
auto-dispose turn, `clearResult` idle/refused-while-running, duplicate refusal
and passphrase wiping. Backup suite + architecture: 287 passed; formatting and
`git diff --check` clean. Generated provider diff inspected
(`AutoDisposeAsyncNotifierProvider` → `AsyncNotifierProvider`).

Release 1.9.1+33: version metadata, README, CI changelog gate and developer
changelog moved from Unreleased. Changelogs 33/331/332 are 432 characters and
333 is 341 after the owner's edit; all pass
`tool/check_fastlane_changelog_chars.py 33` plus its six unit tests. `tool/release_build.sh --sentinel 'GitHubBlobPacer'` ran
its own `flutter clean` and completed in 221 seconds; the signed Play AAB is
`build/app/outputs/bundle/playRelease/app-play-release.aab`, package
`dev.khoj.pitaka`, versionName 1.9.1, versionCode 33, sha256
`f6250cf4082179205c899767d78f0b1cceb278b917e271bbe2ba51fbbaeb8e6c`.
Signature, package/version and fresh-Dart sentinel verification passed.

F-Droid housekeeping: the local recipe mirror was re-synced byte-for-byte with
upstream fdroiddata (1.8.0/313) in `8e9b8cf`; no manual 1.9.1 build blocks are
needed because the bot generates 331/332/333. The fdroid release runtime
classpath and a freshly built arm64 APK's DEX both have no
Google/Firebase/MLKit hits. Signed annotated tag `1.9.1` was verified against
the AAB and pushed together with the fast-forward of `origin/main` to
`8e9b8cf385a06b1e780449113758e95b39b4d74c`; remote tag dereference matches.

---

# Historical: Phase 5 — remaining Low items and nits (L1, L6, L9–L11, L13–L15, L17, RH2, N17)

## Understanding

Phase 5 of `docs/plans/cloudflare-fix-plan-2026-10-29-3-low.md`. Each finding is
a small correctness, security or truthfulness gap that survived the earlier
phases:

- **L1** — an unprefixed 40-character Cloudflare token went only to
  `/user/tokens/verify`. Cloudflare issued that shape for old **user and
  account** tokens, so a pre-2026 account token could never connect.
- **L6** — the shared builder always read the catalogue, periodicals, loan
  counts and `library.json`, and the Cloudflare assembler then threw the
  catalogue away. An invalid periodical link or descriptor failure blocked an
  events publish, and every cover was re-read for nothing.
- **L9** — `shared_preferences` updates its cache before the platform write, so
  a failed journal/settings/share-card write looked saved for the session and
  vanished on restart.
- **L10** — "Keep saved address" copied the other descriptor's name, pin and
  fetch status onto the kept row. The fingerprint is public, so a spoofed site
  could rename or re-pin a row the user chose to keep.
- **L11** — the moved-page template was not frozen: `validatePending`
  re-rendered against the current asset, so a later edit would break every
  pending Retry.
- **L13** — the pasted token could be offered for autofill and learned by the
  keyboard; the token-page button discarded its launch result.
- **L14** — account names rejected only C0/DEL, so bidi/zero-width/separator
  characters reached the picker, and one bad name failed the whole discovery.
- **L15** — `main.dart` imported the AOT memory harness and switched on
  `S8_MEMORY`, so the shipping entry point contained a harness.
- **L17** — a GitHub SOURCE retirement waited 60 s while a GitHub DESTINATION
  waited 10 minutes.
- **RH2** — Worker names may contain A–Z, but the address is a lower-case DNS
  label and the API's case behaviour is undocumented, so one site could have
  two identities.
- **N17** — doc drift and one dead enum value.

## Privacy & threat notes

- No new secret path. L1 holds a legacy token only inside the running async
  setup operation; a prompt answer may carry the existing `CloudflareApiToken`
  (scoped, redacted), never a raw `String`.
- The L14 rule is shared with library names and covers C0/C1 controls, DEL,
  zero-width and bidi characters, U+2028/2029 and U+FEFF. A replacement account
  label is displayed only and is never stored.
- L13 keeps the token out of autofill and IME learning.
- RH2 lists Worker **ids only**, bounded to four pages and 100 per page; a
  failed or truncated listing fails closed and writes nothing.

## Investigation notes

- `CloudflareApiToken.kind` mapped every unprefixed token to `user`;
  `setup_cloudflare_site.begin` had an explicit "no fallback" comment.
- `PublishInputs` had four mandatory catalogue fields; `PublishSnapshot.catalogue`
  was non-null; `read()` took `includeEvents`.
- `PrefsPublishHostStore`, `PrefsSettingsRepository` and
  `PrefsShareCardStyleStore` each repeated the cache-before-write failure.
- `ReconcileLibraryMoveUseCase` applied fetched facts for both choices; a test
  and `ARCHITECTURE.md` §5 pinned it.
- `MovedHtmlBuilder.render` normalized the stored name and loaded a hard-coded
  asset path; no test pinned the bytes.
- `MovedSiteVerifier` defaulted to 12 × 5 s; `CompleteSnapshotVerifier` had a
  Pages constructor.
- `workerExists` gates replacement consent, the new-site decision and Skip; no
  case check existed anywhere.

## Proposed approach

1. **L1:** `CloudflareApiTokenKind.legacy`; `beginCloudflareSetup` tries the
   user endpoint and falls back to the account route only on 401/403;
   `CloudflareAccountDiscovery.accountVerificationPending`; `selectAccount`
   verifies at the chosen account and saves only after `active`; fixed
   explanation copy. The account stage moved into `cloudflare_account_flow.dart`
   because the controller was already over its 500-line ratchet.
2. **L6:** nullable `CatalogueInputs` on `PublishInputs`, `read(sections:)`,
   nullable `PublishSnapshot.catalogue`, section-aware `readInputs` reuse. A
   replacement/missing-hash path still reads both.
3. **L9:** one `core/storage/prefs_write.dart` helper restores the previous
   cached value after `false`/throw; used by the host journal, settings and
   share-card stores.
4. **L10:** keep = no change to the canonical row; use-new applies fetched facts
   only when `hasFetchedFacts`; correct the comment, test and ARCHITECTURE.
5. **L11:** schema → frozen template map, unknown schema fails, renderer no
   longer re-normalizes, asset comment has no brace tokens, SHA-256 freeze test.
6. **L13:** explicit `autofillHints: null`, `enableIMEPersonalizedLearning:
   false`, awaited `launchUrl` with fixed failure copy.
7. **L14:** `core/text/safe_display_text.dart` shared by `NetworkName` and
   `CloudflareAccount`; hostile names become "Account …{last 4}" and are never
   stored.
8. **L15:** `lib/main_dev_harness.dart`; `main.dart` imports no `lib/dev/`.
9. **L17:** `read_back_budget.dart`; `MovedSiteVerifier.gitHubPages`; a
   host-selected progress line.
10. **RH2:** `tryParseNew`, a lower-casing dialog formatter, and
    `CloudflareWorkerNameGuard` (ids-only listing) in setup, preflight and Skip.
11. **N17:** delete `nameTaken`, use `CloudflareLimits.accountsPerPage`, fix the
    manifest/journal/DI/migration comments, record the prompt-completer truth.
12. **Records:** ADR 0017 amendment, Part M rows 109–119, the fix-plan index,
    handoff §7/§8/§9/§13/§17, CHANGELOG and the in-app guide's Worker-name
    sentence.

## Decision points

- **D7 = A**, **D9 = Yes**, **D11 = Yes** (the plan's recommended defaults).
- The legacy fallback is narrow on purpose: only 401/403 falls back, because an
  inactive token, a timeout or a 5xx says nothing about ownership.
- L10 keeps the fetched facts for "use new address" only when a descriptor was
  actually fetched; a card scan proves the address, not the facts.
- RH2 is safe under either API answer; Phase 6's real-host check may delete the
  listing step if Cloudflare proves names case-insensitive.

## Steps

- [x] L9: shared prefs write helper and the three stores.
- [x] L10: keep changes nothing; tests + ARCHITECTURE §5.
- [x] L11: frozen template map, non-normalizing render, SHA-256 freeze test.
- [x] L13: token field flags, awaited launch, failure snackbar.
- [x] L14: shared safe-text rule, tolerant account names.
- [x] L15: dev harness entry point, script/doc update, architecture test.
- [x] L17: read-back budget, GitHub source constructor, phase + copy.
- [x] RH2: new-name rule, listing port + adapter, guard in setup/preflight/Skip.
- [x] L1: legacy kind + fallback, account-stage split.
- [x] L6: section-scoped reads and nullable catalogue.
- [x] N17: nits and doc drift.
- [x] Tests for every item above.
- [x] Records: ADR 0017, Part M, CHANGELOG, handoff, guide, architecture.
- [x] Gates: build_runner, format, analyze, non-golden suite.

## Out of scope

- Phase 6 real-host evidence (Part 3 §6.1), the RELEASING §6.5 smoke rows, the
  Linux golden workflow and the release build.
- H2's optional bucket splitting.

## Result

Phase 5 is implemented end to end.

- **L1:** an old account token now connects through the account route after a
  401/403 from the user endpoint; the record is saved only after the chosen
  account verifies `active`; the picker explains why. The account conversation
  lives in `cloudflare_account_flow.dart` (controller 502 → 450 lines).
- **L6:** an events-only Cloudflare publish reads only the settings and events
  and carries the catalogue from the trusted record; replacements still read
  both sections.
- **L9:** a failed prefs write restores the previous cached value in the journal,
  settings and share-card stores.
- **L10:** keeping the saved address leaves the kept row untouched.
- **L11:** schema 1 is byte-frozen (asset + one rendering pinned); a future
  renderer must add `moved_v2.html` and bump the schema.
- **L13:** the token field is excluded from autofill and IME learning; a failed
  external open is reported.
- **L14:** one shared safe-text rule; hostile account names are replaced and
  never stored; the list and manual path stay.
- **L15:** the AOT harness has its own entry point; `main.dart` cannot select it.
- **L17:** a GitHub source retirement waits the Pages budget and says so.
- **RH2:** new names must be lower case; a case variant refuses the new-site
  path and Skip; a failed/truncated listing fails closed.
- **N17:** dead code and stale comments cleared.

Records: ADR 0017 amended (S7 legacy fallback, lower-case Worker names and the
case guard); Part M rows 109–119; the fix-plan index marks Phase 6 as the only
open phase; handoff §7.1/§8/§9/§13/§17; `CHANGELOG.md` Fixed/Changed/Security;
the in-app guide's Worker-name sentence.
