# libNetwork implementation — handoff (review fixes in progress)

> **For the next session's agent.** All six slices of `libNetwork.md` are
> implemented and committed on branch `libNetwork`. A full code review
> (2026-10-17/18) found a set of composition bugs the unit tests could not
> see; the first batch is FIXED and committed (below). This file records
> exactly where that stopped and what remains. `AGENTS.md` still wins over
> everything.
>
> Rewritten 2026-10-18 after the review-fix session (supersedes the
> post-docs handoff).

---

## 1. Branch state

Branch `libNetwork` (from `main` @ 80b8e89). The feature commits
(88796f5 … eb75215) are unchanged; on top of them, oldest first:

| Commit | Review item | Content |
|--------|-------------|---------|
| 5a3f738 | **H3** | `BookmarkUrl.normalize` returns a canonical SITE ROOT (lower-case host, no query/fragment, trailing `index.html` dropped, trailing `/` guaranteed). Allow-list-only role split out as `BookmarkUrl.sanitize` (used by the fetcher for initial URL + redirect hops — never rewrites). |
| 23b6cf0 | **H1, M6, M11** | Discovered rows start with `fingerprint: null`; a hub's `members` hint is only COMPARED against the member's own fetch. Deterministic conflicts (two no-stored-fp rows publishing one fp ⇒ both flagged). Final uniqueness pass before `applyRefresh`; `applyRefresh` skips a discovered row whose siteUrl the user saved mid-run. Conflict badge clears `memberVerified`. Plan merges leaf/hub facts per URL. `RefreshReport` moved to `domain/refresh_report.dart` (ratchet), re-exported. |
| 07f27b6 | **M5** | `AddMemberUseCase` refuses a card whose fingerprint is saved under another address with a plain `ValidationFailure` (`identityAlreadySavedMessage`) before any write/fetch. |
| eff56da | **H2, M2** | `TimeoutHttpClient.send` chains a caller's `abortTrigger` into its own deadline (the fetcher's 15 s now really aborts under the 60 s decorator). `BoundedHttpFetcher` takes `headers` (default `{'User-Agent': AppUserAgent.value}`), applied on every hop. |
| f599864 | **H4** | `integration_test/vault_smoke_test.dart` compiles again (`CreateBackupResult.bytes`); CI analyze/format now include `integration_test`. |
| de5b86b | **H5** | `LibraryCard.tryCreate` shortens the NAME by whole characters so `encode()` always fits 512 bytes (long Kannada names used to produce cards other phones refused). |
| b47df82 | **M1** | `PublishController` REFUSES the publish (`'Library identity unavailable'`) when `BuildOwnDescriptor.build` is Left, instead of folding to null — which deleted the live `library.json` behind "Published!". |

**Gate status at b47df82:** `flutter analyze lib test integration_test` 0
issues · `dart format` clean · build_runner no diff ·
`fvm flutter test --exclude-tags golden` all green (see §5 for the number
the final run printed).

**Working tree:** clean. An attempt at **M3** (attribution visible on
first frame) was started and DISCARDED — see §3 for what was learned.

## 2. Remaining review items (NOT yet fixed), in suggested order

Full findings with line numbers are in the review message of the
2026-10-17 session; the short list:

| # | Sev | Where | What to do |
|---|-----|-------|------------|
| M3 | Medium | `lib/features/network/presentation/widgets/osm_attribution.dart` | `RichAttributionWidget` default `popupInitialDisplayDuration: Duration.zero` ⇒ only the "i" icon shows until tapped. OSM policy: "do not hide attribution … behind toggles". Make the credit visible on first frame. **Read §3 first.** |
| M4 | Medium | `lib/core/di/src/network_providers.dart:116-121`, `osm_tile_provider.dart` | `osmTileLayerProvider` hands out a `TileLayer` whose State `dispose()` closes the provider's internally-created `RetryClient`; a re-mount after autoDispose timing can hit "Client is already closed". Hand out config (template + headers) or an externally owned `http.Client` (`NetworkTileProvider(httpClient:)` is NOT closed by dispose) + `ref.onDispose(close)`; build `TileLayer` per mount in presentation. Extend `layer_boundaries_test.dart:79-101` regex to forbid `flutter_map` under `core/di` and `/application/`. |
| M7 | Medium | `lib/features/publish/domain/publish_contact_links.dart:84-99` | Under `approximate`, non-coordinate GPS text is published verbatim as a search link (D7 says one switch, one meaning). Return null for unparseable text when `approximate`; keep fallback only for `exact`. Test at `publish_contact_links_test.dart:129-137` currently blesses the old behaviour. |
| M8 | Medium | `lib/features/network/presentation/pages/network_map_page.dart:157-174` | `geo:` URI: `Uri.encodeComponent` keeps `()` (breaks `q=lat,lng(label)`), `double.toString()` may emit `1e-5`. Extract a pure `GeoUri` helper (`toStringAsFixed(6)`, encode `(`/`)`), unit-test it. |
| M9 | Medium | `lib/features/network/domain/network_archive_codec.dart:34-50`, `restore_summary.dart`, `restore_page.dart:389-390` | No byte/row cap, no dedupe (duplicates make `replaceAll` fail wholesale), dropped rows not counted (§6 says "dropped and counted"; `restore_backup_test.dart:680` "count reported" asserts no count). Return `(rows, dropped)`, dedupe first-wins by siteUrl/fingerprint/id, add `networkRowsDropped` + an `applied` flag to the summary and one sentence on the page. |
| M10 | Medium | `add_member_page.dart:96`, `network_page.dart:135` | Only "Done" pops `true`; system back leaves `NetworkController` stale after a successful add. Invalidate in the success branch (or `PopScope`). |
| M12 | Medium | `network_page.dart:101-123`, `network_map_page.dart:112-139`, `add_member_page.dart:55-83` | Business logic in widgets: distance sort per build; viewport math + URL building; page drives the use case with local busy/error state. Move to controllers / pure helpers (`AddMemberController`, `MapViewport.forPoints`). |
| M13 | Medium | `PRIVACY.md` §4 | Says Refresh downloads "from each saved site"; discovery also fetches sites the user never saved (hubs/members, ≤ 500 rows). Add one clause. |
| M14 | Low/Med | `network_providers.dart:54-60` | Migration `Left` → reason-less `StateError`, nothing logged; also blocks publish (reads `networkRepositoryProvider`). `appLog` before throwing; document the blast radius. |
| Lows | — | see review | `StorageFailure('…: $e')` carries `SqliteException` text with bound params (URLs); `count()` loads all rows; "Not now" ⇒ `declined` permanently; `ConfirmMembershipUseCase` has no transition guard; `BackupIdentity` name not control/bidi-filtered; codec `_maxDepth` counts brackets inside strings; haversine `asin(sqrt(h))` NaN at antipodes; `updatedAt` defeats the unchanged-sha skip for `library.json`; `ref.listen` after `await` in `NetworkController.build`; `NetworkWindow` not `freezed`; stale doc headers (`app_database.dart:1`, `network_providers.dart:7-10`, ratchet comment "690 → 631" vs 682). |

Still open from before the review (merge/release items, not code):
golden PNG for `network_library_tiles` (Linux `update-goldens` job),
fastlane changelog, release sentinel, rebase onto current `main` and re-run
all gates.

## 3. Gotchas from the fix session (don't rediscover)

- **M3 attempt that failed:** setting
  `RichAttributionWidget(popupInitialDisplayDuration: Duration(seconds: 8))`
  makes the credit visible on first frame, BUT flutter_map implements it
  with a bare `Future.delayed` in `initState` (widget.dart:143-149), so
  (a) every map-page test that does not pump past the duration fails with a
  pending timer / `findsNothing` expectation, and (b) the open popup's close
  button fails the 48×48 tap-target guideline in the `meetsGuideline` test
  ("map with pins"). Options: wrap the popup in our own widget with a
  cancellable `Timer` and a ≥48 dp close target; or use
  `SimpleAttributionWidget` inside a `FittedBox`/`ConstrainedBox` (always
  visible, no timer — check narrow-screen overflow that the handoff §3
  mentioned); either way update `network_map_page_test.dart:117-132` (it
  currently TAPS `Icons.info_outlined` to reveal the text) and re-run the
  a11y trio.
- **Pre-commit hook regenerates `.g.dart`:** a change to any `@riverpod`
  file body changes its hash; the hook refuses the commit and leaves the
  regenerated file in the tree — `git add` it and commit again.
- **Fake repos must enforce UNIQUE:** the refresh use-case `_FakeRepo` now
  rejects duplicate fingerprints and skips duplicate siteUrls like Drift;
  keep that when adding tests, or H1-class bugs become invisible again.
- **`BookmarkUrl` has two methods now:** `sanitize` (allow-list, verbatim —
  fetcher, redirect hops) vs `normalize` (canonical site root — everything
  stored/compared). Do not pass `normalize` to a fetcher.
- **Testing abort passthrough:** a `MockClient` that "never answers" must
  honour `Abortable` (complete with `RequestAbortedException` when the
  trigger fires) or the test hangs for 30 s — see the COMPOSITION group in
  `test/core/network/bounded_http_fetcher_test.dart`.
- All earlier gotchas (flutter_map API, riverpod `_debugAssertCanDependOn`,
  restore-page `ensureVisible`, ratchet) still apply — see git history of
  this file (`git show f4888e4:libNetwork-handoff.md` §3).

## 4. Quick pointers

| What | Where |
|------|-------|
| URL allow-list + canonical form | `lib/features/network/domain/value_objects/bookmark_url.dart` (`sanitize`, `normalize`) |
| Refresh algorithm + conflict rules | `lib/features/network/domain/usecases/refresh_network_use_case.dart` (`_applyDescriptor`, `_flagConflict`, `_ensureUniqueFingerprints`) |
| Refresh report | `lib/features/network/domain/refresh_report.dart` |
| Discovery plan (role merge) | `lib/features/network/domain/network_discovery_plan.dart` (`_discover`) |
| Abort passthrough | `lib/core/network/timeout_http_client.dart` (`send`, first lines) |
| Fetch headers / UA | `lib/core/network/bounded_http_fetcher.dart` (`headers`, `defaultHeaders`) |
| Card byte cap | `lib/features/network/domain/value_objects/library_card_payload.dart` (`_fitName`) |
| Publish refusal on descriptor Left | `lib/features/publish/application/publish_controller.dart` (after `BuildOwnDescriptor.build`) |
| Tests added this session | `test/features/network/domain/{bookmark_url,refresh_network_use_case,network_discovery_plan,add_member_use_case,library_card_payload}_test.dart`, `test/features/network/infrastructure/drift_network_repository_test.dart`, `test/core/network/bounded_http_fetcher_test.dart`, `test/features/publish/publish_controller_test.dart` |

## 5. Final gate run of this session

At b47df82, working tree clean (2026-10-18):

- `dart run build_runner build --delete-conflicting-outputs` → no diff
- `flutter analyze lib test integration_test` → No issues found
- `dart format --set-exit-if-changed lib test integration_test` → 0 changed
- `fvm flutter test --exclude-tags golden` → **2269 tests, all passed**
  (2233 at the review tip + 36 added by the fixes)
