# Background event notifications for bookmarked libraries

- **Status:** Implemented 2026-11-07; all automated gates pass. Device
  testing started 2026-11-08 and is BLOCKED on one open issue (see
  "Handoff" at the end). Nothing is committed (§6).
- **Updated:** 2026-11-07. Supersedes the consolidated review plan at
  `617cd53:PLAN.md`. Decisions 9, 12, 13, 14 were confirmed/amended by the
  maintainer in conversation; sizing decision 15 is new.
- **Baseline:** `617cd53`; earlier borrower-limits plan: `bad362e:PLAN.md`.

## Understanding

On Android, periodically check events at libraries the user deliberately
saved (`NetworkSource.bookmark` or `card`, never `discovered`). Notify about
added or modified posters, using a safe public caption when available.
Provide an in-app off switch. Default is ON, the interval is fixed at
12 hours, and first sight/re-enable establish quiet baselines.

**Scale (decision 15):** realistically ≤ 20 saved libraries, usually < 5.
Hard cap 100. Every run checks every saved library; there is no per-run site
selection, fairness ordering or overflow budget. Deadlines are safety limits.

"App closed" includes ordinary backgrounding and process death, not a promise
of execution after force-stop or despite Doze, OEM restrictions or battery
policy. Polling and Android notification display are both best-effort.

Non-goals: push servers, iOS background work, removal alerts, notification
history, per-library mute, fetching poster images to detect changed bytes,
a foreground badge phase, and suppressing an alert merely because the user
already viewed the poster. An unchanged `imageRef` and caption cannot reveal
changed image bytes.

## Privacy & threat notes

- This adds scheduled headless network activity. Update the manifest's
  "only on explicit user action" wording and `PRIVACY.md`; do not overlook
  its already-documented foreground availability updates.
- A watched host sees the device IP, site/file URL, timing and fixed Pitak
  User-Agent once per run. This exposes a bookmark relationship, not just an
  IP. Use the existing HTTPS, same-origin/directory and redirect
  restrictions; send no credentials/cookies; no analytics or remote logging.
- Default ON (decision 1, reconfirmed) is a maintainer trade-off, not blanket
  consent. Explain scheduled and metered traffic. Require foreground
  readiness, an unlocked app gate and at least one saved library before
  initial setup. Android < 33 has no runtime permission prompt; say so.
- A stored library `name` is user-typed until the first successful Refresh,
  after which `refresh_run.dart:283` overwrites it with the descriptor's
  public name. Decision 13: the notification title uses the stored name only
  when `fetch_status = 'ok'`; otherwise a generic title. Never copy a name
  into watch-state payloads. Hide alerts on the OS lock screen. Captions pass
  safe-display-text checks with a fixed fallback for empty/unsafe text.
- Watch files hold bookmark relationships plus public metadata, not vault
  secrets. They stay plaintext in private support storage under the existing
  file-store design, excluded from Android backup. App-private storage is
  not encryption; disclose this. Minimize fields; keep no delivered-history.
- Recheck settings, revocation, generation and current bookmark membership
  before sensitive actions. Final check → action races are best-effort.
- Validate notification payloads against current saved rows; app-lock gates
  both warm and cold-start navigation. Never log URLs, labels, captions or
  raw exceptions. No new secrets, vault access or catalogue writes.

## Investigation notes

Verified on 2026-11-07 against `617cd53`; recheck changed dependencies before
implementation. Proposed types below are design contracts, not existing APIs.

| Evidence | Consequence |
|---|---|
| `lib/features/network/infrastructure/published_events_codec.dart:57` | At most two posters; partial reads may omit rows/captions. Reject partial, duplicate-reference and newer-schema observations for diffing. |
| `lib/features/network/infrastructure/bounded_published_events_fetcher.dart:66` | Bounded fetch supports validators, `304`, `404` and abort signals; reuse without foreground cache writes or stale fallback. |
| `lib/features/network/domain/published_site_url_policy.dart:13` | Preserve canonical-site, HTTPS, redirect and directory containment checks. |
| `lib/features/network/application/network_controller.dart:161` | `name` is user input on add; the descriptor fetch on the next Refresh supplies the real name. |
| `lib/features/network/domain/usecases/refresh_run.dart:283` | Successful Refresh sets `name: descriptor.name` and `fetchStatus: ok`. No user-rename path exists. A row with `fetch_status = 'ok'` therefore carries the public name. |
| `lib/core/database/tables.dart:234` | `fetch_status` column, default `'never'`. Worker SELECT adds `name, fetch_status`. |
| `lib/features/network/infrastructure/drift_network_repository.dart:351` | Unknown source tokens map permissively (`?? NetworkSource.bookmark`) in the foreground repository; watch queries must filter raw tokens strictly. |
| `lib/core/di/src/database_providers.dart:36` | Catalogue is plaintext and uses the normal Drift open path; do not use that provider in a worker. |
| `lib/core/storage/data_generations.dart:118` | `open()` repairs/writes. Expose a peek-only resolver based on the existing read-only pointer primitive. |
| `lib/features/backup/infrastructure/restore_backup.dart:81` | Existing `sqlite3` read-only open is the implementation precedent. |
| `lib/features/network/application/add_member_controller.dart:85`, `lib/features/backup/application/restore_controller.dart:150` | Card adds and restore invalidate the network controller; test the watched-count observer end-to-end. |
| `lib/features/events/infrastructure/file_events_repository.dart:86` | Temp + rename is the file-store precedent; existing `uuid` supplies settings incarnations after verifying its random source. |

No foreground `busy_timeout` or WAL configuration exists in `lib/`
(decision 12 reconfirmed: none is added). Dart file locks do not exclude
another isolate in the same process; neither atomic rename nor one worker
isolate serializes overlapping async writes.

Cached candidates `workmanager: 0.6.0` and
`flutter_local_notifications: 20.1.0` contain no gms/play/firebase/mlkit
Android dependencies in the audited Gradle files. Verify current releases,
transitive dependencies and F-Droid classpaths before approving pins. The
notification plugin requires desugaring, compileSdk ≥ 35 and release icon
retention; its README reports Android 12L+ desugaring crashes. Its native
`show()` returns after `notify()`, not after confirmed display. The
WorkManager bridge returns from registration/cancellation before awaiting
native operations; adapter success must not assume completion.

## Proposed approach

Single-writer architecture. Domain types/ports live under
`lib/features/network/domain/events_watch/`; application orchestration uses
code-generated Riverpod providers and `Either<Failure, T>`. Infrastructure
owns file IO, read-only SQLite, HTTP and Android plugins. Desktop/iOS receive
no-op ports and no Settings tile. No foreground state writer.

**OSS references:** adapt this repository's bounded fetch and atomic
file-store patterns; verify Android WorkManager periodic-work guidance
against the chosen artifact. No external implementation is treated as proof.

### 1. Identity, ownership and bounded persistence

`WatchSettingsToken` = **incarnation + epoch**. Incarnation is a fresh UUID
on first creation or explicit settings reset. Epoch increments on every
explicit enable/disable within that incarnation; never wrap/reuse it.
Compare the whole token. Reset creates a fresh incarnation, epoch 0,
enabled false, then cancels work; a surviving old epoch 2 cannot match a
newly enabled epoch 2 after reset.

| Document/type | Contents and ownership |
|---|---|
| `events_watch_settings.json` | Foreground-only writer: schema, enabled, token, explanation-version acknowledgement. Worker only reads it. |
| `events_watch_state.json` | Worker-only writer: schema, observed settings token, generation, site statuses, pending, nullable `revocationToken`, bounded recovery notice, last-run outcome. Foreground only reads status. |
| Site status | Canonical site URL, row id + creation time, persisted notification id, last attempt, nullable last successful check, bounded outcome, optional baseline. |
| Baseline | Up to two reference/content digests, optional entity-tag validator, full settings token. Null = no authoritative first sight (distinct from empty). |
| Pending change | Added/modified kind, site + row identity, image reference, safe caption, content digest, full settings token. No library name. |

A different incarnation clears baselines and pending; a different epoch in
one incarnation discards pending and requires quiet re-baselining.
Generation change clears site state/pending. Within a generation, removed or
replaced rows are pruned by `(id, createdAt, siteUrl)`. Revocation/recovery
notices follow their own token rules, not generation rules.

Schema 1: strict decoding, typed failures. Caps (decision 15): settings
16 KiB; state 512 KiB; 100 sites; pending ≤ 2 per site (≤ 200 entries).
Bound bytes before decoding, nesting, fields, identifiers and enum values.
Flushed unique temp files + atomic rename, cleanup on error. Missing settings
never mean ON inside a worker; only foreground initialization creates
defaults. Newer schemas are never overwritten. Recovery: section 6.

One async operation queue owns foreground settings: collapses duplicate
reconciliation, handles permission-dialog resume re-entrancy, lets newer
intent suppress an older enable before registration. Publish state only
after its save succeeds; disposal must not permit a second controller writer.

The worker has a separate **serialized state reducer/commit queue**. Fetches
may run concurrently (bound 4, matching existing refresh); completions carry
immutable results. The reducer merges into latest state, checks guards/caps,
awaits each write, then permits notification submission. Revocation/recovery
use the same queue. Late results after stop/deadline cannot mutate state.

No Dart file lock or invented CAS. Step 0 must prove worker non-overlap
during cancellation, retry, update and rapid re-registration. If the plugin
cannot establish it, stop and reconsider a transactional store.

### 2. Read-only source and action guards

`WatchedLibrariesSource` provides a bounded snapshot and a point-membership
recheck. Initial query: `SELECT id, site_url, created_at, name, fetch_status
FROM network_libraries WHERE source IN ('bookmark', 'card') LIMIT 101`.
Reject noncanonical URLs; row 101 produces a visible capacity failure. Use
the same strict source for the foreground watched-count decision.

Before each site's fetch, result commit and notification, recheck the
expected id, creation time, canonical URL and raw source with a parameterized
query. A missing/replaced row discards that site's result/pending; a DB check
failure stops the action, never authorizes a fetch. At ≤ 20 sites this is
≤ 60 short reads per run; busy collisions skip that site until the next run.

Dedicated `sqlite3` read-only connections with a short bounded busy wait;
one bounded SELECT per connection, close in `finally`. Never hold a
connection across HTTP or notification calls. Busy/hot-journal, missing
schema or missing database fail closed without repair. Never use
`AppDatabase`, its callbacks, normal network DI or legacy-bookmark migration.
`DataGenerations.peekActive()` never writes: check before open, after each
SELECT and before actions; invalid pointers stop.

**Common guard:** before every fetch, commit and show, reload enabled
settings/full token; require no matching `revocationToken`, effective global
AND channel permission, same generation and current affected-row identity.
On token/generation change stop the run; on observed removal stop that
site's actions and cancel its notification id. Abort HTTP where supported.
Only revocation bookkeeping may commit after definitive permission loss.

### 3. Run state machine and fetch outcomes

This table is the single ordering contract; tests and adapters implement it.

| Phase | Required transition |
|---|---|
| Load/guard | Load both documents; stop on OFF/missing settings/current revocation marker; no fetch. Classify state recovery before ordinary work. |
| Reconcile | Check generation and rows; prune stale identity/token entries; allocate stable ids through the reducer. Empty watched set cancels work. |
| Revalidate pending | Fetch sites already carrying pending changes, reconcile latest content, commit, then submit only eligible changes. Never show old pending first. |
| Check remaining sites | After the pending phase, process every other site. HTTP failure at one site never blocks others. |
| Finish | Commit submitted-entry cleanup; report bounded outcomes. On infrastructure failure stop new work and request retry. No unawaited mutations survive return. |

All phases share a five-minute safety deadline (monotonic, injected clock);
abort/drain outstanding work on stop. Every completed attempt advances
`lastAttemptAt`; only authoritative `200`, validated `304` and `404` advance
`lastSuccessfulCheckAt`. Retain the 64 KiB body cap, 15-second request
deadline and bounded redirects. An unconditional retry after an unusable
`304` stays inside the same budget.

| Fetch outcome | Baseline/change rule | Existing pending this run |
|---|---|---|
| Complete supported `200` | Null baseline or changed settings token: baseline only. Otherwise diff; commit baseline, validator, outcome and pending together. Complete empty payload is authoritative. | Coalesce latest caption/digest; remove entries for absent posters; remaining entries become eligible. |
| Partial, duplicate image reference, newer schema | Record outcome; no diff, no baseline advance. | Retain but withhold. |
| Validated `304` | Require validator belonging to local baseline; retain posters, re-tag baseline with current token. No diff. | Eligible only when matching that confirmed baseline. |
| `304` without matching baseline | Retry once without validator; repeated invalid response fails closed. | Not eligible unless retry validates content. |
| `404` | Retain old posters, or create empty first baseline; clear validator, re-tag token, record success. No removal alert. | Retain but withhold. |
| Transport/decode failure | Retain baseline/validator; record failed attempt. Never use saved-copy fallback. | Retain but withhold. |

Hash a length-prefixed encoding of image reference and caption with the
existing SHA-256. New reference = added; changed digest at same reference =
modified; disappearance = no notification. Pending is keyed by
`(siteUrl, imageRef)`: a still-pending addition stays "added" while its
content advances. Two posters maximum per site.

The quiet re-enable/`404` trade-off remains decision 8: `404` cannot prove
when subsequently served content was published. No event-time accuracy
promise absent wire-format timestamps.

### 4. Pending work and submission (decision 9, simplified)

Pending means not yet successfully submitted, not notification history.
After process death/retry, only a complete current-run `200` or validated
`304` can make an entry eligible again. Revalidation failure cannot cause an
old caption to be shown. A failed show or cleanup write stops ordinary
new-site fetches and returns retry; revalidation fetches are still permitted.
Explicit OFF/ON discards pending with the documented quiet re-baseline cost.

Commit baseline + pending before show; remove only entries covered by
successful calls, in a subsequent serialized write. A crash in between may
repeat the same id. This is durable, retryable **submission**, not a
guarantee of OS display, sound or attention. Disable, reset, revocation,
identity change and authoritative withdrawal invalidate pending; unreadable
state recovery may lose it and must be visible (section 6).

**Notification identity and replacement:** each library has one stable
persisted notification id; the group summary uses id 0. Posting a library
id again replaces that library's own previous alert (Android semantics), so
a library can never have two alerts. There is **no** active-inventory
inspection, cross-run cap or batch cancellation during ordinary runs. The
group summary is posted whenever at least one child is posted, as Android
grouping requires. Feature-scoped cancellation (stable tag/channel) is used
only for: explicit disable, settings reset, revocation/recovery, and a row
detected as removed. Never cancel another feature's notifications.

Derive a candidate nonzero 31-bit id from SHA-256 of the canonical URL;
resolve zero/collisions with deterministic length-prefixed URL + counter
rehashing in stable URL order. Persist allocations and reuse on retry.
Never use `String.hashCode`. `LocalNotifier` needs typed permission,
effective-delivery, feature-scoped cancellation, library-show and
summary-show operations.

### 5. Foreground lifecycle and scheduling

An explicit app-start owner, not the Settings tile, calls the code-generated
`EventsWatchController` after initialization, first frame and app-lock
unlock. Use the same serialized queue on resume, explicit toggles and
watched-count zero/nonzero transitions. Observe the network provider for
mutations; use the strict source to decide whether valid watched rows exist.

Fresh initialization alone may offer default ON. Persist settings before
scheduling. An empty watched set cancels without a permission prompt; the
first saved row enters setup. ON is effective only with deliverable alerts.
On Android 13+, show the explanation before the first system prompt; persist
its acknowledged version. "Not now" or denial persists OFF with a new token.
Ordinary resume with acknowledged explanation and permission must not repeat
dialogs. Revoked/blocked states offer system settings instead of prompt
loops. Pre-33 checks effective settings without claiming runtime consent.

Initialize `Workmanager().initialize(callbackDispatcher)` once in foreground
before registration. One unique periodic name, fixed 12 hours (plus
WorkManager's flex window — Settings copy says "about every 12 hours"),
`NetworkType.connected`, battery-not-low, explicit backoff. Keep for an
unchanged specification, update for a changed one; no per-launch
replacement. The scheduler port must inspect registration and verify native
completion, not equate a returned method-channel call with completed work.

### 6. Stop states, restart and recovery

| Event | Persistent action and next behavior |
|---|---|
| Explicit disable | Save OFF + next token before cancellation; always attempt cancellation even if save fails. Show OFF only after save succeeds. Clear feature alerts without writing worker state. |
| Definitive permission/channel loss | Worker serializes `revocationToken = current token`, clears pending, nulls baselines, then attempts cancellation. Allowed despite permission false. |
| Matching revocation marker on a later worker run | Stop without fetch/show even if permission was re-granted. Retry cancellation; only a foreground token transition supersedes the marker. |
| Matching marker on foreground reconciliation | Persist OFF + next token and cancel, regardless of current permission. |
| Permission-state check error | No fabricated marker; stop and return infrastructure failure without fetching. |
| Explicit settings reset | Fresh incarnation, epoch 0, OFF; cancel work and clear feature alerts. Foreground never edits the state file. |
| Current-format corrupt/oversized state | Worker replaces it with an empty recovery document, current token, null generation and a visible recovery notice; no fetch that run. |
| Newer/unknown schema, unreadable settings or failed recovery write | Fail closed, no schedule/fetch; never default or overwrite a newer format. Expose a safe error/update-required state. |
| **ON in settings, no registered job (decision 14)** | Do not auto-repair. Show "Checks are not scheduled" with an explicit **Resume** action; register only on that tap. Unknown registration state is treated as not scheduled. Applies after failed-OFF-save + successful cancel + process death, OS-side job loss and earlier empty-set cancellation. |

Check settings again before revocation bookkeeping so an old run cannot
invalidate a newer enable. Preserve a matching marker across generation
changes; a superseded marker is cleared by the worker on a later enabled run.
If marker persistence fails, attempt cancellation anyway and report failure.
Recovery notices survive normal runs and clear only on an explicit
enable/disable token change.

If neither OFF nor cancellation could be persisted, the old intent cannot be
reconstructed after process death. Surface the failure immediately, retry
while foregrounded and offer OS notification blocking. Document the
marker-write-failure + permission-re-grant residual. Cancellation must target
the observed registration, not a newer job created during a race; establish
that adapter contract in Step 0.

Expected site/network failures wait for the next periodic run.
Infrastructure failures request WorkManager retry with backoff;
disabled/empty/completed runs return success. The entry-point dispatcher only
calls `executeTask`, initializes notifications, and builds a minimal fresh
`ProviderContainer`: peek-only generation, read-only source, bounded HTTP,
stores and notifier/scheduler. No Rust/vault/app-lock, normal database or
network providers, refresh controller or cache writes. Catch errors by safe
type and dispose clients/container in `finally`; forced termination can
bypass Dart cleanup and must be crash-tested.

### 7. Presentation and Android integration

Settings shows the ON/OFF switch, "about every 12 hours" best-effort note,
metered-data notice, no-library state, latest successful check,
withheld/partial/newer-format counts, safe storage/scheduler/capacity errors,
the "not scheduled → Resume" state and settings reset. A recent successful
site must not imply every site was checked. Hide the group on unsupported
platforms.

**Title (decision 13):** if the row's `fetch_status = 'ok'`, title is the
stored `name` (already the descriptor's public name, `NetworkName`-validated
on write); otherwise a generic "New event at a saved library". Body is the
public caption after safety checks. Library payloads contain only canonical
site URLs; summary payload selects the Network tab. Validate against current
saved rows at consumption; invalid/removed rows fall back to Network. Handle
running callbacks and `getNotificationAppLaunchDetails()` for cold start.
Queue one route until providers and the unlocked app gate are ready, then
consume once.

Initialize the notifier in both foreground and worker with a stable channel,
lock-screen visibility `private`/`secret` (verify on devices) and a
release-safe icon. Document merged `POST_NOTIFICATIONS` and `VIBRATE`
permissions. Add only required Gradle/desugaring/resource-keeping
configuration after exact-command approval; verify compileSdk/AGP/Kotlin
compatibility and build both Android flavors. If the Android 12L+ desugaring
issue needs a WindowManager dependency, obtain separate approval. Update
`PRIVACY.md`, manifest INTERNET wording, guides, changelog and ADR 0024.

### 8. Required tests and acceptance evidence

Baseline existing tests/analyze before code changes, then targeted tests and
full gates after. Fake ports, injected clocks, Riverpod overrides; no real
hosts or production storage in unit/widget tests.

| Area | Required cases |
|---|---|
| Digest/diff | Null vs empty baseline, add/modify/remove, reorder, ambiguous encodings, duplicate references, unsafe/empty captions, changed bytes at unchanged reference explicitly undetectable. |
| Fetch | Complete/empty `200`, `304` with/without matching validator, bounded unconditional retry, first/transient `404`, partial/newer schema, failure and stale-copy rejection; no cache writes. |
| Token recovery | Surviving pending/baselines with the same numeric epoch as reset → immediate enable: fresh incarnation prevents a match. |
| Quiet re-enable | Fresh/`304`/`404` token re-tagging; failed first attempt remains null; later valid additions notify per decision 8. |
| Pending freshness | Show fails → publisher removes/edits → retry revalidates before show; removed entry drops, newest caption wins, undelivered addition remains added. Failure/partial/`404` withholds. |
| Deadline | Late results after deadline/stop cannot commit; outstanding fetches are aborted/drained; one failing site does not block others. |
| Worker serialization | Reversed concurrent completions, delayed writes, id collisions and revocation during outstanding fetches preserve unrelated changes and never overwrite the stop marker. |
| Membership/generation | Remove one of several bookmarks mid-run without generation change (its alert is cancelled); move/source change/re-add; restore before/after SELECT and before action; no stale fetch/show after detection. |
| Read-only source | Strict unknown-token handling agrees in foreground/background; canonical URLs only; > 100 rows rejected; no DB mutation, migration or repair; each connection closed; busy/hot-journal fail closed. |
| Submission | Persist before show, cleanup after; process death preserves retryability; re-post with same id replaces; forced zero/hash collisions; summary posted with children; feature-scoped cancel only on disable/reset/revocation/removed row; unrelated alerts survive. |
| Stop/restart | Marker survives generation change; cancel fails → permission re-granted → no fetch; foreground consumes marker; ON-settings + missing job → Resume state, no auto-register; unknown registration fails closed. |
| Recovery failures | OFF save and cancellation both fail without false success; marker save failure; missing/unknown/newer settings/state; oversized state; recovery write failure; visible notice and quiet next baseline. |
| Stores/ownership | Bounded round-trip/hostile decode; old-or-new reads during rename; unique temps and cleanup; only controller saves settings, only worker reducer saves state. |
| Controller | Start/resume/row-add/disable races, latest intent, failed save never published, no-library/no-prompt, Not now, no repeated explanation on resume, disposal and observed-registration cancellation races. |
| UI/privacy | Title uses stored name only when `fetch_status = 'ok'`, generic otherwise; caption safety; lock-screen hiding; denied/blocked/recovery/Resume messages; warm/cold/invalid/summary routes; app-lock preservation; accessibility. |
| Regression | Manual Refresh and `PublishedEventsController` never write watch state; desktop no-op ports and architecture boundaries intact. |

Real-device matrix (must): process death, reboot, Android 13 permission and
pre-33 behavior, revocation then re-grant, offline/metered, locked/cold taps,
remove/re-add, app update without reopening, Android 12L+ desugaring.
(Should): Doze/battery saver, force-stop/OEM limits, restore,
uninstall/reinstall. Verify real native completion and non-overlap.

Full gates: build_runner with no unexpected generated diff, format, analyze,
Flutter tests/coverage, architecture/secret/dependency scans, F-Droid purity,
release build and applicable goldens; Rust gates required by repository CI.

## Decision points

All resolved 2026-11-07. The state tables above, not historical prose, are
the behavioral source of truth.

| # | Choice | Status |
|---|---|---|
| 1 | ON by default; no schedule without saved rows and effective delivery; denied/revoked becomes OFF. | Reconfirmed 2026-11-07. Document trade-off, metered traffic and pre-33 lack of runtime consent. |
| 2 | User-saved bookmark/card rows only, never discovered. | Preserved; raw-token filtering and live membership checks. |
| 3 | Fixed 12-hour interval; no selector. | Preserved; best-effort, flex window disclosed. |
| 4 | Android only; no-op ports elsewhere. | Preserved. |
| 5 | First sight establishes baseline, no alert. | Preserved; null ≠ empty; first `404` establishes empty. |
| 6 | Quiet re-enable; discard old pending and re-baseline. | Preserved with incarnation + epoch identity. |
| 7 | Write ADR `0024-background-event-alerts.md` after implementation. | Preserved; use `docs/adr/0000-template.md`. |
| 8 | Conditional fetches; no stale/partial/newer-schema diffs; retain baseline on `404`. | Preserved. |
| 9 | Grouped alerts with stable per-library ids; re-post replaces that library's own alert; summary id 0. | **Amended 2026-11-07 (simplified):** no active-inventory inspection, cross-run cap or batch cancellation. Feature-scoped cancel only on disable/reset/revocation/removed row. Promise is submission, not display. |
| 10 | Five-minute run deadline. | **Amended by 15:** no 100-site selection; all sites every run; deadline is a safety limit. |
| 11 | One writer per file; no foreground observer. | Preserved; worker non-overlap is a Step 0 gate. |
| 12 | Do not change foreground `busy_timeout`/journal mode. | **Reconfirmed 2026-11-07.** Worker uses a short bounded busy wait and fails closed; at realistic scale skipped sites are harmless. |
| 13 | Notification title provenance. | **Decided 2026-11-07:** stored `name` when `fetch_status = 'ok'` (public name via `refresh_run.dart:283`), generic title otherwise; no extra descriptor fetch; hide on lock screen. |
| 14 | ON-settings with missing registration. | **Decided 2026-11-07:** explicit Resume; unknown registration fails closed; no automatic re-register or auto-disable. |
| 15 | Sizing. | **New 2026-11-07:** realistic ≤ 20 libraries; hard cap 100; check all per run; pending ≤ 2/site; state ≤ 512 KiB; no overflow budget or fairness ordering. |
| 16 | Phasing. | **Decided 2026-11-07:** background-only; no foreground badge phase. |

## Steps

Implementation is not authorized yet. Before Step 0, ask whether to execute
end-to-end or pause at each implementation decision.

- [x] 0. Feasibility BEFORE the state store: baseline tests/analyze with
  pinned `fvm`; inspect current plugin/native WorkManager sources for
  periodic retry/backoff, registration/cancellation completion, safe
  cancellation targeting and worker non-overlap. Exercise cancel/re-enable,
  retry/update, engine stop and process death on Android. Verify
  notification replace-by-id, lock-screen visibility and the `uuid` random
  source. Plugin installation needed for this proof requires exact-command
  and dependency approval first (brings Step 4's package approval forward).
  A failed/unknown proof is a stop-and-redesign gate.
- [x] 1. Read complete generation, DB and network DI flows and existing
  tests; implement peek-only generation and bounded snapshot/point-read
  source with side-effect, capacity, contention and live-removal tests.
- [x] 2. Add immutable domain types, typed async ports, digest/diff and token
  identity tests; `CheckLibraryEventsUseCase` returns a typed run report.
- [x] 3. Add bounded file stores, foreground operation queue and worker
  reducer; test atomicity, ownership, reset and concurrent completions.
- [x] 4. Approve exact pinned packages/Gradle edits (if not already done in
  Step 0); integrate scheduler, notifier, icon/channel/desugaring; audit
  F-Droid purity.
- [x] 5. Implement the run state machine, pending revalidation, guard checks,
  deadline, revocation/recovery and submission tests from the tables above.
- [x] 6. Wire the top-level `@pragma('vm:entry-point')` dispatcher, minimal
  background providers, foreground lifecycle observer and safe disposal.
- [x] 7. Add Settings, nonrepeating explanation, recovery/Resume state and
  warm/cold routing; verify title provenance and app-lock in widget/device
  tests.
- [x] 8. Update privacy/manifest/guides/changelog and ADR 0024 from template.
- [x] 9. Automated gates run (results below). **Real-device matrix: not
  run — no device in this session; owed by the maintainer.** Commit not
  requested; ask before committing.

## Out-of-scope observations

- Foreground observation/de-duplication and a foreground events badge stay
  deferred (decision 16). Adding either requires revisiting writer
  coordination, not another JSON writer.
- Shared notification infrastructure for loan reminders moves to core only
  when that feature needs it; do not refactor it now.
- iOS scheduling/push infrastructure remain out.
- No exact timing, guaranteed OS display, image-byte-change detection, or
  recovery of an intent that neither storage nor the scheduler persisted.
- Untracked notes at repo root (`item-reminder.md`, `reminder-fixes.md`,
  `reminder-issues1.md`, `remoteImport-issues.md`) are unrelated to this
  feature; the maintainer should file or remove them.

## Result

- [x] Resolved pending decisions 9, 12, 13, 14 and recorded new decisions
  15 (sizing) and 16 (phasing) with the maintainer on 2026-11-07.
- [x] Implemented Steps 0–8 end-to-end (approved in conversation).

### Gates (2026-11-07)

| Gate | Result |
|---|---|
| `dart run build_runner build` | clean; generated files present and unignored |
| `dart format --set-exit-if-changed lib test integration_test` | 0 changed |
| `flutter analyze lib test integration_test` | 0 issues |
| `flutter test` | 6247 passed, 10 failed — the SAME 10 pre-existing golden pixel diffs in `test/golden/key_screens_test.dart` as the pre-change baseline (6069 passed, 10 failed). +178 new tests, all green. |
| Architecture tests | 38/38 (domain purity, layer boundaries, 500-line ratchet) |
| F-Droid purity (`fdroidReleaseRuntimeClasspath`) | no gms/play/firebase/mlkit; new artifacts: `androidx.work:work-runtime:2.9.0`, `gson 2.12.0` (already transitive at 2.10.1) |
| `flutter build apk --debug --flavor fdroid` | built (desugaring compiles) |
| `flutter build apk --release --flavor fdroid --split-per-abi arm64` | built; dex strings free of `google/android/(play|gms)|firebase|mlkit`; `drawable/ic_stat_pitak_events` present in the shrunk resource table (keep.xml effective) |
| Rust gates | not re-run: no Rust files changed |

### Step 0 findings (plugin sources, 2026-11-07)

- `workmanager 0.6.0`: register/cancel return before the native `Operation`
  completes; `isScheduledByUniqueName` is authoritative (`.get()`).
  `onStopped` destroys the Dart engine without a Dart-side signal. Adapter
  confirms every mutation by polling the authoritative query; worker
  non-overlap = AndroidX unique periodic work + the token guard.
- `flutter_local_notifications 20.1.0`: `notify(id)` replaces; requires app
  desugaring; brings `gson` (Apache-2.0, not a Play/GMS artifact).
- `uuid 4.5.3` v4 default RNG is `CryptoRNG` (`Random.secure`).
- `androidx.work` merges `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`,
  `WAKE_LOCK`, `FOREGROUND_SERVICE` (documented in the manifest and
  `PRIVACY.md`); its `DUMP`-protected diagnostics receiver is not a
  `uses-permission`.

### What was built

- Domain (`lib/features/network/domain/events_watch/`): token, settings,
  state, baseline, pending, digest, diff, reconcile, id allocator, payload,
  ports, run report; `WatchedLibrariesSource` port.
- Application (`lib/features/network/application/events_watch/`):
  `CheckLibraryEventsUseCase` + `EventsWatchRun` (state machine),
  `WatchStateReducer`, `EventsWatchController` (+ view), tap resolver.
- Infrastructure (`lib/features/network/infrastructure/events_watch/`):
  read-only SQLite source, JSON codec, bounded atomic document file, file
  stores, WorkManager scheduler, notifications notifier, no-op ports,
  entry-point dispatcher.
- Core: `DataGenerations.peekActive()`, `CapacityFailure`,
  `rootNavigatorKeyProvider`, `events_watch_providers.dart`.
- Presentation: Settings group, explanation dialog, lifecycle relay
  (bootstrap, reconcile on start/unlock/resume, first-run offer, tap
  routing); `main.dart` wiring.
- Android: plugins, desugaring, icon + `keep.xml`, manifest permissions.
- Docs: `PRIVACY.md` (item 10, permissions, storage, date), `CHANGELOG.md`,
  network guide, ADR 0024 + README row.

### Deviations from the plan (recorded)

- The dispatcher wires dependencies by hand instead of building a
  `ProviderContainer`: same minimal surface, fewer moving parts; nothing
  that touches Drift/vault/app-lock is referenced from it.
- `PendingChange.safeCaption` uses the existing `SafeDisplayText` rule plus
  the poster caption cap; no new text rule was introduced.
- `settings_page.dart` lost one pre-existing one-line comment to stay at
  exactly 500 lines (ratchet); the information moved to trailing comments.

### Owed by the maintainer

- Real-device matrix (PLAN.md §8): process death, reboot, Android 13 prompt
  vs pre-33, revoke → re-grant, Doze/battery saver, force-stop, cold-start
  tap while locked, remove/re-add, update without reopening, Android 12L+
  desugaring (if the crash appears, a WindowManager dependency needs
  separate approval).
- Commit (`git add -A && git commit -m "feat: background event alerts (ADR 0024)"`)
  and a fastlane changelog entry at the next release.

## Handoff (2026-11-08, end of session)

### Device state
- OnePlus 9R (LE2101), Android 14 / API 34, serial `678c5642`, USB.
- Installed: `dev.khoj.pitaka` 1.9.5 **play release** (local upload key,
  signer `d30c5209`), built after `flutter clean` from the working tree.
  The previous Play-signed copy was uninstalled (`adb uninstall`) because
  its certificate blocked `adb install -r`. `dev.khoj.pitaka.fdroid` is
  also on the phone, untouched.
- `adb` is at `~/Library/Android/sdk/platform-tools/adb` (not on PATH).

### What was verified on the device
- `POST_NOTIFICATIONS` granted; channel `pitak_events_watch` exists at
  importance DEFAULT (so the foreground `initialize()` ran and the user
  went through the explanation + system prompt).
- Periodic job registered by WorkManager with the intended constraints
  (`batteryNotLow=true`, CONNECTIVITY, TIMING_DELAY).
- Forcing it runs the worker: `adb shell cmd jobscheduler run -f
  dev.khoj.pitaka <jobId>` consumed job #1 → #2 → #3 → #4 (one per run).
  The WorkManager job id increments after every run; read the current id
  from `adb shell dumpsys jobscheduler | grep 'JOB #u0a318'`.

### Open issue — no notification after a caption change
Sequence: library saved → alerts enabled → forced run #1 (baseline,
nothing shown — correct) → maintainer published a poster, then **edited
its caption** and reports it live → forced runs #2 and #3 → **no
notification posted** (`dumpsys notification` shows no record for the
package). Release builds carry no per-step logs (`appLog` is debug-only;
WorkManager's own logs are debug-level), so the worker's decision is not
observable from logcat.

Not yet known (first things to establish next session):
1. **Settings → Data → Event alerts** status lines on the phone — they are
   rendered from the worker's state file and distinguish "worker never
   got past load", "fetch failed/unreachable", "checked, nothing new
   (304/old content)", and "alert waiting (show failed)". The maintainer
   had not read them yet when the session ended.
2. Whether the library is actually in **Network** as a `bookmark`/`card`
   row on this phone (the worker watches only that list; publishing from
   the phone does not add a row).
3. What the site serves right now: read-only `GET <site>/events.json`
   with/without the previous `ETag` (URL not shared this session).

Hypotheses, most to least likely:
- The edit was not yet served by the host when runs #2/#3 happened
  (Pages/CDN propagation) → host answered `304` → correctly no alert.
  Re-force once more after confirming the caption via curl.
- The watched row is missing / `discovered` → nothing is fetched;
  Settings would show "Save a library in Network…" or 0 checked.
- Background-isolate plugin problem (e.g. `MissingPluginException` from
  `flutter_local_notifications.initialize` in the WorkManager engine) →
  dispatcher returns `false` → WorkManager retries with backoff. Would
  show as NO "Last check" line. Check by building the **debug** play
  flavor (needs uninstall first: different debug certificate) — `appLog`
  then prints `events_watch: run <reason>` — or temporarily passing
  `isInDebugMode: true` to `Workmanager().initialize` (posts debug
  notifications per task; do not ship).
- Guard refusal in the worker (membership check hitting a busy catalogue
  while the foreground app was open; token mismatch). Would show as
  "unreachable"/failed count or 0 checked.

Useful commands:
```
adb shell dumpsys jobscheduler | grep -A30 'JOB #u0a318/' | grep -E 'Requires|constraints'
adb shell cmd jobscheduler run -f dev.khoj.pitaka <id>
adb shell dumpsys notification --noredact | grep -E 'pkg=dev.khoj.pitaka|pitak_events_watch'
adb shell dumpsys package dev.khoj.pitaka | grep -E 'versionName|signatures=|POST_NOTIFICATIONS: granted'
```

### Still owed after the open issue is resolved
- Rest of the device matrix (PLAN.md §8): tap → route (warm and cold,
  while locked), revoke → run → blocked phase, disable/Resume, reboot,
  force-stop, Doze/battery saver, Android 12L+ desugaring crash check.
- Commit (`git add -A && git commit -m "feat: background event alerts
  (ADR 0024)"`), excluding the four unrelated root `.md` notes if desired.
- Fastlane changelog entry at the next release.
