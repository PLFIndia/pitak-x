# Cloudflare fix plan — Part 2: Medium (Phases 3–4)

[← Index](cloudflare-fix-plan-2026-10-29.md) ·
[Part 1 — High](cloudflare-fix-plan-2026-10-29-1-high.md) ·
[Part 3 — Low](cloudflare-fix-plan-2026-10-29-3-low.md)

Phase 3 makes moves and reconnects impossible to strand or overwrite. Phase 4
makes verification and messages tell the truth. Both assume Phase 0 and
Phase 1 have landed. File links are relative to `docs/plans/`.

---

## Phase 3 — moves and reconnects (L2, RH3, M5, M4, M3, M6, M11)

Land L2 first: M4's new Skip rules depend on a trustworthy "not found".

### L2 + RH3 — "not found" means not found

**Verified.** `workerExists` treats any 404 as "no Worker", because the
status-only read discards the body
([http_cloudflare_deploy_api.dart:31–45](../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L31-L45)).
This one read gates replacement consent, the new-site decision and Skip. A
test pins the current behaviour. Subdomain absence already requires a 404
plus error code 10007
([http_cloudflare_account_api.dart:107–113](../../lib/features/publish/infrastructure/http_cloudflare_account_api.dart#L107-L113)).
GitHub's repo lookup treats a 404 as gone and follows a 301
([http_github_api.dart:207–211](../../lib/features/publish/infrastructure/http_github_api.dart#L207-L211)).
GitHub also answers 404 for a private repo the token can no longer see.

**Root cause:** "absent" is decided from a status code alone on both hosts.

**Fix.**
1. **Cloudflare:** the status-only path discards only 2xx bodies (a script
   body can be large); a 404 goes through the bounded JSON parser. Return
   "absent" only for a 404 with `success: false` and the "script not found"
   code. No document confirms that code; treat it as 10007 until the Phase 6
   real-host check records it. Any other 404 throws a typed `notFound`, and an
   HTML 404 is malformed. Both fail closed.
2. **GitHub:** "absent" requires a repo 404 **and** a real public 404 for
   `books.json` at the exact old address, read with redirects off. An
   unreadable read does not count; a 301 means "inaccessible", not "gone".
   Public absence alone never authorizes anything (handoff §13).
3. Update the port doc ([cloudflare_api.dart:164](../../lib/features/publish/domain/cloudflare/cloudflare_api.dart#L164)).

**Tests:** replace the pinned test: 404 + 10007 → absent; a bare 404 → typed
`notFound`; an HTML 404 → malformed; a 2xx body is still never read. Preflight,
setup and Skip treat an ambiguous 404 as unknown. GitHub: "repo 404 while Pages
still serves `books.json`" → present; "301" → inaccessible.

### M5 — the pending-move rule runs before any save or remote write

**Verified.** `selectWorker` saves the candidate and runs the verification
deploy
([setup_cloudflare_site.dart:318–332](../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L318-L332))
before `_allowTarget` runs in `_finalize` (:452–453). `begin`,
`selectAccount`, the manual subdomain and `createSubdomain` replace the whole
record with no guard. So reconnecting during a pending move can deploy a
verification marker over the move's old Worker, after which Retry says
"source changed" and Skip refuses.

**Root cause:** the guard checks a finished target, but setup writes partial
targets long before one exists.

**Fix.**
1. A `CloudflareSetupConstraint` derived from the journal's pending move: the
   exact account, subdomain and Worker of its Cloudflare endpoint. Every
   cross-host move has exactly one.
2. Every setup command checks its input against the constraint **before**
   any credential save or remote write. Reads stay allowed (token verify,
   account list, subdomain read, `workerExists`). A mismatch returns
   `MoveSiteMessages.targetMismatch` with nothing written.
3. If the constrained endpoint is the move's **old** target, setup may only
   re-authorize it read-only, never deploy to it. M3's proof path below makes
   that possible.
4. During a pending move, prefill the prompts from the constraint and say why:
   "Reconnect to {address} to finish your move."
5. Fix the guard's comment ([pending_move_target_guard.dart:10](../../lib/features/publish/application/site/pending_move_target_guard.dart#L10)):
   it accepts **either** endpoint, which is correct per plan D.6/F.8. Change
   "destinations" to "endpoints" in handoff §9 too.

**Tests:** one per setup path (begin, account select, manual account, manual
subdomain, create subdomain, Worker select, finish). A wrong account,
subdomain or Worker during a pending move writes nothing and makes no remote
write. The old endpoint never receives a verification deploy.

### M4 — every pending move has a way out (D5 ★)

**Verified.** Every publish is refused while a move is pending
([active_publish_target.dart:45–51](../../lib/features/publish/application/site/active_publish_target.dart#L45-L51)).
Skip needs exact working credentials **and** an authenticated "not found"
([cloudflare_move_source.dart:278–297](../../lib/features/publish/application/cloudflare/cloudflare_move_source.dart#L278-L297),
[github_move_source.dart:172–191](../../lib/features/publish/application/github_move_source.dart#L172-L191)).
The journal has one phase, `retirementPending`, and two transitions,
`beginMove` and `finishMove`
([publish_host_state.dart:79–102](../../lib/features/publish/domain/site/publish_host_state.dart#L79-L102)).
Dead ends: a deleted account or revoked token (401/403); no way to reconnect
to the exact target; another phone published to the old site ("source
changed", and Skip refuses because the site exists); disconnecting without
reconnecting; **N11**, a renamed GitHub repo (the followed 301 makes Skip see
it as existing, and Retry verifies a dead Pages address). **N10:** a GitHub
401/403 reads "The publishing service could not be reached." The Skip dialog
promises Skip for "the account no longer exists"
([pending_move_banner.dart:87–92](../../lib/features/publish/presentation/widgets/pending_move_banner.dart#L87-L92)).

**Root cause:** the journal has a "finish" transition but no "undo", and
Skip's evidence bar cannot be met in the cases the plan wrote it for.

**Fix.** Neither new exit needs a new saved phase, because both clear the
pending record; the journal schema stays at 1.
1. **Cancel move** (journal only; the share address does not change, so ADR
   0017 Decision 5 is amended, not reversed):
   - Domain `PublishHostState.abandonMove(expected)`: returns the state
     without the pending move, keeping `activeHost` and `verifiedTarget`; null
     unless `expected` is the exact pending operation; a repeat is a no-op.
     Repository `abandonMove`, mirroring `finishMove`.
   - New port `MoveSourceOperations.retirementObserved(pending)`: true if the
     exact source's record is `retired`, or one bounded public read of the old
     root equals the recorded moved page. Unreadable counts as false.
   - `MoveSiteUseCase.abandon()`: refused when retirement is observed ("Your
     old address already shows the moved page. Choose Retry move to finish
     moving."); otherwise `abandonMove`, returning a new `MoveSiteAbandoned`.
     Neither site is touched.
2. **Finish without retiring** (★, reverses Decision 5 for this case only;
   record it as "Decision 5a"):
   - `authorizeSkip` becomes a sealed `SourceSkipCheck`: `SourceAbsent` (L2's
     rules), `SourcePresent`, `SourceInaccessible(oldSiteAnswers)` (401/403,
     a 301, or no exact credentials) and `SourceCheckFailed`.
   - Absent → finish as today. Present → offer Retry or Cancel. Inaccessible →
     offer `finishWithoutRetiring()`, which re-checks inside the queue,
     requires Inaccessible or Absent, and calls `finishMove` with
     `retirementSkipped: true`. No record is marked retired.
   - Give `GitHubApiException` a status kind, so 401/403 is no longer a
     network failure (N10).
3. **Which button appears when:**

   | Old site state | Retry | Cancel move | Skip / Finish |
   |---|---|---|---|
   | Live, unchanged | yes | yes | — |
   | Changed by another phone | refused ("source changed") | **yes** | — |
   | Already retired | adopts | refused | — |
   | Cannot sign in (401/403/301, no credentials) | — | yes | **finish without retiring** |
   | Authenticated "not found" (L2 rules) | — | yes | Skip, as today |

4. **Copy.** Banner: "Retry move" · "Skip retirement" · "Cancel move".
   - Cancel dialog: "Cancel this move? Pitak will keep publishing to your
     current site at {old}. Your share link and card stay the same. The new
     site at {new} was already published and stays online with a copy of your
     library. Pitak will not change or delete it; delete it in your
     {GitHub|Cloudflare} account if you don't want it online. You can start the
     move again later." Buttons: "Keep the move pending" / "Cancel move".
   - Cancel done: "Move cancelled. Your site is still {old}. The copy at {new}
     stays online until you delete it."
   - Inaccessible: "Pitak cannot sign in to the old {GitHub repository|
     Cloudflare Worker}, so it cannot check or retire it. Reconnect it and
     choose Retry move. If you no longer have access, you can finish the move
     without retiring the old site."
   - Finish dialog, old site answering: "Your old site at {old} still shows
     your library as it was. Pitak cannot change or remove it, so visitors
     there will see old information and will not be sent to {new}. Your share
     link and card will switch to {new}. Reprint your card." Not answering:
     "Your old site at {old} no longer answers and Pitak cannot sign in to its
     account. If it comes back, it will show old information. Your share link
     and card will switch to {new}." Buttons: "Back" / "Finish move".
   - Skip dialog body: "Use this only when the old GitHub repository or
     Cloudflare Worker was deleted. Pitak checks first and stops if it still
     exists. Your share link switches to {new}. The old address will not show a
     moved page."
   - Publish refused: "Finish, skip or cancel the pending move before
     publishing again."
   - Dialogs move into a new `pending_move_dialogs.dart`.

**Tests:** domain: `abandonMove` clears, repeats as a no-op, refuses another
operation and refuses after finish. Use case (both directions): cancel keeps
the old pointer with exactly one write and no remote call; cancel is refused
when retired; Skip on 401, 403, 301 and missing credentials offers finish;
finish is refused when present or when the check failed. Repository: a save
failure is a `Left`. Widgets: three actions and the dialog copy. Fakes:
`FakeMoveSource.skipCheck`, `.retired` and abandon counters.

**Records ★:** ADR 0017 Decision 5 amendment and "Decision 5a"; plan D.4,
D.6 and F.8 wording; handoff §13 bullet ("a pending move has three explicit
exits"); Part M row; CHANGELOG; in-app guide.

### M3 — rotating the token never deploys over the live site (D4 ★)

**Verified.** `begin` saves a fresh record as soon as a user token verifies
([setup_cloudflare_site.dart:82–87](../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L82-L87)),
dropping the confirmed target and the per-Worker proof. With a token that
cannot read the account subdomain, picking the same live Worker goes through
the marker-only verification deploy (:318–341), which replaces every asset.
The dialog then says "Your other active site is not retired or changed"
([cloudflare_verification_dialog.dart:84–88](../../lib/features/publish/presentation/widgets/cloudflare_verification_dialog.dart#L84-L88)),
which is false when this Worker **is** the active site. The token dialog
suggests an expiry, so rotation is normal.

**Root cause:** setup has no way to recognise "this is the address I already
proved", so it proves it again in the destructive way.

**Fix.**
1. **Recognise a proven address.** If the prospective target (exact account,
   subdomain and stored Worker name) equals the journal's `verifiedTarget`, or a
   pending move's verified `newTarget`, finalize **without** a verification
   deploy. That read-back is the address proof, and a fresh `workerExists`
   under the new token proves the token sees that Worker.
   `workersWriteConfirmed` stays false until the next publish proves write
   access.
2. This keeps "a new token starts a fresh `cf_connection`": no flag is copied
   from the old record. The proof comes from the public journal plus fresh
   remote evidence. Still, it is a new proof path, so it gets an ADR 0017 S7
   amendment and a Part M row.
3. **Defer the first save for user tokens too.** Account tokens are already
   held in the running operation and saved at `selectAccount`; use that path
   for both kinds. Abandoning setup halfway then keeps the old, working
   connection. "Verify before first save" and "save the candidate before its
   first remote write" both still hold.
4. **Copy and prefill.** If the Worker is the active site but the address is
   not recognised as proven (for example, a different subdomain), the
   verification dialog says: "This Worker is your live site. Verifying it
   replaces the whole site with a test page until you publish again." Prefill
   the Worker and manual-subdomain prompts from the verified target. Re-selecting
   the exact stored Worker name stays allowed even with RH2's lower-case rule
   (Part 3).

**Tests:** rotation onto the verified target → no deploy, ready, write not
confirmed; onto the pending move's new target → no deploy; onto a different
Worker → the normal verification flow; abandoning after a new token → the old
record intact; the live-site dialog copy appears when the active Worker is not
proven.

### M6 — an off-screen prompt is shown on return, and can be cancelled

**Verified.** Dialogs open only when the prompt **changes**, through
`ref.listen` without `fireImmediately`
([cloudflare_connection_section.dart:30–36](../../lib/features/publish/presentation/widgets/cloudflare_connection_section.dart#L30-L36)).
The tab is disposed off-screen. On return the tile is in `awaitingInput`, so
every button is disabled
([cloudflare_tile.dart:104–125](../../lib/features/publish/presentation/widgets/cloudflare_tile.dart#L104-L125)),
and `_start` holds `keepAlive` until the app restarts. GitHub's connection tab
shows its device code and repo prompt the same transition-only way
([connection_tab.dart:32–52](../../lib/features/publish/presentation/widgets/connection_tab.dart#L32-L52)).

**Fix.**
1. Move the listener to `initState` with `ref.listenManual(...,
   fireImmediately: true)`. Show the dialog from a post-frame callback, since a
   route cannot be pushed during `initState`. Remember the last shown serial,
   so one prompt is never shown twice but a remount shows it again.
2. Add "Cancel setup" to the tile while `awaitingInput`. It calls
   `CloudflareSetupPrompts.cancel()` (Phase 0.5); the flows already treat a null
   answer as cancel, and `_start`'s `finally` releases `keepAlive`.
3. Apply the same remount rule to the GitHub device-code and repo prompts.

**Tests:** widget tests: a prompt raised while the section is unmounted
appears on mount; no double dialog on rebuild; Cancel returns the tile to idle;
the GitHub device code reappears after a tab switch.

### M11 — a rebuild cancels the old run's waits instead of stranding them

**Verified.** `build()` resets `_disposed`
([cloudflare_connection_controller.dart:41](../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L41)),
but `_operationActive` and `_input` survive. Riverpod rebuilds an invalidated
provider lazily; until then `_emit` drops every update (:458–462). An
invalidate while a command waits in the queue, from
[publish_controller.dart:171–175](../../lib/features/publish/application/publish_controller.dart#L171-L175)
or [move_site_controller.dart:91–95](../../lib/features/publish/application/site/move_site_controller.dart#L91-L95),
followed by a prompt, creates a completer nobody completes. `_operationActive`
then stays true, and Connect, Continue and Disconnect silently do nothing. The
GitHub controller has no such lock, so it can drop an update but cannot get
stuck.

**Fix.**
1. `CloudflareSetupPrompts` carries a generation number. `build()` starts a
   new generation; `onDispose` cancels the old generation's pending waits.
   `_awaitInput` and `_emit` refuse a stale generation and complete with
   "cancelled".
2. `_operationActive` belongs to the generation, so a new build starts
   unlocked, and the old run ends through its cancelled waits.
3. The publish, events and move controllers stop invalidating the connection
   controller. They call a new `refreshStatus()` command that reloads the safe
   status projection without a rebuild, so a refresh never cancels a setup the
   user is in the middle of.

**Tests:** invalidate while a command waits in the queue, then a prompt → the
old run ends and Connect works again; `refreshStatus()` during a prompt keeps
the prompt; the 48f6f14 regression test stays green.

---

## Phase 4 — truthful verification and messages (M9, L3, N3, L4, L7, L12, L16, N4–N6, N9)

### M9 — the moved-page name is valid before anything is written (D6)

**Verified.** `normalizeMovedLibraryName` only trims
([move_plan.dart:22–25](../../lib/features/publish/domain/site/move_plan.dart#L22-L25)).
`PendingMove` rejects names over 256 UTF-16 units or with a C0 control
character or DEL
([pending_move.dart:165–170](../../lib/features/publish/domain/site/pending_move.dart#L165-L170)).
The settings field accepts a pasted tab. The name is read in `_createPending`,
**after** the destination publish
([move_site_use_case.dart:222–223](../../lib/features/publish/application/site/move_site_use_case.dart#L222-L223)).
No pending record exists, so there is no Retry: the user re-runs the move, and
every attempt republishes and then fails at the same point.

**Fix.**
1. **A total normalizer** that leaves every currently valid name unchanged,
   so existing pending records still validate: replace each code unit below
   0x20, and 0x7F, with a space; trim; cut to 256 UTF-16 units (255 if the cut
   would split a surrogate pair); trim again; if blank, use "My Library".
2. **Validate before any write.** In `confirm()`, right after the stale and
   anchor checks and before `publish`, read the name through the typed reader
   (M8), build the candidate `PendingMove` and render its moved page. After
   verification only `beginMove` runs. `prepare()` runs the same dry run
   without writing. Failure copy: "The moved page for your old address could
   not be prepared. Nothing was changed."
3. `render()` uses the stored name as it is; only `build()` normalizes (L11,
   Part 3).

**Tests:** a property test that normalized output always satisfies
`PendingMove`, over `'\tA\tB'`, `'a\r\nb'`, `'\u0000'`, `'\u007f'`, 300 × "a",
255 × "a" plus an emoji, and `' \t '`; "My  Library" and "കേരളം & Co" stay
unchanged. A tab in the name is normalized and recorded. A moved-page failure
stops before any destination write.

### L3 + N3 — Version URLs re-checked wherever a result says "done" (D8)

**Verified.** The ordinary publish repairs Version URLs before its next
deploy, but these paths report success without checking them: verify-only and
repair ([publish_to_cloudflare_use_case.dart:215–273](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L215-L273)),
the final pre-deploy check (it ignores the route it just read), and move
Retry adoption on both sides
([cloudflare_move_destination.dart:186–189](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L186-L189)).
**N3:** if the retirement deploy landed but its route update failed, Retry
sees the exact retired marker, skips straight to verify-and-finish
([cloudflare_move_source.dart:139–185](../../lib/features/publish/application/cloudflare/cloudflare_move_source.dart#L139-L185)),
and completes the move without ever confirming previews are off. ADR 0017
Decision 7 says that failure "blocks retirement completion".

**Fix.** Call Phase 0.2's `CloudflareVersionUrlGate.ensureOff` before every
result that says "verified", "repaired", "adopted" or "complete", and after the
final race check, before the deploy. A failure returns `versionUrlPrivacy`
and keeps any pending move. No local flag: every success consults Cloudflare's
real route state, so an earlier warning cannot be hidden.

**Tests:** previews on before verify-only, repair, and each Retry adoption →
fixed, or blocked with the privacy message; previews re-enabled during a
multi-bucket upload → disabled before the deploy, and nothing deploys if that
fails.

**Records:** ADR 0017 note: "Retry verification may disable Version URLs; it
never uploads or deploys."

### L4 — a landed deploy is recognised next time

**Verified.** Recovery is one immediate marker read that returns only
"already deployed" or "abort"
([cloudflare_publish_marker_probe.dart:74–93](../../lib/features/publish/application/cloudflare/cloudflare_publish_marker_probe.dart#L74-L93)).
The new publish id is saved only after the deploy returns
([publish_to_cloudflare_use_case.dart:432–446](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L432-L446)).

**Why not the review's "deploying" record:** overwriting the single record
before the PUT loses the old identity. If the deploy never lands, the live
marker still carries the old id, nothing matches, and the user is sent to
replacement anyway. The state enum is shared with GitHub, and a schema bump
would make every existing record read as empty.

**Fix.**
1. A second atomic file, `cloudflare_publish_pending.json`, holding an
   ordinary schema-2 record (state `deployed`) of the attempted deploy. The
   manifest store gains `loadPending`, `savePending` and `clearPending`. No
   schema bump; older builds ignore the file, which fails closed.
2. Order: final race check → `savePending` (a failure stops before the PUT:
   "This device could not save its publish record, so nothing was deployed.
   Your live site was not changed.") → PUT → save `deployed` → `clearPending`.
3. At the next preflight, if the marker matches the pending record, promote
   it: preflight stays read-only, and the use case saves it before continuing.
   A pending record for another target claims nothing (the H1 rule).
4. Recovery polls the marker: up to 5 reads, 3 s apart, within 30 s. It never
   returns `retry`, because a public read cannot prove an uncertain PUT will
   not land later. Delete the dead `CloudflareDeployRecovery.retry` value and
   its adapter branch; this also settles the "retry it once" doc nit.
5. New uncertain-deploy copy: "Cloudflare did not confirm the deployment, so
   the site may or may not have changed. Tap Retry verification to check
   before publishing again." Show Retry for it, and drop "Reconnect…".

**Tests:** pending saved before the PUT and cleared after; a failed pending
save stops before deploying; a landed deploy with a lost response is
recognised next time with no replacement (the fake's `onDeployAttempt` runs
before its scripted throw); a deploy that never landed leaves the old record
`known`; a failed `deployed` save is repaired by Retry verification (closes the
review's `failSave` gap); polling finds the marker or aborts at the deadline.

**Records:** ADR 0017's persistence order gains the pending step; handoff
§13's "save the candidate before its first remote write" now also covers
deploys; Part M row.

### L7 + N16 — messages say what happened

**Verified.**
- When the old record verifies but its commit fails, an ordinary publish
  returns a verification "success"
  ([publish_to_cloudflare_use_case.dart:227–237](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L227-L237)).
  The card says "Cloudflare accepted the deployment…"
  ([publish_status_copy.dart:17–25](../../lib/features/publish/application/publish_status_copy.dart#L17-L25))
  although nothing new was deployed. A verify-only success reads
  "Published!".
- "Retry verification" can loop forever: after a failed `deployed` save plus a
  failed read-back, Retry sees an unknown state and offers Retry again
  ([publish_card.dart:163–172](../../lib/features/publish/presentation/widgets/publish_card.dart#L163-L172)).
- The generic `on Exception` branches, and the post-deploy route catch,
  leave no debug log.

**Fix.**
1. An ordinary publish whose old-record commit fails returns a failure: "Your
   previous Cloudflare publish is live, but this device could not record that,
   so your new changes were not published. Your live site was not changed. Try
   publishing again."
2. `PublishSuccess.newDeployment` (false for verify-only) selects "Verified:
   your live site matches this phone's last publish." (events: "Verified: your
   events page is live at {url}.").
3. Offer Retry only where it can succeed: an unreachable verification, an
   uncertain deploy, a deploy not yet verified, or recoverable local state.
   With L4 the "accepted but not saved" case becomes recoverable; until then it
   says "Your next publish will ask you to review a whole-site replacement."
4. `CloudflarePublishOutcomes.unexpectedDiagnostic` logs the error's type,
   stage, progress flags and stack through `appLog`, never its message. Use it
   in every generic branch, including the shared `cloudflare_operation_attempt.dart`
   (Phase 0.4).
5. **N16:** review the remaining copy that says "Reconnect" or "Retry" for
   failures that neither fixes; Part 1 H1 covers `siteUnavailable` and
   `targetMismatch`.

**Tests:** old record verifies, commit fails → failure, zero deploys; the
verify-only copy says "Verified"; no Retry button when it cannot succeed; the
diagnostic names a type but never a path or token.

### L12 + N4 — move steps report their saves and their deploy stage

**Verified.**
[cloudflare_move_destination.dart:284](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L284)
and [github_move_destination.dart:155](../../lib/features/publish/application/github_move_destination.dart#L155)
ignore the `deployed` save results; the later `live` saves are reported.
**N4:** both move paths call `updateWorkerRoute` after a deploy without a
try/catch
([cloudflare_move_destination.dart:286–292](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L286-L292),
[cloudflare_move_source.dart:240–246](../../lib/features/publish/application/cloudflare/cloudflare_move_source.dart#L240-L246)),
so a failure there becomes a generic message that hides "the deploy was
accepted".

**Fix.** Check each save and carry `localStateSaved: false`; on failure
append "This phone could not save its record of the new site." Reuse
`CloudflarePublishOperationProgress` and `CloudflarePublishOutcomes` in both
move paths, so every post-deploy failure says what landed.

**Tests:** a `deployed` save failure followed by a failed verification is
reported; a later `live` save heals it; a route exception after the deploy
says the deploy was accepted.

### L16 — a move into an unknown Cloudflare state asks first

**Verified, and common.** The move destination deploys over any state except
`siteUnavailable` and an exactly matching `known` site
([cloudflare_move_destination.dart:186–200](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L186-L200)).
A setup verification marker or an adopted Worker counts as `unknown`, so the
**first** move into Cloudflare normally takes this path. F.5 step 2 requires
"replacement reconciliation with explicit consent".

**Fix.** When the destination is `unknown`, `prepare` puts its
`CloudflareRemoteAnchor` (Phase 0.3) into the move confirmation and adds a
line: "The Cloudflare Worker "{worker}" already has content this phone did not
publish (for example a setup check or another device). Moving replaces
everything on that Worker." Button: "Replace and move". At publish time, a
missing or changed anchor re-prompts through the existing
`MoveDestinationConfirmationRequired` path. An exact retired marker stays
trusted (F.6). Optional later: record setup's own verification publish id so
that marker counts as `known`.

**Tests:** `unknown` requires the reviewed anchor; a changed anchor
re-prompts; `newSite` and `known` need none; the dialog shows the line.

### N5, N6, N9 — smaller truthfulness fixes

| ID | Problem | Fix | Test |
|---|---|---|---|
| N5 | Any destination anchor change reads as "source changed" ([cloudflare_move_destination.dart:262–263](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L262-L263)) | Split the cases; add `MoveSiteMessages.destinationChanged` | Each case shows its own message |
| N6 | `readInputs` drops the typed read failure with `toNullable()` ([cloudflare_replacement_preparation.dart:110–126](../../lib/features/publish/application/cloudflare/cloudflare_replacement_preparation.dart#L110-L126)), so Cloudflare never shows "member list too large" or "saved libraries unreadable", which GitHub does | Return `Either` and map `PublishReadFailure(message)` to its message | The specific message reaches the card |
| N9 | `verifyingDestination` is emitted only after the destination already verified, and `verifyingOldAddress` only after retirement ([move_site_use_case.dart:104–125](../../lib/features/publish/application/site/move_site_use_case.dart#L104-L125)), so the screen says "Publishing destination…" through a 10-minute GitHub wait | Emit each phase before its step (the destination publisher reports progress through a callback) | Progress order test |
