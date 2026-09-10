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
- D2 F-Droid side: user asked for it after the AAB ("so the fdroid bot picks
  it up"). Mirror recipe blocks copied verbatim from 1.1.10 (option a; the
  `output:` path divergence from upstream fdroiddata stays as-is — upstream is
  authoritative and the bot copies upstream's own block).

## Steps

- [x] 1. Verify signing consistency, toolchain, gates (above).
- [x] 2. Bump `pubspec.yaml` → `1.2.0+17`.
- [x] 3. Add `fastlane/metadata/android/en-US/changelogs/17.txt` (493 chars ≤ 500).
- [x] 4. Rewrite `PLAN.md` for this task.
- [x] 5. Committed `229e765` (`pubspec.yaml`, `changelogs/17.txt`, `PLAN.md`). Not pushed.
- [x] 6. `fvm flutter clean` (build/ + .dart_tool/ gone; cargokit's Rust target
      dir is Gradle `buildDir`, so Android .so files also rebuilt) →
      `pub get --enforce-lockfile` OK.
- [x] 7. `fvm flutter build appbundle --release --flavor play` — **188 s**,
      Rust built for armv7/arm64/x86_64, no debug-signing warning in log
      (`/tmp/pitak-aab-build.log`).
- [x] 8. Artifact verified (see Result).
- [ ] 9. Sideload/phone check and Console upload — user's action.

### F-Droid tag housekeeping (added at user request)

- [x] 10. `changelogs/171.txt 172.txt 173.txt` = byte-identical copies of `17.txt`
      (`cmp` verified; same pattern as 15 → 151/152/153).
- [x] 11. `fdroid/metadata/dev.khoj.pitaka.fdroid.yml`: three 1.2.0 blocks
      (171 x64 / 172 arm / 173 arm64, `commit: 1.2.0`) generated from the
      1.1.10 blocks — `diff` shows only header/version/code/commit changed;
      `CurrentVersion: 1.2.0`, `CurrentVersionCode: 173`. YAML parses; 31
      builds; versionCodes strictly increasing; `UpdateCheckData` on
      pubspec → 17 → 171/172/173 matches.
- [ ] 12. Commit (approval): changelogs 171–173 + recipe + PLAN.md.
- [ ] 13. Annotated tag `1.2.0` on that commit (approval) — the tagged commit
      must contain the F-Droid changelogs, as 1.1.10 did (`6bcfc96`).
- [ ] 14. `git push origin main 1.2.0` (approval). Then watch
      `f-droid.org/api/v1/packages/dev.khoj.pitaka.fdroid` for
      `suggestedVersionCode` → 173 (bot MR typically within ~1 day).

## Out-of-scope observations

- Mirror recipe `output:` paths (`flutter-apk/app-<abi>-fdroid-release.apk`)
  differ from upstream fdroiddata (`apk/fdroid/release/app-fdroid-<abi>-release.apk`)
  for every post-flavor block. Cosmetic in the mirror; fix all blocks together
  in a docs pass, not one at a time.
- `README.md:10` still says "current release 1.1.10" — update after Play accepts.
- `appDetails.md` §1 version table needs the 1.2.0+17 row after upload
  (local-only file).
- Open review findings remain: N03, M15, N04, N11, N08, N07, N09, N10.

## Result

`build/app/outputs/bundle/playRelease/app-play-release.aab` — 92.3 MB,
sha256 `f97496563fa143e008833ae900f7f4e47b0619ff15ef5cf9be6fecfdee8c85dc`,
built from commit `229e765` (code identical to `17e3140` + version/changelog).

| Check | Result |
|---|---|
| Bundle manifest | versionCode **17**, versionName **1.2.0**, package `dev.khoj.pitaka` |
| Signer | `CN=Pitak Upload, OU=Mobile, O=Parallel Line Foundation, C=IN`; `jar verified` |
| Signer cert SHA-256 | `35:FB:C7:0A:…:67:D9:E3:DB` — identical to keystore + `appDetails.md` §6 |
| ABIs | arm64-v8a, armeabi-v7a, x86_64 |
| `libpitak_crypto.so` | present; `frb_pde_ffi_dispatcher` ×2 |
| 16 KB pages | every arm64 .so LOAD align ≥ 0x4000 |
| Debug symbols | 15 `BUNDLE-METADATA/…debugsymbols` entries |
| **Content — M13 (17e3140)** | `This entry was already marked purchased` ×1; `MarkPurchasedAlreadyPurchased` ×1; `Could not save the purchase. Nothing was changed` ×1 (UTF-16LE — see note) |
| Content — M09 (2b92b1a) | `covers.openlibrary.org` ×1 |
| Control (1.1.9) | `Google Books API key` ×1 |

Note for future releases: `strings` only finds ASCII runs. Dart stores any
literal containing a non-ASCII char (here the em dash `—`) as UTF-16 in the
snapshot, so `strings | rg` returns 0 for it even when present. Use an
ASCII-only sentinel, or scan with Python `b.count(s.encode('utf-16-le'))`.

Build-log warnings are toolchain noise only (Gradle native-access on JDK 21,
KGP version hint, plugins compiling with Java 8 target). None from our code.

Not done here: device sideload, Console upload, push of `229e765`, F-Droid tag
(all user actions / deferred — see Out-of-scope).
