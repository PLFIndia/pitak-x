# Pitak

A privacy-first, offline personal **library catalogue** for Android. Pitak is a
Kotlin→Flutter port of the original Android app: catalogue your books, lend
them to borrowers from an **encrypted vault**, keep a wishlist, import/export
(JSON · CSV · PDF), make portable backups, and publish a read-only library site
to GitHub Pages with event posters and bookmarks to other libraries.

> **Status:** published on **F-Droid** (`dev.khoj.pitaka.fdroid`) and
> **Google Play** (`dev.khoj.pitaka`). Current source release is **1.2.0**
> (`pubspec.yaml`, tag `1.2.0`); F-Droid builds from the tag on its own
> schedule, so its index may lag by a release. `PLAN.md` tracks the task in
> flight; the maintainer's full engineering reference (`appDetails.md`) is
> kept locally and is not part of this repository.

---

## Features

- **Library** — add/edit/search/sort/filter books; soft-delete (Remove/Restore)
  and hard delete; on-device cover capture; ISBN barcode scan + metadata lookup
  (Open Library → Google Books, chained + cached).
- **Borrowers vault** — a persistent, **AES-256-GCM encrypted** store for
  borrowers and loans, unlocked by a passphrase (Argon2id KEK). Optional
  biometric unlock, bound to an Android Keystore key that requires a fresh
  strong-biometric authentication per use (see security notes). The vault key
  never crosses the Dart/Rust FFI boundary.
- **Wishlist** — track books to acquire; move to the library on purchase.
- **Import / Export** — JSON, CSV (incl. Goodreads import), and **PDF** (a
  paginated A4 library list with Indic-script support via shaped-image text).
- **Backup / Restore** — `.pitabak` archives. Pitak restores its own archives
  **and** archives made by the original Kotlin app (one-way: Kotlin → Pitak;
  the Kotlin app is retired and is not a restore target). **Honest limit:**
  the archive is *not* fully encrypted — books, wishlist and covers are stored
  plainly inside it; only the borrowers vault (when present) stays encrypted.
  Treat backup files accordingly. Restore is all-or-nothing: the catalogue,
  covers and vault are written into a new data folder and the app switches to
  it in one step, so a failed or interrupted restore leaves your current data
  untouched (the previous folder is deleted right after a successful switch).
- **Publish** — push a read-only library viewer to **GitHub Pages** (device-flow
  auth + git data API), with PII redaction and an https-only cover allow-list.
- **Events** — attach a small set of event posters (image + optional short
  description) to the published site; images stay on-device as ordinary files.
- **Bookmarks** — save labelled links to *other* libraries' published sites.
  URLs are validated strictly (https only; GitHub Pages / Cloudflare Pages
  hosts) and stored as a plain, non-secret list.
- **App-lock** — optional, opt-in biometric/device-credential gate before the
  library screen. It is a **screen cover, not a vault lock**: it deters casual
  access on an unlocked phone but does not encrypt data at rest and does not
  lock an already-unlocked vault.

## Privacy posture

Local-first by default. Sensitive data (vault, tokens) lives in
`flutter_secure_storage` (Keystore/Keychain). Vault secrets — the passphrase
on its way to the Rust core and the biometric secret — are held as wipeable
bytes and never as Dart `String`s; the GitHub token and the ISBN-lookup key are
the honest exceptions (their HTTP/plugin APIs are `String`-typed, so they
transit as immutable strings).
Network calls happen only on explicit user action (ISBN lookup,
publish, remote covers — the last is opt-in, default off, host-allow-listed,
and each cover is downloaded once and then kept as an ordinary local cover).

**Platform matrix (M18):** Android is the only shipping target today.
Screenshot/recents capture is blocked on Android (`FLAG_SECURE`) while
sensitive data is visible; other Flutter targets are not shipped and have no
equivalent protection wired up. The optional biometric app-lock is a screen
cover, not a vault lock (see the security notes below).

### Security notes (honest limits)

- **Vault session lifetime:** once unlocked, the vault stays unlocked in
  memory until you lock it or the app exits. There is deliberately no
  auto-lock timeout (user decision); backgrounding the app does not lock it.
- **App-lock ≠ vault lock:** the optional biometric app gate covers the
  screen; it does not lock or encrypt the vault itself. It is a software
  check (a yes/no from the OS prompt), unlike the vault's biometric unlock
  below.
- **Vault biometric unlock is hardware-bound (Android):** the random secret
  that opens the vault's biometric key blob is stored only as ciphertext under
  an Android Keystore AES key created with `setUserAuthenticationRequired`
  (per use, `BIOMETRIC_STRONG` only) and `setInvalidatedByBiometricEnrollment`.
  The system prompt and the cipher are one object (`BiometricPrompt.
  CryptoObject`), so no app code can release the secret without the user
  authenticating for that exact operation. Consequences: a PIN/pattern cannot
  substitute for the biometric here; devices with only a Class 2 (weak)
  biometric cannot enrol; adding or removing a fingerprint/face destroys the
  key and the user re-enrols with the passphrase. The key is TEE-backed
  (StrongBox is not requested). Users upgrading from a build before this
  change re-enrol once. The passphrase path is never affected.
- **Passphrase change is rewrap, not key rotation:** changing the vault
  passphrase re-wraps the *same* master key (`rust/src/api.rs`). Anyone holding
  an old vault copy *and* the old passphrase can still open that copy; only
  re-creating the vault would rotate the key.

## Tech stack

- **Flutter** 3.44.2 stable (pinned in `.fvmrc`) · **Dart** SDK `^3.11`.
- **Architecture:** Clean Architecture + DDD —
  `domain ← application ← presentation`, `infrastructure` implements domain
  ports. See `lib/features/<feature>/{domain,application,infrastructure,presentation}`.
- **State / DI:** Riverpod with code generation (`@riverpod`).
- **Errors:** `fpdart` `Either<Failure, T>` (no exceptions for expected failures).
- **Persistence:** Drift (SQLite); SQLCipher for the vault.
- **Native core:** a Rust crate (`rust/`, `pitak_crypto`) for Argon2id +
  AES-GCM + the SQLCipher vault, bridged via `flutter_rust_bridge` (cargokit
  builds it during the Android build).

## Project layout

```
lib/
  core/        cross-cutting: app_lock, crypto, database, DI (core/di/providers.dart), error,
               images, layout, network, platform, storage, shared widgets
  features/    library · vault · wishlist · lookup · publish · events · bookmarks ·
               backup · import_export · settings
  src/rust/    flutter_rust_bridge generated bindings (analyzer-excluded)
rust/          pitak_crypto crate (crypto + vault boundary) + tests
assets/        publish viewer, PDF fonts (Noto Sans Indic), branding
test/          Dart tests mirroring lib/ (core/, features/); architecture/ holds the
               domain-purity check; fixtures/ the synthetic hermetic vault
.githooks/     tracked pre-commit hook (see Getting started)
fdroid/        the F-Droid build recipe, version-controlled next to the app
fastlane/      store metadata + per-versionCode changelogs
```

The two `AGENTS.md` files (repo + harness) are the binding engineering contract —
read them before contributing.

## Getting started

Prerequisites: Flutter 3.44.2 (pinned in `.fvmrc`) stable, the Android SDK, and a Rust toolchain
(cargokit compiles the native crate during the Android build).

```bash
flutter pub get

# One-time per clone: enable the tracked pre-commit hook (see below).
git config core.hooksPath .githooks

# Regenerate codegen after editing @riverpod / freezed / drift / json_serializable:
dart run build_runner build --delete-conflicting-outputs

# Regenerate FFI bindings after editing rust/src/api.rs:
flutter_rust_bridge_codegen generate
```

**Why the hook:** every `.g.dart` / `.freezed.dart` file is generated from the
hand-written `.dart` next to it, and riverpod's generated code embeds a hash of
the annotated class's *source code* — so adding a field, renaming a private
member, or touching any code inside a `@riverpod` class silently makes its
`.g.dart` stale (comments and whitespace are ignored), and CI fails with
"Generated files are stale". `.githooks/pre-commit` runs the same check CI
runs (regenerate, then `git diff` on generated files) before the commit is
created, using the Flutter SDK pinned in `.fvmrc`. It never stages or edits
your commit for you; on drift it lists the regenerated files and refuses.
Git does not enable tracked hooks automatically, hence the one-time
`git config` above. Bypass in an emergency with `git commit --no-verify`
(CI will still catch it).

### Run / build

```bash
flutter run -d <device-id> --flavor fdroid            # debug, with hot reload
flutter build apk --release --flavor fdroid           # universal APK (large: bundled Noto fonts + 4 Rust ABIs)
flutter build apk --release --flavor fdroid --split-per-abi   # what the F-Droid recipe builds (one APK per ABI)
flutter build appbundle --release --flavor play       # Google Play AAB
flutter install -d <device-id> --release --flavor fdroid
```

`flutter devices` lists ids. The app ships per-store flavors: `fdroid`
(applicationId `dev.khoj.pitaka.fdroid`, matching the live F-Droid listing)
and `play` (applicationId `dev.khoj.pitaka` for Google Play). Every build
command needs a `--flavor`.

> First Android build is slow: cargokit cross-compiles the Rust core for every
> ABI. Use `flutter build apk` (visible Gradle/Rust progress) rather than a bare
> `flutter run` if you want to watch the compile.

## Quality gates

```bash
dart run build_runner build --delete-conflicting-outputs
git diff --quiet -- '*.g.dart' '*.freezed.dart' # expect: silent, exit 0 (no stale codegen)
flutter analyze lib test                       # expect: No issues found!
dart format --set-exit-if-changed lib test
flutter test                                   # full Dart suite (1441 tests as of 1.2.0 / Sep 2026)
( cd rust && cargo test --release )            # native crate tests (32 run; 2 #[ignore]d — need a real vault via PITAK_* env)
```

These mirror `.github/workflows/ci.yml` one-to-one; the first two are also what
`.githooks/pre-commit` runs.

Tip: the full widget suite can be slow under some harnesses — run by directory
(`flutter test test/features/<area>`) to isolate a slow/hanging file.

## License / fonts

Bundled Noto Sans Indic fonts (for PDF export) are under the SIL Open Font
License 1.1 — see `assets/fonts/OFL.txt`.
