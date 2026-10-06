# PLAN.md — Session 35 — Play flexible in-app update + collapsed publish provider tiles

User request (two independent items, both approved with decisions below):
1. **Play flavor only:** in-app update info — Play's FLEXIBLE flow (download
   in background, never blocking), with a dismissible banner on the library
   page. F-Droid builds stay completely inert.
2. **Publish page UI:** the Connection tab's two providers (GitHub Pages,
   Cloudflare Pages) become collapsible tiles so the whole page fits without
   scrolling. Status trailing per tile; Cloudflare (unimplemented) collapses
   to a one-paragraph "coming soon" body.

## Decision points (ALL RESOLVED by user, 2026-10-06)

- **D1** — `in_app_update` dependency: APPROVED. Verified on pub.dev:
  5.0.0, published 2026-07-04 (3 months old — healthy), requires
  Flutter >=3.44.0 / Dart ^3.12.0 — matches the fvm pin (3.44.2 / 3.12.2)
  exactly. NOTE: this makes Flutter 3.44+ mandatory for the project (the
  older system 3.41.1 can no longer resolve deps) — consistent with the
  committed pubspec.lock, which already carries 3.44.x pins.
- **D2** — Banner location: top of the library page, dismissible, checked
  once per app launch.
- **D3** — GitHub tile status is THREE-state:
  - signed in + target repo set → GREEN "Configured" (✓, as today's check)
  - signed in, no repo → YELLOW/amber "Partially configured"
  - not signed in → RED "Not configured"
  Cloudflare tile: always RED "Not configured" (+ "Coming soon" note).
- **D4** — Auto-expand the GITHUB tile whenever its status is not green.
  Locked interpretation (flagged to user): Cloudflare always starts
  COLLAPSED — auto-expanding it would defeat the no-scroll goal; the user
  expands it only to read the coming-soon note.

## Understanding (verified from source this session)

Item 1 — current state:
- No flavor detection exists in Dart today. applicationIds: play =
  `dev.khoj.pitaka`, fdroid = `dev.khoj.pitaka.fdroid`
  (`android/app/build.gradle.kts:58-68`).
- `MainActivity.kt` hosts TWO narrow channels already
  (`dev.khoj.pitaka/screen_security`, `BiometricSecretVault.CHANNEL`) with a
  "No other native surface is exposed" KDoc — a third minimal channel fits
  the established pattern.
- Dart-side channel convention: `lib/core/platform/screen_security.dart` —
  an abstract interface + `MethodChannel` impl that catches platform errors
  and fails safe (debugPrint only). The update-eligibility probe copies this.
- Library page body is a `Column` (`library_page.dart:152`) — the banner
  slots in above the list.
- Play flexible flow (from Play docs, package API to be verified from source
  in the pub cache AFTER adding — never from memory): check availability →
  start flexible download → observe install-state → when downloaded, offer
  restart (`completeFlexibleUpdate`).

Item 2 — current state:
- `publish_page.dart` (901 lines): Connection tab = ListView with intro text,
  `_SectionCard('GitHub account')` (green `Icons.check_circle` when signed
  in, `:540-553`), `_SectionCard('Target repository')` when signed in
  (`:576`), `_CloudflareComingSoon()` (`:680-737` — a tall greyed card with
  THREE disabled text fields + paragraph), then `_SectionCard('Publish')`
  and `_SectionCard('Your site')` when applicable, then status text.
- State lives in `_ConnectionTabState` (`_signedIn`, `_targetRepo`,
  `_loading` via `_refresh()`); a `_SectionCard` widget exists (`:878`).
- `test/features/publish/publish_page_test.dart`: ~15 testWidgets touch the
  Connection tab (sign-in, device flow, repo picker, sign-out, truncation,
  320px layout) — all will need a tap-to-expand step or a rewrite of the
  Cloudflare-card test (`:202`).

## Privacy & threat notes

- Item 1 adds NO data collection and NO endpoint of ours: the version check
  and download run entirely inside the Play Store app (Google's surface,
  already on the device). The new Kotlin channel returns only the app's OWN
  applicationId — no PII, no secrets, read-only. Every failure path (no Play
  Store, non-Play install, channel missing in tests/desktop) resolves to
  "stay silent" — an update nag can never break or block the app (fail-safe,
  the one place where failing OPEN is correct: the alternative is nagging
  F-Droid users about an update that isn't theirs).
- Update delivery itself is Play-signed; `completeFlexibleUpdate` hands
  control to the Play Store — no sideloading path is introduced.
- Item 2 is pure presentation: no data, storage, or network changes.
- PRIVACY.md: check whether it enumerates third-party services; if Play is
  already covered, no change needed (verify, don't assume).

## Proposed approach

### Workstream A — Play flexible in-app update

Pattern references: the app's own `screen_security.dart` seam (interface +
MethodChannel impl + fail-safe catch); standard Play flexible-update flow
as documented for `in_app_update` (API verified from package source, not
memory).

1. `fvm flutter pub add in_app_update` (D1 approved). Then READ the package
   source in the pub cache to pin the exact 5.0.0 API (check/start/complete
   + state observation) before writing any Dart against it.
2. Kotlin: third channel `dev.khoj.pitaka/app_info` in `MainActivity.kt`,
   one method `applicationId` → `packageName`. Update the KDoc list.
3. `lib/core/platform/app_info.dart`: `AppInfo` interface +
   `MethodChannelAppInfo` (screen_security pattern; on any platform error →
   null, i.e. "unknown → not eligible").
4. New feature slice `lib/features/app_update/`:
   - `domain/app_update_service.dart`: seam interface (eligibility,
     check, startFlexible, complete, state stream) + a pure
     `AppUpdateStatus` enum (ineligible/idle/available/downloading/
     downloaded) — pure Dart, no Flutter/Play imports.
   - `infrastructure/play_app_update_service.dart`: wraps `InAppUpdate` +
     the gate (Android AND applicationId == `dev.khoj.pitaka`; the play
     applicationId as a named constant).
   - `application/app_update_controller.dart`: `@Riverpod(keepAlive: true)`
     (justified: one check per app launch, survives navigation) —
     `build()`: eligibility → check → if flexible available, AUTO-START the
     background download (D2: "update happens in background") → observe
     install state → `downloaded`. EVERY error → silent `idle`.
   - `presentation/widgets/app_update_banner.dart`: Material banner —
     downloading: spinner + "Update downloading in the background";
     downloaded: "Restart to update" + [Restart] (`completeFlexibleUpdate`);
     dismissible for the session; renders nothing in any other state.
5. Wire the banner into `library_page.dart` (top of the body Column).
6. Provider for the service seam in `core/di/providers.dart` (codegen).
7. Tests: controller state machine over a fake service (available →
   downloading → downloaded; ineligible/error → silent idle); banner widget
   states incl. dismiss + restart action; library-page integration (banner
   appears with the fake, absent without); eligibility gate (non-Android /
   fdroid applicationId / missing channel → ineligible).
8. Manual verification checklist (recorded in Result; user-run): build play
   flavor → internal testing track with versionCode 21 → install 20 from
   Play → launch → banner flow. Cannot be automated locally.

### Workstream B — collapsible provider tiles (publish page)

9. `publish_page.dart` Connection tab restructure:
   - New `_ProviderTile` (collapsible card matching `_SectionCard` visuals;
     ExpansionTile-based): title, status trailing (icon + label), body.
   - Statuses (D3): green `Icons.check_circle` "Configured" (signed in AND
     `_targetRepo != null`); amber "Partially configured" (signed in, no
     repo); red "Not configured" (not signed in). Text label is the primary
     carrier, color secondary (accessibility); shades follow the existing
     light/dark green pattern (`:540-543`).
   - GitHub tile body = the EXISTING sign-in / device-flow / target-repo UI,
     moved unchanged. `initiallyExpanded: status != green` (D4), evaluated
     once after `_refresh()` completes; the user can always toggle manually.
   - Cloudflare tile: red "Not configured" + "Coming soon" subtitle; body
     reduced to the existing paragraph + dashboard hint (the three disabled
     fake fields are deleted — they were the height problem). Always
     collapsed initially.
   - `Publish` and `Your site` cards + status text stay ALWAYS visible
     (actions/results, not provider settings) — with both tiles collapsed
     the tab is intro + 2 one-line tiles + publish/site cards: no scroll.
   - No changes to flows: device flow, `SetupGitHubRepo`, publish, sign-out
     untouched (only where they render).
10. Tests: update `publish_page_test.dart` — expand-before-interact for the
    Connection-tab tests; rewrite the "disabled Cloudflare card" test for
    the collapsed tile; NEW tests: the three GitHub status states,
    auto-expand when not green, collapsed-when-green, Cloudflare body
    reduction, Publish/Your-site remain visible with tiles collapsed.
11. Quality gates: `dart run build_runner build --delete-conflicting-outputs`
    (new providers), `dart analyze` zero issues, `dart format`, FULL
    `fvm flutter test` (3.44.2 — the mandatory SDK after D1).

## Steps

- [x] A1. pub add in_app_update; verify 5.0.0 API from package source
- [x] A2. Kotlin `app_info` channel + KDoc
- [x] A3. `core/platform/app_info.dart` seam
- [x] A4. app_update slice (domain/infra/application/banner)
- [x] A5. Wire banner into library page + DI provider
- [x] A6. Workstream A tests
- [x] B1. `_ProviderTile` + Connection-tab restructure (D3/D4)
- [x] B2. publish_page_test updates + new status/auto-expand tests
- [x] G1. build_runner + analyze + format + full fvm test suite
- [x] G2. PRIVACY.md item 5 (Play update check); Result below

## Out-of-scope observations

- Cloudflare Pages Direct Upload remains unimplemented (tile says so).
- Play IMMEDIATE (blocking) update mode — deliberately not used (D: user
  wants background/non-blocking).
- iOS / desktop update nudges (no store API equivalent wired).
- F-Droid gets no in-app update check by design (the F-Droid client handles
  updates); fdroid flavor code path stays inert.
- The stale-README-status pattern: keep an eye on the Status line at the
  NEXT release (updated to 1.3.2 this time).

## Result

DONE, shipped as TWO releases (user decision 2026-10-06 after the
non-free-dependency fork surfaced):

**The fork (recorded):** `in_app_update` bundles Google's PROPRIETARY Play
Core (`com.google.android.play:app-update`), and Flutter plugins apply to
ALL flavors — so the fdroid APK would carry a non-free binary, reversing
the repo's FOSS-first stance (precedent: commit 690f705 replaced MLKit
with flutter_zxing for exactly this reason). User decision: ship
Workstream B alone to F-Droid NOW (tag cut before the dependency exists in
the tree), then keep the plugin (option b) for the Play release.

**DEFERRED OBLIGATION (due before the NEXT F-Droid release):** main now
contains `in_app_update`, so any future fdroid tag would bundle Play Core.
Before that release, either (a) flavor-split the native side (adapt the
plugin's BSD Kotlin into `android/app/src/play/kotlin` + a no-op stub in
`src/fdroid/kotlin` + a `playImplementation` dependency — the Dart seam,
controller, banner and tests already survive that swap unchanged), or
(b) declare the non-free-component anti-feature in fdroiddata. (a) is
recommended.

**Release 1 — F-Droid, B only:** tag `1.3.3` (1.3.3+21), pushed. The tree
at the tag has NO in_app_update anywhere (Workstream A was stashed out;
verified: lock clean, 1756 tests green). Mirror recipe blocks 211/212/213
+ changelogs added per the eb36f7f convention; `CurrentVersion` footer
updated. NOTE: the F-Droid bot builds from fdroiddata — the mirror blocks
must be MR'd there; the pushed tag alone does not trigger a build.

**Release 2 — Play, A+B:** 1.3.4+22. Suite with A restored: 1784 green
(gate run recorded below); AAB built after `fvm flutter clean` with
`--flavor play`, release-signed (key.properties + pitak-upload.jks).

**Workstream A (as committed):**
- Kotlin: third narrow channel `dev.khoj.pitaka/app_info` (one read-only
  method, `applicationId`) in MainActivity.
- `core/platform/app_info.dart`: AppInfo seam (screen_security pattern,
  fail-safe null).
- `features/app_update/`: domain (status/availability enums + pure
  eligibility rule), infrastructure (PlayAppUpdateService over the plugin,
  pure `@visibleForTesting` mappings), application (keepAlive controller:
  gate → check → AUTO-start flexible download → observe → restart offer;
  every error path → silence), presentation (MaterialBanner atop the
  library page; downloading / restart states; dismissible for the session).
- Tests (28): policy eligibility, plugin→domain mappings, controller state
  machine incl. fail-safe + dismiss semantics, banner widget states,
  library-page wiring. Spinner caveat pinned in tests: pumpAndSettle never
  settles against an indeterminate progress indicator — explicit pumps.
- PRIVACY.md: new item 5 (the only passive network event; the Play Store
  makes the call; disabled in the F-Droid build).

**Workstream B (as shipped in 1.3.3):** `_ProviderTile` (Card +
ExpansionTile) with the three-state badge (D3: green Configured / amber
Partially configured / red Not configured), GitHub auto-expand latch (D4:
unless green, latched at first load), Cloudflare collapsed with a "Coming
soon" subtitle and a one-paragraph body (fake fields deleted); Publish +
Your site stay always visible. Flows untouched.

**Device-test checklist (manual, user-run — the real Play flow cannot be
automated locally):**
1. Upload a 1.3.4+22 AAB to an internal-testing track; wait for it to go
   live on the track.
2. On a device with the Play Store, install versionCode 21 (or lower) from
   that track via the store link.
3. Launch Pitak → within seconds the banner should read "Update downloading
   in the background…"; the app stays fully usable.
4. When the download finishes → "Update ready — restart the app to install
   it." → Restart → the store applies 22 and relaunches.
5. Hide/Later must keep the banner gone for the session; relaunch re-offers.
6. Sanity: an fdroid-flavor build (`--flavor fdroid`) must NEVER show a
   banner (eligibility gate).
