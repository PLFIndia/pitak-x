# PLAN.md — current task

Roadmap across sessions: `fix-schedule.md`. This file is the plan for the current
session only.

## Understanding
- Session 2 of the `astra-review.md` remediation. Task: **B01 — app-lock gate
  above the entire navigator** (Blocker).
- Today `AppGate` is only `MaterialApp.home` (`lib/main.dart:62`,
  `lib/core/widgets/app_gate.dart:198`). Every other screen (`app_drawer.dart:28`
  pushes Vault/Publish/Wishlist/Bookmarks/Settings; detail pages; dialogs) sits
  on the navigator *above* home. Re-locking swaps home to `_LockedScreen`, but
  the pushed route stays on top: after a rejected biometric prompt the user is
  still looking at — and can interact with — that route. Reviewer reproduced it.
- Baseline: HEAD `ad47d7c` (== `f3a80a8` + PLAN.md), 794 Flutter tests green,
  cargo 30 green (verified this session before touching code).

## Privacy & threat notes
- Threat: someone holding an unlocked, foregrounded phone resumes the app,
  dismisses the biometric prompt, and keeps reading a screen that was already
  open (worst case: an unlocked borrowers vault page with PII).
- The fix must cover **every** route, dialog and bottom sheet, and block
  **input, focus/keyboard and accessibility semantics** while locked — not just
  paint over them. Recents preview must show the lock screen (already true for
  home; must hold for pushed routes).
- Android back button while locked must not pop hidden routes underneath the
  lock (a hidden dialog's cancel callback would run blind).
- No new data, storage, network or permissions. No secrets involved.
- Honesty unchanged: the gate is a screen cover, not a vault lock (user decided
  Session 1: no vault auto-lock; wording fix folded into M06a).

## Investigation notes (verified in source this session)
- `MaterialApp.builder` wraps the **Navigator itself** (`flutter/src/widgets/app.dart:1721–1727`):
  `builder(context, routing)` where `routing` is the `Navigator`. Anything we
  put around `child` there sits above every route, dialog, sheet and snackbar
  host (`ScaffoldMessenger` is outside builder at `material/app.dart:1047`; a
  `Scaffold` inside builder tolerates `ModalRoute.of == null`, `scaffold.dart:615`).
  The app already uses this slot for `EdgeToEdgeSafeArea`.
- `Offstage` (`rendering/proxy_box.dart:3834–3952`) stops **painting, hit
  testing and semantics** but keeps state and layout. `Visibility(maintainState:
  true)` (`widgets/visibility.dart:266–289`) = `ExcludeFocus` (unfocuses any
  focused descendant, `focus_manager.dart:583–594`) + `TickerMode(off)` +
  `Offstage`. That is exactly "cover and freeze the whole navigator".
- Android back: `WidgetsBinding.handlePopRoute` (`binding.dart:1113`) asks
  observers **in registration order**; `WidgetsApp` registers in its
  `initState` (`app.dart:1467`) and pops the navigator (`app.dart:1607–1619`).
  A widget **above** `MaterialApp` registers first and can consume back while
  locked. Predictive-back is only handled by route transition builders this
  app does not enable — nothing else to intercept.
- Existing tests: `test/core/widgets/app_gate_test.dart` (8 tests, all
  home-only; uses `MaterialApp(home: AppGate())` — must be re-targeted),
  `test/widget_test.dart` boots the real `PitakaApp`. `flutter_test` finders
  skip offstage by default, so "Library hidden" assertions stay meaningful;
  `skipOffstage: false` lets tests assert routes were *preserved* underneath.
- `LockSuppressor` (a `@riverpod` notifier living in `core/widgets/`) is the
  precedent for lock-related Riverpod state in core.

## Proposed approach (with OSS references)
Three small pieces replace the current single stateful widget:

1. **`AppLockController`** — `@Riverpod(keepAlive: true)` `Notifier<AppLockPhase>`
   (`splash | locked | unlocked`), `lib/core/app_lock/app_lock_controller.dart`.
   Holds the state machine now buried in `_AppGateState`: `onSplashDone()`
   (awaits settings, fail-closed), `onAppLifecycle(state)` (re-lock on
   `paused/hidden`, re-prompt on `resumed`, honours `LockSuppressor`),
   `unlock()` (single in-flight prompt, fail-closed, `noCredential` detection),
   `disableAppLock()` (recovery path, persisted-or-stay-locked). Unit-testable
   with `ProviderContainer` — no widget needed.
2. **`AppLockObserver`** — thin `ConsumerStatefulWidget` + `WidgetsBindingObserver`
   placed **above** `MaterialApp` in `PitakaApp`. Forwards lifecycle events to
   the controller; `didPopRoute` returns `true` while not unlocked (back is
   consumed; see decision point 1).
3. **`AppGate(child:)`** — installed in `MaterialApp.builder` (next to
   `EdgeToEdgeSafeArea`). Renders `Stack[ Visibility(visible: unlocked,
   maintainState: true, child: navigator), splash | locked screen ]`. `home`
   becomes `LibraryPage` directly. Locked/splash screens reuse the existing
   `_LockedScreen`/`SplashScreen`.

OSS reference (from memory, unverified — will note as such in code comments):
Bitwarden mobile and Signal-Android both implement the lock as a full-window
overlay owned by the activity/root, not as a route, and treat back on the
lock screen as "leave the app". The Flutter `flutter_app_lock` package uses the
same `MaterialApp.builder` slot for its overlay. Nothing is copied; only the
placement pattern is adopted.

Behaviour change to flag: `LibraryPage` is now built (offstage) during the
splash/locked phases instead of after unlock. Its data begins loading behind
the cover; nothing is painted, hit-testable, focusable or exposed to
accessibility until unlocked.

## Decision points
1. **Back button while locked/splash:** (a) consume it and call
   `SystemNavigator.pop()` — leaves the app like Signal/Bitwarden; or (b)
   just consume it (app stays on the lock screen). **Decided (user, Session 2): (a).**
2. **Route state on re-lock:** keep routes/dialogs alive underneath the cover
   (proposed — user resumes exactly where they were after a good unlock) vs.
   tear the navigator down on lock (simpler, loses in-progress edits).
   Proposed: **keep**.
3. Test harness: re-target `app_gate_test.dart` to the new composition and add
   one end-to-end test on the real `PitakaApp` so the `main.dart` wiring itself
   is guarded (widget_test.dart already boots `PitakaApp` with fakes).

## Steps
- [x] Verify repo state vs `fix-schedule.md` Session 1 record.
- [x] Baseline gates: analyze ok, format ok, flutter test 794 passed, cargo 30 passed.
- [x] Re-read every B01 evidence line + framework source for builder/Offstage/back.
- [x] **Regression test first** — `test/app_lock_navigator_test.dart` boots the
      real `PitakaApp`: pushed Settings route + open dialog must be offstage and
      inert after a rejected re-lock prompt, preserved underneath, restored on
      a good unlock; back while locked → `SystemNavigator.pop`, hidden route
      NOT popped. **Failed on the old code** (route/dialog still onstage).
- [x] `AppLockController` (`lib/core/app_lock/`, `@Riverpod(keepAlive)`) +
      22 unit tests in `test/core/app_lock/app_lock_controller_test.dart`.
- [x] `AppLockObserver` above `MaterialApp`; `AppGate(child:)` in
      `MaterialApp.builder`; `home` is now `LibraryPage`.
- [x] Re-targeted the 8 existing gate tests to the new composition.
- [x] Gates: analyze 0 issues, format 0 changed, **flutter test 819 passed**
      (794 + 25 new), cargo 30 passed; build_runner re-run produced no diffs.
- [x] `fix-schedule.md` §1/§3/§5 updated. Commit approval: pending user.

## Out-of-scope observations
- `UnfocusOnPause` still wraps only `home`; it works globally via
  `FocusManager`, so left alone (its own doc says so).
- Vault auto-lock: decided out (Session 1); wording fix is M06a.
- M07 (stale vault completions after lock) is the next scheduled item.

## Result
B01 fixed in one session (scheduled for two). The lock is now a cover painted in
`MaterialApp.builder` over the whole navigator; routes/dialogs beneath it are
kept alive but unpainted, un-hit-testable, unfocusable and hidden from
accessibility (`Visibility(maintainState: true)`); Android back while locked
leaves the app instead of popping hidden routes. Lock logic moved from widget
state into `AppLockController` (unit-tested with `ProviderContainer`). All
prior behaviour (fail-closed settings load, single in-flight prompt, Q5
recovery, LockSuppressor exemption) is preserved and re-tested.

Files: `lib/main.dart`, `lib/core/widgets/app_gate.dart`,
`lib/core/app_lock/app_lock_controller.dart` (+ `.g.dart`),
`lib/core/app_lock/app_lock_observer.dart`, `test/app_lock_navigator_test.dart`,
`test/core/app_lock/app_lock_controller_test.dart`,
`test/core/widgets/app_gate_test.dart`.

Behaviour change to be aware of: `LibraryPage` now builds (offstage) during the
splash/locked phases rather than after unlock, so its data starts loading behind
the cover. Nothing is visible or interactive until unlocked.

OSS reference: placement pattern (root-owned lock overlay, back = leave app)
as used by Bitwarden mobile / Signal-Android — from memory, unverified; nothing
copied. Flutter's own `binding_test.dart` was the model for mocking
`SystemNavigator.pop` in the back-button test.
