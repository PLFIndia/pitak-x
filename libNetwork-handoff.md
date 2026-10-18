# libNetwork implementation — handoff (review fixes COMPLETE)

> **For the next session's agent.** All six slices of `libNetwork.md` are
> implemented on branch `libNetwork`, and EVERY finding from the full code
> review (2026-10-17/18) is now fixed and committed — H1–H5, M1–M14, and the
> Lows batch. What remains is merge/release work, not code (§2). `AGENTS.md`
> still wins over everything.
>
> Rewritten 2026-10-18 after the second review-fix session (supersedes the
> review-in-progress handoff).

---

## 1. Branch state

Branch `libNetwork` (from `main` @ 80b8e89). Feature commits
(88796f5 … eb75215), then the first review-fix batch (5a3f738 … b47df82,
documented in `git show ea28599:libNetwork-handoff.md`), then the docs
commit ea28599, then THIS session, oldest first:

| Commit | Review item | Content |
|--------|-------------|---------|
| 77281c7 | **M8** | `GeoUri` (network domain, pure) builds the Directions `geo:` URI: fixed six decimals (no `1e-7` exponent form) and percent-encoded parentheses (`Uri.encodeComponent` leaves `()` alone, which breaks `q=lat,lng(label)`). |
| 90a6641 | **M7** | `PublishContactLinks.gpsItem` drops non-coordinate GPS text under `approximate` (D7: free text cannot be rounded to ~1 km); the search-link fallback survives only under `exact`. Matches what the descriptor builder already did. |
| 165d11e | **M10, M12 p1** | `AddMemberController` (@riverpod AsyncNotifier) owns the add-member flow's one `AsyncValue`, serialises adds, guards dispose-mid-await (`_disposed` pattern), and invalidates `networkControllerProvider` the moment a save lands — system back can no longer leave the list stale. The page is render-only. |
| c4e7977 | **M13** | PRIVACY.md §4: Refresh also fetches descriptors of libraries discovered via hubs/members (≤2 hops, ≤500/run, same allow-list); each contacted host sees the device IP once. |
| 681acf2 | **M14** | Migration failure is logged (failure TYPE only, never the message — it can quote SQLite text with URLs), throws `LegacyBookmarksMigrationException` (an **Exception**, so downstream `on Exception` handlers work — `StateError` skipped them all), and PublishController refuses in words instead of publishing an empty member list. |
| 901d805 | **M9** | `NetworkArchiveCodec.decode` returns `(rows, dropped)`: first-wins dedupe on siteUrl/fingerprint/id (duplicates used to fail the whole `replaceAll` on UNIQUE), 5000-row cap, 4 MiB entry cap in the reader before UTF-8 decode. Summary gains `networkRowsDropped` + `networkApplied`; the restore page names skipped rows. |
| 9ba0a34 | **M4** | DI hands the map an OWNED `http.Client` (`osmTileHttpClient`, RetryClient, `ref.onDispose(close)`); the page builds a fresh `TileLayer` per mount around it (a layer dispose never closes the shared client — flutter_map only closes clients it created). `OsmTiles` config moved to `core/network/` so presentation can read it without importing infrastructure. Boundary test now forbids `flutter_map` under `core/di` + `/application/`. |
| cfc7798 | **M3** | `OsmAttribution` is our own always-visible chip ("© OpenStreetMap contributors" from the first frame — the policy forbids hiding it behind toggles), opaque background, one ≥48 dp tap target, wraps on narrow screens. Also fixed two latent issues this surfaced: the map carries a `Semantics(label: 'Map of saved libraries')` so flutter_map's gesture/focus actions merge into a LABELLED node (the unlabelled tab-panel node made the a11y gate pass only in full-file test ordering), and tests disable the tile disk cache via `osmTileDiskCacheProvider` (the built-in cache needs path_provider + spawns a worker isolate). |
| 8f25cc0 | **M12 p2** | `NetworkLibrarySort.byDistanceThenName` (domain, pure) owns the ordering; `networkListViewProvider` derives sorted rows + window as ONE snapshot (no per-build sort, no unsorted flash; settings awaited, failure ⇒ name order); `MapViewport.forPoints` (presentation, pure) owns the camera bounds. |
| 998146a | **Lows p1** | Drift network repo: `StorageFailure` no longer interpolates exception text (bound params = URLs); `count()` is a real `COUNT(*)`; `BackupIdentity` names pass the §6 control/bidi rules via `NetworkName`; descriptor-codec depth guard is string-aware; haversine clamps `h` before `asin` (antipodes NaN). |
| 6942fbc | **Lows p2** | "Not now" renamed to "No" (it declined PERMANENTLY while sounding like a snooze; not answering is the snooze). `ConfirmMembershipUseCase` guards transitions: pending→confirmed/declined, declined→pending (Reconsider), same-state no-op; everything else refused. |
| fb83398 | **Lows p3** | `library.json` reuses the live file's `updatedAt` when `samePublishedContentAs` says nothing changed — the sha-skip actually skips now. Stale/absent live copy ⇒ upload anyway (safe direction; manifest shas come from GitHub's tree). |
| 7059d66 | **Lows p4** | `NetworkController.build` registers its refresh-settle listener BEFORE the first await (a settle inside the gap used to be missed). `NetworkWindow` stays hand-written (no freezed anywhere in `lib/features`; one-blessed-way; rationale on the class). Stale doc headers refreshed (`app_database.dart`, `network_providers.dart`). |

**Gate status at 7059d66:** `flutter analyze lib test integration_test` 0
issues · `dart format` clean · build_runner no diff ·
`fvm flutter test --exclude-tags golden` all green (§5).

**Working tree:** clean.

## 2. What remains (merge/release items, NOT code)

- Golden PNG for `network_library_tiles` (Linux `update-goldens` job).
- Fastlane changelog + release sentinel.
- Rebase onto current `main` and re-run all gates.
- The ratchet comment "690 → 631" for `settings_page.dart` was flagged stale
  in the review; verified consistent NOW (file = recorded = 631) — no change
  needed.

## 3. Gotchas from the fix sessions (don't rediscover)

- **flutter_map + tests**: the map tests override `osmTileHttpClientProvider`
  (MockClient serving a 1×1 PNG) AND `osmTileDiskCacheProvider` → false. The
  built-in tile cache resolves `getApplicationCacheDirectory()` and spawns a
  worker isolate — without the override you get MissingPluginException or a
  dangling isolate, and the failure SURFACES ONLY in some test orderings.
- **flutter_map semantics**: `MapInteractiveViewer` unconditionally registers
  tap/longPress recognizers + an autofocus Focus; their actions merge into
  the nearest ancestor semantics node. Without the map's explicit
  `Semantics(label:)` that node is the unlabelled TabBarView panel and the
  a11y "tappable needs a label" check fails — but only when the map test
  runs alone (the full-file run masked it). Always run a11y tests standalone
  AND in-file before trusting them.
- **Container + `alignment:` + loose constraints expands to fill** (the map)
  and eats every tap — the M3 chip uses symmetric padding to reach 48 dp
  instead. **InkWell inside the map** adds a focusable gesture subtree that
  merged confusingly into the map's semantics; the proven pattern here is
  `Semantics(button: true, label: …)` + `GestureDetector` (same as the pins).
- **Pre-commit hook regenerates `.g.dart`:** a change to any `@riverpod`
  file body changes its hash; the hook refuses the commit and leaves the
  regenerated file in the tree — `git add` it and commit again.
- **Backticks in commit messages**: `git commit -m "…\`none\`…"` runs shell
  command substitution. Use `git commit -F -` with a heredoc.
- **Fake repos must enforce UNIQUE:** the refresh use-case `_FakeRepo`
  rejects duplicate fingerprints and skips duplicate siteUrls like Drift;
  keep that when adding tests, or H1-class bugs become invisible again.
- **`BookmarkUrl` has two methods:** `sanitize` (allow-list, verbatim —
  fetcher, redirect hops) vs `normalize` (canonical site root — everything
  stored/compared). Do not pass `normalize` to a fetcher.
- **Testing abort passthrough:** a `MockClient` that "never answers" must
  honour `Abortable` (complete with `RequestAbortedException` when the
  trigger fires) or the test hangs for 30 s — see the COMPOSITION group in
  `test/core/network/bounded_http_fetcher_test.dart`.
- **Dart's `double.toString()`** only switches to exponent form below 1e-6
  (`0.00001.toString()` is `'0.00001'`, not `1e-5`) — pick test values
  accordingly.
- **`final` + try/catch**: a final local can't be assigned in both try and
  catch (definite-assignment analysis) — use a non-final.
- **Literal control characters are invalid JSON**: to test a hostile `\t` in
  a JSON string, the source must carry the ESCAPE sequence (`\\t`), not a
  literal tab — otherwise jsonDecode refuses before your validation runs.
- All earlier gotchas (riverpod `_debugAssertCanDependOn`, restore-page
  `ensureVisible`, ratchet) still apply — see
  `git show f4888e4:libNetwork-handoff.md` §3.

## 4. Quick pointers

| What | Where |
|------|-------|
| URL allow-list + canonical form | `lib/features/network/domain/value_objects/bookmark_url.dart` (`sanitize`, `normalize`) |
| Refresh algorithm + conflict rules | `lib/features/network/domain/usecases/refresh_network_use_case.dart` |
| Refresh report | `lib/features/network/domain/refresh_report.dart` |
| Discovery plan (role merge) | `lib/features/network/domain/network_discovery_plan.dart` |
| Abort passthrough | `lib/core/network/timeout_http_client.dart` (`send`, first lines) |
| Fetch headers / UA | `lib/core/network/bounded_http_fetcher.dart` (`headers`, `defaultHeaders`) |
| Tile endpoint + UA config | `lib/core/network/osm_tiles.dart` (`OsmTiles`) |
| Tile client lifecycle | `lib/core/di/src/network_providers.dart` (`osmTileHttpClient`, `osmTileDiskCache`) |
| Card byte cap | `lib/features/network/domain/value_objects/library_card_payload.dart` (`_fitName`) |
| Publish refusal on descriptor Left | `lib/features/publish/application/publish_controller.dart` (after `BuildOwnDescriptor.build`) |
| updatedAt reuse (sha skip) | `publish_controller.dart` + `LibraryDescriptor.samePublishedContentAs` |
| geo: URI builder | `lib/features/network/domain/geo_uri.dart` |
| Display sort | `lib/features/network/domain/network_library_sort.dart` + `networkListViewProvider` |
| Initial map viewport | `lib/features/network/presentation/widgets/map_viewport.dart` |
| Add-member flow | `lib/features/network/application/add_member_controller.dart` |
| Archive caps/dedupe | `lib/features/network/domain/network_archive_codec.dart` (`maxRows`, `maxBytes`, `(rows, dropped)`) |
| Migration failure type | `lib/core/di/src/network_providers.dart` (`LegacyBookmarksMigrationException`) |

## 5. Final gate run of this session

At 7059d66, working tree clean (2026-10-18):

- `dart run build_runner build --delete-conflicting-outputs` → no diff
- `flutter analyze lib test integration_test` → No issues found
- `dart format --set-exit-if-changed lib test integration_test` → 0 changed
- `fvm flutter test --exclude-tags golden` → **2319 tests, all passed**
  (2269 at the previous handoff + 50 added by this session's fixes)
