# Cloudflare publishing — implementation review (2026-10-29)

- **Reviewed:** branch `cloudflare` at `77e6acb` (merge-base with `main`: `e8c4d8e`), mainly the ~20k changed lines in `lib/` plus their tests.
- **Method:** static, read-only review. Three parallel sub-reviews covered the publish pipeline, setup/UI and moves. Their key findings were spot-checked against the code. No builds or tests were run.
- **Verdict:** the security core is strong (see "What looks solid"). **Nothing Critical was found.** No path leaks the API token or the upload JWTs. No path switches the share address to an unverified site, retires the old site before the new one is verified, or deletes a file the app did not write. The problems are mostly **dead ends a user cannot get out of**, robustness on slow networks, and a few gaps against the plan's own contracts.

Severity combines user impact with likelihood. Confidence is high unless stated. Each "Fix" is a suggestion, not a decision.

---

## High

### H1. A leftover Cloudflare publish record can block publishing forever

- **Where:** [publish_to_cloudflare_use_case.dart:190–198](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L190-L198>) returns `targetMismatch` when the stored record describes a different target. [:211–213](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L211-L213>) stops on `siteUnavailable`.
- **Why it never clears:** nothing ever resets the single `cloudflare_publish_manifest.json`. Disconnect clears only the credentials ([setup_cloudflare_site.dart:375](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L375>)), and choosing a Worker never touches the record.
- **Scenario (a):** disconnect, then reconnect with a different Worker, account or subdomain. Every publish now fails with "The saved Cloudflare target does not match this publish. Reconnect and verify…". Reconnecting cannot fix it.
- **Scenario (b):** the Worker is deleted in the dashboard, and the user reconnects to the same target with an API-readable subdomain, so setup deploys nothing. Every publish now returns `siteUnavailable`.
- **Impact:** the only way out is clearing app data, which also wipes the library unless it was backed up.
- **Contract:** the record's own doc says a record for another target "claims nothing… the file map is discarded" ([cloudflare_site_manifest.dart:12–15](<../../lib/features/publish/domain/cloudflare/cloudflare_site_manifest.dart#L12-L15>)). Handoff §13 repeats this, and [cloudflare_move_reader.dart:59–62](<../../lib/features/publish/application/cloudflare/cloudflare_move_reader.dart#L59-L62>) already does it. Plan R10 asks for an explicit recreate flow, and none exists.
- **Fix:**
  - Treat a record that does not describe the target as `CloudflareSiteManifest.empty`. The publish then becomes a new-site publish or a consented R4 replacement.
  - Send `siteUnavailable` into the R4 complete-snapshot confirmation.
  - Decide, and tell the user, what happens to the old Worker: it keeps serving the old site.
  - Add tests for both scenarios; none exist today.

### H2. Each upload bucket must finish within 60 seconds

- **Where:** [cloudflare_limits.dart:56](<../../lib/features/publish/domain/cloudflare/cloudflare_limits.dart#L56>) sets `uploadDeadline = 60 s`. It is used for bucket uploads ([http_cloudflare_deploy_api.dart:155](<../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L155>)) and for deploys ([:204](<../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L204>)).
- **How the limit applies:**
  - The transport passes the same value as both the per-phase timeout and the total deadline ([cloudflare_http_transport.dart:223–228](<../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L223-L228>)).
  - The first phase of `TimeoutHttpClient` includes sending the whole request body ([timeout_http_client.dart:108–121](<../../lib/core/network/timeout_http_client.dart#L108-L121>)).
  - Buckets are uploaded exactly as Cloudflare groups them ([cloudflare_bucket_uploader.dart:82–99](<../../lib/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart#L82-L99>)).
- **Numbers:**
  - The S2 trial saw a 41,984,000-byte bucket. Base64 makes that about 56 MB on the wire; the AOT memory run measured `requestBytes = 56,131,788`.
  - Finishing that in 60 s needs about 7.5 Mbit/s of sustained upload.
  - Each timeout is retried (3 attempts). A slow link therefore uses about 170 MB of mobile data and still fails, and the next publish starts again from zero.
- **Why tests missed it:** the J.7 smoke used a one-book site, and the memory scenario uploads to a loopback server.
- **Fix:**
  - Derive the deadline from the request size, for example 60 s plus bytes divided by a conservative floor such as 64–128 KiB/s, with a cap.
  - Replace the fixed total with an upload-progress idle timer that re-arms on every chunk the client pulls from the multipart stream.
  - Do not blindly retry a large bucket that timed out; tell the user.

---

## Medium

### M1. Switching tabs or leaving the page mid-publish cuts in-flight Cloudflare requests

- **Where:**
  - `cloudflareApiProvider` is auto-dispose and closes its HTTP clients on dispose ([publish_providers.dart:83–85](<../../lib/core/di/src/publish_providers.dart#L83-L85>)).
  - The publish, events and move controllers only `ref.read` their factories ([publish_controller.dart:164](<../../lib/features/publish/application/publish_controller.dart#L164>), [publish_events_controller.dart:92](<../../lib/features/events/application/publish_events_controller.dart#L92>), [move_site_controller.dart:74](<../../lib/features/publish/application/site/move_site_controller.dart#L74>)).
  - The only thing that keeps the API alive is the Connection tab: publish card → `publishSiteStatus` → connection controller → `setupCloudflareSite`. That tab is a plain `TabBarView` child ([publish_page.dart:49–50](<../../lib/features/publish/presentation/pages/publish_page.dart#L49-L50>)), so it is disposed whenever the user switches to "Basic info"/"Events" or leaves the page.
  - Riverpod 2.6.1 disposes a provider nobody listens to after a `read`, and `IOClient.close()` closes connections with `force: true`.
- **Effect** (the publish itself keeps running because the controller holds `keepAlive`):
  - Reads and bucket uploads retry, which re-sends the whole bucket.
  - The post-deploy route update has no recovery, so the user gets the "Version URLs may be public" failure.
  - A cut deploy goes into recovery and usually ends as "deploy uncertain". The next publish then asks for a whole-site replacement (see L4).
- **Fix:** make `cloudflareApiProvider` keepAlive (it holds no secrets). Alternatively, have each outer command hold a `ref.listen` on its factory for the whole operation, or let the use case create and close its own API per operation.

### M2. Read-back downloads the whole site after every publish

- **Where:** [cloudflare_publication_verifier.dart:75–81](<../../lib/features/publish/application/cloudflare/cloudflare_publication_verifier.dart#L75-L81>) checks every file in the record: all covers, HTML and JSON.
  - Files are read one at a time at full size, for up to 12 rounds of 5 s, with a 15 s limit per request ([bounded_published_site_verifier.dart:25](<../../lib/features/publish/infrastructure/bounded_published_site_verifier.dart#L25>)).
  - There is no total deadline, and the app-wide queue is held the whole time.
- **Docs:** ADR 0017 and handoff §8 list a narrower set: marker, `books.json`, descriptor or its 404, `events.json`, current posters and removed-poster 404s.
- **Impact:** a library with 1,000 covers downloads tens of MB after each publish, and setup, disconnect and moves are blocked meanwhile.
- **Dead end:** a `deployed` record must verify before the next deploy ([publish_to_cloudflare_use_case.dart:215–226](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L215-L226>)) and there is no fallback. One file that cannot be read in time blocks publishing.
- **Fix:** verify the documented set plus the site root, add a total deadline, and offer R4 replacement when an old `deployed` record keeps failing verification.

### M3. Reconnecting or rotating the token can take the live site offline

- **Where:** `begin` saves a fresh record as soon as the new token verifies ([setup_cloudflare_site.dart:82–87](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L82-L87>)). That drops the confirmed target and the per-Worker proof.
- **What goes wrong:** with a token that cannot read the account subdomain, picking the same live Worker goes through the marker-only verification deploy ([:318–341](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L318-L341>)). That deploy replaces every asset on the Worker, so the public catalogue is gone until a whole-site replacement publish.
- **Misleading copy:** the verification dialog says "Your other active site is not retired or changed" ([cloudflare_verification_dialog.dart:84–88](<../../lib/features/publish/presentation/widgets/cloudflare_verification_dialog.dart#L84-L88>)). That is false when this Worker *is* the active site.
- **Friction:** the Worker-name prompt is not prefilled, and `targetId` is case-sensitive.
- **Why it is likely:** the token dialog suggests setting an expiry, so token rotation is a normal event.
- **Fix:**
  - When the account and Worker equal the active/verified target, prove the address read-only from the existing live marker instead of deploying.
  - At minimum, warn and prefill the Worker name.
  - Don't persist the fresh record until setup finishes or the user explicitly chooses to replace it.

### M4. A pending move can get stuck forever

- **Where:**
  - While a move is pending, every publish is refused ([active_publish_target.dart:45–51](<../../lib/features/publish/application/site/active_publish_target.dart#L45-L51>)).
  - Skip needs working credentials for the exact old target *and* an authenticated "not found" from its host ([cloudflare_move_source.dart:278–297](<../../lib/features/publish/application/cloudflare/cloudflare_move_source.dart#L278-L297>), [github_move_source.dart:172–189](<../../lib/features/publish/application/github_move_source.dart#L172-L189>)).
- **Cases with no way out:**
  - The old account was deleted or its token revoked: the host answers 401/403, so Skip is refused.
  - The user cannot reconnect to that exact target.
  - Another phone published to the old site after the move was recorded: Retry fails with "source changed" every time, and Skip is refused because the site exists.
- **Copy:** the Skip dialog and plan D.4/D.6 promise Skip for "the account no longer exists" ([pending_move_banner.dart:88](<../../lib/features/publish/presentation/widgets/pending_move_banner.dart#L88>)).
- **Fix:** add "Abandon move", which clears the pending record and keeps the old host active. Alternatively, allow a strongly warned Skip when the old host can no longer be authenticated.

### M5. The pending-move guard runs only after remote writes

- **Where:** `selectWorker` saves the candidate and runs the verification deploy ([setup_cloudflare_site.dart:318–332](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L318-L332>)) before `_allowTarget` runs in `_finalize` ([:452–453](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L452-L453>)). `begin`, `selectAccount`, manual subdomain entry and `createSubdomain` replace the whole record with no guard at all.
- **Scenario:**
  - A Cloudflare → GitHub move is pending, and the retirement step asks the user to reconnect.
  - The user reconnects, enters the subdomain manually and picks the old Worker.
  - The verification deploy replaces the old site.
  - Retry then refuses ("source changed") and Skip refuses (the Worker exists), so the move is stuck.
- **Fix:** build the prospective target and run the guard before any save or remote write. During a pending move, only allow reconnecting to the exact recorded endpoint.

### M6. Setup can freeze when the Connection tab is off-screen

- **Where:** dialogs open only when the prompt *changes*, because `ref.listen` is used without `fireImmediately` ([cloudflare_connection_section.dart:30–36](<../../lib/features/publish/presentation/widgets/cloudflare_connection_section.dart#L30-L36>)). The tab is disposed while off-screen.
- **What goes wrong:**
  - A prompt raised while the tab is gone is never shown.
  - On return, the tile is in `awaitingInput`, so every button is disabled ([cloudflare_tile.dart:104–125](<../../lib/features/publish/presentation/widgets/cloudflare_tile.dart#L104-L125>)).
  - `_start` holds `keepAlive` ([cloudflare_connection_controller.dart:435–437](<../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L435-L437>)), so the tile stays stuck until the app restarts.
- **Fix:** use `listenManual(..., fireImmediately: true)` in `initState`, or re-show the pending prompt on mount. Add a Cancel action while waiting for input.

### M7. An unreadable Cloudflare record cannot be recovered inside the app

- **Where:**
  - The controller's `build()` throws when the read fails ([cloudflare_connection_controller.dart:49–55](<../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L49-L55>)).
  - The error tile only says "Restart the app" ([cloudflare_connection_section.dart:46–53](<../../lib/features/publish/presentation/widgets/cloudflare_connection_section.dart#L46-L53>)).
  - `_start` needs a loaded state, so Disconnect cannot run.
  - Publishing fails too, because the resolver returns the storage failure.
- **Triggers:** a schema mismatch after a downgrade ([secure_storage_cloudflare_credential_store.dart:49–53](<../../lib/features/publish/infrastructure/secure_storage_cloudflare_credential_store.dart#L49-L53>)), or a Keystore decrypt failure.
- **Fix:** offer "Forget Cloudflare connection" in the error state. `clear()` does not need to read the record.

### M8. Some errors are not `Exception`s and slip past the catch blocks

- **Where:**
  - `Failure` does not implement `Exception` ([failure.dart:11](<../../lib/core/error/failure.dart#L11>)).
  - After any failed settings write, `settingsControllerProvider.future` rejects with a `Failure` ([settings_controller.dart:94–99](<../../lib/features/settings/application/settings_controller.dart#L94-L99>)).
  - The move wiring reads the library name that way ([move_publish_providers.dart:133–134](<../../lib/core/di/src/move_publish_providers.dart#L133-L134>)). It does so after the destination is already published ([move_site_use_case.dart:223](<../../lib/features/publish/application/site/move_site_use_case.dart#L223>)).
  - [move_site_controller.dart:98](<../../lib/features/publish/application/site/move_site_controller.dart#L98>) catches only `on Exception`, so `busy` stays true and the error goes unhandled.
- **Ordinary publish (inferred, not traced end to end):** it has the same shape. `publishSnapshotBuilderProvider` awaits the same future, and [publish_controller.dart:76](<../../lib/features/publish/application/publish_controller.dart#L76>) catches only `on Exception`, so the card's spinner stays until the page is reopened.
- **Fix:** turn these into typed `Left`s where they are read; the settings controller already has a safe name read. Outer controllers should catch `on Object` and reset `busy` and state.

### M9. Some library names make every move fail after the new site is published

- **Where:** `normalizeMovedLibraryName` only trims ([move_plan.dart:22–25](<../../lib/features/publish/domain/site/move_plan.dart#L22-L25>)). The pending record rejects names over 256 UTF-16 units or with any control character, such as a pasted tab ([pending_move.dart:165–170](<../../lib/features/publish/domain/site/pending_move.dart#L165-L170>)).
- **Effect:** "move could not be recorded" ([move_site_use_case.dart:134–135](<../../lib/features/publish/application/site/move_site_use_case.dart#L134-L135>)) appears *after* the destination publish. Every Retry republishes and fails at the same point.
- **Fix:** validate in `prepare()`, or normalize (strip control characters, cap the length) before any write.

### M10. Replacement consent is not tied to what the user saw

- **Where:** `PublishReplacementSummary` has no remote anchor ([publish_result.dart:28–61](<../../lib/features/publish/application/publish_result.dart#L28-L61>)). On confirm, the use case only re-checks that a replacement is still required ([publish_to_cloudflare_use_case.dart:280–309](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L280-L309>)).
- **Scenario:** another device deploys while the dialog is open. The confirmed replacement overwrites it without asking again, although R4 says confirmation revalidates remote anchors.
- **Fix:** put `workerExists` and the marker id/state into the summary, and require them to match on confirm.

### M11. The `_disposed` reset from 48f6f14 does not cover per-operation state (confidence: medium)

- **Where:** [cloudflare_connection_controller.dart:41](<../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L41>) resets `_disposed` in `build()`. `_operationActive` and `_input` survive the reset.
- **Trigger:** an invalidation while a command is mid-flight. [publish_controller.dart:171–175](<../../lib/features/publish/application/publish_controller.dart#L171-L175>) invalidates the controller inside the queue, possibly with a setup command queued behind it.
- **What goes wrong:**
  - The next prompt is dropped: `_emit` does nothing ([:459](<../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L459>)), and the completer is never completed.
  - `_operationActive` stays true, so Connect, Continue and Disconnect silently do nothing ([:435](<../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L435>)).
- **Test gap:** the regression test only invalidates while idle.
- **Fix:** give each build a generation (cancel) token, and have `_awaitInput` and `_emit` refuse a stale one.

---

## Low

1. **Pre-2026 account tokens can never connect.**
   - Cloudflare's [token formats](https://developers.cloudflare.com/fundamentals/api/get-started/token-formats/) page says old account tokens are unprefixed 40-character strings.
   - Every non-`cfat_` token is verified at `/user/tokens/verify` with no fallback ([cloudflare_api_token.dart:86–88](<../../lib/features/publish/domain/cloudflare/cloudflare_api_token.dart#L86-L88>), [setup_cloudflare_site.dart:72–75](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L72-L75>)).
   - Fix: on a 401/403 for a legacy-shape token, offer the account path.
2. **`workerExists` treats any 404 as "no Worker"** ([http_cloudflare_deploy_api.dart:31–45](<../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L31-L45>)), because the body is discarded.
   - This one read gates replacement consent, the new-site decision and Skip.
   - Subdomain absence already requires 404 plus error 10007; do the same here.
3. **Version URLs are not always re-checked.** The gaps are:
   - the verify-only and repair paths ([publish_to_cloudflare_use_case.dart:215–273](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L215-L273>));
   - move Retry adoption ([cloudflare_move_source.dart:139](<../../lib/features/publish/application/cloudflare/cloudflare_move_source.dart#L139>), [cloudflare_move_destination.dart:186–189](<../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L186-L189>));
   - the final pre-deploy check ([cloudflare_publish_preflight.dart:58–77](<../../lib/features/publish/application/cloudflare/cloudflare_publish_preflight.dart#L58-L77>)).

   After a post-deploy privacy failure, a later "verified" result hides the warning.
4. **Uncertain deploys.**
   - Recovery is one immediate marker read and never returns `retry` ([cloudflare_publish_marker_probe.dart:74–93](<../../lib/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart#L74-L93>)).
   - The new publish id is saved only after the deploy returns ([publish_to_cloudflare_use_case.dart:432–446](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L432-L446>)).
   - So if a deploy landed but its response was lost, the next publish asks for a whole-site replacement.
   - Fix: persist a "deploying" record with the publish id before the PUT, and poll briefly.
5. **Temporary upload files are never cleaned up after a crash.**
   - `publish_artifacts/run-*` lives in Documents ([cloudflare_publish_providers.dart:59–65](<../../lib/core/di/src/cloudflare_publish_providers.dart#L59-L65>)). It is removed only in `finally` ([publish_to_cloudflare_use_case.dart:140–145](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L140-L145>)).
   - A killed publish leaves a full copy of the site behind, and iOS backs up Documents.
   - Fix: use the temp/cache directory and delete leftovers at the start of each queued operation.
6. **An events-only publish builds the whole catalogue** ([publish_snapshot_builder.dart:120–130](<../../lib/features/publish/application/site/publish_snapshot_builder.dart#L120-L130>)). Catalogue problems and remote cover fetches therefore block an events publish.
7. **Some outcome messages are misleading.**
   - When the old record verifies but its commit fails, an ordinary publish returns a verification "success" ([publish_to_cloudflare_use_case.dart:232–237](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L232-L237>)). The UI shows "Cloudflare accepted the deployment…" ([publish_status_copy.dart:17–21](<../../lib/features/publish/application/publish_status_copy.dart#L17-L21>)), but the new edits were never deployed.
   - "Retry verification" is offered when it cannot succeed: the `deployed` save failed and verification failed too.
   - The generic `on Exception` branches leave no debug log ([publish_to_cloudflare_use_case.dart:132–139](<../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L132-L139>), [setup_cloudflare_site.dart:504–507](<../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L504-L507>)).
8. **Some errors are classified wrongly.**
   - A non-JSON 5xx/429 body, such as Cloudflare's HTML error pages, becomes "Cloudflare returned an unreadable response." ([cloudflare_http_transport.dart:268–279](<../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L268-L279>)).
   - A hash mismatch inside the upload stream becomes a "network" error and is retried ([:229–238](<../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L229-L238>)).
9. **A failed prefs write still looks saved for the rest of the session.** Legacy `shared_preferences` updates its in-memory cache before writing ([prefs_publish_host_store.dart:91–93](<../../lib/features/publish/infrastructure/prefs_publish_host_store.dart#L91-L93>)). Fix: reload or restore the old value on failure.
10. **Reader side: "keep saved address" still copies the other address's name, map pin and fetch status** ([reconcile_library_move_use_case.dart:91–102](<../../lib/features/network/domain/usecases/reconcile_library_move_use_case.dart#L91-L102>)). That contradicts the comment on line 93. Fingerprints are public, so a spoof site can rename and re-pin a row the user chose to keep.
11. **The moved-page template is not actually frozen.**
    - `validatePending` compares against the *current* asset ([moved_html_builder.dart:66–83](<../../lib/features/publish/infrastructure/moved_html_builder.dart#L66-L83>)), and no test pins its hash. Editing `moved.html` later breaks every pending Retry.
    - The placeholders inside the template's HTML comment also get substituted ([moved.html:6–8](<../../assets/publish/moved.html#L6-L8>)). They are escaped, so this is harmless.
12. **Two move destinations ignore save results** ([cloudflare_move_destination.dart:284](<../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L284>), [github_move_destination.dart:155](<../../lib/features/publish/application/github_move_destination.dart#L155>)).
13. **Token dialog.**
    - `autofillHints` is left at its default, so password managers may offer to save the token.
    - There is no `enableIMEPersonalizedLearning: false` for when "Show token" is on ([cloudflare_token_dialog.dart:94–116](<../../lib/features/publish/presentation/widgets/cloudflare_token_dialog.dart#L94-L116>)).
    - `launchUrl` is not awaited.
14. **Account names are only loosely checked.** Only basic control characters are rejected ([cloudflare_connection.dart:295–302](<../../lib/features/publish/domain/cloudflare/cloudflare_connection.dart#L295-L302>)), so bidi, zero-width and line-separator characters reach the picker. One bad name fails the whole account list.
15. **A dev harness is wired into the shipping entrypoint** ([main.dart:9](<../../lib/main.dart#L9>), [main.dart:18–21](<../../lib/main.dart#L18-L21>)). It sits behind a compile-time flag and is tree-shaken, so it is not a runtime risk. Prefer a separate `-t` entrypoint.
16. **A move into an unknown Cloudflare state overwrites it without replacement consent** ([cloudflare_move_destination.dart:88–92](<../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L88-L92>)). Plan F.5.2/F.6 asks for a confirmation; the consent given at connect time partly mitigates this.
17. **The GitHub-source retirement check still waits 12 × 5 s** ([moved_site_verifier.dart:20–21](<../../lib/features/publish/application/site/moved_site_verifier.dart#L20-L21>)), while Pages builds were measured at 81 s. This is UX only, because Retry adopts the retirement.

**Nits:**
- `CloudflareApiExceptionKind.nameTaken` is never used ([cloudflare_api.dart:52](<../../lib/features/publish/domain/cloudflare/cloudflare_api.dart#L52>)).
- `'per_page': '50'` is hard-coded ([http_cloudflare_account_api.dart:64](<../../lib/features/publish/infrastructure/http_cloudflare_account_api.dart#L64>)).
- The deploy port's doc says "retry it once", but the transport allows two repeats ([cloudflare_api.dart:111](<../../lib/features/publish/domain/cloudflare/cloudflare_api.dart#L111>)).
- The storage factory's doc mentions macOS, but no `mOptions` are set ([hardened_secure_storage.dart:13–16](<../../lib/core/security/hardened_secure_storage.dart#L13-L16>)).
- Doc drift:
  - Handoff §7.1 says prompt completers never carry the token; they do, briefly.
  - Plan F.3's order of route reconfirmation and the `deployed` save differs from the code, and the code's order is safer.
  - The [pending_move_target_guard.dart:10](<../../lib/features/publish/application/site/pending_move_target_guard.dart#L10>) comment says "exactly the pending destination", but the code (correctly, per D.6/F.8) accepts either endpoint.
  - [prefs_publish_host_store.dart:36](<../../lib/features/publish/infrastructure/prefs_publish_host_store.dart#L36>) says an unknown schema "reads as absent"; it actually reads as unreadable.

## Needs a real-host check (not verified)

- **First publish to a Worker that does not exist yet.** The final pre-deploy check compares `workerExists` ([cloudflare_publish_preflight.dart:60–65](<../../lib/features/publish/application/cloudflare/cloudflare_publish_preflight.dart#L60-L65>)). The adapter comment says creating the upload session "may also create the Worker" ([http_cloudflare_deploy_api.dart:87–89](<../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L87-L89>)).
  - If that is true, the first publish after an API-subdomain setup always ends as "stale".
  - J.7 never ran this path, because the Worker was created by the verification deploy.
- **Worker-name case.** If Cloudflare matches script names case-insensitively, `workerExists("MyLib")` could miss an existing `mylib`, which would skip the replacement consent.
- **Skip's "not found".** Cloudflare answers 404 without error 10007 in some cases, and GitHub returns 404 for a private repo the token can no longer see.

## Test gaps

- a stored record for another target;
- recovery from `siteUnavailable`;
- the `deployed` save failing (the fake's `failSave` is never used in use-case tests);
- a positively retired site going to replacement;
- previews re-enabled between the pre-upload check and the deploy;
- the verification time budget;
- a large bucket timing out;
- `cloudflareApiProvider` being disposed mid-operation;
- a prompt raised while the Connection section is off-screen;
- an invalidation in the middle of an operation;
- the pending-move guard on any setup path other than `finishSetup`.

## What looks solid (keep it)

- **Secrets:**
  - The token is read only through a scoped `use()`, and `toString` is redacted.
  - It never enters Riverpod state, logs, the journal, the spool or the manifest.
  - It is stored as one versioned, bounded secure-storage record.
  - Upload/completion JWTs must be printable ASCII, so no header injection is possible.
  - Diagnostics are debug-only and contain only numeric codes.
- **Transport:**
  - Requests go only to the fixed API origin, and redirects are refused.
  - Responses are streamed with a 1 MiB cap and a JSON depth pre-scan.
  - Only numeric error codes are kept from responses.
  - Deadlines abort the request, and an uncertain write re-reads remote state before any retry.
- **Protocol** (all match Cloudflare's [Direct Uploads](https://developers.cloudflare.com/workers/static-assets/direct-upload/) guide):
  - The asset-hash formula matches Cloudflare's own example.
  - Empty `buckets` means the session JWT is the completion token.
  - The completion token is taken only from the final bucket.
- **Safety:**
  - Freshness is decided only from positive marker evidence.
  - Version URLs are gated before and after deploys.
  - Adopting an existing Worker needs consent, and a subdomain is created only on explicit availability.
  - The manifest fails closed, and saves are atomic.
  - Publish ids come from a CSPRNG.
  - There is one app-wide operation queue.
  - Moves never switch to an unverified destination or delete unowned files, and the moved page escapes the name and URL.
  - Android backup and device transfer are disabled.

## Suggested fix order

1. **H1 and M7.** They are dead ends whose only exit is clearing app data, and the fixes are small.
2. **M1 (one-line keepAlive) and M8 (catch-all plus a typed name read).**
3. **H2.** Make the upload deadline depend on size.
4. **M4, M5, M3.** Move and reconnect safety. Then M6 and M11 (setup controller robustness).
5. **M2, M9, M10,** then the Low items.
