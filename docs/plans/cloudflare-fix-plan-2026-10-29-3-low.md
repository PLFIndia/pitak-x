# Cloudflare fix plan — Part 3: Low items, evidence and records (Phases 5–6)

[← Index](cloudflare-fix-plan-2026-10-29.md) ·
[Part 1 — High](cloudflare-fix-plan-2026-10-29-1-high.md) ·
[Part 2 — Medium](cloudflare-fix-plan-2026-10-29-2-medium.md)

Phase 5 finishes the remaining Low items and nits. Phase 6 collects the
real-host evidence and updates every record. File links are relative to
`docs/plans/`.

---

## Phase 5 — remaining Low items and nits

### L1 — pre-2026 account tokens can connect (D7 ★)

**Verified, partly.** Every unprefixed token goes only to
`/user/tokens/verify` with no fallback
([cloudflare_api_token.dart:86–88](../../lib/features/publish/domain/cloudflare/cloudflare_api_token.dart#L86-L88),
[setup_cloudflare_site.dart:72–75](../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L72-L75)).
That was a deliberate, recorded decision (handoff §7.1). Cloudflare's
[token formats](https://developers.cloudflare.com/fundamentals/api/get-started/token-formats/)
page says old user **and** account tokens are both 40-character strings, so
the shape cannot tell them apart.

**Fix.**
1. Domain: a non-secret `CloudflareApiTokenKind.legacy` for unprefixed tokens.
2. The logic lives in `setup_cloudflare_account.dart`; `begin` only
   delegates, because the orchestrator must not grow. For a legacy token, try
   the user endpoint first:
   - active → user route, as today;
   - inactive → "inactive token", no fallback;
   - 401/403 → account route: list accounts with the bounded call (on this
     route a 401 there also leads to manual Account ID entry), save nothing yet,
     and return a discovery flagged `accountVerificationPending`;
   - any other error → reported, no fallback.
3. `selectAccount` verifies at `/accounts/{id}/tokens/verify` for a pending
   non-`cfut_` token; the record is saved only after `active`. The controller
   passes the token only when verification is pending.
4. No log line or state names the token kind or the route taken.
5. Copy: "Cloudflare did not accept this older token as a personal token. If
   it belongs to an account, choose or enter that account to check it."

**Tests:** legacy verified as a user token → user route, saved; legacy 401 →
fallback, nothing saved; legacy then `/accounts` 403 → manual ID → account
verify active → saved; account verify 401 → reconnect copy, nothing saved;
timeout/5xx and inactive → no fallback; `cfut_` never falls back; `cfat_`
unchanged.

**Records ★:** Part M row reversing §7.1; ADR 0017 S7 wording.

### L6 — an events-only publish builds only the events

**Verified, partly.** Only the Cloudflare events path is affected; the GitHub
events path uses `PublishEventsUseCase` and never builds the catalogue. The
shared builder always reads the catalogue, periodicals, loan counts and
`library.json` (which fetches the live descriptor) and always builds the
catalogue
([publish_snapshot_builder.dart:65–161](../../lib/features/publish/application/site/publish_snapshot_builder.dart#L65-L161)).
The Cloudflare assembler then keeps only the events section and throws the
fresh catalogue away. So an invalid periodical link or a `library.json` read
failure blocks an events publish, and every local cover is re-read and spooled
for nothing.

**Fix.** `PublishInputs` groups the catalogue reads as a nullable
`CatalogueInputs`. `read(sections:)` reads only what was requested; `build()`
builds only the sections present. `PublishSnapshot.catalogue` becomes nullable
(the GitHub callers always have it). `CloudflareReplacementPreparation.readInputs`
takes the required sections and reuses earlier inputs only if they cover them.
A replacement, or the missing-hash path, still does a full complete read. This
keeps "one builder per section, one merge" and "one builder wiring"; the
deploy is still a whole-Worker snapshot, with the catalogue carried from the
trusted record.

**Tests:** an events-only read never calls `catalogueItems` or `libraryJson`;
an events publish succeeds despite an invalid periodical link; no covers are
read; a missing carried hash leads to replacement with a complete read.

### L9 — a failed prefs write never looks saved

**Verified.** `shared_preferences` 2.5.5's legacy API updates its in-memory
cache before the platform write
([prefs_publish_host_store.dart:90–98](../../lib/features/publish/infrastructure/prefs_publish_host_store.dart#L90-L98)).
After a failed `beginMove`, the cache says "pending" for the rest of the
session: the banner appears, Retry may retire the source, and a restart loses
the record. The settings and share-card stores share the pattern.

**Fix.** One helper, `lib/core/storage/prefs_write.dart`
(`writePrefsString`, plus bool and remove variants). It captures the previous
value, and on `false` or an exception writes it back through the same API
(`remove` if it was null), which restores the cache even if that write also
fails. It returns `Left(StorageFailure)`. Use it in the host journal, settings
and share-card stores. Rejected: `reload()` (depends on another platform read
succeeding); `SharedPreferencesWithCache` (also updates its cache first);
`SharedPreferencesAsync` (needs an async `load()` and a data migration).

**Tests:** a `false` result and a throw both restore the cache; a failed
journal save leaves `load()` returning the previous record; a failed
`beginMove` reports `retirementPending: false`.

### L10 — "Keep saved address" changes nothing on the kept row (D11)

**Verified.** Only `siteUrl` depends on the user's choice; name, pin, fetch
status and time are copied from the other address for both choices
([reconcile_library_move_use_case.dart:91–102](../../lib/features/network/domain/usecases/reconcile_library_move_use_case.dart#L91-L102)).
The comment at :93 says the opposite. A test asserts the current behaviour, as
does `docs/ARCHITECTURE.md` §5, so this is a spec change. Fingerprints are
public, so a spoof site can rename and re-pin a row the user chose to keep.
The card-scan path already writes nothing for "keep".

**Fix.** Keep → the canonical row is unchanged; the transaction only deletes
the duplicate placeholder. Use new address → unchanged: repoint, and apply
fetched facts only when `hasFetchedFacts` ("a card scan never clears a pin").
Fix the comments, the test and the architecture doc.

**Tests:** "keep deletes the duplicate and changes nothing"; "keep never
copies a spoofed pin"; the network controller test updated.

### L11 — the moved-page template is frozen per schema

**Verified.** `validatePending` re-renders against the **current** asset and
re-normalizes the name
([moved_html_builder.dart:55–83](../../lib/features/publish/infrastructure/moved_html_builder.dart#L55-L83)).
No test pins the template, so any later edit to `assets/publish/moved.html`
breaks every pending Retry. The placeholders inside the template's HTML
comment are substituted too (harmless, because escaped). The feature is
unreleased, so this can still be fixed at no cost.

**Fix.** Before release, take the braces out of the comment's placeholders
(finish or skip any pending move on the J.7 test phone first). Map each
schema to its own template (`{1: 'assets/publish/moved.html'}`); an unknown
schema fails validation; schema 1 renders the stored name as it is (M9). Add
`moved_page_freeze_test.dart`, pinning SHA-256 of the asset and of one
rendering; its failure message says "add `moved_v2.html` and bump the schema
instead". Rejected: a stored template hash (it would live in the same
untrusted store as the bytes).

### L13 — the token field is kept out of autofill and the keyboard's memory

**Verified** ([cloudflare_token_dialog.dart:83–116](../../lib/features/publish/presentation/widgets/cloudflare_token_dialog.dart#L83-L116)).
**Fix:** `autofillHints: null` (on Android this opts the field out of
autofill, so password managers do not offer to save the token);
`enableIMEPersonalizedLearning: false`; `await launchUrl`, with a snackbar if
it fails. **Test:** a widget test of the field's flags.

### L14 — account names: one shared safe-text rule, tolerant per item

**Verified.** Only C0 controls and DEL are rejected
([cloudflare_connection.dart:295–302](../../lib/features/publish/domain/cloudflare/cloudflare_connection.dart#L295-L302)),
so bidi, zero-width and line-separator characters reach the picker. One bad
name fails the whole discovery with no manual-account path
([setup_cloudflare_account.dart:23–29](../../lib/features/publish/application/cloudflare/setup_cloudflare_account.dart#L23-L29)).

**Fix.** Extract the forbidden-character rule from
[network_name.dart](../../lib/features/network/domain/value_objects/network_name.dart)
into one shared pure helper, and extend it with C1 controls, U+200B–U+200F,
U+2028/2029 and U+FEFF. Use it for account names. A bad name no longer fails
the list: it shows as "Account …{last 4 of id}" (saved as no name), and the
manual path stays offered. **Tests:** bidi, zero-width and separator names are
replaced; the list still shows; the manual path remains.

### L15 — the dev harness leaves the shipping entry point

**Verified.** `main.dart` imports `dev/cloudflare_aot_memory_app.dart` and
switches on `S8_MEMORY` ([main.dart:9](../../lib/main.dart#L9),
[:18–21](../../lib/main.dart#L18-L21)). **Fix:** move it to
`lib/main_dev_harness.dart`, run with `-t`, and update any script or doc that
uses the flag. **Test:** `main.dart` imports nothing under `lib/dev/`.

### L17 — one GitHub Pages wait budget

**Verified.** The GitHub-source retirement check still waits 12 × 5 s
([moved_site_verifier.dart:20–21](../../lib/features/publish/application/site/moved_site_verifier.dart#L20-L21)),
while the destination check waits 60 × 10 s since `1e11842`. **Fix:** a
shared `read_back_budget.dart` (Pages 60 × 10 s, default 12 × 5 s) and
`MovedSiteVerifier.gitHubPages`; DI gives the GitHub source the Pages budget.
Progress copy: "Verifying the old address… This can take a few minutes."
**Test:** an 81 s build verifies; Cloudflare keeps 60 s.

### RH2 — Worker-name case (D9)

**Cannot verify statically.** Cloudflare allows A–Z in Worker names and uses
the name as a DNS label, which ignores case, but does not document how API
lookups treat case. `targetId` keeps the case
([publish_target.dart:168](../../lib/features/publish/domain/publish_target.dart#L168))
while the address is lower-case, so one site can have two identities.

**Fix, safe either way.**
1. Keep the lenient parse for **stored** records; no rewrite. An existing
   mixed-case target was proven by read-back.
2. Add `CloudflareWorkerName.tryParseNew`, which requires lower-case. Use it
   for new entries, with a visible lower-casing formatter. Re-selecting the
   exact stored name stays allowed (M3). Copy: "Use lower-case letters,
   numbers and hyphens for the Worker name. Cloudflare uses it in your site
   address."
3. When `workerExists` says absent (setup, preflight, Skip), double-check
   with the documented `GET /accounts/{id}/workers/scripts`, reading only each
   `id`. A name that differs only in case refuses: "A Worker whose name differs
   only in letter case already uses this address. Choose another name." A
   failed listing fails closed. If Phase 6 shows Cloudflare ignores case, drop
   this step.

**Tests:** `tryParseNew` boundaries; upper case refused before any API call;
a case variant blocks the new-site path; a failed listing fails closed; a
stored mixed-case target still publishes.

### Nits and doc drift (N17)

| Item | Fix |
|---|---|
| `CloudflareApiExceptionKind.nameTaken` is never used ([cloudflare_api.dart:52](../../lib/features/publish/domain/cloudflare/cloudflare_api.dart#L52)) | Delete it |
| `'per_page': '50'` hard-coded ([http_cloudflare_account_api.dart:64](../../lib/features/publish/infrastructure/http_cloudflare_account_api.dart#L64)) | Use `CloudflareLimits.accountsPerPage` and note Cloudflare's maximum of 50. Pagination already exists, so no accounts are lost |
| Deploy port doc says "retry it once" ([cloudflare_api.dart:111](../../lib/features/publish/domain/cloudflare/cloudflare_api.dart#L111)) | Settled by L4 (Part 2): the dead `retry` value is deleted |
| Storage factory doc mentions macOS but sets no `mOptions` ([hardened_secure_storage.dart:13–16](../../lib/core/security/hardened_secure_storage.dart#L13-L16)) | macOS does not ship; make the doc say iOS, with a note to add `mOptions` and a test if desktop ever ships |
| Handoff §7.1 says prompt completers never carry the token | They do, briefly: `answerToken` completes the controller's completer with a `CloudflareApiToken` (a scoped, redacted type). Correct the doc and point to ADR 0007's accepted interval |
| Plan F.3 puts the route reconfirmation before the `deployed` save | The code's order (save first) is safer; record it in Part M |
| Guard comment says "exactly the pending destination" | Covered by M5 (Part 2) |
| Journal store comment says an unknown schema "reads as absent" ([prefs_publish_host_store.dart:36](../../lib/features/publish/infrastructure/prefs_publish_host_store.dart#L36)) | The code is right: it reads as **unreadable** (a typed `Left`). Fix the comment |
| `cloudflare_site_manifest.dart:404` says an unknown state is treated as `deployed` | The code discards the whole record, which is safer. Fix the comment |
| `network_providers.dart:52–53` mentions `GitHubConnectionController.publish` | That method no longer exists. Fix the comment |
| `PublishHostStateRepository.verifiedSiteUrl` ignores the migration save result (:172) | Harmless (the next read retries); document it |

---

## Phase 6 — real-host evidence, records and release

### 6.1 Real-host checks — run these early

They need no code. Run them on the disposable account as soon as Phase 0
lands. Each design in this plan is safe under either answer; the evidence
only lets you delete a fallback branch. Record every answer in handoff §12 and
a Part M row. Never paste a token, JWT, account id or raw body.

| Check | Record | Unblocks |
|---|---|---|
| `GET /workers/scripts/{name}` for a Worker that does not exist | HTTP status and error codes | L2's "script not found" code |
| `POST …/assets-upload-session` for a Worker that does not exist | Does it succeed? Does `GET /workers/scripts/{name}` then return 200 or 404? Route and preview settings after the session and after the first deploy. What the public marker URL returns before and after the deploy. Whether an abandoned session leaves a Worker behind. | RH1's baseline branch |
| Create a Worker named `MyLib`, then `GET` it as `mylib` | Does the API ignore case? | RH2 step 3 |
| A GitHub repo made private or deleted, read with the current token | Repo status; the public `books.json` status | RH3 |
| Optional: split one bucket into two upload requests | Is it accepted, and does the completion token still arrive? | H2's optional split |

### 6.2 New rows for the RELEASING §6.5 smoke matrix

| # | Check | Expected |
|---|---|---|
| 11 | Reconnect to a different Worker, then publish (H1, D1) | A `targetChanged` review names both addresses; the old Worker is untouched |
| 12 | Delete the Worker in the dashboard, reconnect to the same target, publish (H1) | A `workerMissing` review; the site comes back and verifies |
| 13 | First publish to a brand-new Worker after an API-subdomain setup (RH1) | Deploys without "stale" |
| 14 | Publish a library with a ≥ 40 MB bucket over a link throttled to ~1 Mbit/s (H2) | The upload completes; a forced stall fails with the "stopped making progress" copy and no resend |
| 15 | Switch tabs during a large publish (M1) | The publish completes |
| 16 | Rotate the token for the live site on the manual-subdomain path (M3) | No verification deploy; the live site is unchanged |
| 17 | Cancel a pending move; then, with a revoked token, finish without retiring (M4) | The old site stays active after Cancel; the stronger warning appears before Finish |
| 18 | The first move into a Cloudflare Worker that holds a setup marker (L16) | The "Replace and move" line appears |
| 19 | Publish after Cloudflare forgets a carried file (N1) | The `localBytesMissing` review can be confirmed and deploys |

### 6.3 Records to update

- **ADR 0017** (keep "Accepted"; add an "Amended" line with the date):
  Decision 5 and "5a" (M4); Decision 7 note (L3); Decision 8 (H2); the S7
  paragraph (M3, L1); the S8 paragraphs (H1 recreate and target rule, M2
  Option B and the documented read-back set, M10 anchor binding, L4 pending
  file, N15 preparation exception); Consequences (Cancel move).
- **ADR 0007:** the upload JWT string may now live up to an hour (H2).
- **Plan Part M:** rows 83 onward, one per changed decision: H1, N1/M10, M2
  (two rows), H2, M3, M4, L1, L4, the F.3 step order, and the real-host
  results.
- **Handoff:** §7.1 (L1, token-in-completer), §8 (M2, L4), §9 ("endpoints",
  Cancel move), §12 (evidence), §13 new bullets ("a pending move has three
  explicit exits", "a moved-page schema's template never changes",
  "verification uses the documented set").
- **`docs/ARCHITECTURE.md`:** §5 reconciliation wording (L10).
- **`CHANGELOG.md` `[Unreleased]`:** "Fixed" for every user-visible fix;
  "Changed" for the new reviews and dialogs (target changed, Worker missing,
  missing files, Cancel move, Finish without retiring).
- **README, PRIVACY and the in-app guide:** Cancel move and Finish without
  retiring; what happens to an old Worker after reconnecting elsewhere; the
  slow-connection messages.
- **RELEASING §6.5:** the rows in 6.2.
- **`SECURITY.md`:** no change. No fix adds a stored or entered secret.

### 6.4 Release gates

All must pass before the release build:
- build_runner leaves no diff; `flutter analyze` reports zero issues;
  `dart format --set-exit-if-changed` is clean;
- the full non-golden suite passes, including the architecture tests (the
  size ratchet with the setup entry deleted, the bare-catch rule, the new
  settings-future guard);
- the Linux golden workflow, since M4, M6 and M7 change the connection tile
  and the move banner (never commit a macOS-rendered golden);
- Rust, OSV and F-Droid purity, unchanged;
- the J.7 smoke matrix, including the rows in 6.2.
