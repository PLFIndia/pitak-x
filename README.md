# Pitak

A privacy-first, offline personal **library catalogue** for Android (and other
Flutter targets). Pitak is a Kotlin→Flutter port of the original Android app:
catalogue your books, lend them to borrowers from an **encrypted vault**, keep a
wishlist, import/export (JSON · CSV · PDF), make portable backups, and publish a
read-only library site to GitHub Pages.

> **Status:** published on **F-Droid** (`dev.khoj.pitaka.fdroid`) and
> **Google Play** (`dev.khoj.pitaka`); current release 1.1.10. `PLAN.md`
> tracks the task in flight; the maintainer's full engineering reference
> (`appDetails.md`) is kept locally and is not part of this repository.

---

## Features

- **Library** — add/edit/search/sort/filter books; soft-delete (Remove/Restore)
  and hard delete; on-device cover capture; ISBN barcode scan + metadata lookup
  (Open Library → Google Books, chained + cached).
- **Borrowers vault** — a persistent, **AES-256-GCM encrypted** store for
  borrowers and loans, unlocked by a passphrase (Argon2id KEK). Optional
  biometric unlock. The vault key never crosses the Dart/Rust FFI boundary.
- **Wishlist** — track books to acquire; move to the library on purchase.
- **Import / Export** — JSON, CSV (incl. Goodreads import), and **PDF** (a
  paginated A4 library list with Indic-script support via shaped-image text).
- **Backup / Restore** — `.pitabak` archives. Pitak restores its own archives
  **and** archives made by the original Kotlin app (one-way: Kotlin → Pitak;
  the Kotlin app is retired and is not a restore target). **Honest limit:**
  the archive is *not* fully encrypted — books, wishlist and covers are stored
  plainly inside it; only the borrowers vault (when present) stays encrypted.
  Treat backup files accordingly.
- **Publish** — push a read-only library viewer to **GitHub Pages** (device-flow
  auth + git data API), with PII redaction and an https-only cover allow-list.
- **App-lock** — optional, opt-in biometric/device-credential gate before the
  library screen. It is a **screen cover, not a vault lock**: it deters casual
  access on an unlocked phone but does not encrypt data at rest and does not
  lock an already-unlocked vault.

## Privacy posture

Local-first by default. Sensitive data (vault, tokens) lives in
`flutter_secure_storage` (Keystore/Keychain); secrets are held as wipeable bytes
where the design allows it (some platform-managed secrets, like the GitHub
token, transit as immutable strings — see `astra-review.md` trade-offs).
Network calls happen only on explicit user action (ISBN lookup,
publish, remote covers — the last is opt-in, default off).

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
  screen; it does not lock or encrypt the vault itself.
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
  core/        cross-cutting: crypto, images, platform, DI (core/di/providers.dart), shared widgets
  features/    library · vault · wishlist · lookup · publish · backup · import_export · settings
  src/rust/    flutter_rust_bridge generated bindings (analyzer-excluded)
rust/          pitak_crypto crate (crypto + vault boundary) + tests
assets/        publish viewer, PDF fonts (Noto Sans Indic), branding
test/          Dart tests (unit + widget); test/helpers/ for shared harness
```

The two `AGENTS.md` files (repo + harness) are the binding engineering contract —
read them before contributing.

## Getting started

Prerequisites: Flutter 3.44.2 (pinned in `.fvmrc`) stable, the Android SDK, and a Rust toolchain
(cargokit compiles the native crate during the Android build).

```bash
flutter pub get

# Regenerate codegen after editing @riverpod / freezed / drift / json_serializable:
dart run build_runner build --delete-conflicting-outputs

# Regenerate FFI bindings after editing rust/src/api.rs:
flutter_rust_bridge_codegen generate
```

### Run / build

```bash
flutter run -d <device-id> --flavor fdroid            # debug, with hot reload
flutter build apk --release --flavor fdroid           # F-Droid APKs (~98 MB; bundled Noto fonts)
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
flutter analyze lib test                       # expect: No issues found!
dart format --set-exit-if-changed lib test
flutter test                                   # full Dart suite (794 tests)
( cd rust && cargo test --release )            # native crate tests (22)
```

Tip: the full widget suite can be slow under some harnesses — run by directory
(`flutter test test/features/<area>`) to isolate a slow/hanging file.

## License / fonts

Bundled Noto Sans Indic fonts (for PDF export) are under the SIL Open Font
License 1.1 — see `assets/fonts/OFL.txt`.
