# HANDOFF — Pitak Kotlin→Flutter port

> Read this first, then `PLAN.md` (authoritative: full roadmap + every step's
> "Result" entry, decisions, feature-gap analysis).

_Last updated: 2026-06-26 (PDF-text-as-images doc sync)._

**Status: Feature-rich and stable. Recent sessions shipped: PDF export, Pitaka→
Pitak UI rename, launch splash + opt-in app-wide biometric gate, user library-
logo feature, the Track-B batch (logo→PDF header, multi-maintainer Merge port,
Pitak launcher icon), and two on-device bugfixes: (a) Android export/backup save
(share_plus — file_selector had no Android save dialog), and (b) **Devanagari
PDF shaping — PDF TEXT IS NOW RENDERED AS SHAPED IMAGES** (Flutter/HarfBuzz
shapes each run → embedded PNG tile; fixes conjuncts/half-letters/matra; tradeoff
= text not selectable). See §8 + PLAN.md "Bugfix 2". Host-tested; built + installed
on the Pixel 8a but NOT yet user-confirmed on-device — see §6.**

- Gates green: `flutter analyze lib test` 0 · `dart format` clean ·
  **400 Dart tests** · **22 Rust tests** · multi-ABI release APK builds
  (~101.8MB — Noto fonts add weight) + installs on a physical Pixel 8a (FRB
  dispatcher verified surviving R8).
- **NO git repo** here. Real `*.pitabak` archives live untracked in the repo root.
- Release is **debug-signed** (a real keystore is the main pre-ship gate).

---

## 1. What this project is

Porting Kotlin/Android **Pitak** (`~/Pitak_fdroid/`) to **Flutter** (this repo:
`~/development/pitak_flutter/`). One-way (Kotlin→Flutter), hard guarantee of
**zero data loss**. Backup is BIDIRECTIONAL: our writer emits Room-compatible
DBs so the original Kotlin app can also restore our backups.

Two `AGENTS.md` govern this: the repo one (Flutter/Dart: Clean Arch + DDD,
Riverpod codegen, `fpdart Either<Failure,T>`, drift, secrets as wipeable bytes
never `String`) and the harness one (verify-don't-assume; ask before §9 actions;
stop-and-report after one failed approach; pause at decision points). **Read the
Kotlin source before porting any feature** — its `data/`, `domain/usecase/`, and
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
new ids / typed errors. The single wrap site is `crypto::wrap_vault_key`;
`derive_kek` is shared so wrap/unwrap can't drift.

**Envelope model:** the passphrase only ever WRAPS a random MK.
- **#28A change-passphrase** = unwrap MK with old → rewrap under new.
- **#34 vault biometric** = a SECOND wrapping of the SAME MK under a random
  secret S (`wrap_for_biometric`). The PASSPHRASE IS NEVER STORED; S lives in
  hardware-backed storage, gated by a `local_auth` prompt.

**NOTE — two distinct biometric features, don't confuse them:**
- **Vault biometric (#34)**: unlocks the SQLCipher vault; releases secret S; MK
  never crosses FFI. (`features/vault/...biometric...`)
- **App-lock biometric (NEW this session)**: a UI GATE before the Library
  screen. It does NOT encrypt anything and holds no secret — it just calls the
  same `BiometricAuthenticator` capability to decide whether to show the app.
  (`core/widgets/app_gate.dart`, `settings.appLockBiometric`)

---

## 3. Architecture map (Clean Arch: domain ← application ← presentation;
infrastructure implements domain ports)

```
rust/  (crate pitak_crypto — trusted crypto + vault boundary)  [UNCHANGED]
  src/crypto.rs / vault.rs / api.rs ; tests/vault_fixture.rs

lib/
  src/rust/**   flutter_rust_bridge generated bindings (analyzer-excluded)
  core/
    crypto/secret_bytes.dart, secure_passphrase_field.dart
    images/image_downscaler.dart (400x600 q80 JPEG)
    platform/screen_security.dart (FLAG_SECURE)
    widgets/
      app_drawer.dart  (nav drawer; header now shows LibraryLogo + "Pitak")
      book_cover.dart
      library_logo.dart   ← NEW: LibraryLogo widget (user logo or default Pitak
                            icon; resolves via CoverPaths+coversDirProvider like
                            BookCover). kDefaultLogoAsset = assets/branding/app_icon.png
      splash_screen.dart  ← NEW: 2s launch splash. Big centred LibraryLogo, small
                            Pitak icon bottom, Brahmi "𑀧𑀺𑀝𑀓" (kPitakBrahmi,
                            NotoSansBrahmi font). holdDuration default 2s.
      app_gate.dart       ← NEW: splash→(biometric gate if on)→Library state
                            machine. Fail-closed; re-locks on background, re-prompts
                            on resume. main.dart home = AppGate (was LibraryPage).
    di/providers.dart  ALL Riverpod @riverpod DI. biometricAuthenticatorProvider
                       (#34) is REUSED by the app gate.
  features/
    library/     books CRUD/search/sort/filter/soft+hard delete; cover capture;
                 library_page app bar leading is now LibraryLogo→openDrawer
    vault/       persistent encrypted vault (+#28A change-pass, #34 biometric)
    lookup/      #29 scanner + #30 ISBN lookup (OL→GoogleBooks chained+cached)
    publish/     #32 Publish to GitHub Pages (device-flow + git data API)
    backup/      .pitabak writer (Room-format, bidirectional) + restore
    import_export/
      domain/pdf_column.dart        ← NEW: pure PdfColumn (14 cols, weights,
                                      wrapLines, mandatory Title, private cols),
                                      CSV (de)ser, resolvePrintColumns (Source
                                      merge), wrapCell. Faithful Kotlin port.
      infrastructure/
        pdf_library_renderer.dart   ← NEW: paginated A4 via `pdf` pkg; header
                                      logo+name, attribution footer+icon, serial
                                      gutter, weighted cols, portrait→landscape
                                      >6 cols. Y-axis flipped (ty(y)=pageH-y).
        pdf_text_rasterizer.dart    ← PRIMARY PDF TEXT PATH: UiPdfTextRasterizer
                                      shapes each run with Flutter's engine
                                      (HarfBuzz) via dart:ui ParagraphBuilder →
                                      Picture.toImage → PNG tile (supersampled 3×),
                                      embedded as an IMAGE in the PDF. This is how
                                      Devanagari conjuncts/half-letters/matra
                                      reordering render correctly (e.g. बच्चे).
                                      TRADEOFF (user-accepted): PDF text is RASTER,
                                      not selectable. Registers bundled Noto TTFs
                                      at runtime via FontLoader (fallback group).
        pdf_fonts.dart              ← FALLBACK ONLY: PdfFontResolver — per-string
                                      font selection by glyph coverage. Used by the
                                      renderer's drawString path when NO rasterizer
                                      is passed (Latin-only callers / pure tests).
                                      NOT used by the live export (it passes a
                                      rasterizer). drawString does NOT shape Indic.
        pitaka_json_exporter.dart, cover_paths.dart, ...
      application/export_library_use_case.dart  ExportFormat{json,csv,PDF};
                  ExportResult now carries Uint8List bytes+mimeType (was String);
                  defaultPdfLabels() + kPdfFooterAttribution. Filenames pitak-*.
      presentation/pages/export_page.dart  PDF segment + column picker; loads
                  footer icon; builds a UiPdfTextRasterizer (which owns the Noto
                  fonts). NB: live PDF export = shaped-IMAGE text, not vector text.
    wishlist/ settings/ (settings_page = 4 tabs; Appearance has the NEW logo
                 picker _LogoRow; Security has the NEW app-lock toggle)
  assets/
    publish/index.html  (bundled library viewer, #32)
    pdf/app_icon.png    (PDF footer icon)
    fonts/  10 Noto Sans Indic scripts × {Regular,Bold} = 20 TTFs + OFL.txt.
            PDF-only: loaded by the `pdf` pkg via rootBundle, NOT Flutter `fonts:`.
    branding/  app_icon.png + NotoSansBrahmi-Regular.ttf. Brahmi IS a Flutter
               `fonts:` family (rendered by the text engine on the splash).
```

---

## 4. Entry points / navigation

- **App launch**: `main.dart` → **AppGate**. Cold start shows the 2s **splash**
  (big logo, small Pitak icon, Brahmi text), then: if app-lock is ON → biometric
  prompt (fail-closed locked screen w/ Unlock retry); else → Library. Returning
  from background re-locks + re-prompts when app-lock is on.
- **Library home**: app-bar **leading is the library logo** (user's or default
  Pitak icon) → opens the drawer (replaced the hamburger). App bar also has
  scan-to-add + overflow (import/export/backup/restore). FAB = add book.
- **Drawer**: header shows the logo + "Pitak"; tiles Vault · Publish · Wishlist ·
  Settings.
- **Settings (4 tabs)**: Appearance (theme, names, **Library icon picker**,
  remote-cover toggle) · Data (import/export/backup/restore) · Security
  (**Require biometric to open Pitak** toggle + vault biometric + change-pass) ·
  Contribute (publish-contact fields — see §7 DEFERRED).
- **Export**: JSON / CSV / **PDF**. PDF shows a column picker (Title locked on;
  Location/Source default-off as private). PDF is always the library list.

---

## 5. Build / verify / on-device

```bash
cd ~/development/pitak_flutter
flutter analyze lib test            # No issues found!
dart format --set-exit-if-changed lib test
flutter test                        # 400 pass
( cd rust && cargo test --release ) # 22 pass
# After @riverpod/freezed/drift edits: dart run build_runner build --delete-conflicting-outputs
# After rust/src/api.rs edits: flutter_rust_bridge_codegen generate

# On-device (Pixel 8a, pkg dev.khoj.pitaka):
flutter build apk --release         # rebuild from CURRENT code (stale APK = known trap)
ADB=$HOME/Library/Android/sdk/platform-tools/adb   # adb not on PATH
# verify frb dispatcher survived R8 (expect 2 lines: _primary + _sync):
nm -D $(find build -path '*arm64*/libpitak_crypto.so'|head -1) | grep frb_pde_ffi_dispatcher
$ADB install -r build/app/outputs/flutter-apk/app-release.apk   # -r preserves vault data
$ADB shell monkey -p dev.khoj.pitaka -c android.intent.category.LAUNCHER 1
```

Release still **debug-signed**. Device also carries Kotlin
`dev.khoj.pitaka.fdroid*` variants — different apps, leave them.

---

## 6. On-device verification status (honesty)

- **VERIFIED earlier** (user-confirmed): native vault write path, #28A/#34/#29/
  #30, plus the older UX batch (drawer, scan-to-add, cover capture).
- **BUILT + INSTALLED this session, NOT yet user-confirmed** (the current APK on
  the Pixel 8a, splash = 2s):
  1. **Splash** — big Pitak/logo centred, small Pitak icon + Brahmi 𑀧𑀺𑀝𑀓 at
     bottom, ~2s, then Library.
  2. **PDF export** — Export→PDF→columns→save; OPEN the PDF and confirm Latin
     AND Indic (Hindi etc.) titles render correctly, incl. Devanagari conjuncts/
     half-letters (बच्चे), not boxes/full-letters+halant. NOTE: text is now
     embedded as SHAPED IMAGES (pdf_text_rasterizer.dart), so it will NOT be
     selectable/searchable in the viewer — that's the accepted tradeoff, not a
     bug. Confirm glyph correctness + acceptable print sharpness.
  3. **Library logo** — Settings→Appearance→Library icon→Choose (gallery); it
     should appear in splash centre, drawer header, and toolbar button; toolbar
     icon still opens the drawer.
  4. **App-lock biometric** — Settings→Security→toggle on; background+return
     should re-prompt; cancel should stay locked with Unlock button.
  5. **Rename** — launcher label reads **Pitak**.
- **Still MockClient-only**: #32 Publish (real GitHub OAuth + push never run live).

---

## 7. What's DONE vs NEXT

### DONE
Library (CRUD/search/sort/filter/soft+hard delete, cover capture), Wishlist,
Import/Export (JSON/CSV/**PDF**), Backup create+restore (bidirectional),
persistent encrypted vault (+#28A change-pass, #34 biometric), FLAG_SECURE,
#29 scanner, #30 ISBN lookup, #32 Publish to GitHub Pages, nav drawer + tabbed
settings. **NEW this session:** PDF export (Indic-capable), Pitaka→Pitak UI
rename, launch splash, opt-in app-lock biometric gate, user library-logo
feature (logo = drawer button).

### NEXT (pick by value/risk; network/platform items are §2a/§9 decisions)
- **Contribute tab (DEFERRED, user wants it "last")** — Kotlin's tab is TWO new
  subsystems that DON'T exist in Flutter: (a) app-wide LocalizedText i18n
  (long-press any string → suggest a translation via GitHub) and (b) crash
  capture/store/send (#35, opt-in, default-off, POSTs to GitHub). Each is a
  large feature + a privacy/§9 decision. Read Kotlin `ui/settings/SettingsScreen.kt
  ::ContributeTab`, `ui/contribute/**`, `data/crash/**`. When picked, scope it
  with the user first (full mirror vs crash-only vs static guide).
- **Cloudflare Pages publish** — deferred half of #32. Kotlin
  `ui/publish/CloudflareWizardScreen.kt` — READ before designing (new auth/upload).
- **#33 Merge** (cross-maintainer by book_uid/isbn) — mostly local logic;
  Kotlin `domain/usecase/MergeLibraryUseCase.kt`.
- **PDF header logo follow-up** — the renderer accepts a logo but the export
  page doesn't pass one yet (only the footer icon). Now that a library-logo pref
  EXISTS (`settings.libraryLogo`), wire it into the PDF header (resolve
  covers/<uuid>.jpg → bytes → render logoBytes). Small, additive.
- Bookmarks, #35 crash reporting (folds into Contribute), i18n (large).

### Release hardening (before any public ship)
- Real signing keystore (`android/app/build.gradle.kts` uses the debug key).
- `cargo clippy` never run (not installed; install is a §9 action).

---

## 8. Decisions already made (don't re-litigate — see PLAN.md "Result" entries)

- **PDF** (Kotlin parity): pure column/layout logic in `domain/pdf_column.dart`
  (unit-tested) + `pdf` pkg renderer with Y-axis flip. ExportResult is bytes.
  User chose broad Indic (Q-B) + Regular+Bold (Q-2A), bundled 10 Noto Sans
  scripts × {Regular,Bold} (assets/fonts/, SIL OFL, notofonts.github.io static
  hinted instances).
  **PDF TEXT IS RENDERED AS IMAGES (current, final approach).** The `pdf`
  package's `drawString` maps codepoints to glyphs 1:1 with NO complex-script
  shaping (Arabic only), so Indic conjuncts/half-letters/matra reordering broke
  (बच्चे came out as full letters + visible halant). Kotlin sidesteps this by
  drawing on an Android `Canvas` (OS HarfBuzz shapes). Our cross-platform fix
  (user = option A): let Flutter's engine (HarfBuzz) shape each run, capture it
  as a PNG tile (supersampled 3×, user = per-cell tiles), and embed the IMAGE in
  the PDF — `infrastructure/pdf_text_rasterizer.dart` (UiPdfTextRasterizer:
  FontLoader registers the Noto TTFs at runtime → `ui.ParagraphBuilder` →
  `Picture.toImage`). `PdfLibraryRenderer.render` takes an optional
  `textRasterizer`; when present it pre-rasterizes every run into a tile cache
  and `drawText` embeds the tile at baseline. TRADEOFF (accepted): PDF text is
  RASTER, not selectable. The old `PdfFontResolver`/`drawString` vector path
  SURVIVES only as the fallback when no rasterizer is passed (Latin-only callers
  / pure tests); the live export ALWAYS passes a rasterizer. Harmless dart_pdf
  "Helvetica has no Unicode support" log line still fires (boilerplate, even for
  all-Latin shaped renders).
- **Splash/gate/logo**: app-lock is OPT-IN, default OFF (Q1=A); re-locks on every
  background/resume (Q2=B); Brahmi-only text 𑀧𑀺𑀝𑀓 no Devanagari (Q3, glyph from
  Kotlin WelcomeScreen, NotoSansBrahmi font); logo = GALLERY pick only (Q4=A),
  downscaled + stored as covers/<uuid>.jpg via CoverStore; device PIN/pattern
  fallback allowed (Q5=A, biometricOnly:false). Splash hold = **2s** (user set).
  App-lock is a UI GATE ONLY — copy says so; does NOT encrypt at rest.
- **Rename**: only USER-VISIBLE "Pitaka"→"Pitak" (drawer, title, import labels,
  publish copy, Android label, iOS CFBundleDisplayName). LEFT as-is: Dart package
  `pitaka`, class names (PitakaExport/PitakaJsonExporter), dartdoc, schema const,
  and the publish git commit message "Pitaka publish $now" (Kotlin repo contract).
- Earlier: vault at-rest = borrowers.db + blob in app docs; session passphrase
  wiped on exit. #34 = second-blob, passphrase never stored, NON-auth-bound key
  + software gate. #32 = one atomic git-data commit, PII redaction, https cover
  allow-list mirrors viewer CSP, token in secure storage.

---

## 9. Source-of-truth (Kotlin app, for verifying contracts)

- PDF (already ported): `data/export/{PdfLibraryRenderer,PdfColumn,Exporters,
  PdfExportAssets}.kt`, `domain/usecase/ExportUseCase.kt`.
- Splash/logo (already ported): `ui/welcome/WelcomeScreen.kt` (Brahmi glyph +
  font noto_sans_brahmi.ttf), `data/prefs/AppPreferences.kt` (libraryLogoUri),
  `ui/settings/SettingsScreen.kt::LibraryLogoRow`.
- App-lock (Kotlin has a richer PIN+lockout subsystem we did NOT fully port —
  user asked for biometric only): `data/security/AppLock*.kt`, `ui/applock/**`.
- Contribute (NEXT): `ui/settings/SettingsScreen.kt::ContributeTab`,
  `ui/contribute/**`, `data/crash/**`.
- Cloudflare (NEXT): `ui/publish/CloudflareWizardScreen.kt`, `data/publish/**`.
- Merge (NEXT): `domain/usecase/MergeLibraryUseCase.kt`, `ui/merge/`.

---

## 10. Test fixtures + gotchas

- `test/fixtures/vault/` — committed SYNTHETIC vault, passphrase
  `test-pass-not-secret`. Regenerate:
  `cd rust && cargo run --release --example gen_test_vault -- ../test/fixtures/vault`.
- Real archive (untracked, repo root): `Pitak-backup-20260625-150727.pitabak`
  (HAS vault; pass `khoj@pitak`).
- **Splash timing in widget tests**: AppGate opens on a 2s SplashScreen. Tests
  that boot the app must `await tester.pump(const Duration(seconds: 2))` to fire
  the splash timer before the Library/gate appears (`pumpAndSettle` alone won't
  advance the Timer). See `test/widget_test.dart` + `test/core/widgets/app_gate_test.dart`.
- **PDF text = shaped images (current path).** Live export passes a
  `UiPdfTextRasterizer`; every text run is shaped by Flutter's engine and
  embedded as a PNG tile (NOT selectable text — accepted tradeoff, see §8). The
  rasterizer needs a live engine, so renderer/use-case tests exercising it are
  WIDGET tests (`TestWidgetsFlutterBinding.ensureInitialized()`), not pure tests.
- **PDF fonts (drawString FALLBACK path only)**: `pdf` Helvetica is Latin-1 only
  → if you call the renderer WITHOUT a rasterizer and pass non-Latin text it
  throws "Cannot decode the string to Latin1". The fallback expects the font
  byte bundles; the live PDF path no longer uses them (the rasterizer owns the
  Noto fonts via FontLoader). A harmless dart_pdf "Helvetica has no Unicode
  support" log line fires regardless (boilerplate, even for all-Latin renders).
- `ImageDownscaler` catches `on Object` (the `image` pkg THROWS on garbage bytes).
- APK is 101.6MB now (bundled fonts) — expected, not a regression.
- frb codegen runs from a runtime pin (2.12.0); regenerate after any api.rs change
  and re-check the `nm -D` symbols.

---

## 11. Suggested first moves for the next session

1. Re-verify green (§5) — confirms a clean inherited tree (400 Dart / 22 Rust).
2. **If the user reports an on-device issue with this session's batch (§6)**,
   start there. PDF Indic shaping is now SOLVED via shaped-image embedding
   (§8) — on-device, verify glyph correctness + print sharpness, and that the
   accepted non-selectable-text tradeoff is fine. Other first-failure points:
   gallery logo pick (image_picker); biometric resume re-lock; Android export/
   share save path (share_plus, see PLAN bugfix).
3. Otherwise pick a NEXT item (§7). The user explicitly wants the **Contribute
   tab "last"** — if other NEXT work is done, that's the cue. Scope it with the
   user before building (it's two large new subsystems).
4. Before any public ship: real signing keystore (§7 hardening).
