# F-Droid release notes (pitak-x → dev.khoj.pitaka.fdroid)

This directory holds the F-Droid build recipe for shipping **pitak-x** (the
Flutter + Rust rewrite) as an **in-place update** to the already-published
F-Droid app `dev.khoj.pitaka.fdroid` (was the Kotlin app, last at 1.0.3 / 4).

`metadata/dev.khoj.pitaka.fdroid.yml` is a **drop-in replacement** for the same
file in your `fdroiddata` fork (https://gitlab.com/PLFIndia/fdroiddata). It is
kept here so the recipe is version-controlled alongside the app it builds.

## Why this ships as an update (not a new app)

- `applicationId = dev.khoj.pitaka.fdroid` (set in `android/app/build.gradle.kts`)
  — identical to the published package, so F-Droid serves it as an update.
- `version: 1.1.0+5` in `pubspec.yaml` → versionName 1.1.0, versionCode 5,
  both strictly greater than the live 1.0.3 / 4.
- Verified on the built APK with `aapt2 dump badging`:
  `package=dev.khoj.pitaka.fdroid versionCode=5 versionName=1.1.0`.

## Free-software status (Route A blocker #1 — resolved)

- The MLKit/Play-Services scanner (`mobile_scanner`) was replaced with
  **`flutter_zxing`** (zxing-cpp via FFI, MIT, no Google deps).
- Release-APK class scan: **no** `com.google.mlkit` / `com.google.android.gms`
  classes. The only "Play Services" hits are inert string constants inside
  AndroidX CameraX, which F-Droid already accepts.

## Reproducibility / build-from-source (blocker #5)

- The Rust crypto core (`rust/`, crate `pitak_crypto`) is compiled by
  **cargokit during the Gradle build**, via `rustup`. There is **no
  `cargokit.yaml`** with a precompiled-binary public key, so cargokit's
  precompiled-download path is disabled and it **always builds from source**
  (confirmed: our local release build logs `Precompiled binaries are disabled`).
- No prebuilt `.so`/`.a` or other binaries are committed to the repo.
- Toolchain pins the recipe assumes (keep the app in sync with these):
  - Flutter **stable 3.41.1** (F-Droid `flutter` srclib)
  - Android **NDK 28.2.13676358**, **AGP 8.11.1**, **Gradle 8.14**, **Kotlin 2.2.20**
  - Rust **stable**, edition 2021, Android targets:
    `armv7-linux-androideabi aarch64-linux-android i686-linux-android x86_64-linux-android`

## Maintainer steps to actually publish

These need YOUR action (tags, the fdroiddata fork, and the F-Droid tooling —
none of which live in this repo):

1. **Tag the release** in `PLFIndia/pitak-x`:
   `git tag -a 1.1.0 -m "pitak-x 1.1.0 (F-Droid)" && git push origin 1.1.0`
   (`UpdateCheckMode: Tags` keys off this tag.)
2. In the recipe, the new build entry uses `commit: '1.1.0'` (the tag). If you
   prefer pinning to a SHA, replace it with the exact release commit.
3. Copy `metadata/dev.khoj.pitaka.fdroid.yml` into your `fdroiddata` fork at
   `metadata/dev.khoj.pitaka.fdroid.yml`.
4. **Lint + build locally** in the fdroiddata checkout (Docker recommended):
   - `fdroid lint dev.khoj.pitaka.fdroid`
   - `fdroid build -v -l dev.khoj.pitaka.fdroid`
   Confirm the APK installs over an existing 1.0.3 install as an update and
   the scanner works.
5. Open a merge request from your fork to upstream F-Droid `fdroiddata` (or
   publish via your own F-Droid repo). Once merged and built, existing users
   get it as a normal app update.

## Rust toolchain placement (subtle, important)

F-Droid runs `sudo:` steps as **root** and `prebuild:`/`build:` as the
**unprivileged build user**. A `rustup` installed into root's `$HOME` would not
be visible to the build steps. The recipe therefore installs Rust into a shared
`/opt/rust` (`RUSTUP_HOME=/opt/rust/rustup`, `CARGO_HOME=/opt/rust/cargo`,
`--no-modify-path`), `chmod`s it world-usable, and re-exports those two vars +
PATH in the `build:` phase. cargokit reads `cargo`/`rustup` from PATH, so this
is what lets it cross-compile `pitak_crypto` from source. If the buildserver
image already ships Rust, you can drop the rustup install and just ensure the
Android targets are added.

## Known risks to watch at build time

- **NDK availability in the buildserver**: NDK 28.2.x must be installable by the
  recipe's environment; if the F-Droid buildserver image lags, pin a
  buildserver-supported NDK in `android/app/build.gradle.kts` and re-verify the
  Rust cross-compile.
- **First-time Flutter+Rust recipes are scrutinised**: expect F-Droid reviewers
  to ask for the source-build proof above; the no-`cargokit.yaml` point is the
  key argument.
- **Build time/RAM**: compiling zxing-cpp + the Rust core for four ABIs is
  heavier than the old Kotlin build; the buildserver should handle it but it is
  slower.
