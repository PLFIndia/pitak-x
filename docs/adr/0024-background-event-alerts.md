# ADR 0024: Background event alerts for saved libraries

- **Status:** Accepted
- **Date:** 2026-11-07

## Context

Users save other Pitak libraries (by address or in-person card) and those
libraries publish up to two event posters in a public `events.json`. Until
now a user only learned about a new poster by opening the library. The
request: be told while the app is closed, on Android.

Constraints (PLAN.md 2026-11-07, decisions 1–16):

- Privacy: a scheduled request reveals a *bookmark relationship* to the host,
  not just an IP; a stored library name may be a private label the user
  typed; watch bookkeeping lives in plaintext private storage. Nothing may
  be logged (URL, label, caption, raw exception).
- One writer per file. The foreground and a WorkManager isolate can run at
  the same time; neither may open the Drift catalogue path that migrates and
  repairs, and no Dart file lock excludes another isolate in-process.
- `workmanager 0.6.0` returns from register/cancel before the native
  operation completes and destroys the Dart engine on `onStopped` without
  signalling Dart (`BackgroundWorker.kt:113-141`). Only
  `isScheduledByUniqueName` is authoritative.
- `flutter_local_notifications 20.1.0` requires core-library desugaring and
  resource keeping for the icon; `notify(id)` replaces the same id.
- Realistic scale is ≤ 20 saved libraries (usually < 5).
- F-Droid purity: no gms/play/firebase/mlkit may enter any flavor.

## Decision

Add an Android-only periodic WorkManager job (fixed 12 h + flex, connected,
battery-not-low, exponential backoff) that reads `events.json` of
user-saved libraries only, diffs posters against a per-site baseline, and
submits one grouped local notification per library plus a summary.

Architecture:

- **Two documents, two writers.** `events_watch_settings.json` is written
  only by the foreground `EventsWatchController` (through a `SerialOpQueue`).
  `events_watch_state.json` is written only by the worker's
  `WatchStateReducer` (serialized commit queue; publishes after the write).
  Both are bounded (16 KiB / 512 KiB, ≤ 100 sites, ≤ 2 pending per site,
  JSON depth ≤ 8), strictly decoded, and replaced via unique temp + flush +
  rename. A newer schema is never overwritten.
- **Identity = incarnation + epoch** (`WatchSettingsToken`). Epoch bumps on
  every explicit enable/disable; incarnation is a fresh UUID on first
  creation and on reset. Every baseline and pending entry carries the token
  it was made under; a different epoch discards pending, a different
  incarnation also nulls baselines. Compared whole, never by integer.
- **Read-only source.** `SqliteWatchedLibrariesSource` opens its own
  `sqlite3` read-only connection (`query_only`, 250 ms `busy_timeout`) on
  the catalogue path from `DataGenerations.peekActive()` (new, side-effect
  free), filters `source IN ('bookmark','card')` as raw tokens, rejects
  non-canonical URLs, caps at 100 rows (101 → visible `CapacityFailure`),
  and re-checks the generation on both sides of every read. The foreground
  `busy_timeout`/journal mode is unchanged (decision 12); a busy read fails
  closed and the site is skipped until the next run.
- **Common guard** before every fetch, commit and show: settings token
  unchanged, generation unchanged, delivery still possible, row identity
  `(id, createdAt, siteUrl)` still saved. A removed row is pruned and its
  alert cancelled; a failed check skips, never authorizes.
- **Diff** (`diffPublishedEvents`, pure): length-prefixed SHA-256 of
  `(imageRef, caption)`; new reference → added, changed digest → modified,
  disappearance → nothing. Null baseline or baseline from another token →
  baseline only (quiet first sight / quiet re-enable). Partial read, newer
  schema, duplicate reference → withheld. Validated `304` re-tags the
  baseline; `304` without a local validator retries once unconditionally;
  `404` keeps old posters, clears the validator, withholds pending.
- **Submission** (decision 9, simplified): stable per-library notification
  id derived from SHA-256 of the canonical URL (collisions rehashed with a
  counter; never `String.hashCode`), persisted and reused; posting replaces
  that library's own alert. Summary id 0. No active-inventory inspection or
  cross-run cap. Pending is committed before show and removed only after
  child + summary succeed; a crash in between may repeat an id.
- **Title provenance** (decision 13): the stored `name` is shown only when
  the row's `fetch_status = 'ok'` — i.e. it was overwritten by the
  descriptor's public name (`refresh_run.dart:283`) — otherwise a generic
  title. Lock-screen visibility `private`. Payload is the canonical URL
  only, re-validated against current saved rows on tap.
- **Stop states** (decision 14): explicit disable saves OFF + next token
  first, then cancels regardless; a blocked channel makes the worker write
  `revocationToken = token`, clear pending, null baselines and cancel; a
  later run under the same token stops even if permission returned, until
  the foreground consumes the marker by persisting OFF. Settings ON with no
  registered (or unknown) job shows "not scheduled" and requires explicit
  Resume; nothing is auto-repaired.
- **Default ON** (decision 1) is an *offer*: with a saved library and no
  settings file, the app shows the explanation once per session while
  unlocked; "Turn on" enables (Android 13+ prompt follows), "Not now"
  persists OFF with the explanation acknowledged.
- **Worker non-overlap** relies on AndroidX unique periodic work (next
  period starts only after the current run completes) plus the token guard
  for the cancel + re-enqueue window while the old engine is being
  destroyed. A real timer aborts in-flight HTTP at the 5-minute deadline.

## Consequences

- New direct dependencies `workmanager ^0.6.0`,
  `flutter_local_notifications ^20.1.0` (brings `androidx.work`,
  `androidx.core/media`, `gson`); `isCoreLibraryDesugaringEnabled = true` +
  `desugar_jdk_libs 2.1.4`; `res/raw/keep.xml` keeps
  `ic_stat_pitak_events`; manifest declares `POST_NOTIFICATIONS`/`VIBRATE`
  and documents the permissions `androidx.work` merges. `fdroidRelease`
  classpath verified free of gms/play/firebase/mlkit.
- `DataGenerations.peekActive()` and `CapacityFailure` are new public API.
- `MaterialApp` gains a `navigatorKey` (`rootNavigatorKeyProvider`) and the
  `EventsWatchLifecycleRelay` above it.
- The foreground never writes the state file; the worker never writes the
  settings file. Adding a second writer to either requires revisiting this
  ADR.
- Not promised: exact timing, guaranteed OS display, image-byte change
  detection, removal alerts, iOS, or recovery of an intent neither storage
  nor the scheduler persisted. A failed OFF save with a successful cancel
  surfaces as a storage error immediately and, after process death, as
  "not scheduled" requiring Resume.
- Enforcement: `test/features/network/{domain,application,infrastructure,
  presentation}/events_watch/` (reads leave the catalogue byte-identical;
  EXCLUSIVE lock fails closed; token/epoch/incarnation rules; guard and
  stop-state matrix; privacy of notification payloads), architecture
  boundary tests, and the manual device matrix in PLAN.md §8.
- Device verification still owed by the maintainer: process death, reboot,
  Android 13 prompt vs pre-33, revoke-then-regrant, Doze/battery saver,
  force-stop, cold-start tap while locked, Android 12L+ desugaring.
