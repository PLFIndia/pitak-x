# Phase 5 — remaining Low items and nits (L1, L6, L9–L11, L13–L15, L17, RH2, N17)

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
