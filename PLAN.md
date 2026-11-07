# Background event notifications for bookmarked libraries — plan

- **Status:** Planned. Decisions 1–4 made; safety contracts added and
  Decisions 5–10 remain as marked; awaiting go-ahead to implement.
  No code written.
- **Date:** 2026-11-07
- **Review hardening:** 2026-11-07 — added explicit read-only database,
  cross-isolate concurrency, fetch/diff, delivery, cold-start and Android
  setup contracts.
- **Branch:** `reminders` (after `bad362e`)
- **Previous plan:** borrower limits, complete, in git history (`bad362e:PLAN.md`).

## Understanding

A user has Library A saved in the Network tab. Library A publishes (or
changes) an event poster on its public site. The maintainer wants the phone
to show an OS notification — **even when the app is closed** — saying an
event was added or modified, with the poster's caption as the body when the
publisher wrote one. The feature must have an in-app switch to turn it off.

Decision 2 interpretation (decided): "iff added by user" = only libraries
the user saved themselves (`NetworkSource.bookmark` / `card`), not rows that
arrived via hub discovery (`NetworkSource.discovered`).

"Even when the app is closed" means normal background execution or process
death. WorkManager is best-effort: force-stop, OEM background restrictions,
Doze and battery policy can delay or prevent a run; the UI and guides must
not promise exact delivery times.

Non-goals: push servers (no server exists; this is device polling), iOS
background work (Decision 4), notifying on poster removal, notification
history screen, per-library mute.

## Privacy & threat notes

This is the app's **first unattended network activity**. Today every fetch
follows a tap (`AndroidManifest.xml:12` promises INTERNET "only on explicit
user action"; `PRIVACY.md` must be updated).

- **Who learns what:** each watched library's host (GitHub Pages / Cloudflare)
  sees the device's IP, the canonical site/`events.json` URL, request timing
  and the stable Pitak User-Agent. That reveals "this IP has me bookmarked
  and checks every N hours" even when the user is not using the app; timing
  and the URL can also be correlated across requests. There are no cookies
  or credentials, and the same https-only URL policy as the foreground fetch
  applies (`published_site_url_policy.dart:13`). Do not describe IP as the
  only metadata exposed.
- **Mitigations:** default ON (Decision 1, maintainer), but no permission
  prompt or schedule is created until foreground initialization has completed
  and at least one user-saved library exists. The switch copy states plainly
  that the phone contacts each saved library on a schedule, including on
  metered connections (`NetworkType.connected` is not Wi-Fi-only). Only
  user-saved libraries are polled (Decision 2), with a long interval,
  battery-not-low and network-connected constraints. The worker re-reads the
  setting and effective notification-delivery state before every fetch and
  again before saving or notifying. Disabling persists OFF and cancels the
  WorkManager job; cancellation of an already-running request is best-effort,
  so the in-task checks and revision checks are mandatory.
- **What is stored locally:** per watched site, a SHA-256 digest of an
  unambiguous, length-prefixed encoding of `imageRef` and caption, an optional
  entity-tag validator, and the last check time. The versioned state also
  contains a revision, settings and only **undelivered** changes awaiting
  notification. Public data and saved site URLs only; written to the app's
  private support dir (excluded from Android backup by
  `data_extraction_rules.xml`). Delivered changes are removed: the pending
  queue is not a notification-history screen. Snapshots are pruned or
  deliberately migrated when rows are deleted, moved or restored.
- **Notification content:** the library's public name and the public caption
  — data the library itself published — after the project's safe-display-text
  checks. Empty captions get a fixed fallback body. Shown with default
  lock-screen visibility; nothing private is intentionally included.
- **Untrusted inputs:** `events.json` goes through the existing bounded,
  size-capped reader (`bounded_published_events_fetcher.dart`). Partial or
  newer-schema reads are not authoritative for watch diffs. The notification
  tap payload (siteUrl) is canonicalized and validated against the saved rows
  before navigating (§6.5 deep links are untrusted).
- **New permission:** `POST_NOTIFICATIONS` (Android 13+ runtime), requested
  from the foreground after the UI is ready when default-on initialization
  finds watched libraries, or when the user turns the switch on. Denial
  leaves the switch OFF and cancels scheduling (fail closed). Android < 33
  has no equivalent runtime prompt: check the effective notification setting
  instead and document that default-on is not an explicit consent prompt on
  those versions. The worker also checks global/channel delivery state so
  revocation or a blocked channel while the app is closed cannot cause
  polling without a way to notify. `VIBRATE` is merged in by the plugin
  manifest; document both permissions in `AndroidManifest.xml`.
- **Background isolate safety:** it must never run the generation repair
  path (`DataGenerations.open()` writes the pointer), the normal
  `AppDatabase` open/migration/`beforeOpen` path, or the legacy-bookmarks
  migration. It uses a dedicated read-only SQLite query for bookmarks and
  writes only its own JSON state under a cross-isolate lock with revision
  checks and unique temp files. It does not write the published-file cache.
  The background `ProviderContainer`, DB and HTTP clients are disposed in
  `finally`.

## Investigation notes (verified 2026-11-07; review corrections included)

- `lib/features/network/domain/entities/published_events.dart` — up to 2
  `PublishedEventPoster(imageRef, description)`; no ids or timestamps.
  `published_events_codec.dart:57-94` drops malformed rows, replaces an
  invalid caption with `''`, and sets `hasPartialRead`; those omissions must
  not become watch changes.
- `lib/features/network/domain/usecases/load_published_events_use_case.dart`
  + `infrastructure/bounded_published_events_fetcher.dart` provide the
  bounded foreground fetch. The fetcher DOES support `If-None-Match` and
  `304` (`bounded_published_events_fetcher.dart:5-7,66-97`). Its result
  variants are fresh, unchanged, missing and failed. The loader can return a
  saved copy after failure and writes the published-file cache
  (`published_file_loader.dart:104-158`); neither stale data nor an
  uncoordinated cache write belongs in the background watch algorithm.
  `PublishedContent.current` distinguishes fresh from saved data but does NOT
  carry the entity-tag validator (`published_content.dart:26-43`). The
  foreground observation boundary therefore needs a small domain result
  containing events, freshness/completeness, checkedAt and validator (or an
  equivalent watch-specific fresh-result path); it must not infer validator
  state from a racy cache read.
- `network_refresh_controller.dart:60` — manual Refresh fetches only
  `library.json`. The published-catalogue page independently loads and
  reloads `events.json` through `PublishedEventsController`
  (`published_catalogue_page.dart:84-90,126-130`), so a Refresh-only hook
  cannot provide foreground de-duplication.
- `network_library.dart:30-38` — `NetworkSource { bookmark, card, discovered }`;
  `:106-154` row fields incl. `siteUrl`, `name`, `fetchStatus`.
- `database_providers.dart:36-44` — the catalogue DB (holding
  `network_libraries`, `tables.dart:182`) is NOT encrypted; opened via
  `activeDataGenerationProvider`. `data_generations.dart:118-147` `open()`
  REPAIRS (writes pointer); `_readPointer()` at `:266` is the read-only
  primitive to expose as `peekActive()`.
- The normal `AppDatabase` path is NOT background read-only:
  `app_database.dart:56-124` runs migrations and `beforeOpen`, including
  index/FTS setup and possible FTS rebuild. `networkRepositoryProvider`
  (`network_providers.dart:101-131`) also awaits a legacy-bookmarks migration
  that can write the DB/preferences. The watch source therefore needs a
  dedicated `sqlite3` `OpenMode.readOnly` connection (or an equivalent Drift
  executor with ALL migration/open callbacks disabled), never those providers.
- `RefreshRun`/`NetworkDiscoveryPlan` has a 500-row run cap, but that cap is
  not inherited by a new watched-library query. The watch run needs its own
  site budget and total deadline, with deterministic oldest-check ordering.
- No notification plugin or background scheduler is in `pubspec.yaml`.
  Shipping platforms: Android (flavors `fdroid`, `play`, `build.gradle.kts:58-64`,
  minSdk ≥ 23 at `:75`); desktop dirs exist and CI runs tests on Linux. iOS
  `Info.plist` has no background modes; `hardened_secure_storage.dart:18`
  says macOS is not a shipping target.
- Plugin audit (pub cache, `android/build.gradle`):
  `flutter_local_notifications-20.1.0` → androidx.core, androidx.media,
  gson. `workmanager-0.6.0` → androidx.work, androidx.concurrent. **No
  gms/play/firebase/mlkit** → F-Droid rule (AGENTS §9) satisfied. Still run
  the `docs/RELEASING.md` §2 classpath check after adding.
  `flutter_local_notifications` merges `POST_NOTIFICATIONS` + `VIBRATE`;
  `workmanager` requires a top-level `@pragma('vm:entry-point')`
  `callbackDispatcher` and has no desktop impl.
- The cached `flutter_local_notifications` 20.1.0 setup documentation also
  requires core-library desugaring and compileSdk ≥ 35, and warns about
  release resource keeping for notification icons. Its tap callback does
  NOT cover a notification that launches a terminated app;
  `getNotificationAppLaunchDetails()` is required for cold start.
- `AndroidManifest.xml:1-20` — every permission has a plain-English comment;
  INTERNET currently promises "only on explicit user action".
- Settings precedent: `settings_page.dart`, `isbn_lookup_settings_tile.dart`
  (`SwitchListTile`), `prefs_settings_repository.dart`; file-JSON precedent
  `file_events_repository.dart:86-93` (temp + rename). Atomic rename alone
  does not serialize foreground/background read-modify-write cycles.
- `crypto ^3.0.3` (sha256) and `path_provider` already present.
- `publish_contact_links.dart`, `cloudflare_limits.dart:50` — events body cap
  64 KiB.

## Proposed approach

**OSS reference (from memory, unverified):** Android's own guidance for
periodic polling (WorkManager `PeriodicWorkRequest` with
`Constraints(NetworkType.CONNECTED, requiresBatteryNotLow)`), and the
Tusky/AntennaPod pattern of "background refresh + notification channel +
re-check the user setting inside the worker". We borrow the shape, not code.
Plugins are exactly `workmanager: 0.6.0` and
`flutter_local_notifications: 20.1.0`; §6 approval covers both the pinned
pub additions and the required Gradle/desugaring changes.

### 1. Domain (pure Dart) — `lib/features/network/domain/events_watch/`

```dart
/// One poster's identity + content digest. Keyed on imageRef because the
/// wire format has no ids.
final class PosterDigest { final String imageRef; final String contentSha256; }

/// What the app last saw for one site. checkedAt is the last successful
/// host check; validator is the entity tag for the next conditional fetch.
final class EventsWatchSnapshot {
  final String siteUrl;
  final List<PosterDigest> posters;
  final int checkedAt;
  final String? validator;
}

/// One versioned document. revision changes on EVERY mutation; pending
/// contains only changes not yet delivered, never notification history.
final class EventsWatchState {
  final int schemaVersion;
  final int revision;
  final EventsWatchSettings settings;
  final Map<String, EventsWatchSnapshot> snapshots;
  final List<EventChange> pending;
}

sealed class EventChange {
  final String siteUrl;
  final String libraryName;
  final String imageRef;
  final String description;
  final String contentSha256;
}
final class EventAdded extends EventChange {}
final class EventModified extends EventChange {}

/// Pure diff, called ONLY for a complete, fresh, supported-schema payload.
/// previous == null → first sight: returns [] (baseline only).
/// New imageRef → EventAdded; same imageRef, different digest → EventModified;
/// disappeared imageRef → nothing. Duplicate current imageRefs make the
/// payload non-authoritative for watch (no diff), never response-order dependent.
List<EventChange> diffPublishedEvents({EventsWatchSnapshot? previous, required PublishedEvents current, ...});

/// User setting. Default: enabled = true (Decision 1). Interval is a
/// domain constant, not a setting (Decision 3).
final class EventsWatchSettings { final bool enabled; }
const eventsWatchInterval = Duration(hours: 12);
```

Ports (domain, abstract; all IO is asynchronous and expected failures are
typed):
- `EventsWatchStore` — `Future<Either<Failure, EventsWatchState?>> load()` and
  `Future<Either<Failure, Unit>> save(EventsWatchState state, {required int expectedRevision})`.
  A stale revision returns `StaleStateFailure` and never overwrites newer
  settings or snapshots. An unreadable/corrupt store is a failure, not an
  implicit enabled/default state.
- `WatchedLibrariesSource` — `Future<Either<Failure, List<WatchedLibrary>>>`
  (siteUrl + name, user-saved rows only).
- `EventsWatchFetcher` — returns `fresh`, `unchanged`, `missing` or `failed`;
  `fresh` carries a complete `PublishedEvents` and optional validator. It
  never returns a stale saved-copy fallback as fresh data.
- `BackgroundScheduler` — `Future<Either<Failure, Unit>> schedule()` (fixed
  `eventsWatchInterval`) and `cancel()`.
- `LocalNotifier` — asynchronous `requestPermission()`, `canNotify()` and
  `show(EventChange)` with typed failure results. `canNotify` includes the
  effective global/channel state, not just the runtime permission.

The digest uses length-prefixed fields (not ambiguous string concatenation).
A stable notification/change key is derived from siteUrl, imageRef, change
kind and the NEW digest, so retries address the same change while a later
modification gets a new key. Empty captions use a fixed safe fallback body.

### 2. Infrastructure
- `FileEventsWatchStore` — `<support dir>/events_watch.json`, schema 1,
  raw-length and snapshot-count caps, strict decode (unreadable →
  `StorageFailure`), and temp+rename writes with unique temp names. A
  cross-isolate OS file lock covers every read/modify/write cycle; `save`
  checks `expectedRevision` while holding that lock. A stale writer retries
  from fresh state or aborts without notifying; it can never overwrite a
  newer disable, snapshot or pending-delivery mutation. A **file, not
  SharedPreferences**, avoids per-isolate preference caches. Prune snapshots
  AND matching pending changes for deleted rows. Pending is always cleared
  on a move; only a confirmed same-identity move may migrate the baseline,
  while an uncertain move clears it. Restore clears pending and retains only
  matching canonical identities, resetting uncertain baselines rather than
  risking false alerts.
- `ReadOnlyWatchedLibrariesSource` — `SELECT site_url, name FROM
  network_libraries WHERE source IN ('bookmark', 'card')` through a dedicated
  `sqlite3` `OpenMode.readOnly` connection (or an equivalent executor with
  migrations and all open callbacks disabled). Never use
  `appDatabaseProvider`, `networkRepositoryProvider`, `AppDatabase` migration,
  `beforeOpen`, or the legacy-bookmarks migration. Close the connection in
  `finally`; a missing/changing generation or DB failure skips the run
  without fetching.
- `BoundedEventsWatchFetcher` — adapts the existing bounded events fetcher,
  including its validator/`304` support, without writing the published-file
  cache. It maps fresh/unchanged/missing/failed explicitly. A `304` without
  a matching local baseline retries once without a validator; a failure
  keeps the old snapshot and is never interpreted as an empty event list.
- `WorkmanagerBackgroundScheduler` (Android) + `NoopBackgroundScheduler`
  (desktop/iOS) chosen by `Platform`. Unique periodic task name,
  `NetworkType.connected` + `requiresBatteryNotLow`, and explicit backoff.
  Use `keep`/`update` for an unchanged registration; do NOT `replace` on
  every launch and reset the next-run timing. Schedule only when enabled,
  delivery is permitted and at least one watched row exists; cancel on
  disable, revocation or an empty watched set.
- `FlutterLocalNotifier` + `NoopLocalNotifier`. Initialize the plugin in the
  foreground and in the WorkManager isolate, create one stable "Library
  events" channel, and configure a release-safe notification icon. Payload =
  canonical siteUrl; notification IDs derive from the stable change key.
- `DataGenerations.peekActive()` — read-only resolve that NEVER repairs;
  returns null when the pointer is invalid (background exits without
  fetching; the foreground repairs on next launch). Re-check the generation
  immediately before opening the read-only DB so a restore race fails closed.

### 3. Application
- `CheckLibraryEventsUseCase` returns
  `Future<Either<Failure, EventsWatchRunReport>>`, not a bare list. A store
  load failure, disabled setting, failed delivery-state check, unavailable
  generation or empty watched set fails closed without fetching; disabled or
  empty states also cancel the schedule. The source is read in deterministic
  oldest-`checkedAt`, then siteUrl, order, with bounded concurrency, a hard
  site budget and a total run deadline (Decision 10). Rows not reached keep
  their snapshots and are prioritized on the next run.
- Before EVERY fetch, and again before each state commit or notification,
  the use case re-reads `enabled` and `canNotify`. A disable/revocation or a
  stale revision stops new work; an already-running HTTP request is aborted
  where the fetcher supports it and is never followed by a notification.
- Per-site outcome rules:
  - **Fresh, complete, supported schema:** diff against the previous
    snapshot. First sight creates a baseline without alerts; added/modified
    posters become pending changes. Save the new snapshot, validator and
    pending changes atomically with the expected revision.
  - **Partial or newer schema:** do not diff, enqueue or advance the poster
    snapshot. Record a bounded per-site check result instead; malformed or
    omitted data must never become a false add/modify/remove.
  - **Unchanged (`304`):** update only the check timestamp after confirming
    the validator belongs to the stored snapshot; do not diff.
  - **Missing (`404`):** retain the last poster baseline, update only the
    check timestamp, clear the validator and do not diff or emit removal
    alerts. If no baseline exists, create an EMPTY one so a later first
    poster is an addition, not a suppressed first-sight baseline. A later
    fresh payload compares against the retained/empty baseline, avoiding
    re-add spam after a temporary 404. A fresh, complete empty `200` is
    authoritative and advances to an empty snapshot without removal alerts.
  - **Failed:** retain snapshot, validator and pending state; never treat a
    transport/decode failure or a stale saved-copy fallback as fresh data.
- **Delivery is at-least-once, with an explicit disable exception.** The
  background path atomically stores snapshots plus pending changes before
  attempting notifications, then shows at most 5 pending changes in stable
  siteUrl/imageRef/kind/digest order (never network-completion order) per
  run. Successful `show` removes that change under the store lock;
  failures remain pending for retry. A crash after `show` but before the
  removal can duplicate an alert, but a crash cannot silently lose one.
  Remaining pending changes stay queued for the next run; there is no
  lossy "and N more" summary. A hard pending-count/byte cap stops new watch
  commits and surfaces a retryable backlog error rather than growing without
  bound or silently discarding changes; existing pending delivery still
  proceeds so the backlog can drain. Disabling or revoking permission
  atomically persists OFF and clears pending changes while retaining
  snapshots.
- Expected per-site network failures are included in the run report and wait
  for the next scheduled run. Store/DB/notifier infrastructure failures and
  unexpected exceptions are logged by safe type only and return WorkManager
  retry (`false`) with the configured backoff; disabled/already-complete
  runs return success (`true`). No exception escapes the callback.
- `EventsWatchController` (`AsyncNotifier<EventsWatchSettings>`):
  `build()` loads (absent document ⇒ default `enabled: true`, Decision 1;
  corrupt/unreadable ⇒ safe error and no scheduling). An explicit app-start
  owner calls `ensureScheduled()` AFTER the first frame, not the Settings
  tile: no watched rows ⇒ cancel without a permission prompt; enabled ⇒
  request/check delivery permission in the foreground; denied/revoked ⇒
  persist OFF, clear pending and cancel; granted ⇒ `schedule()` using
  `keep`/`update`. Watched-set mutations invoke the same reconciliation:
  the first saved row starts the permission/schedule flow, the last row
  cancels, and delete/move/restore performs the snapshot/pending cleanup
  described above. `enable()` follows the same path and never schedules
  after a failed save. `disable()` persists OFF + clears pending before
  cancelling, ALWAYS attempts cancellation even if that mutation fails, and
  reports any save/cancel failure without claiming success. A failed disable
  requires visible reconciliation/retry before a later launch may schedule
  again; an unreadable store remains OFF. Snapshots are kept according to
  Decision 6. State publishes only after the corresponding successful
  mutation; scheduler failures are visible and retried on the next launch.
- `lib/core/background/background_dispatcher.dart` —
  `@pragma('vm:entry-point') callbackDispatcher`: initializes the notification
  plugin, builds a MINIMAL fresh `ProviderContainer` with only the
  background-safe read-only source, peek-only generation, fetcher, store and
  notifier (no normal `AppDatabase`/network repository, legacy migration,
  app-lock, Rust initialization, refresh controller or published-cache
  writes), runs the use case and maps its result to WorkManager success or
  retry. `try/finally` disposes the container, DB and HTTP clients; no raw
  URLs, captions or exception messages are logged.
- **Foreground observation is shared, not Refresh-only.** Manual Refresh and
  every fresh `PublishedEventsController` load/reload call one observation
  coordinator. Only current, complete payloads update watch snapshots;
  saved-copy fallbacks never do. Explicit foreground observations update
  baselines even while alerts are disabled, remove matching pending OS
  changes, and never create a duplicate OS alert for what the user just saw.
  Manual Refresh additionally returns the changes for an in-app report.
  The coordinator consumes the domain observation result described above,
  including validator and freshness metadata; `PublishedContent` alone is
  insufficient for that commit. Changes not observed while disabled remain
  eligible on re-enable (Decision 6). Revision retries reconcile a
  simultaneous worker write.

### 4. Presentation
- Settings → new group "Library event alerts": `SwitchListTile` with plain
  copy that polling contacts bookmarked libraries about every 12 hours, may
  use metered data and is best-effort under Android battery rules. Show the
  last successful host-check time (not a misleading last-notification time),
  storage/scheduler errors and a no-saved-libraries state. No interval
  selector. Permission-denied/revoked or channel-blocked states show safe
  inline text with "Open system settings"; no permission prompt is shown
  when there is nothing to watch.
- Notification tap → validate the canonical siteUrl against the current
  user-saved rows, then open that library's published catalogue page;
  otherwise open the Network tab. Handle BOTH a running-app callback and a
  terminated-app launch via `getNotificationAppLaunchDetails()`. Queue one
  pending route until the first frame/providers are ready and until the
  existing app-lock gate permits navigation; consume it once and never
  bypass the lock.
- `AndroidManifest.xml`: comment block for `POST_NOTIFICATIONS`/`VIBRATE`
  (merged by plugin) and amend the INTERNET comment ("…or, when Library event
  alerts is ON, on a user-chosen schedule"). Add the required notification
  icon/resource-keeping configuration and the plugin's desugaring setup to
  `android/app/build.gradle.kts`; verify compileSdk/AGP and build a release
  artifact. `PRIVACY.md`, guides and the changelog must describe default-on,
  older-Android behavior, metered polling, revocation and best-effort timing.

### 5. Tests
- Domain: diff matrix (first sight → none; added; modified; removed → none;
  both; reorder; duplicate imageRefs; empty caption; digest canonicalization
  and stability). Partial/newer-schema payloads never diff or advance a
  snapshot.
- Fetch/use-case fakes: fresh `200`, `304`, `404`, transport/decode failure,
  stale saved-copy fallback, validator retry, first `404` → empty baseline →
  later addition, empty fresh `200`, per-site failure isolation,
  oldest-first budget/deadline and deterministic overflow.
  Disabled/revoked before a fetch, between fetches and before commit/show
  proves no new network or notification; an in-flight disable follows the
  cancellation contract.
- Delivery: snapshot + pending commit is atomic; successful show removes
  only that pending change; show failure and process death leave it retryable;
  retry uses the same stable ID; five-per-run cap never drops overflow;
  pending-count/byte cap produces a retryable backlog error; disable clears
  pending but retains snapshots.
- Store: absent → null; round trip; corrupt/oversized/wrong version →
  `StorageFailure`; stale revision → `StaleStateFailure`; concurrent
  foreground/background writers cannot resurrect enabled state or lose a
  newer snapshot; unique temp files and no orphaned temp files; pruning and
  move/restore behavior.
- Read-only watched source: discovered rows excluded; legacy migration and
  normal `AppDatabase` open callbacks are never invoked; DB bytes, schema,
  FTS and preferences remain unchanged; generation/restore races skip
  safely; connections are closed.
- Controller (`ProviderContainer` overrides): absent default, corrupt-store
  fail-closed, no-library no-prompt/no-schedule, permission denied/revoked →
  OFF + cancel, granted → saved then scheduled with keep/update, scheduler
  failure surfaced, disable → OFF + pending clear + cancel, save failure →
  not published.
- Foreground coordinator: manual Refresh AND published-catalogue fresh loads
  update the same baseline; saved copies do not; observed changes remove
  matching pending OS alerts; disabled observations do not enqueue.
- Widget: settings tile toggles, denied/revoked/channel-blocked copy,
  no-library state, first/last watched-row scheduling transitions,
  cold-start and invalid-payload routing, app-lock preservation and a11y
  guideline checks.
- Architecture/tooling: domain purity (automatic), build_runner diff, F-Droid
  classpath check, desktop test run (no-op ports keep Linux CI green),
  desugaring/compileSdk verification and a release Android build with the
  notification icon retained.
- Manual real-device matrix: cold headless release run after process death
  and reboot, Android 13 permission prompt, pre-33 behavior, permission and
  channel revocation while closed, airplane mode, metered connection,
  battery saver/Doze, force-stop/OEM limitation documentation, notification
  tap from terminated and locked states, uninstall/reinstall leaves no orphan
  job, and restore/move/delete lifecycle.

## Decision points

| # | Decision | Status |
|---|---|---|
| 1 | **Default state.** | **Decided (maintainer, 2026-11-07): ON by default** — rationale: polling only touches libraries the user chose to bookmark. Agent flagged the trade-off (AGENTS §3 default-to-not-collecting; existing "only on explicit user action" promise in the manifest/PRIVACY.md) — accepted. On Android 13+ the foreground first-launch path requests `POST_NOTIFICATIONS` only after the UI is ready AND a watched row exists; **denied/revoked ⇒ OFF, pending cleared, nothing scheduled**. Android < 33 has no equivalent runtime prompt, so effective notification settings are checked and the documentation must not call this explicit consent. Existing users with watched rows may start polling after the update; PRIVACY.md, the manifest INTERNET comment and the changelog must say so plainly. |
| 2 | Which libraries are polled | **Decided (follows from the maintainer's rationale):** user-saved rows only (`bookmark`, `card`). `discovered` rows are auto-inserted by Refresh, not bookmarked. The source filters raw stored source tokens, not a permissive unknown-enum fallback. |
| 3 | Interval | **Decided (maintainer, 2026-11-07): fixed 12 h**, a domain constant, no setting. WorkManager treats it as a floor (best-effort under Doze); `keep`/`update`, not per-launch `replace`, preserves registration timing. |
| 4 | Platforms | **Decided (maintainer, 2026-11-07): Android only.** Desktop/iOS get no-op scheduler/notifier ports (Linux CI stays green); the Settings tile is hidden off-Android; no `Info.plist` changes. |
| 5 | First sight of a library = baseline, no notification | Proposed yes, only for a complete fresh supported-schema payload. A partial, failed or stale first read creates no baseline and no alert. |
| 6 | Disabling keeps snapshots (no re-fire on re-enable) | Proposed yes, precisely: disable clears undelivered pending alerts and retains baselines. Already observed/delivered changes do not re-fire; changes not observed while disabled remain eligible on re-enable. Explicit foreground reads while disabled update the baseline without enqueueing. |
| 7 | ADR `0024-background-event-alerts.md` recording the first unattended network path, default-on + permission/revocation behavior, read-only DB, cross-isolate revisions, pending delivery and cold-start rules | Proposed yes |
| 8 | Fetch and missing-file semantics | **Required safety contract:** use the existing conditional fetch support; never diff stale fallback data. `304` only confirms a matching baseline; `404` retains the poster baseline (or creates an empty first baseline), clears its validator and emits no removal alert; a complete empty `200` advances to empty. Partial/newer-schema reads never advance the watch snapshot. |
| 9 | Delivery semantics | Proposed at-least-once pending delivery: snapshot + pending commit precedes `show`; successful show removes pending; crash may duplicate but cannot silently lose; five per run, overflow remains queued; a hard pending cap produces a retryable backlog while existing pending still drains; disable is the explicit cancellation exception. |
| 10 | Run budget | Proposed starting limits: 100 sites and 5 minutes per run, bounded concurrency, oldest-`checkedAt` first, with unprocessed rows prioritized next run. Validate on a real device; any change must retain a hard site cap and total deadline. |

## Steps (not started — awaiting go-ahead)

- [ ] 0. Baseline tests + analyze with pinned SDK (`fvm`); verify the cached
  plugin setup documents and current AGP/compileSdk before editing Gradle.
- [ ] 1. Read `data_generations.dart`, `app_database.dart` and the network DI
  flow fully; add `peekActive()` and a dedicated read-only watched-library
  source with no migration/open-write callbacks + side-effect tests.
- [ ] 2. Domain types, fetch outcomes, canonical digest/diff, revisioned
  state, pending-delivery model and typed ports + tests.
- [ ] 3. `FileEventsWatchStore` with cross-isolate lock, revision/CAS,
  unique temp files, pruning and failure tests; finish read-only source and
  generation-race tests.
- [ ] 4. §6 approval for EXACT pinned `workmanager 0.6.0` and
  `flutter_local_notifications 20.1.0` pub additions AND Gradle changes;
  add desugaring, verify compileSdk/AGP, configure notification icon/keep
  rules and manifest comments; run F-Droid classpath check.
- [ ] 5. Scheduler/notifier ports with Android + no-op impls; foreground and
  background plugin initialization, stable channel, permission/channel
  status checks, backoff and cold-start launch-details scaffolding.
- [ ] 6. Use case + controller + tests for every fetch outcome, partial
  suppression, revision races, disable/revocation, budgets, pending delivery
  and scheduler/save failures.
- [ ] 7. Background dispatcher with minimal overrides and `finally` disposal;
  shared foreground observation coordinator for BOTH manual Refresh and
  published-catalogue loads/reloads.
- [ ] 8. Settings UI + running/cold-start tap routing + app-lock-safe pending
  navigation + widget tests; PRIVACY.md, guides, ADR 0024 and CHANGELOG.
- [ ] 9. Full gates (build_runner, format, analyze, tests, F-Droid purity,
  release Android build, goldens if settings golden changes); manual device
  matrix above; report; ask before commit.

## Out-of-scope observations

- Manual Refresh could also fetch `events.json` and show an in-app badge
  without any of the background machinery (the "option A" discussed). The
  foreground observation coordinator is included only to keep snapshots and
  pending delivery consistent across ALL fresh foreground event reads.
- iOS: `BGAppRefreshTask` is opportunistic and would need `Info.plist`
  background modes; not planned.
- Conditional requests (`If-None-Match`) are IN scope because the existing
  fetcher already supports them. They reduce bytes but not the metadata leak.
  Saved-copy fallback remains a foreground viewing concern and is never a
  fresh watch observation.
- Exact background timing, execution after force-stop and OEM-specific
  background execution cannot be guaranteed by WorkManager; these are
  documented limitations, not hidden fallback behavior.

## Result

(pending — review hardening complete; implementation not started)
