# Pitak — Releasing

> **What this file is:** the single authoritative procedure for shipping a
> version to Google Play and F-Droid. If something here disagrees with
> `tool/release_build.sh`, the script is right — fix this file.
>
> Promise protected: **P4 — honest, reproducible releases** (one pinned
> toolchain, one committed lockfile, one signing key, one signed tag → both
> stores, artefact verified before upload). See `docs/ARCHITECTURE.md` §1.1.

---

## 1. Identity and channels

| | F-Droid | Google Play |
|---|---|---|
| Flavor | `fdroid` | `play` |
| applicationId | `dev.khoj.pitaka.fdroid` | `dev.khoj.pitaka` |
| Artefact | 3 split APKs (one per ABI), built by F-Droid's server | 1 `.aab`, built here by `tool/release_build.sh` |
| versionCode | pubspec `+N` × 10 + ABI rank (x86_64 1, armeabi-v7a 2, arm64-v8a 3) | pubspec `+N` as-is |
| Changelog file | `fastlane/…/changelogs/N1.txt`, `N2.txt`, `N3.txt` | `fastlane/…/changelogs/N.txt` (≤ 500 chars) |
| Signed by | F-Droid's own key (the `fdroid` flavor is debug-signed locally on purpose — never distribute that) | our **upload key** → Play App Signing |
| Trigger | the signed tag `x.y.z` (checkupdates bot, or a manual fdroiddata MR) | upload the verified `.aab` in Play Console |

- The applicationId lives on the **flavor** (`android/app/build.gradle.kts`);
  the Kotlin/resource namespace is `dev.khoj.pitaka` for both. **Every build
  command needs `--flavor`.** The two apps can coexist on one phone and share
  no data.
- Per-ABI versionCodes are computed in `build.gradle.kts` (`abiCodes`);
  F-Droid rejects splits that share a code.
- Release tags are bare versions (`1.5.1`), **annotated and signed**, and
  immutable. F-Droid's `UpdateCheckMode: Tags ^[\d.]+$` reads them and pins
  the commit. Never move a tag; ship a new version instead.
- Source of truth for the version: `version: x.y.z+N` in `pubspec.yaml`.
  `N` must be greater than every code Play has **ever** seen, including
  discarded uploads.

---

## 2. Flavors: what may link where (F-Droid purity, P3)

| flavor | may use Google libraries? |
|---|---|
| `fdroid` | **No.** F-Droid rejects any non-free dependency (Play Services, Play Core, Firebase, MLKit). |
| `play` | Yes, when justified (today: Play Core for in-app updates). |

The Dart code is identical; only what the Android build links differs.

1. **Flutter plugins link into EVERY flavor** — there is no way to add a pub
   plugin to one flavor. Before adding any plugin, open its
   `android/build.gradle` (`~/.pub-cache/hosted/pub.dev/<plugin>/`) and look
   for `com.google.android.gms`, `com.google.android.play`, `firebase`,
   `mlkit`. If present, do **not** add it — write the feature as
   **flavor-split Kotlin** (ADR 0008): same class name and public surface in
   `android/app/src/play/kotlin/…` (real) and `android/app/src/fdroid/kotlin/…`
   (inert no-op); the Google dependency goes in `build.gradle.kts` as
   `"playImplementation"(…)`, never `implementation(…)`. `AppUpdateChannel.kt`
   is the worked example. Precedents: MLKit scanner → `flutter_zxing`;
   `in_app_update` → our own channel.
2. The `fdroid-purity` CI job is the automated check and self-tests by
   requiring the same grep to *match* on the `play` classpath.

Verify by hand before tagging (both must print **nothing**):

```bash
( cd android && ./gradlew -q :app:dependencies --configuration fdroidReleaseRuntimeClasspath 2>/dev/null ) \
  | grep -E 'com\.google\.android\.(play|gms)|firebase|mlkit'
fvm flutter build apk --release --flavor fdroid --split-per-abi --target-platform=android-arm64
unzip -p build/app/outputs/apk/fdroid/release/app-fdroid-arm64-v8a-release.apk 'classes*.dex' \
  | strings -n 8 | grep -E 'google/android/(play|gms)|firebase|mlkit'
```

(To prove the check works, run the second one on a `play` APK and watch it
light up. The only "Play Services" hits F-Droid tolerates are inert string
constants inside AndroidX CameraX.)

---

## 3. Signing

- **Play App Signing** holds the real app-signing key at Google (enrolled at
  first upload). Nothing to do unless Google asks.
- **Upload key** signs every upload: a PKCS12 keystore kept **outside the
  repo** (`chmod 600`), alias `pitak-upload`, RSA 2048. Wiring lives in
  `android/key.properties` (git-ignored; template
  `android/key.properties.example`, which also has the `keytool` command).
  - **PKCS12 trap:** modern `keytool` silently ignores a `keyPassword` that
    differs from `storePassword` at creation and then fails signing with
    "Given final block not properly padded". Use the same password for both.
  - The upload certificate's **SHA-256 fingerprint is public**; the script
    prints it — it must match Play Console → App integrity → Upload key.
  - **Back up the keystore and password** (password manager / encrypted
    backup). Losing it means Play's key-reset support flow.
- `build.gradle.kts` fails closed: a `play` **release** build without
  `key.properties` throws. `-PallowUnsignedPlayRelease=true` is a
  compile-only escape for CI and must never produce a distributed artefact.
- The `fdroid` release build falls back to debug signing because F-Droid
  re-signs with its own key. Never distribute a debug-signed build.
- Tags are SSH-signed. One-time setup: `git config gpg.format ssh` and
  `git config user.signingkey <path to your public key>`.
  `tool/release_build.sh --verify` refuses a lightweight or unsigned tag.

---

## 4. The stale-artefact trap (read before every release)

Flutter caches the compiled Dart snapshot (`libapp.so`) under
`.dart_tool/flutter_build/<hash>/` and `build/app/intermediates/flutter/`.
The Gradle up-to-date check on the AOT task **cannot be trusted** after a run
of source edits: it has repackaged a stale `libapp.so` with a fresh manifest
**twice** (1.1.10 on 2026-09-03: months-old Dart code with the right
versionCode; again on 2026-10-18 after only the `.aab` had been removed).
`flutter analyze` / `flutter test` cannot catch this — they read source, not
the artefact.

Rules, all enforced by `tool/release_build.sh`:

1. **`flutter clean` before every release build.** It wipes `build/` **and**
   `.dart_tool/`. Deleting the `.aab` is not enough. (Rust's `target/` is
   rebuilt by cargokit on a clean tree; no separate `cargo clean` needed.)
2. **Verify the artefact's contents**, not just its version: an ASCII string
   that exists only in the code you are shipping must be present inside
   `libapp.so` (the `--sentinel` check, §5). A new UI string works; so does a
   new class name (they survive AOT). Dart stores any literal containing a
   non-ASCII char (an em dash, Indic text) as UTF-16, so pick an **ASCII-only**
   sentinel.
3. **Tell-tale:** a real release build takes minutes (Rust × 3 ABIs + Dart
   AOT). A "release" that finishes in ~25 s is a repackage. Do not upload it.
4. Sideload the matching APK and look at the new feature on a phone (the APK
   shares `libapp.so` with the `.aab`).

F-Droid builds from a clean clone and is immune to this; only local Play
builds are at risk.

---

## 5. `tool/release_build.sh` — the only way to build a Play `.aab`

```bash
tool/release_build.sh --sentinel 'An ASCII string new in this release'   # build + verify
tool/release_build.sh --verify  --sentinel '…'                           # re-verify an existing bundle
```

What it refuses, in order (each is a hard check that fails closed):

1. Any Flutter but the one pinned in `.fvmrc` (via `.fvm/flutter_sdk` or
   `fvm`); `.fvmrc` and `pubspec.yaml`'s `environment: flutter:` must agree.
2. A `pubspec.lock` that the pinned SDK would change
   (`pub get --enforce-lockfile` — the gate CI and the F-Droid recipe run).
3. A `CHANGELOG.md` without a `## [x.y.z]` heading for the version being built.
4. A missing `android/key.properties`.
5. Stale Flutter build outputs: it runs `flutter clean` itself, then `pub get`
   again. This is **not** a Git-worktree check — uncommitted source changes are
   not refused, so build only from the reviewed release commit (§6.1).
6. After the build, the **artefact**: signature valid; signer certificate
   equals the upload keystore's; bundled package/versionCode/versionName
   equal `pubspec.yaml`; the `--sentinel` string is present in the arm64
   `libapp.so`; and, if the tag already exists, it is annotated, signed, and
   points at HEAD.

It prints the certificate fingerprint (public) and never echoes a secret.
It does **not** bump the version, write changelogs, commit, tag or upload.

---

## 6. Release procedure (one tag feeds both stores)

### 6.1 Prepare (one `chore(release): x.y.z+N` commit)

1. Bump `version: x.y.z+N` in `pubspec.yaml`.
2. Move the `## [Unreleased]` entries in `CHANGELOG.md` under
   `## [x.y.z] - YYYY-MM (tag x.y.z, versionCode N)`.
3. Add `fastlane/metadata/android/en-US/changelogs/N.txt` (Play, ≤ 500
   characters) and `N1.txt`, `N2.txt`, `N3.txt` (F-Droid, one per ABI).
   Verify the limit as UTF-8 text characters, not bytes and not an exact
   count. Pass the release versionCode as the command's only argument (`29`
   below; change it for a later release):

   ```bash
   python3 tool/check_fastlane_changelog_chars.py 29
   ```

   The checked-in check prints every count, accepts exactly 500, and exits
   nonzero above 500, when any of the four required files is missing, or when
   an unexpected prefix-matching file is present. Its unit tests cover those
   file-set cases, the boundary, and multibyte text whose byte count exceeds
   its character count; CI runs the tests and checks all four release files.
4. Update the version in the status note at the top of `README.md`.
5. Run the quality gates (`CONTRIBUTING.md`) and the purity check (§2).
6. Walk Library → Magazines → Vault → Settings → Library network once with
   TalkBack on (5 minutes), including the series detail, magazine forms,
   Others form, add sheet, and the native published-catalogue viewer (search,
   filter, sort, detail, browser fallback).
7. On-device smoke test on a **cleared** install (it creates the vault, so
   it needs an empty app):
   `adb uninstall dev.khoj.pitaka.fdroid`, then
   `fvm flutter test integration_test --flavor fdroid -d <device>`.
   The suite includes `published_catalogue_smoke_test.dart` (ADR 0015): it
   adds a uniquely named bookmark through the real dialog/Drift, opens the
   native viewer, searches/filters, opens the read-only detail, returns,
   reloads once, checks the injected browser hand-off and removes the row.
   It uses fake catalogue/cover ports, so it needs **no** live network.
8. Commit.

### 6.2 Google Play

```bash
tool/release_build.sh --sentinel '<ASCII string new in this release>'
# Expect MINUTES. Read the summary: package, version, cert SHA-256.
fvm flutter build apk --release --flavor play       # optional: eyes on a phone
adb install -r build/app/outputs/flutter-apk/app-play-release.apk
```

Play Console → Production → **discard any stale in-review release** → Create
release → upload the `.aab` the script verified → notes from
`changelogs/N.txt` → roll out. Record the AAB sha256 and the sentinel in
`CHANGELOG.md` under the version heading.

### 6.3 Tag

```bash
git tag -s x.y.z -m 'Release x.y.z'
tool/release_build.sh --verify --sentinel '…'   # now also checks the tag
git push origin main x.y.z
```

### 6.4 F-Droid

The recipe (`fdroid/metadata/dev.khoj.pitaka.fdroid.yml`) is a **verbatim
mirror** of the file in upstream `fdroiddata`. Upstream is authoritative;
re-sync the mirror whenever review amends it.

- The recipe is on `AutoUpdateMode: Version` + `UpdateCheckMode: Tags`: the
  **checkupdates bot** reads `version:` from `pubspec.yaml` at the tag and
  opens the fdroiddata MR itself (typically within a day). It copies the
  previous build block and pins the full commit hash.
- Open a **manual MR** only when the recipe body must change (build command,
  toolchain, a skipped version) or when you want it faster than the bot. In
  that case add the three build blocks (`versionCode` N1/N2/N3, `commit:
  'x.y.z'`) and bump `CurrentVersion` / `CurrentVersionCode` to N3.
- Lint and build locally in an fdroiddata checkout if the recipe changed:
  `fdroid lint dev.khoj.pitaka.fdroid` · `fdroid build -v -l dev.khoj.pitaka.fdroid`.
- Watch `https://f-droid.org/api/v1/packages/dev.khoj.pitaka.fdroid` for
  `suggestedVersionCode` to move. Build + publish lag is days.

Recipe facts worth knowing:

- **Builds from source, always.** There is no `cargokit.yaml` with a
  precompiled-binary key, so cargokit's download path is disabled and the
  Rust core is cross-compiled on the build server (`Precompiled binaries are
  disabled` in the log). No prebuilt `.so`/`.a` is committed.
- **Rust comes from the distribution's `rustup` package.** The current recipe
  installs it with `apt-get` and runs `rustup default 1.96.0` in each
  split-ABI Flutter/Rust build entry's `prebuild:` block, then adds the
  Android target. It does **not**
  install under `/opt/rust`, set `RUSTUP_HOME` or `CARGO_HOME`, or chmod a
  shared toolchain; those older instructions were removed when the recipe
  changed.
- Toolchain the recipe assumes — keep the app in sync: Flutter from `.fvmrc`
  (checked out from the `flutter@stable` srclib at that exact version),
  NDK r28c, Gradle 8.14, Kotlin 2.2.20, Rust 1.96.0 (`rust-version` in
  `rust/Cargo.toml`), Android targets
  `armv7-linux-androideabi aarch64-linux-android x86_64-linux-android`.
- Output paths are `build/app/outputs/apk/fdroid/release/app-fdroid-<abi>-release.apk`.
- A version that must be skipped on F-Droid (as 1.3.4 was, for a non-free
  dependency) stays in the recipe as `disable: <reason>`, never silently
  absent.

---

## 7. Toolchain (what the pins mean)

- **Flutter** is pinned in `.fvmrc` **and** `pubspec.yaml`
  (`environment: flutter:`). Bump both together. `pub get` under any other
  Flutter fails closed. Use `fvm flutter …` / `fvm dart …`, never PATH's.
- **JDK:** Kotlin 2.2.20 needs JDK ≤ 21; set `org.gradle.java.home` in the
  user-global `~/.gradle/gradle.properties`, not in the repo.
- **Rust:** stable via rustup; cargokit cross-compiles `pitak_crypto` during
  the Gradle build. After editing `rust/src/api.rs`:
  `flutter_rust_bridge_codegen generate`, then confirm
  `llvm-nm -D libpitak_crypto.so | grep -c frb_pde_ffi_dispatcher` prints 2.
- **16 KB pages:** NDK 28 defaults to 16 KB-aligned loads; every `.so` in the
  bundle must show `LOAD` alignment ≥ `0x4000` under `llvm-readelf -l`.
- Fat APK ≈ 97 MB (fonts ≈ 4 MB); per-ABI split ≈ 40 MB. Expected.
- Flutter 3.44 warns that the app and six plugins still apply the Kotlin
  Gradle Plugin the old way; a future Flutter will refuse. Track it.

---

## 8. Play Console answers (keep consistent with `PRIVACY.md`)

- **Data safety:** "No data collected or shared." No developer servers; ISBN
  lookups carry book metadata only; publish, exports, network Refresh and map
  tiles are **user-directed transfers** to sites/OSM the user chose; a
  published location pin is the user's own deliberate publish choice (off by
  default). If Play ever counts opt-in tiles as "sharing", the honest edit is
  "Location → approximate, user-directed, not collected by the developer" —
  still no collection.
- **Content rating** Everyone · **Target audience** 18+ (keeps the Families
  policy out of scope) · **Ads** No · News / COVID / Government No.
- **App access:** core needs no account; optional Publish uses the user's own
  GitHub sign-in.
- **Privacy policy URL** points at `PRIVACY.md` on the `main` branch —
  moving or renaming that file breaks the link.
- **Listing** copy: `fastlane/metadata/android/en-US/{short,full}_description.txt`;
  icon via `tool/gen_app_icon.py`, feature graphic via `tool/gen_play_assets.py`;
  category Books & Reference. Organisation account ⇒ no closed-test gate.
