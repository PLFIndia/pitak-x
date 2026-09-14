# PLAN.md — Session 32 — Library share card (visiting-card PNG, 4 styles)

User request: "Share library link" today shares only a text URL. Add a
visiting-card style IMAGE share: library logo top-left, library name beside
it (same height), address below, QR of the library link on the right, link
text under the address, and a smaller "Made with · [Pitak icon] Pitak / A
community library app" footer. Four styles (Classic / Dark / Gradient /
Framed — HTML mockups approved rev 2) and the user picks one before sharing.

## Understanding (verified from source this session)

- Share entry points: `lib/features/publish/presentation/pages/publish_page.dart:502`
  (`_sharePublishedUrl` → `fileShareServiceProvider.shareText(url)`) and
  `lib/core/widgets/app_drawer.dart:93-105` ("Share Library Website" tile,
  same `shareText`). Both are gated on a published URL.
- `FileShareService` (`lib/core/platform/file_share.dart:37`) already has
  `shareBytes({bytes, fileName, mimeType})` — used by PDF/backup export. No
  new platform surface needed.
- `QrView` (`lib/core/widgets/qr_view.dart`) paints a QR from the `qr`
  package (EC level M) — reusable as-is.
- `LibraryLogo` (`lib/core/widgets/library_logo.dart`) resolves the user's
  logo via `CoverPaths.leafOf` + `coversDirProvider`, falling back to the
  Pitak icon. The card needs a MONOGRAM fallback instead (the footer already
  shows Pitak) → add an optional `fallback` widget param (additive).
- Data: `AppSettings.libraryName` / `.publishContactAddress` / `.libraryLogo`
  (`lib/features/settings/domain/app_settings.dart`), read through
  `settingsControllerProvider`. Published URL: `publishedSiteUrlProvider`
  (`providers.dart:548`) for the drawer; `_publishedUrl` state on the page.
- `SettingsRepository` has 17 fake impls under `test/`; adding a field means
  touching all of them. `PrefsBookmarksRepository` is the precedent for a
  small separate prefs store → follow it for the remembered card style.
- Domain purity test (`test/architecture/domain_purity_test.dart`) forbids
  `dart:ui`/Flutter in `domain/` → colours live in presentation; domain holds
  the enum + pure text helpers only.
- Pinned SDK: `/Users/genescan/fvm/versions/3.44.2/bin/flutter` (shell
  `flutter` is 3.41.1 — do not use). Full suite must run detached.

## Privacy & threat notes

- Card content = library name, public address, public URL: all data the user
  DELIBERATELY published already (#32). Nothing new is collected.
- PNG produced by Flutter's `Image.toByteData(png)` carries no EXIF/GPS.
- Nothing leaves the device except via the OS share sheet the user invokes.
- Card style preference is non-secret → `shared_preferences` is appropriate.
- Logo file path resolution reuses `CoverPaths.leafOf` (traversal-safe).
- Text is rendered, never interpreted; URL is encoded into the QR verbatim
  (it is our own GitHub Pages URL from the manifest).

## Proposed approach (OSS reference)

Capture = `RenderRepaintBoundary.toImage(pixelRatio)` → PNG. This is exactly
what the `screenshot` package (github.com/SachinGanesh/screenshot, MIT) does
under the hood; adapted inline (≈20 lines) rather than adding a dependency
(§9: do not add a package for a solved problem). `OffsetLayer.toImage`
renders the boundary's own subtree at its own layout size, so a scaled-down
live preview inside a `FittedBox` still captures the full 1050×600 card at
2× (2100×1200 px).

Layers (§3):
- **domain** `publish/domain/share_card_style.dart` — `ShareCardStyle` enum
  (+ `token`/`fromToken` like `AppThemeMode`), `ShareCardStyleStore`
  interface, and pure helpers `ShareCardText.displayName / monogram /
  displayUrl / fileName`.
- **infrastructure** `publish/infrastructure/prefs_share_card_style_store.dart`
  — prefs-backed store, `Either<Failure, Unit>` writes (M17 pattern).
- **application** `publish/application/share_card_style_controller.dart` —
  `@riverpod` AsyncNotifier: `build()` loads the stored style; `select()`
  updates state optimistically and persists, returning `Either` so the UI
  can say "couldn't remember your choice" without blocking the share.
- **presentation** `publish/presentation/widgets/library_share_card.dart`
  (fixed 1050×600 card, explicit palette per style, `MediaQuery.
  withNoTextScaling` for deterministic output), `share_card_capture.dart`
  (boundary → PNG bytes), `share_library_sheet.dart` (bottom sheet: live
  preview, 4 style swatches, "Share card", "Share link only").
- **DI** `core/di/providers.dart` — `shareCardStyleStoreProvider`.
- **wiring** publish page + drawer open the sheet instead of `shareText`.

## Decision points (assumptions taken — user gave end-to-end go-ahead)

1. Entry points: BOTH the publish page "Share" button and the drawer tile
   open the same sheet (one blessed way). The sheet keeps "Share link only".
2. No logo set → monogram tile (first letters of up to two words). No
   address → the line is omitted. Blank name → "My Library" (same fallback
   as `ViewerHtmlBuilder._nonBlank`).
3. Card style persisted in its own small prefs store (bookmarks precedent),
   not `AppSettings` (17 fakes would need edits — out of proportion).
4. Style picker = live preview + 4 colour swatches (not 4 mini cards) —
   same information, far less code, and the preview IS the result.
5. Display URL strips `https://` (as in the mockups); the QR encodes the
   full URL.

## Steps

- [x] 1. Domain: `ShareCardStyle`, `ShareCardStyleStore`, `ShareCardText` + tests (18)
- [x] 2. Infra: `PrefsShareCardStyleStore` + tests (default, round-trip, corrupt token, false-write) (4)
- [x] 3. DI provider + application `ShareCardStyleController` + tests (4)
- [x] 4. `LibraryLogo.fallback` (additive)
- [x] 5. `LibraryShareCard` widget + `captureBoundaryPng` + tests (content, fallbacks, 4-style no-overflow, text-scale pinned, PNG 2100×1200, unmounted key) (7)
- [x] 6. `ShareLibrarySheet` + tests (preview + swatches, restyle + persist, reopen remembered, failed save reported, share card → shareBytes png, share link → shareText) (6)
- [x] 7. Wire publish page + drawer; drawer test updated (opens sheet, link path still shares URL)
- [x] 8. build_runner ✓ · `dart analyze` 0 issues in lib/test (47 pre-existing infos are all `rust_builder/cargokit` + pubspec sort, untouched) · `dart format` 0 changed · full suite **1690 passed, 0 failed** (baseline 1651 + 39 new)
- [x] 9. Result section

## Out-of-scope observations

- `RenderObject.debugNeedsPaint` (Flutter 3.44.2 `object.dart:3276`) reads a
  `late` local that is only assigned inside an `assert` — calling it in a
  release build throws. Guarded with `kDebugMode` in
  `share_card_capture.dart`; worth remembering for any future capture code.
- `flutter_test` renders text with the Ahem block font, so a PNG produced
  under test is layout-faithful but not glyph-faithful. A golden test of the
  card would need a real font loaded via `FontLoader`; not added (golden
  infra does not exist in this repo yet).
- Drawer share now needs the *Scaffold's* navigator context (drawer context
  dies on pop). Pattern noted in `app_drawer.dart`; the other `_go` tiles
  push routes before the pop resolves so they were never affected.

## Result

**Implemented; not committed (§6 — awaiting your go-ahead).**

Plain English: tapping **Share** on the publish page or **Share Library
Website** in the drawer now opens a bottom sheet with a live preview of a
visiting-card image (logo/monogram, name, address, QR, link, small "Made
with Pitak" footer), four colour swatches (Classic / Dark / Gradient /
Framed) that restyle the preview and are remembered for next time, a
**Share card** button that hands a 2100×1200 PNG to the OS share sheet, and
a **Share link only** button that does what the old button did.

Files:
- `lib/features/publish/domain/share_card_style.dart` (new)
- `lib/features/publish/infrastructure/prefs_share_card_style_store.dart` (new)
- `lib/features/publish/application/share_card_style_controller.dart` (+ `.g.dart`, new)
- `lib/features/publish/presentation/widgets/library_share_card.dart` (new)
- `lib/features/publish/presentation/widgets/share_card_capture.dart` (new)
- `lib/features/publish/presentation/widgets/share_library_sheet.dart` (new)
- `lib/core/di/providers.dart` (+ `.g.dart`) — `shareCardStyleStoreProvider`
- `lib/core/widgets/library_logo.dart` — optional `fallback` param
- `lib/core/widgets/app_drawer.dart`, `lib/features/publish/presentation/pages/publish_page.dart` — open the sheet
- tests: 5 new files under `test/features/publish/`, `test/core/widgets/app_drawer_test.dart` updated

OSS credit: capture approach adapted from `screenshot` (SachinGanesh, MIT) —
`RenderRepaintBoundary.toImage` → PNG; inlined, no new dependency. No
`pubspec.yaml` change.

Manual verification still recommended on device: font rendering of the card
(tests use the Ahem block font), Indic library names in the monogram tile,
and the WhatsApp/Drive share targets receiving `*-card.png`.
