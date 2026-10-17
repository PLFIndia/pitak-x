# libNetwork implementation — handoff (S1–S6 + docs DONE; merge prep remains)

> **For the next session's agent.** All six slices of `libNetwork.md` are
> implemented, gated and committed on branch `libNetwork`, and the §9 docs
> sweep (owed since S2) landed with them. This file now records only what a
> merge/release session still needs. `AGENTS.md` still wins over everything.
>
> Rewritten 2026-10-17 after the docs commit (supersedes the S4 handoff,
> which supersedes the S1–S3 one).

---

## 1. Branch state

Branch `libNetwork` (from `main` @ 80b8e89). Commits, oldest first:

| Commit | Content |
|--------|---------|
| 88796f5 | the spec (`libNetwork.md`) |
| 70e5382…ce786b3 (6) | **S1** foundation (VOs, BoundedHttpFetcher, AppUserAgent, QrScanPage, ADR 0012) |
| 968344e | **S2** publish side (LocationSharing, descriptor codec, library.json) |
| e447f49 | **S3** network table (schema v3), card QR, add-member, NetworkPage |
| 46845bc | **S4** refresh/discovery/membership, bookmarks migrated + deleted |
| 55ec411, f4888e4 | earlier handoffs |
| 72bba91 | **S5** map tab (flutter_map + OSM, consent-gated) |
| a68735f | **S6** identity.json + network.json in .pitabak |
| (docs) | §9 sweep: PRIVACY.md, README.md, appDetails.md, CHANGELOG.md |

**Gate status (docs commit):** analyze 0 issues · format clean ·
build_runner no diff · `fvm flutter test --exclude-tags golden` →
**2233 tests, all green**.

## 2. Open items for the merge/release session (NOT code)

1. **Golden PNG for `network_library_tiles`** (test/golden/key_screens_test.dart,
   tag `golden`): cannot be generated on macOS — run the `update-goldens`
   workflow_dispatch job on Linux and commit the uploaded PNG
   (dart_test.yaml + architecture.md B2). Until then the golden job is red
   by design; everything else is green.
2. **fastlane changelog** (`fastlane/metadata/android/en-US/changelogs/<code>.txt`)
   — written at release time (spec §9), user-facing ≤ 500 chars.
3. **Release sentinel** for the next version: `LibraryFingerprint` (recorded
   in appDetails.md §9's network entry; ASCII-only class name, survives in
   libapp.so — see appDetails.md §5 step 3 for the check).
4. Merge mechanics: `main` may have moved since 80b8e89; the branch touches
   `pubspec.*`, settings, backup and network — re-run all gates after
   rebase/merge.

## 3. Gotchas that cost time in S5/S6 (don't rediscover)

- **flutter_map 8.3.2 verified API:** `TileLayer(urlTemplate, tileProvider:
  NetworkTileProvider(headers:))`; `headers` must be a MUTABLE map (TileLayer
  does `headers.putIfAbsent` for a fallback UA — a const map throws). The
  built-in tile cache is the default when `cachingProvider` is null and
  honours server freshness headers with a 7-day fallback (exactly §5.9 — no
  override needed). `SimpleAttributionWidget` overflows narrow screens with
  its fixed "flutter_map | © " prefix — use `RichAttributionWidget`
  (permanent bottom-right toggle + popup); its credit text renders as
  `'© ' + source`. `latlong2` is NOT re-exported — import it directly.
- **TileLayer's UA assert:** `TileLayer` injects `'flutter_map
  (userAgentPackageName)'` when headers lack a UA — always pass ours.
- **A11y on map pins:** markers need 48×48 (icon 40 inside) + a Semantics
  label; the bare Icon fails both tap-target and labelled-target guidelines.
- **riverpod `_debugAssertCanDependOn` BUILDS the target of a
  `ref.invalidate` in debug/test runs** (element.dart:287 →
  readProviderElement). Invalidating a provider nobody watches is a no-op in
  production but constructs the whole chain in tests — the S6 restore tests
  pin the chain with `container.listen(...)` (see
  restore_controller_test.dart's `pinRestoreController`) or teardown
  double-completes a provider's future ("Future already completed",
  flaky-looking but deterministic per wiring).
- **Restore page taps:** the warning copy grew; tests must
  `ensureVisible` + `pumpAndSettle` before tapping 'Restore' or the hit test
  misses silently (the M03/N11 page tests show the pattern).
- **`restore_backup.dart` ratchet:** still recorded at 553 lines — the §3.4
  readers and the covers builder were extracted to
  `backup_extras_reader.dart` / `restore_covers_builder.dart` to stay there.
- **Settings fakes:** `networkMapTilesConsent` broke the same 6 explicit
  `SettingsRepository` fakes as S2 (all fixed); every other fake has
  `noSuchMethod` and needs nothing.

## 4. Quick pointers into the S5/S6 additions

| What | Where |
|------|-------|
| Tile config (one const + UA + cache) | `lib/features/network/infrastructure/osm_tile_provider.dart` (`OsmTiles.urlTemplate`, `buildOsmTileLayer`) |
| DI hand-out (presentation never imports infrastructure) | `osmTileLayerProvider` in `lib/core/di/src/network_providers.dart` |
| Map tab | `…/presentation/pages/network_map_page.dart` (`NetworkMapGate` = consent gate, `NetworkMapPage`, `initialOptions` viewport math, pin sheet) |
| Consent dialog / attribution | `…/widgets/tiles_consent_dialog.dart`, `…/widgets/osm_attribution.dart` |
| Consent setting | `AppSettings.networkMapTilesConsent` (key `network_map_tiles_consent`) + Settings › Appearance switch |
| identity.json codec | `lib/features/backup/domain/backup_identity.dart` (`BackupIdentity`, LibraryId-validated) |
| network.json envelope | `lib/features/network/domain/network_archive_codec.dart` (schemaVersion 1; rows re-validated, bad rows dropped) |
| §3.4 restore readers | `lib/features/backup/infrastructure/backup_extras_reader.dart` |
| Manifest flags | `hasIdentity` / `hasNetwork` on `BackupManifest` (default false) |
| Post-switch adoption | `RestoreController._applyIdentityAndNetwork` (adopt via namespace port, then replaceAll; Lefts fold into the summary) |
| Inspection for page copy | `ArchiveInspection` (manifest + parsed identity) |
| Backup tests | `test/features/backup/{backup_identity,create_backup_use_case}_test.dart` + groups in `restore_backup_test.dart` / `restore_controller_test.dart` / `restore_page_test.dart` |
| Map tests | `test/features/network/presentation/network_map_page_test.dart` (blank in-memory tile provider — no HTTP) |
