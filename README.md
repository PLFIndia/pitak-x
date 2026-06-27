# Pitak

A privacy-first, offline personal **library catalogue** for Android (and other
Flutter targets). Pitak is a Kotlin→Flutter port of the original Android app:
catalogue your books, lend them to borrowers from an **encrypted vault**, keep a
wishlist, import/export (JSON · CSV · PDF), make portable backups, and publish a
read-only library site to GitHub Pages.

> **Status:** feature-rich and stable on a physical device (Pixel 8a). The
> release build is still **debug-signed** — a real signing keystore is the main
> pre-ship gate. See `HANDOFF.md` for the authoritative engineering status and
> `PLAN.md` for task history.

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
- **Backup / Restore** — `.pitabak` archives that are **bidirectional** with the
  original Kotlin app (Room-compatible DBs).
- **Publish** — push a read-only library viewer to **GitHub Pages** (device-flow
  auth + git data API), with PII redaction and an https-only cover allow-list.
- **App-lock** — optional, opt-in biometric/device-credential gate before the
  library screen (a UI gate, not at-rest encryption).

## Privacy posture

Local-first by default. Sensitive data (vault, tokens) lives in
`flutter_secure_storage` (Keystore/Keychain); secrets are held as wipeable bytes,
never `String`. Network calls happen only on explicit user action (ISBN lookup,
publish, remote covers — the last is opt-in, default off). Screenshots are
blocked (`FLAG_SECURE`) while sensitive data is visible.

## Tech stack

- **Flutter** 3.41.x (stable) · **Dart** SDK `^3.11`.
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

Prerequisites: Flutter 3.41.x stable, the Android SDK, and a Rust toolchain
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
flutter run -d <device-id>            # debug, with hot reload
flutter build apk --release           # multi-ABI release APK (~98 MB; bundled Noto fonts)
flutter install -d <device-id> --release
```

`flutter devices` lists ids. The Android package id is `dev.khoj.pitaka`.

> First Android build is slow: cargokit cross-compiles the Rust core for every
> ABI. Use `flutter build apk` (visible Gradle/Rust progress) rather than a bare
> `flutter run` if you want to watch the compile.

## Quality gates

```bash
flutter analyze lib test                       # expect: No issues found!
dart format --set-exit-if-changed lib test
flutter test                                   # full Dart suite (currently 400 tests)
( cd rust && cargo test --release )            # native crate tests (22)
```

Tip: the full widget suite can be slow under some harnesses — run by directory
(`flutter test test/features/<area>`) to isolate a slow/hanging file.

## License / fonts

Bundled Noto Sans Indic fonts (for PDF export) are under the SIL Open Font
License 1.1 — see `assets/fonts/OFL.txt`.
