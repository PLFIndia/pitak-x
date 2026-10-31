# Cloudflare fix plan — Part 1: High (Phases 1–2)

[← Index](cloudflare-fix-plan-2026-10-29.md) ·
[Part 2 — Medium](cloudflare-fix-plan-2026-10-29-2-medium.md) ·
[Part 3 — Low](cloudflare-fix-plan-2026-10-29-3-low.md)

This part removes every state whose only exit is clearing app data, then
makes large libraries upload on slow networks. It assumes Phase 0 (index §4)
has landed. File links are relative to `docs/plans/`; `UC` means
[publish_to_cloudflare_use_case.dart](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart)
at `77e6acb`.

---

## Phase 1A — publishing dead ends (N1, M10, H1, RH1, M2, N2)

These share one cause: the publish flow can reach a state whose only way out
is a confirmation it will never accept, or no confirmation at all. Land them
in this order.

### N1 + M10 — bind a replacement to the remote state the user saw

**Verified.** [PublishReplacementSummary](../../lib/features/publish/application/publish_result.dart#L28-L61)
holds the target, section, digest and counts, but no remote anchor. On
confirm, the use case accepts a replacement only while
`initial.requiresReplacement` is true ([UC:280–283](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L280-L283)),
meaning only `unknown` or `knownRetired`. That causes two bugs:

- **M10:** another device deploys while the dialog is open. The confirm
  still succeeds, because the state is still "unknown", and overwrites that
  deploy without asking again. R4 says confirmation revalidates remote anchors.
- **N1 (new, High):** a replacement offered because **bytes are missing**
  ([UC:344–353](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L344-L353)
  for the assembler; [UC:395–401](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L395-L401)
  when Cloudflare asks for a carried-forward hash) is offered while freshness
  is `known`. Every confirm fails with `stalePublish`, while the copy promises
  "Review a whole-site replacement to continue". The existing test stops before
  confirming ([publish_to_cloudflare_use_case_test.dart:244–276](../../test/features/publish/application/cloudflare/publish_to_cloudflare_use_case_test.dart#L244-L276)).

**Root cause:** consent is modelled as a freshness category instead of the
remote facts the user saw. So it accepts a changed remote and rejects an
unchanged one.

**Fix.**
1. Add to the summary: `remoteAnchor` (the `CloudflareRemoteAnchor` from Phase
   0.3), `reason`, `previousSiteUrl` and `remoteChangedSinceReview`. `reason` is
   a new enum `PublishReplacementReason`: `unknownRemoteState`, `retiredSite`,
   `workerMissing`, `localBytesMissing`, `recordContradicted`, `targetChanged`,
   `addressChanged`. `CloudflareReplacementPreparation.prepare` and
   `prepareResult` set them.
2. **New confirm rule:** if the fresh preflight's anchor equals the summary's
   anchor, replace, whatever the freshness category. Skip re-verifying the old
   record, then run today's digest check. If the anchor differs, write nothing:
   return a fresh summary with `remoteChangedSinceReview: true` if a
   replacement is still needed, otherwise `stalePublish`. The publish card
   re-opens the dialog because the summary is a new object
   ([publish_card.dart:37–44](../../lib/features/publish/presentation/widgets/publish_card.dart#L37-L44)).
3. Dialog copy by reason. With the changed flag, prefix: "The Cloudflare site
   changed after you reviewed this. Review the replacement again."
   `localBytesMissing`: "Some files from your last publish are no longer on this
   phone or on Cloudflare. Publishing your whole library again repairs the
   site: {n} items, {m} posters."
4. **N15 (doc):** the missing-hash path must open an upload session (that is
   how Cloudflare reports missing hashes), and it may disable Version URLs
   first. Amend ADR 0017's "no route update, upload session … during
   preparation" sentence to name this exception.

**Tests:** extend the missing-hash test so it confirms and deploys once.
Confirm after the marker id changed, the Worker appeared or vanished, or the
marker became unreadable → a fresh summary, no upload. A changed digest still
re-prompts. Cancel writes nothing. Update the summary helper in
`publish_card_test.dart`.

**Records:** Part M row ("R4 confirmation is anchor-bound"); ADR 0017 S8 says
what the anchor contains. CHANGELOG "Fixed".

### H1 — a record for another target, and a deleted Worker

**Verified.** The use case returns `targetMismatch` when the stored record
describes a different target ([UC:190–198](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L190-L198)),
and stops on `siteUnavailable` ([UC:211–213](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L211-L213)).
Nothing rewrites the record: disconnect only clears credentials
([setup_cloudflare_site.dart:374–375](../../lib/features/publish/application/cloudflare/setup_cloudflare_site.dart#L374-L375)),
and plan D.6 says it must not clear the record. Moving away does not help
either: moving out needs a matching `live` record, which the stale record
blocks.

**Root cause:** two rules exist where one was decided. The record's contract
([cloudflare_site_manifest.dart:12–15](../../lib/features/publish/domain/cloudflare/cloudflare_site_manifest.dart#L12-L15)),
handoff §13 and the move reader ([cloudflare_move_reader.dart:59–62](../../lib/features/publish/application/cloudflare/cloudflare_move_reader.dart#L59-L62))
say a non-describing record claims nothing; the ordinary publish treats it as
an error. Separately, the explicit recreate flow that R10 and F.9 require was
never built.

**Fix.**
1. **One rule.** Add `CloudflareSiteManifest.forTarget(target)`: the record
   when it describes the target and its file set is valid, otherwise
   `CloudflareSiteManifest.empty`. Use it in the use case (delete
   UC:190–198) and in `CloudflareMoveReader.connection`. Keep `targetMismatch`
   only for credentials whose target differs from the operation's
   (UC:183–188).
2. **Classification already gives the safe answers** with an empty record.
   No Worker and a real marker 404 → `newSite`, nothing to lose. An existing
   Worker → `unknown` → replacement consent. An existing Worker is never
   adopted silently, provided `workerExists` is trustworthy (L2, Part 2).
3. **Recreate flow.** Add `siteUnavailable` to `requiresReplacement` and
   delete UC:211–213. A deleted Worker now yields a `workerMissing` summary;
   confirming deploys a complete snapshot that recreates the Worker, and the
   normal read-back re-verifies the address. That is F.9's "explicit
   setup/recreation with a complete snapshot and re-verified address". (There
   is no older version to expose, so the pre-deploy Version-URL gate does not
   apply; the post-deploy gate runs as today.)
4. **D1.** Keep the stored record's target as `previousTarget` when it does
   not describe the operation target. Then require a `targetChanged` review
   (other Worker or account) or an `addressChanged` review (same Worker,
   different subdomain). Both deploy a complete snapshot, because
   `library.json` embeds the address.
5. **The old Worker is untouched** and keeps its last version. The share
   link switches only after the new site's read-back
   ([publish_host_state_repository.dart:67–76](../../lib/features/publish/application/site/publish_host_state_repository.dart#L67-L76)).
   The stale record is not deleted; the first `deployed` save for the new
   target overwrites it (with L4, the pending file comes first).
6. "Retry verification" with no matching record returns a new
   `nothingToVerify` message and shows no Retry button.
7. **N16:** stop advising "Reconnect and verify" where reconnecting cannot
   help. It can even trigger M3's verification deploy over the live site
   ([cloudflare_error_messages.dart:42–49](../../lib/features/publish/domain/cloudflare/cloudflare_error_messages.dart#L42-L49)).
   After this fix, `siteUnavailable` only means "the account subdomain
   changed".

Proposed copy:
- `workerMissing`: "The Cloudflare Worker "{worker}" no longer exists.
  Publishing recreates it at {siteUrl} with this phone's catalogue ({n} items)
  and {m} event posters."
- `targetChanged` (extra paragraph): "This library was last published from
  this phone to {previousSiteUrl}. That site is not changed or deleted — it
  keeps showing its last version. Your share link switches to {siteUrl} once
  the new site is verified."
- `addressChanged`: "Your workers.dev address changed from {previousSiteUrl}
  to {siteUrl}, so the old address no longer works. Publishing rebuilds this
  Worker's site at the new address."
- `nothingToVerify`: "This phone has no publish on this Cloudflare site to
  verify yet. Publish to continue."
- `siteUnavailable`: "Your Cloudflare account's workers.dev address changed,
  so this site's address no longer works. Reconnect Cloudflare and choose the
  new address."

**Tests** (`publish_to_cloudflare_use_case_test.dart`, plus a shared
`forTarget` test for the move reader):
- a record for another Worker, with that Worker absent → `targetChanged`
  review, then a complete deploy; the record now describes the new target;
- a record for another target never drives an incremental deploy to an
  existing Worker;
- the same Worker at an old subdomain → `addressChanged`;
- a deleted Worker → a `workerMissing` summary with no route write, session,
  deploy or record write; confirming recreates it and saves `deployed` then
  `live`; confirming re-prompts if the Worker reappeared;
- verify-only with only another target's record → `nothingToVerify`;
- domain tests for `forTarget`.

**Records:** Part M row (F.3 step 1's "manifest target match" means
*discard*, never *fail*; the R10/F.9 recreate flow exists). ADR 0017 S8 note.
CHANGELOG "Fixed".

### RH1 — the first deploy to a Worker that does not exist yet

**Verified risk.** The final race check compares `workerExists`
([cloudflare_publish_preflight.dart:60–77](../../lib/features/publish/application/cloudflare/cloudflare_publish_preflight.dart#L60-L77)).
The adapter's own comment says creating the upload session "may also create
the Worker" ([http_cloudflare_deploy_api.dart:87–89](../../lib/features/publish/infrastructure/http_cloudflare_deploy_api.dart#L87-L89)).
If it does, the first publish uploads everything and then stops as "stale";
the second needs a replacement consent for a brand-new site. H1's recreate
flow and every move to a new Worker hit the same wall; the move even reports
it as "source changed" (N5). J.7 never ran this path.

**Fix, correct under both host behaviours** (land with H1). Only when the
first preflight saw no Worker:
1. Re-read `workerExists` right before `createUploadSession`. If it now
   exists, stop as stale: someone else created it.
2. Right after the session, re-read `workerExists` and the marker. If the
   Worker appeared during our request and the marker is absent or unreadable
   (never present), use that as the new baseline. Otherwise keep the old
   baseline, and the marker must still be absent.
3. The final race check compares against that baseline.

Our own session's change passes, and a foreign change still stops; the only
window for misattribution is the session request itself. A foreign Pitak
deploy is still caught by its marker. A comment states this is observed
staleness, not compare-and-swap (handoff §13). Use the same baseline in the
move destination.

**Tests:** session creates the Worker → the first publish deploys; session
does not → unchanged; foreign creation before the session → stale; a marker
appearing after the session → stale; a fresh Worker with an unreadable
marker still deploys; the recreate variant. The Phase 6 checklist records the
real behaviour.

### M2 — re-verification without the dead end (D2 ★)

**Verified.** The verifier checks **every** file in the record
([cloudflare_publication_verifier.dart:75–81](../../lib/features/publish/application/cloudflare/cloudflare_publication_verifier.dart#L75-L81)),
against its own doc (:3–5). It reads one file at a time at full size: 12
rounds of 5 s, with 15 s per read and no total deadline (:88–101). It holds
the app-wide queue, so the worst case is about 12 × (5 s + 15 s × pending
files). It only answers verified or not, and a `deployed` record must pass it
before the next deploy ([UC:215–226](../../lib/features/publish/application/cloudflare/publish_to_cloudflare_use_case.dart#L215-L226)).

**Root cause:** the GitHub path follows the maintainer's Option B (Part M row
55). [publish_verification_check.dart:15–25](../../lib/features/publish/application/site/publish_verification_check.dart#L15-L25)
says it was written so Cloudflare could share it, but the Cloudflare path
never adopted it. It also used "download everything" as proof, although the
upload protocol guarantees every hash exists before a completion token is
issued, and versions are atomic.

**Fix.**
1. **The documented set only** (R16, ADR 0017 S8): the exact marker,
   `books.json`, the root `index.html`, `library.json` or its real 404,
   `events.json` and `events.html` when recorded, posters (at most two), and
   removed-poster 404s. No covers. Moves use the same set.
2. **Three outcomes:** `verified`; `contradicted` (some file answered with
   different bytes, or with a body where a 404 was required); `unreachable`
   (timeout, 404, oversize, redirect — the §13 definition).
3. **Budgets** in `CloudflareLimits`: after a deploy, 12 × 5 s within 90 s
   total; for an earlier deployment, 3 × 2 s within 20 s. Inject a clock and
   check the deadline before each round and each read. A read already in
   flight may overrun by its own 15 s limit; document that.
4. **Policy for an earlier `deployed` (or repair-needing `live`) record:**
   verified → commit `live` and continue; contradicted → replacement with
   reason `recordContradicted`; unreachable → continue the publish without
   marking the old one live. The marker match already proves the record
   describes the live version, and the new deploy's read-back decides `live`.
5. **Retry verification** copy. Contradicted: "The live Cloudflare site does
   not match this phone's last publish. Publish to review a whole-site
   replacement." Unreachable: "The Cloudflare site could not be checked right
   now. Nothing was changed. Try again later."

**Tests:** the verifier never reads `covers/`; contradicted when a body
differs at the end of the budget; unreachable with only timeouts or 404s; a
descriptor body where a 404 was required is contradicted; the total deadline
ends slow reads (fake clock). In the use case: unreachable does not block and
the record stays `deployed` until the new read-back; contradicted gives a
`recordContradicted` summary with no writes; the existing
verification-failure test changes its expected copy.

**Records ★:** ADR 0017 "verification failure stops" amended (Option B for
Cloudflare, mirroring row 55); Part M rows for Option B and for "covers are no
longer read back"; handoff §8.

### N2 — the move destination has the same deleted-Worker stop

**Verified.** [cloudflare_move_destination.dart:88–92](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L88-L92)
and [:180–184](../../lib/features/publish/application/cloudflare/cloudflare_move_destination.dart#L180-L184)
refuse a move to a target whose Worker was deleted, and reconnecting cannot
fix it. A move always deploys a complete snapshot from an empty previous
publication, behind the D.4 confirmation. So `siteUnavailable` there proceeds
like `newSite`, with RH1's baseline, and the confirmation names the case: "The
Worker for {address} no longer exists. Pitak creates it with your whole
library."

**Tests:** a move to a deleted-Worker target publishes, verifies and records
the pending move.

---

## Phase 1B — app-state dead ends (M7, N7, M1, M8)

Independent of 1A; can be built in parallel.

### M7 — forget an unreadable Cloudflare connection in the app

**Verified.** `build()` throws when the record cannot be read
([cloudflare_connection_controller.dart:49–55](../../lib/features/publish/application/cloudflare/cloudflare_connection_controller.dart#L49-L55)).
The error tile says only "Restart the app"
([cloudflare_connection_section.dart:46–53](../../lib/features/publish/presentation/widgets/cloudflare_connection_section.dart#L46-L53)).
`_start` needs a loaded state (:435), so Disconnect cannot run. Publishing
reports "could not be **saved**" for a **read** failure.

**Root cause:** an expected condition (an older app version, a reset
Keystore) is modelled as a crash instead of a state the user can act on.

**Fix.**
1. `build()` returns data: add `CloudflareConnectionPhase.unreadable`. It
   carries no secret.
2. New command `forgetConnection()`, allowed in that state, runs
   `setup.disconnect()` inside the queue. `clear()` deletes the key without
   decoding it.
3. Tile copy: "Cloudflare setup on this phone can't be read. This can happen
   after installing an older version of Pitak or after the phone's secure
   storage was reset. Forget it and connect again. Your public site, its Worker
   and your share link are not changed." The "Forget Cloudflare connection"
   button opens a confirmation.
4. Add `CloudflareErrorMessages.connectionUnreadable`: "Cloudflare setup on
   this phone can't be read. Open Publish → Connection to fix it." Use it on
   the publish path instead of `storage`.
5. Plan D.6/F.8 still hold: only `cf_connection` is cleared. The record, the
   journal and any pending move stay.
6. **Same class on GitHub:** the GitHub connection tab's error state ("Couldn't
   load your connection status.") has no action either. If the GitHub
   credential store can surface a read failure, give it the same "Forget"
   action.

**Tests:** a read failure → `unreadable`; forget → `clear()` called once, then
"not connected"; forget is refused while another operation runs; widget test
of the tile and dialog; store test that `clear()` works on a newer-schema and
on an undecodable value.

### N7 — reset an unreadable host journal (D10)

**Verified (new).** A newer schema or tighter target validation makes the
journal's `load()` return `Left`
([prefs_publish_host_store.dart:49–65](../../lib/features/publish/infrastructure/prefs_publish_host_store.dart#L49-L65)).
Publishing, moves and the setup guards then fail closed forever, with no exit
inside the app.

**Fix.** Add `PublishHostStateRepository.resetUnreadable()`. It deletes the
key **only** when the stored journal is unreadable; it is never a general
reset. The publish card shows it in that state behind a confirmation: "Pitak
can't read its record of where your library is published. This can happen
after installing an older version. Reset the record? Your sites are not
changed. Your share link is hidden until your next successful publish, and
any unfinished move is cancelled; the old site keeps its current content."
After a reset, the active host falls back to the existing legacy rule.

**Tests:** reset refused when the journal is readable; reset clears an
unreadable one; the card shows the action only in that state.

### M1 — the Cloudflare API outlives the screen that started the work

**Verified.** `cloudflareApiProvider` is auto-dispose and closes its clients
on dispose ([publish_providers.dart:77–87](../../lib/core/di/src/publish_providers.dart#L77-L87)).
In `http` 1.6.0, `IOClient.close()` is `close(force: true)`. The publish,
events and move controllers only `ref.read` their factories, so the API stays
alive only while the Connection tab's listeners exist. Switching tabs
disposes it mid-request. The transport re-creates clients lazily after a
close ([cloudflare_http_transport.dart:80–97](../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L80-L97)),
so exactly the requests in flight are cut.

**Root cause:** the doc comment says "an operation owns its connections", but
nothing makes the operation the owner. Their lifetime follows whichever
widget happens to be listening.

**Fix.**
1. `@Riverpod(keepAlive: true)`, the same pattern as the shared
   `httpClientProvider` ([platform_providers.dart:48–56](../../lib/core/di/src/platform_providers.dart#L48-L56)).
   This is safe because the facade holds no token or JWT: tokens arrive per
   call ([cloudflare_http_transport.dart:3–6](../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L3-L6)),
   and idle sockets close themselves. Replace the comment with the
   justification AGENTS §4 asks for.
2. **N14:** key the transport's native-client cache by a fixed connect
   timeout, not by the operation deadline. Otherwise H2's size-derived
   deadlines would create one connection pool per distinct value, each with a
   connect timeout of minutes.

**Alternative rejected:** a per-operation API created and closed by each
outer command. It is more precise, but every collaborator receives the API
through DI, so about ten constructors would change for no safety gain.

**Tests:** a `ProviderContainer` test proves the instance survives losing its
last listener and is closed only with the container. A publish test pauses the
deploy with the gated fake, disposes the Connection section, releases the gate
and asserts the publish completes and nothing was closed.

### M8 — a thrown `Failure` never freezes a spinner (+N8)

**Verified end to end.** `Failure` is not an `Exception`
([failure.dart:11](../../lib/core/error/failure.dart#L11)). After any failed
settings write, `SettingsController` sets `state = AsyncError(failure)`
([settings_controller.dart:86–103](../../lib/features/settings/application/settings_controller.dart#L86-L103)).
Riverpod 2.6.1's `onError` then makes `.future` equal `Future.error(failure)`.
The provider is keepAlive, so this lasts until another write succeeds. Every
`await …settingsControllerProvider.future` then throws a non-`Exception`:
- the snapshot builder provider ([publish_providers.dart:297](../../lib/core/di/src/publish_providers.dart#L297)),
  so **every** publish;
- `PublishController.libraryJson` ([publish_controller.dart:232](../../lib/features/publish/application/publish_controller.dart#L232));
- the events GitHub path ([publish_events_controller.dart:123](../../lib/features/events/application/publish_events_controller.dart#L123));
- the move library-name read ([move_publish_providers.dart:133–134](../../lib/core/di/src/move_publish_providers.dart#L133-L134)),
  after the destination is already published.

The outer controllers catch only `on Exception`
([publish_controller.dart:76](../../lib/features/publish/application/publish_controller.dart#L76),
[publish_events_controller.dart:52](../../lib/features/events/application/publish_events_controller.dart#L52),
[move_site_controller.dart:98](../../lib/features/publish/application/site/move_site_controller.dart#L98)),
and so do the widget callbacks ([publish_card.dart:174–190](../../lib/features/publish/presentation/widgets/publish_card.dart#L174-L190)).
The card's spinner stays on and the move's `busy` stays true, so every later
move command answers "stale". **N8:** the same `AsyncError` makes the settings
page show "Couldn't load settings." One failed theme toggle is enough.

**Root cause:** a `Failure` is used as a thrown error object, and callers
read an `AsyncNotifier`'s `.future` as if it could only fail with an
`Exception`.

**Fix.**
1. **Foundation (settings feature, own PR in this phase):** a failed write
   keeps `AsyncData(last persisted value)` and reports the failure through the
   setter's `Either`. The settings UI shows "Couldn't save that setting. Try
   again." instead of "Couldn't load settings". This removes the cause for
   every consumer.
2. **One typed read:** `SettingsController.loaded()` returns
   `Future<Either<Failure, AppSettings>>`. It answers the last good value,
   folds a never-loaded state into `Left(StorageFailure)`, and never invents
   defaults (handoff §13: "a corrupt read is not empty content"). Rebuild the
   existing safe `_loadedLibraryName` on it.
3. **Typed read sites.** `libraryJson` and the events GitHub path map `Left`
   to the fixed read-failure message. The move name reader becomes
   `Future<Either<Failure, String>> Function()`, read **before** the
   destination write (see M9 in Part 2), and is passed in by the controller
   instead of capturing the use-case provider's `ref`.
4. **Snapshot settings without DI awaits:** add
   `PublishReads.pageSettings()` (name, contact, sharing), read in phase 1,
   carried on `PublishInputs` and passed to both section builders. Each
   operation then uses one settings snapshot. "Read before build" and "one
   builder wiring" both stay.
5. **Outer catches never stay busy.** `PublishController.publish` and
   `PublishEventsController.publish` catch `on Object`, log only the error
   type through `appLog`, set `AsyncError` and rethrow. That keeps the
   contract the existing test checks ([publish_controller_test.dart:317–335](../../test/features/publish/publish_controller_test.dart#L317-L335)).
   The widget catches in `publish_card.dart` and `events_page.dart` become
   `on Object`. `MoveSiteController._run` catches `on Object`, logs, sets a
   generic failure and resets `busy`. Each catch has the justification comment
   the architecture test requires.
6. `moved_html_builder.dart:80` becomes `on Object` → false, because
   `rootBundle` throws `FlutterError`.
7. **Guard:** an architecture test forbids reading
   `settingsControllerProvider.future` outside `lib/features/settings/`.
8. Do **not** make `Failure implement Exception`. ADR 0002 keeps failures as
   values, the `only_throw_errors` lint relies on it, and it would still miss
   `Error`s such as `FlutterError`.

**Tests:** after a failed write, `loaded()` returns the last good value, a
publish succeeds with the saved settings, and the settings page shows the
save error; a builder `Error` ends loading; events, both hosts; a move whose
name read fails resets `busy` (use `Future.error(...)`, since
`only_throw_errors` forbids throwing a `Failure`); "settings unavailable"
stops a move before any destination write.

---

## Phase 2 — large libraries upload on slow networks (H2, L8, L5)

### H2 — deadlines that follow request size and progress (D3 ★)

**Verified.** `uploadDeadline` is 60 s
([cloudflare_limits.dart:56](../../lib/features/publish/domain/cloudflare/cloudflare_limits.dart#L56)).
The transport passes it as both the per-phase timeout and the total
([cloudflare_http_transport.dart:223–228](../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L223-L228)).
`IOClient.send` returns only after the whole body is piped, so
`TimeoutHttpClient`'s first phase covers the entire upload
([timeout_http_client.dart:108–121](../../lib/core/network/timeout_http_client.dart#L108-L121)).
Buckets are idempotent, so a timeout re-sends the whole bucket from byte 0,
up to 3 attempts ([cloudflare_http_transport.dart:170–186](../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L170-L186)).
The adapter refuses any grouping other than Cloudflare's. A 56 MB wire bucket
needs about 7.5 Mbit/s of sustained upload. No multi-megabyte bucket has ever
been uploaded to the real host (S2 recorded `uploaded=no`).

**Also bounding it:** the upload JWT and the completion token each live
**one hour**
([Direct Uploads](https://developers.cloudflare.com/workers/static-assets/direct-upload/)).
All buckets, and the deploy after them, must fit in that hour.

**Root cause:** one wall-clock number stands in for two questions: "is the
connection dead?" (idle) and "has this run too long?" (total).

**Fix.**
1. **Pure domain constants** in `CloudflareLimits`: `deployDeadline` 60 s;
   `uploadConnectTimeout` and `uploadIdleTimeout` 60 s; `uploadFloorBytesPerSecond`
   64 KiB; `maxUnobservedInFlightBytes` 8 MiB (socket and TLS buffers);
   `uploadResponseWait` = 60 s + 8 MiB ÷ floor ≈ 188 s; `maxUploadDeadline`
   20 min; `uploadSessionBudget` 55 min; `blindResendMaxBytes` 1 MiB. Pure
   function `uploadTotalDeadline(bytes) = min(20 min, 60 s + bytes ÷ floor)`. A
   56,131,788-byte request gets about 15.3 min.
2. **`TimeoutHttpClient` opt-in upload mode** (all new parameters default to
   null, so GitHub, lookups and the viewer are unchanged):
   `requestBodyIdleTimeout`, `responseHeadersTimeout`,
   `onRequestBodyProgress(int sent)`. `_AbortableRequest.finalize()` wraps the
   body in a `StreamTransformer` that counts bytes and re-arms an idle timer on
   every chunk the client pulls. Bytes and content length are unchanged.
   dart:io pauses the stream while the socket buffer is full, so a pull means
   the network really drained. Phases: connect (until the first pull) →
   sending (idle timer) → waiting for headers (`responseHeadersTimeout`); the
   total timer stays. New fixed messages: "Upload stalled for Ns" and "Response
   headers timed out after Ns". Aborts still use the same trigger.
3. **Transport timing profiles:** a new `CloudflareRequestTiming {connect,
   idle?, responseWait?, total}` replaces the single `Duration`. API calls use
   30/30, deploy 60/60, and buckets take their total from `request.contentLength`
   (`MultipartRequest` computes it without reading the streams). **N13:** any
   request body over 256 KiB, including the upload-session manifest of up to
   ~1.6 MB, uses the upload profile.
4. **No blind resend of a big bucket** (bucket-only policy; bytes sent come
   from the progress callback):
   - network error, timeout or stall with ≤ 1 MiB sent: retry as today;
   - the same after more than 1 MiB: no retry; typed `uploadStalled`;
   - total deadline exceeded: `uploadTooSlow`, never retried;
   - 5xx/429 after a body over 1 MiB: at most one resend.
   Deploy keeps its re-read-before-repeat recovery.
5. **Session budget.** `CloudflareUploadSession` gets a non-secret
   `issuedAtMillis` from the adapter's clock. `uploadBucket` refuses to start
   at 55 min and caps each request at the time left. **N12:** a 401 from the
   bucket endpoint means the upload JWT expired; map it to `uploadTooSlow`, not
   "Reconnect Cloudflare".
6. **Copy** (the existing outcome mapping already appends "Your live site was
   not changed." and the uploaded-bytes note):
   - `uploadStalled`: "The upload to Cloudflare stopped making progress, so it
     was not repeated automatically. Try again on a faster or steadier
     connection, such as Wi-Fi."
   - `uploadTooSlow`: "This connection is too slow to finish the upload in the
     time Cloudflare allows. Try again on a faster connection, such as Wi-Fi."
7. **Splitting buckets** is neither forbidden nor documented as supported:
   buckets "should be uploaded together", and the completion token arrives
   "once every file in the manifest has been uploaded". It would change plan
   B.2, the final-bucket token rule and `_matchesBucket`, and it cannot split a
   single 25 MiB file. Treat it as an optional follow-up after a real-host
   trial (Part 3, Phase 6).

**Alternatives rejected:** a bigger constant (a dead link would hang that
long); a size formula without the idle timer (a stall waits out the whole
budget); three blind retries (about 3 × 56 MB of mobile data).

**Tests:**
- new `test/core/network/timeout_http_client_upload_progress_test.dart`,
  with a paced `MockClient.streaming` under `fakeAsync`: a slow but pulled body
  outlives `timeout`; no pull for the idle time → "Upload stalled" and the
  abort fires; the headers wait starts when the body ends; the total still ends
  a trickle; progress is cumulative; with the parameters null, behaviour is
  unchanged;
- the existing timeout, multipart and bounded-fetcher tests stay unchanged as
  the GitHub regression guard;
- `cloudflare_socket_abort_test.dart` (real loopback): the server reads
  ~2 MiB of an 8 MiB body, then stalls → `uploadStalled`, exactly one
  connection, socket closed; a server reading 64 KiB per 20 ms finishes past
  the old limit;
- transport: total scales with size; a connect failure with 0 bytes retries
  three times; a stall after 1 MiB does not; a 5xx after a large body resends
  once; the native-client map stays small;
- deploy API: a 401 on upload → `uploadTooSlow`; an exhausted session refuses
  a bucket;
- use case: a stalled bucket shows the new copy and never deploys; the memory
  test is unchanged (no buffering).

**Records ★:** ADR 0017 Decision 8 ("30 s / 60 s deadlines") and plan R20
amended; ADR 0007 notes that the upload JWT string can live up to an hour;
Part M row; CHANGELOG "Fixed".

### L8 — classify by status first; never retry a changed file

**Verified.** Any JSON parse failure becomes "unreadable response",
whatever the status ([cloudflare_http_transport.dart:268–279](../../lib/features/publish/infrastructure/cloudflare_http_transport.dart#L268-L279)).
That covers the last 5xx, the second 429 and writes without recovery, whose
Cloudflare edge pages are HTML. A hash mismatch inside the upload stream, a
missing spool file and the base64 chunk check all pass through as exceptions
that `_open` maps to a retryable "network" error (:229–238). A test pins this
retry ([http_cloudflare_deploy_api_test.dart:495–522](../../test/features/publish/infrastructure/http_cloudflare_deploy_api_test.dart#L495-L522)).

**Fix.**
1. In `_parse`, a JSON failure with status 429 or ≥ 500 returns a status-only
   response, so the existing mapping yields `rateLimited` or `server`. A
   non-JSON 4xx stays "unreadable": an HTML 403 must not trigger setup's
   "403 → manual entry" branches.
2. New non-retryable kind `artifactChanged`, thrown with `uncertain: false`
   (the declared length is never reached). Copy: "Some site files on this
   device changed or could not be read during the upload, so it stopped.
   Publish again."

**Tests:** a final HTML 502 → server; a second HTML 429 → rate-limited; an
HTML 403 stays malformed; rewrite the pinned test (2 opens, no delays,
`artifactChanged`); a spool file removed mid-upload → `artifactChanged`.

### L5 — spools live in temporary storage and are swept safely

**Verified, partly.** Spools live under Documents/`publish_artifacts/run-*`
([cloudflare_publish_providers.dart:59–65](../../lib/core/di/src/cloudflare_publish_providers.dart#L59-L65))
and are removed only in `finally`. Android is the only shipping target and
backup is off (`allowBackup="false"`), so iOS backup is moot. The real harm:
Documents is never cleared and survives "Clear cache", so every killed publish
leaves a full copy of the site behind.

**Fix.**
1. A keepAlive `appTempDir` provider using `getTemporaryDirectory()`.
2. A new infrastructure `PublishArtifactSpoolRoot` over the new temp root and
   the legacy Documents root. It holds a lock and the set of run folders this
   process is using:
   - `createRunDirectory()` sweeps stale folders under the lock, then creates
     and registers a new `run-` folder;
   - the sweep touches a root only if it is a real directory, lists without
     following links, and deletes only real directories named
     `^run-[A-Za-z0-9_-]{1,64}$` that are not in use;
   - links, files and other names are left alone; failures are typed.
3. **When it runs:** lazily at the first spool, which happens only inside a
   queued operation. Never when a provider is built: the move provider is
   built outside the queue and could race a running publish.
4. Keep every `cloudflare_spool_security_test.dart` guarantee.

**Tests:** stale folders swept in both roots; a live folder is never deleted;
a `run-x` symlink is skipped and its target survives; a symlinked root is not
swept; a deletion error is typed; stores root at the overridden temp dir.

**Records:** ADR 0017's "spools … cleaned in `finally`" gains "and swept at
the next operation". CHANGELOG "Fixed".
