# HANDOFF — Pitak (Kotlin→Flutter port)

> Read this first, then `PLAN.md` (authoritative task log: roadmap, per-step
> "Result" entries, decisions, out-of-scope observations).

_Last updated: 2026-09-03 (comprehensive review remediation → 1.1.10; see PLAN.md top task)._

**Status: stable; shipped on F-Droid as 1.1.8 (live — versionCodes 131–133,
confirmed via the F-Droid API).** The round-2 security review is fully
remediated (1 Blocker, 4 Majors, 10 Minor/Nits — see PLAN.md "Fix
REVIEW_FINDINGS_2" → Result). The two `REVIEW_FINDINGS*.md` files and
`design_preview/` were removed as superseded; they remain in git history and
their open items live in PLAN.md's out-of-scope sections.

- Gates green (2026-09-03, pre-1.1.10): `flutter analyze lib test` 0 issues ·
  `dart format` clean · **794 Dart tests** · **27 + 3 Rust tests** · per-ABI
  release APK ~40 MB (arm64; the ~100 MB figure is the FAT apk — fonts are
  only ~4 MB of it).
- Repo: `origin` → `https://github.com/PLFIndia/pitak-x.git`, default branch
  `main`. `*.pitabak` + `build/` are git-ignored. Commit/push/branch ops need
  explicit per-invocation approval (§9 of the harness AGENTS.md).
- Package id: namespace `dev.khoj.pitaka`; applicationId
  `dev.khoj.pitaka.fdroid` (matches the live F-Droid listing so F-Droid users
  get updates). A Play/direct channel must be a **product flavor with its own
  applicationId** (see the comment in `android/app/build.gradle.kts`) — do NOT
  ship the `.fdroid` id to Play.
- Signing: release builds use `android/key.properties` when present
  (template: `android/key.properties.example`). WITHOUT it, a `play` release
  build now FAILS (fail closed — `-PallowUnsignedPlayRelease=true` is the
  compile-only escape hatch) while an `fdroid` release still falls back to
  debug signing (F-Droid signs with its own key). The upload keystore lives on
  the maintainer's other machine.
- Toolchain: `.fvmrc` pins Flutter 3.44.2 (F-Droid reproducibility) and the
  dev machine's PATH Flutter is also 3.44.2 (verified 2026-09-03). Dart SDK
  `^3.11`.

---

## 1. What this project is

Port of the Kotlin/Android **Pitak** (`~/Pitak_fdroid/`) to Flutter. One-way
(Kotlin→Flutter), hard guarantee of **zero data loss**. Backup compatibility
is ALSO one-way (decided 2026-09-03: "only this app, there is no old app
functionality"): Pitak restores Kotlin-era `.pitabak` archives and its own,
but the Kotlin app is NOT a restore target for ours. The writer still emits
Room-shaped `books.db`/`wishlist.db` because that is simply the archive
format both readers understand — not because Kotlin must open them.

Two `AGENTS.md` govern: the repo one (Clean Arch + DDD, Riverpod codegen,
`fpdart Either<Failure,T>`, drift, secrets as wipeable bytes never `String`)
and the harness one (verify-don't-assume; ask before §9 actions). **Read the
Kotlin source before porting any feature** — its `data/`, `domain/usecase/`,
`ui/` are the contract.

---

## 2. The crypto chain (verified on real data + on-device, read + WRITE)

```
backup_blob = base64(salt16).base64(iv12).base64(ciphertext48)
  → Argon2id(t=3, m=65536 KiB, p=1, 32B, v0x13) over passphrase UTF-8 + salt → KEK
  → AES-256-GCM (un)wrap → 32-byte vault key (MK)   [tag-fail = wrong passphrase]
  → sqlite3_key(db, raw 32 bytes, 32)   ← raw bytes, NOT PRAGMA key
  → zetetic-written borrowers.db (SQLCipher 4.5.7 opens zetetic 4.5.4 @ default)
```

The 32-byte vault key (MK) NEVER crosses FFI — it lives only in Rust
`Zeroizing<>`. Dart sends passphrase bytes + blob + db path; gets back rows /
new ids / typed errors. Single wrap site: `crypto::wrap_vault_key`;
`derive_kek` is shared so wrap/unwrap can't drift.

**Envelope model:** the passphrase only ever WRAPS a random MK.
- **Change-passphrase** = unwrap MK with old → rewrap under new.
- **Vault biometric** = a SECOND wrapping of the SAME MK under a random
  secret S (`wrap_for_biometric`). The PASSPHRASE IS NEVER STORED; S lives in
  hardware-backed storage, gated by a `local_auth` prompt.

**Two distinct biometric features — don't confuse them:**
- **Vault biometric**: unlocks the SQLCipher vault; releases secret S; MK
  never crosses FFI (`features/vault/...biometric...`).
- **App-lock biometric**: a UI GATE before the Library screen
  (`core/widgets/app_gate.dart`, `settings.appLockBiometric`). Encrypts
  nothing, holds no secret.

---

## 3. Architecture map (Clean Arch: domain ← application ← presentation;
infrastructure implements domain ports)

```
rust/  crate pitak_crypto — trusted crypto + vault boundary
  src/crypto.rs / vault.rs / api.rs ; tests/vault_fixture.rs

lib/
  src/rust/**   flutter_rust_bridge generated bindings (analyzer-excluded)
  core/
    crypto/     secret_bytes.dart, secure_passphrase_field.dart
    images/     image_downscaler.dart (400x600 q80 JPEG; CLEARS EXIF incl. GPS
                before encode — round-2 Blocker fix; single choke point for
                covers/posters/logos) + header-dimension guard (>8192px/side
                rejected before allocation)
    platform/   screen_security.dart (FLAG_SECURE; also covers passphrase
                entry via PassphraseEntryVisibility)
    widgets/    app_drawer.dart, book_cover.dart, library_logo.dart,
                splash_screen.dart (2s), app_gate.dart (splash→gate→Library),
                qr_view.dart
    di/providers.dart  ALL Riverpod @riverpod DI
  features/
    library/        books CRUD/search/sort/filter/soft+hard delete; cover
                    capture; domain/merge/library_merge_engine.dart (#33)
    vault/          persistent encrypted vault (change-passphrase, biometric)
    lookup/         barcode scanner + ISBN lookup (OL→GoogleBooks chained)
    publish/        Publish to GitHub Pages (device-flow + git data API);
                    viewer + events page upload
    events/         event posters (publish flow); EXIF-stripped on ingest
    bookmarks/      external-library bookmarks (https allow-list launch)
    backup/         .pitabak writer (Room-shaped DBs; Pitak↔Pitak + Kotlin→Pitak) + restore
    import_export/  JSON/CSV/PDF export (CSV export is formula-injection-
                    neutralised), Goodreads import, merge UI/use case
    settings/       4 tabs: Appearance · Data · Security · Contribute
  assets/
    publish/    index.html (library viewer), events.html (events viewer)
    pdf/        app_icon.png (PDF footer)
    fonts/      10 Noto Sans Indic scripts × {Regular,Bold} = 20 TTFs + OFL.txt
                (PDF-only, loaded by the `pdf` pkg via rootBundle)
    branding/   app_icon.png + NotoSansBrahmi-Regular.ttf (splash Brahmi text)
```

**PDF text is rendered as SHAPED IMAGES** (accepted tradeoff, not a bug):
Flutter's engine (HarfBuzz) shapes each run → PNG tile embedded in the PDF
(`import_export/infrastructure/pdf_text_rasterizer.dart`). This is what makes
Devanagari conjuncts/half-letters correct (बच्चे). Consequence: PDF text is
NOT selectable. The vector `drawString` path survives only as a no-rasterizer
fallback (Latin-only callers / pure tests).

---

## 4. Entry points / navigation

- **App launch**: `main.dart` → **AppGate**. Cold start: 2s splash, then
  biometric prompt if app-lock is ON (fail-closed), else Library. Returning
  from background re-locks + re-prompts when app-lock is on.
- **Library home**: app-bar leading = library logo → opens drawer; scan-to-add
  + overflow (import/export/backup/restore); FAB = add book.
- **Drawer**: logo header, tiles: Borrowers vault · Publish to web · Wishlist ·
  Bookmarks · Share Library Website (when a site is published) · Settings.
- **Settings (4 tabs)**: Appearance (theme, names, library-icon picker,
  remote-cover toggle) · Data (import/export/backup/restore + **Merge from a
  file**) · Security (app-lock toggle, vault biometric, change-passphrase) ·
  Contribute (publish-contact fields).
- **Events**: reached from the Publish page.
- **Export**: JSON / CSV / PDF (column picker; Location/Source default-off as
  private).

---

## 5. Build / verify / on-device

```bash
cd ~/projects/pitak-x
flutter analyze lib test            # expect: No issues found!
dart format --set-exit-if-changed lib test
flutter test                        # 794 pass pre-1.1.10
( cd rust && cargo test --release ) # 27 unit + 3 fixture pass
# After @riverpod/freezed/drift edits: dart run build_runner build --delete-conflicting-outputs
# After rust/src/api.rs edits: flutter_rust_bridge_codegen generate

# On-device (Pixel 8a, pkg dev.khoj.pitaka.fdroid). Flavors are REQUIRED on
# every build/run command since 2026-08-15 (channel dimension: fdroid/play):
flutter build apk --release --flavor fdroid   # rebuild from CURRENT code (stale APK = known trap)
ADB=$HOME/Library/Android/sdk/platform-tools/adb   # adb not on PATH
# verify frb dispatcher survived R8 (expect 2 lines: _primary + _sync):
nm -D $(find build -path '*arm64*/libpitak_crypto.so'|head -1) | grep frb_pde_ffi_dispatcher
$ADB install -r build/app/outputs/flutter-apk/app-fdroid-release.apk   # -r preserves vault data
# Google Play artifact: flutter build appbundle --release --flavor play
```

The device also carries Kotlin `dev.khoj.pitaka.fdroid*` variants — different
apps, leave them.

---

## 6. On-device verification status (honesty)

- **User-confirmed earlier**: native vault write path, change-passphrase,
  vault biometric, scanner, ISBN lookup, drawer, scan-to-add, cover capture.
- **Built + installed on the Pixel 8a, never explicitly user-confirmed**
  (batch from the splash/PDF session): splash timing, Indic PDF glyph
  correctness (बच्चे) + print sharpness, gallery logo pick, app-lock
  resume re-lock, launcher label "Pitak". If the user reports an issue in
  any of these, start there.
- **Still MockClient-only**: Publish (real GitHub OAuth + push never run live).

---

## 7. DONE vs NEXT

### DONE
Library (CRUD/search/sort/filter/soft+hard delete, cover capture), Wishlist,
Import/Export (JSON/CSV/PDF with Indic shaping), Backup create+restore
(Pitak↔Pitak + legacy Kotlin→Pitak), encrypted vault (+change-passphrase, +biometric),
FLAG_SECURE (incl. passphrase entry), scanner, ISBN lookup, Publish to GitHub
Pages, **Merge (#33: engine + UI, atomic apply, dup-ISBN safe)**, **Events
(posters + events.html publish)**, **Bookmarks**, nav drawer + tabbed
settings, splash + app-lock + library logo, **round-2 security remediation
(EXIF/GPS stripping, CSV-injection neutralisation, merge atomicity, redirect
re-validation, decoder-bomb guard — full list in PLAN.md)**.

### NEXT
- **Google Play track** — see §8.
- **Dependency upgrade programme** (PLAN.md top task, 3 tiers) — the hard
  gate is now satisfied: 1.1.8 is live on F-Droid (suggestedVersionCode 133).
  Tier 2 touches security-critical packages (flutter_secure_storage,
  local_auth, archive 4.x port) — re-run §10 security tests per step.
- **Contribute tab (DEFERRED, user wants it "last")** — two new subsystems:
  app-wide LocalizedText i18n + opt-in crash reporting. Scope with the user
  first. Kotlin: `ui/settings/SettingsScreen.kt::ContributeTab`,
  `ui/contribute/**`, `data/crash/**`.
- **Cloudflare Pages publish** — deferred half of Publish. Kotlin
  `ui/publish/CloudflareWizardScreen.kt` — READ before designing.

### Release hardening (before any public ship)
- Real signing keystore (Play: upload key + Play App Signing enrollment).
- `cargo clippy` never run (install is an approval-gated action).

---

## 8. Google Play track (started 2026-08-15)

Readiness analysis done; gaps and order of operations:

1. **applicationId**: create a `play` product flavor with a clean id
   (candidate `dev.khoj.pitaka` — verify it's free on Play). Keep the
   `.fdroid` id untouched for F-Droid.
2. **Signing**: generate upload keystore (command in
   `android/key.properties.example`), create `android/key.properties`,
   enroll in Play App Signing, back up the keystore outside the repo.
3. **Build**: `flutter build appbundle --release` (Play accepts AAB only).
   The ABI-split versionCode logic in build.gradle.kts is APK-only and
   harmless for AAB.
4. **16 KB page-size verification** (hard Play requirement for native code):
   no explicit `max-page-size=16384` flag exists in rust/ or cargokit, but
   the pinned NDK r28.2 defaults to 16 KB alignment. Verify on the built
   bundle: `readelf -lW` each `.so` (LOAD segments aligned 16384) — covers
   pitak_crypto (Rust), sqlite3_flutter_libs 0.5.42, flutter_zxing 2.3.0.
5. **Privacy policy**: none exists — required (CAMERA permission). Write +
   host at a public URL.
6. **Data safety form**: no data collected/shared by the developer;
   user-initiated-only transmissions to Open Library / Google Books (ISBN)
   and the user's own GitHub (publish). Camera photos stay on-device unless
   the user publishes.
7. **Listing assets**: 512×512 icon (regenerate — `tool/gen_app_icon.py`;
   current fastlane icon is 192×192), feature graphic 1024×500, ≥2 phone
   screenshots. Store copy can be adapted from `fastlane/metadata/`.
8. **Console formalities**: content rating (Everyone), target audience NOT
   children, app-access note for reviewers (core app needs no account;
   publish needs the reviewer's own GitHub), new personal dev accounts must
   run a closed test (12 testers / 14 days) before production.

---

## 9. Decisions already made (don't re-litigate — PLAN.md "Result" entries)

- **PDF**: text as shaped images (§3). Column/layout logic is pure
  (`domain/pdf_column.dart`, unit-tested); `pdf` pkg renderer with Y-axis
  flip. Bundled 10 Noto Sans scripts × {Regular,Bold} (SIL OFL).
- **Splash/gate/logo**: app-lock OPT-IN, default OFF; re-locks on
  background/resume; Brahmi-only splash text 𑀧𑀺𑀝𑀓 (NotoSansBrahmi);
  logo = gallery pick only, downscaled to covers/<uuid>.jpg; device
  PIN/pattern fallback allowed. App-lock is a UI GATE ONLY — copy says so.
- **Rename**: only USER-VISIBLE "Pitaka"→"Pitak". LEFT as-is: Dart package
  `pitaka`, class names, schema const, publish commit message (Kotlin repo
  contract).
- **Vault**: at-rest = borrowers.db + blob in app docs; session passphrase
  wiped on exit; biometric = second wrapping, passphrase never stored.
- **Publish**: one atomic git-data commit, PII redaction, https cover
  allow-list mirroring viewer CSP, token in secure storage, fixed error
  strings only. Cover fetcher follows redirects MANUALLY, re-validating each
  hop against the allow-list (max 3 hops).
- **Merge**: add-only semantics, removal-as-conflict, identity order
  uid→ISBN→fuzzy, single-transaction apply, incoming-file dup-ISBN/uid
  surfaced as PossibleDuplicate.

---

## 10. Test fixtures + gotchas

- `test/fixtures/vault/` — committed SYNTHETIC vault, passphrase
  `test-pass-not-secret`. Regenerate:
  `cd rust && cargo run --release --example gen_test_vault -- ../test/fixtures/vault`.
- **Splash timing in widget tests**: boot tests must
  `await tester.pump(const Duration(seconds: 2))` to fire the splash timer
  (`pumpAndSettle` alone won't advance it).
- **PDF rasterizer needs a live engine** — renderer/use-case tests
  exercising it are WIDGET tests (`TestWidgetsFlutterBinding.ensureInitialized()`).
- **PDF drawString fallback is Latin-1 only** — without a rasterizer,
  non-Latin text throws "Cannot decode the string to Latin1". A harmless
  dart_pdf "Helvetica has no Unicode support" log line fires regardless.
- `ImageDownscaler` catches `on Object` (the `image` pkg THROWS on garbage).
- APK ~100 MB (bundled fonts) — expected, not a regression.
- frb codegen runs from a runtime pin (2.12.0); regenerate after any api.rs
  change and re-check the `nm -D` symbols.
- Schema-migration test scaffold + schemaVersion tripwire test exist —
  forward-migration tests must land with the first schema bump.

---

## 11. Suggested first moves for the next session

1. Re-verify green (§5) — confirms a clean inherited tree (794 Dart / 27+3 Rust).
2. If the user reports an on-device issue with the unconfirmed batch (§6),
   start there.
3. Play track (§8): the first code touch is the `play` product flavor +
   keystore; everything else is console/assets work.
4. Dependency upgrade tiers (PLAN.md top task) — gate satisfied, but tier 2/3
   are security-critical and F-Droid-coupled; don't mix with the Play track.
