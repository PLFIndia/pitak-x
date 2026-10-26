# `appViewer` review remediation plan

- **Date:** 2026-10-25
- **Branch:** `appViewer`
- **Source review:** [`appView_review.md`](appView_review.md)
- **Status:** R1–R4 implementation complete in `1fac761`, `6e1f2e3`,
  `9c8400d`, `7527ec7`, `d3d938a` and `dd162b7`. Manual device/TalkBack
  evidence remains outstanding as described in §4 and `docs/RELEASING.md`.
- **Merge rule:** All ten findings and all three test/release gaps must be closed with the evidence below before the branch is treated as merge-ready

## 1. Objective and constraints

Fix the reviewed defects without weakening the viewer's existing privacy, security, read-only, or lifecycle contracts. The result must be a proper repair of the affected foundations, not UI-only masking of invalid state.

Binding constraints:

- Follow [`AGENTS.md`](AGENTS.md) and the existing ADR 0015 design in [`appViewer_plan.md`](appViewer_plan.md). No new dependency, persistent catalogue/cover cache, WebView, deep link, schema change, local-library write, or publish-format change.
- Keep domain URL rules pure Dart. Keep Flutter's global `ImageCache` out of the domain and application layers; its cleanup belongs in presentation.
- Preserve remote-cover consent, bounded fetching, one FIFO cover worker, failure deduplication, the 100-entry/16 MiB cache limits, query-intent preservation across reload, and exactly one catalogue GET per deliberate reload.
- Treat every published string and redirect as hostile. Reject unsafe input before network work, catch only expected decode failures, fail closed, and never show raw exception text or remote values in the UI.
- Keep every non-generated Dart file at or below 500 lines. Split a responsibility into a focused file rather than adding a file-size ratchet entry.
- Use small, independently green commits. Do not delete or weaken an existing regression test to make a fix pass.

## 2. Implementation order and coverage

| Stage | Review items | Reason for this order |
|---|---|---|
| R1 | Findings 1, 6, 9, and 10 | Establish non-throwing, size-bounded, canonical request inputs before changing lifecycle code. |
| R2 | Findings 2, 4, and 7 | Repair reload, eviction, visible retries, and image-cache ownership as one coherent cover-session lifecycle. |
| R3 | Findings 3, 5, and 8 | Repair query-state reconciliation, derived-query recovery, and visible warning semantics. |
| R4 | Smoke cleanup, timezone CI, and golden blocker | Add release protection only after the behavior being protected is stable. |

Each stage must finish with its focused tests, formatting, analysis, and relevant architecture tests green. A later stage may strengthen an earlier test but must not remove its assertions.

---

# R1 — Defensive input and canonical cover requests

## Finding 1 — Invalid percent-encoded UTF-8 must not break cover rendering

**Production files**

- [`published_site_url_policy.dart`](lib/features/network/domain/published_site_url_policy.dart#L92-L130)

**Implementation**

1. Keep `_hasValidEscapes` as the first guard so malformed percent syntax is handled deliberately rather than by a catch-all.
2. Wrap only the `Uri.decodeComponent(part)` call in a narrow `try`/`on FormatException` block and return `null` for a decoding failure. This covers syntactically valid escapes whose bytes are not valid UTF-8, including `%FF` and overlong `%C0%AF`.
3. Do not catch `Object`, `Error`, or every exception, and do not allow a malformed value to fall back to its encoded form. A path that cannot be decoded safely is not requestable.
4. Preserve the existing traversal, encoded-separator, origin, directory, query, and fragment checks. Update the nearby comment to distinguish malformed escape syntax from invalid decoded UTF-8.

**Regression tests**

- Extend [`published_site_url_policy_test.dart`](test/features/network/domain/published_site_url_policy_test.dart#L125-L160) with `%FF`, `%C0%AF`, a truncated multibyte sequence, and a valid multibyte sequence. Assert invalid sequences return `null` and never throw; assert the valid sequence still resolves inside the saved library.
- Keep the existing malformed-percent cases and their current documented behavior unchanged.
- Extend [`published_item_cover_test.dart`](test/features/network/presentation/published_item_cover_test.dart#L76-L102) with visible rows containing same-site cover leaves using `%FF` and `%C0%AF`. Each must render the placeholder, make zero fetcher calls, and leave `tester.takeException()` null.

**Done when:** No malformed percent-encoded UTF-8 can escape the policy as an exception or a request, while valid Unicode and all existing allowed paths still work.

## Findings 6 and 10 — Apply one third-party URL policy and remove fragments before keying

These findings share one root cause and must be fixed together. The initial URL and every redirect currently use slightly different validation, and the retained string doubles as the cache key.

**Production files**

- [`published_cover_resolver.dart`](lib/features/network/domain/published_cover_resolver.dart#L26-L38)
- [`published_cover_resolver.dart`](lib/features/network/domain/published_cover_resolver.dart#L57-L68)
- [`published_cover_resolver.dart`](lib/features/network/domain/published_cover_resolver.dart#L105-L115)

**Implementation**

1. Add one private third-party sanitization helper in this network-domain library and use it for both `PublishedCoverResolver.resolve` and `ThirdPartyCoverRequest.sanitize`.
2. The helper must first apply `CoverUrlAllowList.remoteHttpsOf`, then parse and enforce the viewer's complete request rule: HTTPS only, no userinfo, an allow-listed host, and no explicit port other than 443. Keep the shared publish allow-list unchanged; the viewer's stricter port rule must not silently change other features.
3. Remove the fragment with `Uri.removeFragment()` after validation and return that canonical, fragment-free URL. Preserve the path and query because Internet Archive redirect queries are required.
4. Construct the initial `ThirdPartyCoverRequest` from the same canonical URI. Redirect sanitization must also return the fragment-free form so initial requests and redirect hops cannot diverge in policy.
5. Document that fragments are discarded, rather than rejected, because HTTP does not send them and they must not create distinct downloads or cache entries. Same-site references continue to reject fragments under the existing narrower publisher contract.
6. Keep `PublishedCoverRequest.url` as the sole scheduler cache/deduplication key. Do not introduce a second key-normalization rule in the controller.

**Regression tests**

- In [`published_cover_resolver_test.dart`](test/features/network/domain/published_cover_resolver_test.dart#L105-L163), prove initial URLs and redirect hops both refuse port 8443, HTTP, userinfo, and non-allow-listed hosts; explicit port 443 and the existing Open Library to Internet Archive path remain allowed.
- Resolve two third-party URLs differing only by `#a` and `#b`; assert both requests have the same fragment-free `url`. Assert redirect sanitization also strips a fragment while retaining a required query.
- In [`bounded_published_cover_fetcher_test.dart`](test/features/network/infrastructure/bounded_published_cover_fetcher_test.dart#L230-L314), add an allow-listed initial endpoint that redirects to the same allow-listed host on port 8443. The fetch must return `null` and the mock client must record exactly the initial request.
- In [`published_catalogue_cover_controller_test.dart`](test/features/network/application/published_catalogue_cover_controller_test.dart#L77-L119), request the `#a` and `#b` variants and assert one scheduler key and exactly one fetch. This is the behavioral deduplication gate; a string-only resolver assertion is not sufficient.

**Done when:** Initial and redirected third-party requests enforce identical scheme/userinfo/host/port rules, port-8443 redirect traffic is never sent, and fragment variants cannot cause redundant fetches or cache entries.

## Finding 9 — Enforce the retained-field cap on sanitized cover strings

**Production files**

- [`published_catalogue_item_reader.dart`](lib/features/network/infrastructure/published_catalogue_item_reader.dart#L189-L205)
- [`published_catalogue_item_reader.dart`](lib/features/network/infrastructure/published_catalogue_item_reader.dart#L250-L261)

**Implementation**

1. Keep cover sanitization at the infrastructure boundary, then check `safe.length` against `CatalogueRules.maxFieldChars` before retaining it. The contract applies to the sanitized, trimmed reference, not to untrimmed input padding.
2. If the sanitized value is over 8,000 characters, return `null` and increment `invalidOptionalFields` exactly once. Do not truncate a URL, retain the raw value, or defer rejection until request time.
3. Preserve the existing silent handling of absent/null/blank covers and the single warning increment for a nonblank unsafe value. Avoid double-counting an unsafe value that is also long.
4. Because `_readCover` serves both item and periodical rows, keep the rule in that shared helper rather than duplicating it at both call sites.

**Regression tests**

- Add a cover-boundary group to [`published_catalogue_codec_test.dart`](test/features/network/infrastructure/published_catalogue_codec_test.dart#L493-L540).
- Build valid allow-listed absolute references of exactly 8,000 and 8,001 sanitized characters. The former is retained with no new warning; the latter becomes `null`, increments `invalidOptionalFields` by one, and makes `hasPartialRead` true.
- Repeat the boundary for long `covers/<leaf>` references so an over-cap same-site reference cannot survive the reader merely because the later resolver would reject it.
- Exercise both `books[]` and `periodicals[]`, and include surrounding whitespace to prove the limit is measured after trimming/sanitization.
- Assert no over-cap value appears in the retained model or in test failure output; identify cases by labels rather than printing the complete generated string.

**Done when:** Every retained cover reference, for every row kind, satisfies the same 8,000-character contract and every over-cap nonblank reference produces the existing safe partial-read warning.

---

# R2 — One coherent cover-session lifecycle

Findings 2, 4, and 7 interact. In particular, clearing `_remembered` on reload is insufficient: a visible row must request again, but it must not request an old payload's cover while the replacement catalogue is still loading.

## Finding 2 — Reset only an accepted reload and resume covers on the new payload

**Production files**

- [`published_catalogue_controller.dart`](lib/features/network/application/published_catalogue_controller.dart#L68-L98)
- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L71-L73)
- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L104-L120)
- [`published_catalogue_list.dart`](lib/features/network/presentation/widgets/published_catalogue_list.dart#L45-L90)
- [`published_item_cover.dart`](lib/features/network/presentation/widgets/published_item_cover.dart#L72-L124)

**Implementation**

1. Expose a read-only `canRefresh` decision on `PublishedCatalogueController` that is true only when the notifier is alive, the initial load is not running, and no manual refresh is active. Make `refresh()` use that same decision as its enforcement guard so the two cannot drift; the getter lets the page coordinate related session state without guessing.
2. In the page's reload callback, return immediately when `canRefresh` is false. Otherwise, synchronously reset the cover controller and then call `refresh()`. There must be no `await` between the check, reset, and refresh call, so a second event cannot interleave on the single UI isolate. Add a beginner-friendly comment explaining this ordering.
3. A reload accepted after either data or a typed error must reset covers. A tap during initial loading or a second tap during an active reload must not clear covers, abort new work, or add another GET.
4. `PublishedCatalogueCoverController.reset()` remains the single generation boundary: increment the generation, complete the current abort signal, clear queued and remembered work, clear bytes/usage, and publish an empty session. Existing late-completion guards remain mandatory.
5. Thread a `coverRequestsPaused` flag from the catalogue page's `state.isLoading` through `PublishedCatalogueList` into list-row `PublishedItemCover` widgets. While an accepted reload is in progress, old rows may remain visible with placeholders but must make no new cover requests from the old payload.
6. On successful completion, the flag becomes false and visible rows from the new payload request their cache misses. On failure, the existing catalogue error body replaces the rows, so no old-payload cover traffic resumes. Item-detail covers keep the default unpaused behavior and must not start watching or fetching the catalogue provider merely to support this flag.
7. Preserve the user's query intent throughout reload. Do not invalidate the catalogue, query controller, languages provider, derived view, or HTTP client as a substitute for the targeted cover reset.

**Regression tests**

- Extend [`published_catalogue_controller_test.dart`](test/features/network/application/published_catalogue_controller_test.dart#L112-L151) to pin `canRefresh` during initial loading, after data, after error, and during a manual refresh. Existing one-GET and concurrent-refresh tests must remain.
- Extend the page harness in [`published_catalogue_page_test.dart`](test/features/network/presentation/published_catalogue_page_test.dart#L382-L399) with injectable settings and cover-fetch fakes and with item fixtures that retain a `coverUrl`.
- Add the required page-level same-URL/changed-image test: finish loading cover bytes A, begin a real manual reload, verify no old-payload replacement request starts while the catalogue GET is pending, then complete the reload with the same cover URL and return different valid JPEG bytes B. Assert exactly one new cover fetch and that the rendered `MemoryImage` contains B, not A.
- Add a separate in-flight page test: keep the old cover request pending, reload, assert its abort signal completes, then complete it late after the new catalogue arrives and prove its bytes never enter the new session.
- Double-tap Reload in a focused action test and assert one additional catalogue GET, one observable cover abort/reset cycle, and no extra cover request from the ignored tap.

**Done when:** An actual reload starts with a clean cover generation, obsolete work cannot land, visible covers refresh even when URLs are unchanged, and ignored reload taps have no cover side effects.

## Finding 4 — Eviction must release successful-request deduplication only

**Production files**

- [`published_catalogue_cover_controller.dart`](lib/features/network/application/published_catalogue_cover_controller.dart#L107-L131)
- [`published_catalogue_cover_controller.dart`](lib/features/network/application/published_catalogue_cover_controller.dart#L177-L212)
- [`published_item_cover.dart`](lib/features/network/presentation/widgets/published_item_cover.dart#L92-L138)

**Implementation**

1. When LRU count/byte eviction removes a successfully cached key, remove that key from `_remembered` at the same time as its bytes and usage metadata. A later visible cache miss may then request it again.
2. Do not clear the whole remembered set on ordinary eviction. Failed downloads/decodes remain remembered for the session, and queued/in-flight keys retain their existing deduplication behavior.
3. Keep reset semantics distinct: reset still clears all remembered keys, including failures, because it creates a deliberate new cover generation.
4. In `PublishedItemCover.build`, a resolved visible request with `bytes == null` must call the existing post-frame `_scheduleRequest` path when cover requests are not paused. `_scheduled` continues to coalesce rebuilds, and the controller remains the authoritative deduplicator.
5. Do not schedule directly in `build`; only schedule the existing post-frame callback. Recheck `mounted`, request identity, consent, and pause state before calling the controller. A remembered failure must produce no repeated network traffic on unrelated rebuilds.
6. Preserve bounded queue behavior. If the queue is full, the key is forgotten as today so a later visible frame can try when capacity exists.

**Regression tests**

- Extend both eviction tests in [`published_catalogue_cover_controller_test.dart`](test/features/network/application/published_catalogue_cover_controller_test.dart#L157-L190): after count-based and byte-based eviction, request the evicted URL again and assert a second fetch plus a newly cached result.
- Request a still-cached URL again and assert no duplicate fetch. Request a previously failed URL again and assert failure deduplication still prevents another fetch.
- Add a widget-level cache-miss check in [`published_item_cover_test.dart`](test/features/network/presentation/published_item_cover_test.dart) proving a visible placeholder requests after a controller reset without recreating the row. Rebuild a remembered failure and prove it does not hammer the fetcher.
- Retain FIFO, queue-bound, consent, reset-abort, and late-completion tests unchanged.

**Done when:** Evicted successful covers are fetchable by visible rows, cached successes and session failures remain deduplicated, and no rebuild or queue-full path creates a request storm.

## Finding 7 — Evict this session's Flutter image keys on removal and teardown

**Production files**

- [`published_catalogue_cover_controller.dart`](lib/features/network/application/published_catalogue_cover_controller.dart#L35-L54)
- [`published_item_cover.dart`](lib/features/network/presentation/widgets/published_item_cover.dart#L115-L138)
- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L49-L76)
- New presentation-only helper: `lib/features/network/presentation/widgets/published_cover_image_cache_cleanup.dart`

**Implementation**

1. Do not import Flutter painting/binding APIs into the application controller. Instead, expose the session's cached URL keys through a read-only `PublishedCoverSession` getter and keep `bytesFor` as the byte lookup. This lets presentation identify precisely which `MemoryImage` keys disappeared.
2. Add `PublishedCoverImageCacheCleanup`, owned by `PublishedCataloguePage` for the entire viewer route. It subscribes with `ref.listenManual` to the cover session and tracks the latest snapshot, including while an item-detail route covers the list.
3. On each new snapshot, compare the previous session's keys/byte identities with the next. For every removed key or replaced byte buffer, evict exactly `MemoryImage(oldBytes)` from `PaintingBinding.instance.imageCache` with `includeLive: true`. This covers LRU eviction and reset, including entries still referenced by a visible `Image` during the transition.
4. On route disposal, close the subscription and evict every key in the last tracked session. The application controller's disposal still aborts work and clears its maps; the presentation helper owns the separate Flutter global-cache cleanup.
5. Use the same default scale/key construction as `Image.memory`, whose `MemoryImage` equality uses byte-buffer identity and scale. If the image scale ever changes, centralize key construction first; do not silently mismatch eviction keys.
6. Never call global `imageCache.clear()` or `clearLiveImages()`: those would evict unrelated screens' images. Evict only this viewer session's byte-backed keys.
7. Do not evict independently from each row's `dispose`. List and detail can share the same byte-backed key; uncoordinated per-widget eviction could remove an image still used by the other route. Session-scoped ownership avoids that lifecycle bug.

**Regression tests**

- Add teardown/reset tests to [`published_catalogue_page_test.dart`](test/features/network/presentation/published_catalogue_page_test.dart), using a real small JPEG and the injected cover port.
- After the image completes, capture its `MemoryImage` key and assert `PaintingBinding.instance.imageCache.statusForKey(key).tracked` is true. Reset the cover controller, settle, and assert the key is untracked.
- Render again, then unmount the whole viewer route and assert the new key is untracked. Cover both a visible image and a cached image whose row has scrolled off-screen but remains in the Riverpod session.
- Assert an unrelated pre-seeded image key remains tracked, proving cleanup is session-scoped rather than a global cache clear. Evict all test-seeded keys in test teardown so the global cache cannot leak state into another test.
- Keep the existing undecodable-bytes placeholder test and verify cleanup does not surface an asynchronous image exception.

**Done when:** Every encoded/decoded image inserted by this viewer is explicitly untracked on session removal/reset/route teardown, with no effect on unrelated Flutter images and no cross-layer Flutter import.

---

# R3 — Query state, recovery, and visible warnings

## Finding 3 — Reconcile the selected language in query state on a new payload

**Production files**

- [`published_catalogue_query.dart`](lib/features/network/domain/published_catalogue_query.dart#L142-L189)
- [`published_catalogue_query_controller.dart`](lib/features/network/application/published_catalogue_query_controller.dart#L29-L83)
- [`published_catalogue_query_controller.dart`](lib/features/network/application/published_catalogue_query_controller.dart#L119-L132)
- [`published_catalogue_controls.dart`](lib/features/network/presentation/widgets/published_catalogue_controls.dart#L105-L126)

**Implementation**

1. Add one pure `PublishedQueryEngine.canonicalLanguageSelection` helper beside `languagesOf`. Given the current selection and latest facets, it returns the facet's canonical display spelling for a trimmed case-insensitive match, or `null` when no match exists. Controller and controls must use this same helper rather than duplicating normalization.
2. Add a `reconcileLanguages` operation to `PublishedCatalogueQueryController`. A null current selection is unchanged. Otherwise, apply the pure helper: an identical match is a no-op, a differently cased match calls `setLanguage(canonicalLabel)`, and no match calls `setLanguage(null)`. This repairs the real filter; never retain an invisible selection.
3. Subscribe the query controller to `publishedCatalogueLanguagesProvider(siteUrl)` with `ref.listen` in `build`, and reconcile whenever a newly computed facet list arrives. Do not `watch` it in a way that reruns the notifier's `build` and resets search/kind/sort.
4. A reload start that exposes the previous payload must not clear the selection prematurely. Reconciliation must produce a state change only for a genuine case remap or absence in the latest facet list.
5. Keep `PublishedCatalogueControls` controlled by query state, with no second selection and no post-frame repair. To protect the dropdown during the provider-notification transition itself, compute its displayed value with the same pure helper: a case-remapped label or All languages until the controller's notified state arrives. This is only a transient render invariant, not a substitute for step 2; the widget test must prove the actual query state is repaired.
6. Preserve search text, active search, kind, sort, debounce behavior, and the rule that filtering never performs catalogue IO.

**Regression tests**

- Add pure helper boundary tests to [`published_catalogue_query_test.dart`](test/features/network/domain/published_catalogue_query_test.dart), then add application tests to [`published_catalogue_query_controller_test.dart`](test/features/network/application/published_catalogue_query_controller_test.dart) for exact-match no-op, case remap, missing-facet clearing, and preservation of all other query fields.
- Add the required widget reproduction to [`published_catalogue_page_test.dart`](test/features/network/presentation/published_catalogue_page_test.dart): select a language, reload with changed facets, and settle.
  - Case-only change: no Flutter dropdown assertion, query state uses the new spelling, and the visible rows still reflect that language filter.
  - Selection removed: no assertion, query state is `null`, the dropdown shows All languages, and no invisible old filter hides rows.
- Assert the reload causes exactly one additional catalogue GET and the reconciliation itself causes none.
- Run the existing controlled-dropdown, Clear filters, no-matches, and query-preservation tests.

**Done when:** The dropdown value and actual query filter remain the same valid selection after every payload replacement, including case changes and removal.

## Finding 5 — Derived-query failures need a safe terminal state and targeted retry

**Production files**

- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L209-L220)
- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L265-L340)

**Implementation**

1. Read `viewAsync.hasError` explicitly. A query error is not loading, regardless of whether `valueOrNull` is null or contains a previous view.
2. When the derived query fails, keep the loaded catalogue header and controls available but replace the results area with a safe message such as “Couldn't display these catalogue results.” Do not render the isolate exception, stack trace, URL, or remote field content.
3. Hide the stale result count and previous rows while the failed query has no valid current result. Do not present an old view as though the failed filter/sort succeeded.
4. Add a Retry action in the results error state that calls `ref.invalidate(publishedCatalogueViewProvider(_siteUrl))` only. It must not call catalogue `refresh`, reset covers, clear query intent, invalidate the languages provider, or recreate the viewer HTTP client.
5. Keep the existing catalogue-fetch error mapping and its Retry behavior separate. Initial query loading still shows a spinner only when there is no error and no view; empty/no-match behavior stays unchanged.
6. If these additions push the page over 500 lines, extract the feedback/banner/result-message widgets into a focused presentation file. Do not add a file-size exception.

**Regression tests**

- Extend the page test harness in [`published_catalogue_page_test.dart`](test/features/network/presentation/published_catalogue_page_test.dart#L93-L112) so `publishedCatalogueQueryRunnerProvider` can fail once with a sentinel exception and then succeed.
- Load a valid catalogue, fail the derived query, and assert the safe error and Retry are visible, the indefinite spinner is absent, and neither the sentinel text nor previous rows/count is shown.
- Tap Retry and assert a second runner invocation produces the rows while the catalogue fetch count remains exactly one. Assert search/filter/sort intent is retained and no cover reset occurs.
- Add a previous-view-then-error case so `valueOrNull` cannot hide the failure behind stale rows. Existing catalogue-fetch error tests must continue to prove their separate retry issues one more GET.

**Done when:** Every derived-query failure reaches a recoverable safe UI, and retry reruns only the derived query against the already loaded catalogue.

## Finding 8 — Duplicate series must reach the visible partial-read warning

**Production files**

- [`published_catalogue.dart`](lib/features/network/domain/entities/published_catalogue.dart#L211-L267)
- [`published_catalogue_page.dart`](lib/features/network/presentation/pages/published_catalogue_page.dart#L244-L263)

**Implementation**

1. Include `duplicateSeriesUids > 0` in `PublishedCatalogueWarnings.hasPartialRead`.
2. Update the getter documentation: last-valid-wins means an earlier duplicate series representation is not displayed, so this belongs in the same visible warning path as other omitted/replaced entry data. Keep `invalidExportedAt` excluded and keep unknown-kind wording separate.
3. Reuse the existing safe banner rather than adding duplicate-specific remote strings or a second banner. No UID, title, or count from the hostile payload is printed.

**Regression tests**

- Strengthen the duplicate cases in [`published_catalogue_codec_test.dart`](test/features/network/infrastructure/published_catalogue_codec_test.dart#L818-L854): a canonical-equivalent duplicate with no other defect must make `hasPartialRead` true; an invalid later row that is not counted as a duplicate must not create a duplicate warning.
- Extend the page fixture helper in [`published_catalogue_page_test.dart`](test/features/network/presentation/published_catalogue_page_test.dart#L45-L57) to accept a complete warnings object or a duplicate count.
- Add a page test whose only defect is `duplicateSeriesUids == 1` and assert “Some entries couldn't be displayed.” is visible. Also assert a zero-duplicate catalogue does not show that warning.

**Done when:** The visible UI gate, not merely the counter, reports duplicate-series replacement with no other warning source required.

---

# R4 — Test isolation and release gates

## Smoke-test cleanup — Make the exact generated row revealable and removable

**Files**

- [`published_catalogue_smoke_test.dart`](integration_test/published_catalogue_smoke_test.dart#L34-L164)
- [`smoke_support.dart`](integration_test/smoke_support.dart#L97-L143)

**Implementation**

1. Create one local tile finder from the generated unique name, `find.widgetWithText(NetworkLibraryTile, name)`, and use it for initial visibility, opening, normal cleanup, and failure cleanup.
2. Use the existing `reveal` helper with the `CustomScrollView` descended from `NetworkPage`. Do not assume a newly added row is already built in the lazy list.
3. Derive the Remove button with `find.descendant(of: generatedTile, matching: find.byTooltip('Remove'))`. Never tap an unscoped Remove tooltip.
4. Extract an idempotent `removeGeneratedRow` helper. It returns immediately after a successful removal; otherwise it returns to `NetworkPage` with a bounded number of back navigations, reveals the exact tile, taps only its Remove action, settles, and verifies that exact row is gone.
5. Register `addTearDown` for this helper after the row is confirmed created and before the steps that can fail. Register it after the container-disposal teardown so normal LIFO teardown runs row cleanup while the provider container is still available. The normal path calls the same helper; teardown retries only if normal cleanup did not complete.
6. Keep cleanup specific to this run's site/name. Do not clear the network table or remove pre-existing saved libraries, and do not let a cleanup attempt turn an unrelated earlier failure into an ambiguous-finder error.

**Verification**

- Run the journey on a cleared install and again with at least one other visible saved library before and after the generated row.
- Run it twice on the same install to prove unique-row cleanup, then deliberately interrupt a run from the viewer/detail step and confirm teardown removes only the generated row.
- Finish with no smoke row left behind and all pre-existing rows unchanged.

## Two-timezone CI — Include every new issue-date path

**Files**

- [`.github/workflows/ci.yml`](.github/workflows/ci.yml#L103-L113)
- [`published_catalogue_codec_test.dart`](test/features/network/infrastructure/published_catalogue_codec_test.dart)
- [`published_catalogue_item_page_test.dart`](test/features/network/presentation/published_catalogue_item_page_test.dart#L123-L151)
- [`published_catalogue_contract_test.dart`](test/features/publish/published_catalogue_contract_test.dart#L46-L96)

**Implementation**

1. Append the network codec and item-detail test paths to both existing `TZ=Asia/Calcutta` and `TZ=America/New_York` commands.
2. Include the writer-to-reader contract suite in the same two commands as well: it retains issue-date round-trip coverage and was part of the review's focused timezone verification.
3. Keep the existing calendar-date, catalogue-item, periodical-domain, and add-issue paths unchanged. Use the same ordered file list in both commands so the matrices cannot drift.
4. Do not replace the explicit paths with a broad suite that makes timezone failures harder to localize.

**Done when:** Both CI commands execute the codec, detail, and contract issue-date paths, and both timezone runs pass locally and in CI.

## Golden release blocker — Add deterministic populated viewer goldens on Linux

**Files**

- [`key_screens_test.dart`](test/golden/key_screens_test.dart#L45-L134)
- [`golden_names.dart`](test/golden/golden_names.dart)
- [`golden_files_exist_test.dart`](test/golden/golden_files_exist_test.dart)
- [`update_goldens.yml`](.github/workflows/update_goldens.yml)
- Planned outputs: `test/golden/goldens/published_catalogue_populated_light.png` and `test/golden/goldens/published_catalogue_populated_dark.png`
- [`appViewer_plan.md`](appViewer_plan.md#L51-L63) deviation D2
- [`ci.yml`](.github/workflows/ci.yml#L157-L165)

**Implementation**

1. Add `published_catalogue_populated_light` and `published_catalogue_populated_dark` to `kGoldenNames` in the same change that adds their rendering tests. Do not register names without committing the corresponding Linux PNGs; the non-tagged existence guard intentionally fails otherwise.
2. Build one deterministic populated-catalogue fixture containing a book, an issue/series, and an Other row, fixed publication metadata, and a small valid in-memory JPEG cover. Use production `AppTheme.light`/`AppTheme.dark` and the existing phone viewport helper.
3. Inject an immediate catalogue port, synchronous query runner, explicit settings fake with remote-cover consent enabled, and a cover port returning the safe JPEG. No real HTTP, preferences, clock, isolate timing, or platform launcher may affect the image.
4. Reuse `expectGolden` so the registration guard and `matchesGoldenFile` path remain the single blessed approach. Settle catalogue, query, and image decoding before comparison.
5. Generate the PNGs only through the Linux `update_goldens` workflow, download its `goldens` artifact, copy only the two new images into the golden directory, and commit them. Never commit macOS renderer output. Because the workflow needs committed wiring while the existence guard needs the PNGs, use a temporary branch commit to obtain the artifact, then amend/squash the wiring, names, and PNGs into one complete commit before merge; do not leave a registration-only red commit in the final branch history.
6. Run the ordinary existence guard and the Linux tagged golden suite. Once both PNGs and CI evidence are committed, update deviation D2 in [`appViewer_plan.md`](appViewer_plan.md#L51-L63) to record that the blocker is closed, with the workflow/run evidence; until then it remains an explicit merge blocker.

**Done when:** Both populated images are committed from Linux, their names and rendering tests agree, the normal existence guard passes, and Linux `flutter test --tags golden` passes. Merely adding test wiring is not completion.

---

# 3. Consolidated regression matrix

This table is the final audit checklist. Each review item has a behavioral gate, not just a code edit.

| Review item | Required proof |
|---|---|
| 1. Invalid UTF-8 escapes | Policy returns `null` without throwing for `%FF`/`%C0%AF`; visible rows show placeholders and make zero requests; valid Unicode remains allowed. |
| 2. Reload stale covers/work | Page test proves same URL renders new bytes, old work is aborted/ignored, no old-payload request starts during reload, and duplicate Reload has no side effects. |
| 3. Invalid selected language | Case remap and removal widget tests prove query state and dropdown agree, with no assertion or invisible filter and no extra GET. |
| 4. Evicted-cover retry | Count and byte eviction suites refetch evicted successes; cached success and failure deduplication remain intact. |
| 5. Query-worker error | Page shows safe non-spinner error; Retry runs only the derived query and keeps catalogue GET count at one. |
| 6. Redirect port bypass | Resolver applies one port policy to initial/redirect URLs; port-8443 redirect fetch records only the initial request. |
| 7. Global image retention | `ImageCache.statusForKey` becomes untracked after reset and route teardown, including off-screen session images; unrelated keys survive. |
| 8. Duplicate warning | Duplicate-only codec state sets `hasPartialRead`; page displays the safe warning with no other defect. |
| 9. Cover field cap | Item and periodical tests cover 8,000/8,001 sanitized characters for absolute and same-site references with exactly one warning increment. |
| 10. Fragment deduplication | Fragment variants have one canonical key and one fetch; redirect canonicalization removes fragments while preserving required queries. |
| Smoke cleanup | Exact generated tile is revealed and removed on success/failure with other saved rows present; reruns leave no smoke row. |
| Golden blocker | Two Linux PNGs, registrations, existence guard, and tagged Linux golden suite are all complete. |
| Timezone CI gap | Codec, detail, and contract paths appear in both CI commands and pass in both timezones. |

# 4. Verification sequence

Run from the repository root with the pinned FVM toolchain. Focused tests run after each stage; the complete gates run before merge.

## Focused suites

```bash
fvm flutter test \
  test/features/network/domain/published_site_url_policy_test.dart \
  test/features/network/domain/published_cover_resolver_test.dart \
  test/features/network/domain/published_catalogue_query_test.dart \
  test/features/network/infrastructure/bounded_published_cover_fetcher_test.dart \
  test/features/network/infrastructure/published_catalogue_codec_test.dart \
  test/features/network/application/published_catalogue_controller_test.dart \
  test/features/network/application/published_catalogue_cover_controller_test.dart \
  test/features/network/application/published_catalogue_query_controller_test.dart \
  test/features/network/presentation/published_item_cover_test.dart \
  test/features/network/presentation/published_catalogue_page_test.dart \
  test/features/network/presentation/published_catalogue_item_page_test.dart \
  test/features/publish/published_catalogue_contract_test.dart \
  test/architecture
```

## Full local gates

```bash
fvm flutter pub get --enforce-lockfile
fvm dart run build_runner build --delete-conflicting-outputs
# Confirm no generated-file diff; no provider-signature change is expected.

fvm flutter analyze lib test integration_test
fvm dart format --output=none --set-exit-if-changed lib test integration_test
fvm flutter test --coverage --exclude-tags golden

TZ=Asia/Calcutta fvm flutter test \
  test/features/library/domain/value_objects/calendar_date_test.dart \
  test/features/library/domain/catalogue_item_validated_test.dart \
  test/features/periodicals/domain \
  test/features/periodicals/application/add_issue_use_case_test.dart \
  test/features/network/infrastructure/published_catalogue_codec_test.dart \
  test/features/network/presentation/published_catalogue_item_page_test.dart \
  test/features/publish/published_catalogue_contract_test.dart

TZ=America/New_York fvm flutter test \
  test/features/library/domain/value_objects/calendar_date_test.dart \
  test/features/library/domain/catalogue_item_validated_test.dart \
  test/features/periodicals/domain \
  test/features/periodicals/application/add_issue_use_case_test.dart \
  test/features/network/infrastructure/published_catalogue_codec_test.dart \
  test/features/network/presentation/published_catalogue_item_page_test.dart \
  test/features/publish/published_catalogue_contract_test.dart
```

The existing coverage floor must not fall, and touched domain/application code must retain the project's high-coverage requirement. Dependency and lockfile changes are not expected; all existing CI jobs, including secret/dependency/OSV scans, Rust checks, and F-Droid purity, must remain green.

## Linux and on-device evidence

1. Run Linux `flutter test --tags golden` through CI after committing the workflow-generated PNGs. A local macOS golden comparison is not a substitute.
2. Run the focused smoke journey with an attached F-Droid device:

   ```bash
   fvm flutter test integration_test/published_catalogue_smoke_test.dart --flavor fdroid -d <device>
   ```

3. Repeat on the same install with pre-existing saved libraries, then run the complete integration command in [`docs/RELEASING.md`](docs/RELEASING.md#L190-L202) before release.
4. Complete the outstanding device evidence from [`appViewer_plan.md`](appViewer_plan.md#L564-L580): large-fixture decode/query/lazy-scroll behavior, bounded cover memory, and the TalkBack walkthrough. Exercise the safe derived-query error using a fail-once test seam; do not weaken production error handling to create it.
5. Perform the planned disposable real-host smoke before merge. Cloudflare remains conditional on a real publisher; do not create provider-specific behavior for this remediation.

# 5. Commit and completion plan

Use small Conventional Commits along the stage boundaries:

1. `fix(network): harden published cover input validation` — R1 findings and tests.
2. `fix(network): repair published cover session lifecycle` — R2 reload/eviction/global-image-cache changes and tests.
3. `fix(network): recover catalogue query and warning states` — R3 changes and tests.
4. `test(network): harden viewer smoke and timezone coverage` — smoke isolation and both CI timezone commands, independently green before golden wiring.
5. `test(network): add populated viewer goldens` — the final amended/squashed atomic change containing rendering tests, names, and both Linux PNGs.
6. `docs: record appViewer review remediation evidence` — only after all checks complete; update the original plan's D2 status and summarize verification without changing release versions or notes.

Do not bump the app version, change release-note files, add dependencies, or declare the golden/device gates complete without their actual artifacts and runs. The branch is ready only when every row in the consolidated matrix has passing evidence and the full CI/device checks above are complete.
