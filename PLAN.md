# PLAN.md — Release 1.2.0+17: Play AAB build

## Understanding

Build the Google Play `.aab` for the 23 commits landed since the last Play
upload (`6219438`, 1.1.10+16, accepted 2026-09-04). Remaining review findings
(N03, M15, N04, N11, N08, N07, N09, N10 in `fix-schedule.md`) are deferred by
user decision — this release ships what is on `main` now.

User constraints: signing must be the SAME upload key Play already knows;
build must run after `flutter clean` so no stale Dart snapshot is packaged
(the 1.1.10+15 incident, `appDetails.md` §5).

Version: **1.2.0+17** (user chose minor bump for the security release;
17 > every code Play has ever seen, including discarded 15).

## Privacy & threat notes

- No code changes in this task — only `pubspec.yaml` version, a Play changelog
  and this file. Permissions unchanged (`CAMERA`, `INTERNET`, `USE_BIOMETRIC`),
  `allowBackup=false` unchanged.
- Signing secrets stay where they are: `~/pitak-upload.jks` (chmod 600, outside
  repo) + `android/key.properties` (git-ignored). Neither is printed or copied.
- Threat: a debug-signed or stale artifact reaching Play. Mitigations:
  `build.gradle.kts` fails closed without key.properties; post-build
  `jarsigner` + content-string checks below.

## Investigation notes (verified 2026-09-10, HEAD `17e3140` = `origin/main`)

- Keystore: PKCS12, alias `pitak-upload`, RSA 2048, valid to 2053, SHA-256
  `35:FB:C7:0A:4F:4D:FB:5B:2A:D4:2D:EE:70:53:DE:E6:1E:93:18:F0:38:69:E3:7F:CE:FE:3A:2D:67:D9:E3:DB`
  — matches the upload cert recorded in `appDetails.md` §6. `key.properties`
  alias matches.
- `android/app/build.gradle.kts:130-153`: `bundlePlayRelease` throws when
  key.properties is absent (fail closed). Play flavor applicationId
  `dev.khoj.pitaka`.
- Toolchain: FVM Flutter 3.44.2 (`.fvmrc`), Dart 3.12.2, JDK 21 via
  `~/.gradle/gradle.properties`, NDK 28.2.13676358 (matches
  `FlutterExtension.kt`), Rust android targets ×4, cmdline-tools present, no
  `cargokit.yaml` → Rust built from source.
- targetSdk/compileSdk 36 (Flutter defaults). minSdk 23.
- Gates on HEAD before bump: analyze 0; format 389/0; `flutter test` 1322
  passed; `cargo test --release` 32 passed; build_runner 0 outputs, no diff.
- `pubspec.yaml:24` was `1.1.10+16` → code 16 already used on Play → bump
  mandatory.
- Sentinel strings for the content check (exist ONLY in post-16 code):
  `Could not save the purchase. Nothing was changed`
  (`lib/features/wishlist/presentation/pages/wishlist_detail_page.dart:188`, M13).
  Control string from 1.1.9: `Google Books API key`.

## Proposed approach

Follow `appDetails.md` §5 "Play release — step by step" exactly. No new
tooling. OSS reference: none needed (release procedure is this repo's own).

## Decision points

- D1 version string: **(b) 1.2.0+17** — decided by user.
- D2 F-Droid side (tag, changelogs 171–173, recipe bump): deferred; not needed
  for the AAB. Recorded in Out-of-scope.

## Steps

- [x] 1. Verify signing consistency, toolchain, gates (above).
- [x] 2. Bump `pubspec.yaml` → `1.2.0+17`.
- [x] 3. Add `fastlane/metadata/android/en-US/changelogs/17.txt` (493 chars ≤ 500).
- [x] 4. Rewrite `PLAN.md` for this task.
- [ ] 5. Commit (approval required): `pubspec.yaml`, `changelogs/17.txt`, `PLAN.md`.
- [ ] 6. `fvm flutter clean` → `fvm flutter pub get --enforce-lockfile`.
- [ ] 7. `fvm flutter build appbundle --release --flavor play` — expect
      minutes; ~25 s = stale snapshot → stop.
- [ ] 8. Verify artifact: versionCode 17 / versionName 1.2.0 in the bundle
      manifest; package `dev.khoj.pitaka`; `jarsigner` → `CN=Pitak Upload`;
      `libpitak_crypto.so` present for arm64; 16 KB LOAD alignment;
      debug symbols metadata present; sentinel string count ≥ 1; control ≥ 1.
- [ ] 9. Report AAB path + sha256 + verification table. Sideload/phone check
      and Console upload are the user's (§6 external action).

## Out-of-scope observations

- F-Droid release for 1.2.0: annotated tag `1.2.0`, changelogs `171/172/173.txt`,
  three build blocks + `CurrentVersion`/`CurrentVersionCode` in
  `fdroid/metadata/dev.khoj.pitaka.fdroid.yml`. Not done here.
- `README.md:10` still says "current release 1.1.10" — update after Play accepts.
- `appDetails.md` §1 version table needs the 1.2.0+17 row after upload
  (local-only file).
- Open review findings remain: N03, M15, N04, N11, N08, N07, N09, N10.

## Result

_(pending)_
