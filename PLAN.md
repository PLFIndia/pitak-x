# PLAN.md — Session 36 — Keep Pitak on F-Droid: flavor-split the Play in-app updater

User request: F-Droid reviewer (licaon-kter, fdroid/fdroiddata!51441,
2026-10-06 19:20) asked "We can't rip the autoupdater and continue? Why?"
User chose **Path 2**: remove the non-free Google Play in-app-update
library from the `fdroid` flavor, ship 1.3.5 to F-Droid, and rework the
MR accordingly (instead of declaring 1.3.3 the final release with
`NoSourceSince`).

## Understanding (verified from source this session)

- **The MR (!51441)** — open, no conflicts, label `waiting-for-upstream`.
  Pipeline: `fdroid build`, `fdroid lint`, `check apk`, `check source
  code` PASS; two jobs FAIL:
  - `fdroid rewritemeta`: the 7 YAML comment lines are stripped by the
    rewriter (fdroidserver `metadata.py` rebuilds the file, no comments).
  - `checkupdates`: `AutoUpdateMode: None` only suppresses new build
    blocks; `UpdateCheckMode: Tags` still finds tag `1.3.4` and wants
    `CurrentVersion: 1.3.4 / 223` → diff → job fails.
  - Reviewer note: "Remove comments / Add `NoSourceSince:` / We can't rip
    the autoupdater and continue? Why?"
- **Why the fdroid APK is tainted:** `pubspec.yaml:124` `in_app_update:
  ^5.0.0` (MIT, Victor Choueiri). Its `android/build.gradle` declares
  `com.google.android.play:app-update:2.1.0` + `app-update-ktx:2.1.0`
  (proprietary). Flutter plugins apply to EVERY flavor, so the fdroid
  build bundles Play Core even though the Dart side is gated to the `play`
  applicationId at runtime (`lib/core/platform/app_info.dart`).
- **Blast radius in Dart is tiny:** only
  `lib/features/app_update/infrastructure/play_app_update_service.dart`
  and `test/features/app_update/play_app_update_service_test.dart` import
  `package:in_app_update`. The domain port (`AppUpdateService`), the
  controller, the banner, the library-page wiring and their tests are
  plugin-agnostic (S35 design intent, confirmed).
- **Native side today:** `android/app/src/main/kotlin/dev/khoj/pitaka/
  MainActivity.kt` already hosts three narrow channels; flavors `fdroid`
  / `play` exist (`build.gradle.kts:58-66`) but there are no per-flavor
  source sets (`android/app/src/{debug,main,profile}` only).
- **Play Core API (verified by `javap` on the cached `app-update-2.1.0`
  AAR):** `AppUpdateManager.getAppUpdateInfo()`, `registerListener /
  unregisterListener(InstallStateUpdatedListener)`, `completeUpdate()`,
  and the modern `startUpdateFlowForResult(AppUpdateInfo,
  ActivityResultLauncher<IntentSenderRequest>, AppUpdateOptions)` exist.
  `MainActivity` is a `FlutterFragmentActivity` → `registerForActivityResult`
  is available, so no `onActivityResult` override / request-code juggling.
- **fdroidserver 2.4.5 (local):** `lint.py:801 check_updates_expected`
  requires BOTH `AutoUpdateMode` and `UpdateCheckMode` to be `None` when
  `NoSourceSince` is set — irrelevant now (Path 2 drops NoSourceSince),
  recorded for completeness.
- **fdroiddata conventions seen:** `disable: non-free dep` build entries
  (e.g. `metadata/org.cis_india.wsreader.yml:34`) document skipped
  versions. Upstream master has `AutoUpdateMode: Version`.
- **GitLab PAT:** fresh token `pitak-api` (scopes `api`,
  `write_repository`, expires 2026-11-06) captured from the clipboard,
  stored in the macOS keychain for gitlab.com (replaced the revoked one),
  verified 200. Never printed; referenced only via the keychain.

## Privacy & threat notes

- No new data flows. The Play flow is the same one approved in S35
  (PRIVACY.md item 5: the only passive network event, play flavor only).
- The fdroid flavor loses the Play Core BINARY entirely (not just the
  runtime gate) — strictly better than today: no proprietary code in the
  F-Droid APK at all, no Play Store IPC surface.
- Method/event channel payload shrinks to the three fields Dart actually
  uses (`updateAvailability`, `flexibleAllowed`, `installStatus`); the
  plugin used to send `packageName`, `clientVersionStalenessDays`,
  `availableVersionCode`, `updatePriority` which we never read (data
  minimization §3.1).
- Boundary validation: the Dart side treats a malformed/missing reply as
  "no update" (fail closed to silence), same as a PlatformException.
- Secrets: none involved. The PAT lives in the keychain only.

## Proposed approach (OSS references)

Adapt the native side of `in_app_update` 5.0.0 (MIT,
`InAppUpdatePlugin.kt`, Victor Choueiri) into our own flavor-split Kotlin,
keeping ONLY the flexible flow (D2 from S35). Credit in the file header.
Pattern for flavor-specific Kotlin: standard AGP source sets
(`src/<flavor>/kotlin`) + `"<flavor>Implementation"(...)` dependency
configuration — the same mechanism F-Droid-friendly apps such as
Screenstream (`info.dvkr.screenstream`, in fdroiddata) use to keep Play
libs out of their FOSS flavor.

### A. Android (Kotlin, flavor-split)
1. `android/app/src/play/kotlin/dev/khoj/pitaka/AppUpdateChannel.kt` —
   real implementation over `AppUpdateManagerFactory`:
   - channel `dev.khoj.pitaka/app_update` methods: `checkForUpdate` →
     `{updateAvailability:int, flexibleAllowed:bool, installStatus:int}`;
     `startFlexibleUpdate` → `null` on accept, `USER_DENIED_UPDATE` /
     `IN_APP_UPDATE_FAILED` / `REQUIRE_CHECK_FOR_UPDATE` errors (same
     codes as the plugin so Dart semantics are unchanged);
     `completeFlexibleUpdate`.
   - event channel `dev.khoj.pitaka/app_update/install_state` emitting
     Play's raw `InstallStatus` ints (0–6, 11).
   - uses `registerForActivityResult(StartIntentSenderForResult())`
     registered in `MainActivity` (must happen before STARTED).
   - listener registered once, unregistered on engine detach (the plugin
     leaked a second listener per `startFlexibleUpdate`; not copied).
2. `android/app/src/fdroid/kotlin/dev/khoj/pitaka/AppUpdateChannel.kt` —
   no-op twin with the same public surface: registers NOTHING, so Dart
   gets `MissingPluginException` and the existing fail-safe path yields
   silence. Zero Play symbols in the fdroid flavor.
3. `MainActivity.kt` — one call `AppUpdateChannel.register(...)`, plus
   the launcher field; doc comment updated to list the 4th channel.
4. `build.gradle.kts` `dependencies {}` —
   `"playImplementation"("com.google.android.play:app-update:2.1.0")`.
   DEVIATION from the first draft (`-ktx`): the ktx artifact only adds
   Kotlin extension sugar we do not use and drags `kotlin-stdlib-jdk7:
   1.3.72`; the plain artifact is the one whose API we call (verified by
   `javap`). Same version the plugin pinned → nothing new for Play users,
   nothing at all for fdroid.

### B. Dart
5. `lib/features/app_update/infrastructure/play_app_update_service.dart`
   — drop `package:in_app_update`; talk to the two channels directly.
   Define tiny private value types for the reply (`_UpdateCheck`) and
   keep `availabilityFrom` / `statusFromInstall` as pure
   `@visibleForTesting` statics over Play's int codes (same tables as the
   plugin's enums, documented with the Android reference names).
6. `pubspec.yaml` — remove `in_app_update`; `flutter pub get` refreshes
   the lock (dependency REMOVAL only; no approval-gated install).
7. Tests — rewrite `play_app_update_service_test.dart`: the pure
   mappings (same cases as today, over int codes) PLUS channel-level
   tests with `TestDefaultBinaryMessengerBinding` for: no handler →
   `none`/`false` (this IS the fdroid-flavor behaviour), PlatformException
   → `none`/`false`, malformed reply → `none`, happy path → `available`,
   event stream mapping. Controller/banner/library tests untouched.

### C. Verification (the F-Droid-relevant proof)
8. `./gradlew :app:dependencies --configuration fdroidReleaseRuntimeClasspath`
   → zero `com.google.android.play` lines; the play configuration shows
   `app-update(-ktx):2.1.0`.
9. `fvm flutter build apk --release --split-per-abi --flavor fdroid`
   (local, debug-signed fallback is fine) → class scan of the arm64 APK
   for `com/google/android/play` → none. `fvm flutter build apk --flavor
   play --debug` compiles the real channel.
10. `dart analyze` (0 issues), `dart format --set-exit-if-changed`,
    `fvm flutter test` (baseline 1784 → expect same count ± the rewritten
    service tests).

### D. Release + F-Droid
11. `pubspec.yaml` → `1.3.5+23`; fastlane changelogs `231.txt/232.txt/
    233.txt` (per the eb36f7f convention); README test count; PRIVACY.md
    wording ("plugin" → our own channel; fdroid flavor has no Play code);
    `fdroid/README.md` status note rewritten (no longer "final").
12. Commit (`sec:`/`feat:` conventional), tag `1.3.5`, push tag + main
    — **each a §6 approval**.
13. fdroiddata branch `pitaka-1.3.3-final` (local checkout at
    `~/development/fdroiddata`): rewrite the recipe —
    remove all comments; keep 1.3.3 ×3 (211/212/213); add ONE
    `1.3.4 / 223` entry with `disable: non-free dep (Google Play
    in-app-update); fixed in 1.3.5` as the record; add 1.3.5 ×3
    (231/232/233) cloned from the 1.3.3 blocks; restore
    `AutoUpdateMode: Version`; `CurrentVersion: 1.3.5 / 233`.
    `fdroid rewritemeta` + `fdroid lint` locally; amend commit, retitle
    the MR, force-push the fork branch (§6 approval), reply to
    licaon-kter. Re-sync the in-repo mirror
    `fdroid/metadata/dev.khoj.pitaka.fdroid.yml` verbatim.

## Decision points

- **D1 (open)** — the 1.3.4 entry in fdroiddata: (a) one `disable:`
  block recording why 1.3.4 is skipped [proposed], or (b) omit 1.3.4
  entirely (1.3.3 → 1.3.5). (a) is the fdroiddata convention and answers
  the reviewer's question in the file itself.
- **D2 (open)** — keep the fork branch name `pitaka-1.3.3-final` (MR
  stays the same, history amended) [proposed], or open a fresh MR. Same
  MR keeps the reviewer's context.
- **D3 (resolved by precedent, S35)** — flexible flow only; the
  immediate flow is not ported.

## Steps

- [x] A1 play-flavor `AppUpdateChannel.kt`
- [x] A2 fdroid-flavor no-op `AppUpdateChannel.kt`
- [x] A3 `MainActivity.kt` wiring + launcher (field init; `cleanUpFlutterEngine` detach)
- [x] A4 `build.gradle.kts` `playImplementation` (plain `app-update:2.1.0`)
- [x] B5 Dart service over own channels (`PlayUpdateCheck.fromChannel` validates the reply)
- [x] B6 drop `in_app_update` from pubspec + lock (lock: 8 lines removed; SDK floor relaxed to 3.41/3.11 — fvm still pins 3.44.2)
- [x] B7 tests: 38 in `test/features/app_update/` (11 new: boundary validation + channel no-handler/error/malformed/stream)
- [x] C8 `fdroidReleaseRuntimeClasspath`: 0 `com.google.android.play`, 0 `com.google.android.gms`; play: `app-update:2.1.0` + `core-common:2.0.3` (+ gms basement/tasks)
- [x] C9 fdroid arm64 release APK dex scan: 0 `google/android/(play|gms)` refs; play debug APK compiles, links `AppUpdateManagerFactory`
- [x] C10 analyze: 47 issues, IDENTICAL set to HEAD (worktree diff) — none new; format clean; `flutter test` 1795 passed (1784 + 11)
- [x] D11 `1.3.5+23`; changelogs `23.txt` (Play) + `231/232/233.txt` (F-Droid); README status + test count; PRIVACY.md item 5; `fdroid/README.md` status
- [ ] D12 commit + tag 1.3.5 + push (approvals)
- [ ] D13 fdroiddata recipe rework, lint, force-push, MR reply (approvals)
- [ ] Mirror re-sync + PLAN.md Result

## Out-of-scope observations

- `in_app_update`'s Kotlin registers an extra `InstallStateUpdatedListener`
  on every `startFlexibleUpdate` and never unregisters it (leak). Not
  carried over; noted so nobody "restores" it.
- The revoked PAT was still in the keychain; stale credentials should be
  erased when revoked (done now as a side effect of storing the new one).

## Result

(pending)
