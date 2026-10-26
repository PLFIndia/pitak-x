# `appViewer` branch code review

- **Date:** 2026-10-25
- **Result:** Changes requested before merge (resolved by follow-up commits)
- **Scope:** `main...HEAD`, from merge-base `d551416` through `1e85607`
- **Excluded:** Pre-existing uncommitted documentation changes, which were left untouched
- **Resolution (2026-10-26):** findings 1–10 were fixed in `1fac761`,
  `6e1f2e3` and `9c8400d`; smoke/timezone coverage landed in `7527ec7`; the
  golden blocker closed in `d3d938a` and `dd162b7`. Pre-events CI run
  `40275336216` passed. Manual device/TalkBack evidence remains a separate
  release-checklist item, not a claim made by this review.

## Findings

### 1. Medium — Invalid percent-encoded UTF-8 can break cover rendering

**Location:** `lib/features/network/domain/published_site_url_policy.dart:118`

The URL policy validates escape syntax but not whether the decoded bytes are valid UTF-8. A hostile cover containing `%FF` or `%C0%AF` passes the initial sanitizer, then `Uri.decodeComponent` throws instead of allowing the UI to show a placeholder.

**Fix:** Catch the decoding failure and reject the URL. Add policy and visible-row resolver tests for malformed UTF-8 escapes.

### 2. Medium — Manual reload keeps stale covers and obsolete network work

**Location:** `lib/features/network/presentation/pages/published_catalogue_page.dart:71-73`

Manual reload refreshes only the catalogue and never resets the cover session. If an image changes while its URL stays unchanged, reload continues displaying the old bytes because the URL remains cached and remembered. In-flight requests from the old payload can also complete into the reloaded session.

**Fix:** Reset covers when a reload actually starts, cancel old work, and make visible covers request again after reset. Add a page-level same-URL/changed-image test; the existing page test checks only the catalogue GET count.

### 3. Medium — A refreshed catalogue can invalidate the selected language

**Location:** `lib/features/network/presentation/widgets/published_catalogue_controls.dart:111-124`

The controls preserve `state.language` while replacing the dropdown items from the new payload. If the selected language disappears or changes casing, the value has no matching item. A focused widget reproduction confirmed Flutter's assertion. In release builds, the dropdown can display a different or blank facet while the invisible old filter remains active.

**Fix:** Remap the selection case-insensitively or clear it in query state when absent. Do not merely mask the dropdown value. Add a select-language/reload-with-changed-facets widget test.

### 4. Medium — Evicted covers cannot be fetched again during the session

**Locations:**

- `lib/features/network/application/published_catalogue_cover_controller.dart:117-121`
- `lib/features/network/application/published_catalogue_cover_controller.dart:187-205`

Requests are permanently deduplicated through `_remembered`, but eviction removes only bytes and usage metadata. After exceeding 100 entries or 16 MiB, scrolling back to an evicted row leaves a placeholder until the viewer is reopened because the recreated row's request is rejected as a duplicate.

**Fix:** Forget successfully cached keys when evicting them while retaining failure deduplication, and allow visible cache misses to request again. Extend the eviction tests to request an evicted URL again.

### 5. Medium — Query-worker failures produce an endless spinner

**Locations:**

- `lib/features/network/presentation/pages/published_catalogue_page.dart:210-215`
- `lib/features/network/presentation/pages/published_catalogue_page.dart:311-319`

The page ignores `viewAsync.hasError` and treats every null view as loading. If the query isolate fails to start or completes with an error, the loaded catalogue remains behind an indefinite spinner with no recovery action.

**Fix:** Render a safe query-error state and offer a retry that invalidates only the derived query, without refetching the catalogue. Add a derived-query failure test; existing error tests cover catalogue-fetch failures only.

### 6. Low — Third-party redirects bypass the non-default-port restriction

**Locations:**

- `lib/features/network/domain/published_cover_resolver.dart:59-67`
- `lib/features/network/domain/published_cover_resolver.dart:107-114`

The initial URL receives a port check, but redirect sanitization delegates to `CoverUrlAllowList.sanitize`, which does not inspect ports. An allow-listed cover endpoint can therefore redirect the device to an unapproved service on the same host using a non-default port. Arbitrary hosts remain blocked, limiting the impact.

**Fix:** Apply scheme, userinfo, host, and port validation uniformly to initial URLs and every redirect. Add a redirect-to-port-8443 refusal test.

### 7. Low — Route disposal does not clear Flutter's global image cache

**Locations:**

- `lib/features/network/presentation/widgets/published_item_cover.dart:127-138`
- `lib/features/network/application/published_catalogue_cover_controller.dart:96-103`

`Image.memory`/`MemoryImage` inserts completed entries into Flutter's global `ImageCache`. Those entries remain after widget disposal; clearing the Riverpod map does not remove the encoded key bytes or decoded image. This contradicts the documented viewer-session cleanup.

This was verified against Flutter's implementations: `ImageProvider` uses `PaintingBinding.imageCache.putIfAbsent`, completed entries remain in the cache independently of listeners, and `Image.dispose` stops listening without evicting.

**Fix:** Explicitly evict session image keys on reset/teardown or use a rendering path without global retention. Add an `ImageCache.statusForKey` teardown test.

### 8. Low — Duplicate series are overwritten without the required warning

**Locations:**

- `lib/features/network/domain/entities/published_catalogue.dart:258-263`
- `lib/features/network/presentation/pages/published_catalogue_page.dart:250-263`

`hasPartialRead` omits `duplicateSeriesUids`, and the page has no separate duplicate warning. Canonical-equivalent duplicate UIDs use last-valid-wins behavior but produce no visible warning when no other defect exists.

**Fix:** Include duplicates in the visible warning path, either through `hasPartialRead` or a dedicated banner. Test the visible gate, not just the counter.

### 9. Low — Cover strings bypass the retained-field size cap

**Location:** `lib/features/network/infrastructure/published_catalogue_item_reader.dart:252-260`

The cover reader sanitizes `coverUrl` without enforcing `CatalogueRules.maxFieldChars`. Over-cap absolute cover URLs remain retained and requestable without a partial-read warning, violating the 8,000-character reader contract. Over-cap same-site references are also retained even when later URL policy rejects them.

**Fix:** Reject over-cap sanitized references, increment `invalidOptionalFields`, and add 8,000/8,001-character boundary tests.

### 10. Low — URL fragments defeat cover deduplication

**Locations:**

- `lib/features/network/domain/published_cover_resolver.dart:34`
- `lib/features/network/domain/published_cover_resolver.dart:107-114`

Third-party cover resolution preserves fragments, while the resulting string is used as the cache/deduplication key. HTTP clients remove fragments before sending, so `#a` and `#b` variants cause separate cache entries and redundant identical downloads.

**Fix:** Strip or reject fragments before constructing the request and canonicalize redirect hops consistently. Test that fragment variants share one key and one fetch.

## Test and release gaps

### Smoke-test cleanup is ambiguous with existing saved libraries

**Location:** `integration_test/published_catalogue_smoke_test.dart:158`

The journey taps an unscoped `Remove` tooltip. With another visible saved library, the finder is ambiguous and cleanup fails, leaving the smoke row behind. Earlier visibility steps also assume the newly added row is already built in the lazy list.

**Fix:** Scope the action to the generated tile, reveal it using the existing scroll helpers, and register failure-safe cleanup for the exact created row.

### Golden release blocker remains open

The populated light/dark golden images and registrations remain absent. `appViewer_plan.md:59` explicitly identifies this as a release blocker. Golden and on-device checks were not run during this review.

### New date paths are absent from the two-timezone CI commands

**Location:** `.github/workflows/ci.yml:109-112`

The CI timezone commands do not include the new issue-date reader/detail tests. The focused New York run passed locally, but CI currently will not protect those paths.

## Verification completed

- `fvm flutter analyze lib test integration_test` — passed with zero issues.
- `fvm dart format --output=none --set-exit-if-changed lib test integration_test` — passed with zero changes.
- `fvm flutter test --exclude-tags golden` — all 3,325 tests passed.
- Focused `America/New_York` codec/detail/contract tests — all 73 tests passed.
- Focused stale-language widget reproduction — confirmed the dropdown assertion; the temporary test was removed afterward.
- No source files were modified by the review.
