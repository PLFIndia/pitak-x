# Native saved-library viewer — implementation plan

- **Branch:** `appViewer` (created from `main` on 2026-10-25)
- **Status:** Ready for implementation; this planning step deliberately changes no feature code
- **Scope:** **Option 1 only** — tapping an already-saved Library network row opens that library's published catalogue inside Pitak
- **Product promises protected:** P1 (no silent data downgrade), P2 (hostile input and privacy), P3 (no new F-Droid risk), P5 (one maintainable Riverpod/Clean Architecture path); P4 is protected by the documentation and release gates
- **Authoritative contracts:** `AGENTS.md`, `docs/ARCHITECTURE.md`, ADR 0012, ADR 0013, ADR 0014, and the existing `books.json` writer/web viewer

This plan is written as discrete, independently green sessions. A session may change the plan only by recording a deviation first; it must not silently weaken a security, compatibility, or privacy rule.

---

# Part A — Scope and binding decisions

## A.1 User-visible outcome

After the work is complete:

1. The user opens **Library network → Libraries**.
2. Tapping any saved row opens a native Flutter page showing that row's published catalogue.
3. The first open fetches `books.json` once, on that explicit action. Rebuilding widgets, rotating, or opening an item detail does not fetch it again.
4. The user can search, filter, sort, open a read-only item detail, and explicitly reload the catalogue.
5. The normal tap never opens the external browser. An explicit **Open in browser** action remains available on loading, success, empty, and error screens.
6. Leaving the viewer discards its in-memory catalogue and cover cache and aborts its outstanding HTTP work. A later open fetches fresh data again.

There is no external entry point. The saved row is both the navigation input and the proof that this library was saved; no deep-link bookmark lookup is needed.

## A.2 Binding decisions

| ID | Decision | Reason |
|---|---|---|
| V1 | **Every saved `NetworkLibrary` row is eligible**: `bookmark`, `card`, and `discovered`. Do not check `NetworkSource` when opening. | They are all rows in the one Library network list. Different tap behavior by provenance would be surprising and would recreate a bookmark/network split. |
| V2 | **The viewer is native Flutter and read-only.** It has no WebView, edit, lend, delete, membership, publish, or import actions. | Preserves the existing rule that untrusted HTML/JavaScript stays outside the app process and prevents a remote row from masquerading as a local catalogue item. |
| V3 | **Do not reconstruct local `CatalogueItem` or `Periodical` entities.** Use separate published-view models. | Local entities have private fields, local IDs, editing behavior, and lending semantics that do not exist in `books.json`. Separate models make accidental mutation much harder. |
| V4 | **No deep links or platform URL work.** No custom scheme, App Links, association files, `AndroidManifest.xml` change, router migration, or published-HTML button. | Option 1 needs only ordinary internal navigation. |
| V5 | **Fetch on open; no persistent catalogue cache in v1.** Keep data only in auto-dispose, screen-scoped providers. No Drift schema change, files, backup entries, or background refresh. | This is the smallest honest implementation and avoids stale-data and cache-invalidation design before offline viewing is requested. |
| V6 | **Read the existing publish schema 1; do not change the writer or wire format.** Unknown keys remain additive. A newer root schema still renders fields this build understands, with a persistent visible newer-schema warning and browser fallback. | Matches the HTML viewer's intended forward-tolerant behavior without copying its bug that immediately overwrites the warning. Known fields must never be presented as proof that every newer field was understood. |
| V7 | **Trusted writer models and hostile-reader models stay separate.** Compatibility is pinned by shared fixtures and writer→reader tests, not by making network code depend on the publish feature's encode-only classes. | Reader validation is deliberately more defensive than writer construction, and the current dependency direction must not gain a network→publish application cycle. |
| V8 | **Default ordering is “Published order”, not “Recently added”.** Preserve payload order and the original row index as the stable tie-break. | `addedDate` is deliberately stripped by `redactForPublish`; the native viewer must not invent it. The current HTML label must not be copied into a promise the payload cannot support. |
| V9 | **Display reads are tolerant, never coercive.** Only an absent `kind` means book; exact current tokens map to their kinds; any other value remains `unknown` and renders as a plain item, not as a book and not as an import rejection. Invalid rows/fields are dropped according to the matrix below and counted for a safe warning. | Matches ADR 0014 W3's display behavior while treating every byte as hostile. Import/write-back rules and the broader enum-name aliases accepted by some local parsers do not apply here. |
| V10 | **The browser is a deliberate fallback, not the default.** Revalidate the saved site URL before launching it externally. | Preserves access to the full website, including things outside native v1, without weakening URL validation. |
| V11 | **Every viewer cover request retains the existing remote-cover opt-in, including same-site covers.** The explicit row tap authorizes only `books.json`; covers stay placeholders while `loadRemoteCovers` is off or unknown. Both origin classes are bounded, lazy, decoded safely, and memory-only. | This deliberately fails closed and is stricter than the web viewer. Cover requests reveal viewed paths/timing even to an already-contacted library host; the existing setting must not acquire a silent same-site exception. Settings/privacy copy will explain ephemeral viewer downloads alongside permanent local materialization. |
| V12 | **Use per-request caller abort, a viewer-scoped HTTP client, per-load revisions, and explicit mount invalidation.** Caller abort cancels one socket on reset/dispose; closing the viewer-owned client is the backstop and never touches the shared Refresh/Publish client; late bytes/query results cannot overwrite newer state. | Auto-dispose alone neither proves socket cancellation nor guarantees that a rapid close/reopen creates a fresh provider. Resource ownership and fetch-per-mount semantics must be explicit and tested. |
| V13 | **Cloudflare needs no second viewer path.** The existing `BookmarkUrl` policy and the same schema-1 reader handle both `github.io` and `pages.dev`. | Provider differences belong to publishing, not reading. Cloudflare publishing itself remains out of scope. |
| V14 | **No new dependencies.** Reuse Riverpod codegen, `fpdart`, `http`, `image`, existing value objects, and existing test helpers. | Avoids dependency review, lockfile churn, native-plugin risk, and a second image/cache/network stack. |
| V15 | **Identity conflicts are not silently cleared or “repaired”.** Catalogue loading never writes a fingerprint or network row; a current conflict gets a visible warning in the viewer. | The viewer is read-only, but it must not imply that a conflict was resolved. The browser fallback remains available. |
| V16 | **Every non-generated Dart file stays at or below 500 lines.** Split the reader, query logic, controls, list, detail, and cover scheduler by responsibility rather than adding ratchet entries. | Required by the existing architecture fitness test and beginner-maintainability rule. |
| V17 | **Only the saved-list row changes.** The separate `NetworkMapPage` pin/sheet “Open site” action remains an external-browser action in v1. | Option 1 covers the Library network list, not every possible website entry point. |
| V18 | **Catalogue and same-site cover redirects stay inside the selected library.** Every hop must pass `BookmarkUrl`, retain the normalized origin (scheme/host/effective port), and remain inside the saved site's directory boundary. Another Pages host or another library on the same host is refused. | The broad Pages allow-list is necessary but not sufficient to prevent a saved site from redirecting the viewer into unrelated content or tracking. |

## A.4 Deviations recorded during implementation (2026-10-25)

Recorded before the affected session finished, per the Part C rule. None weakens
a security, compatibility or privacy rule.

| # | Plan said | What shipped | Why |
|---|---|---|---|
| D1 | `freezed` UI query/cover state (`*.freezed.dart`) | Hand-written immutable state classes (`PublishedCatalogueQueryState`, `PublishedCoverSession`) | The repository has never used `freezed` in `lib/features` (`NetworkWindow`, `AppSettings`, `RefreshReport` are plain immutable classes, and `network_controller.dart` records the "one blessed way" reasoning). Immutability — the real requirement — is unchanged; rebuild scope uses record `select`. |
| D2 | A golden PNG pair for the populated viewer | Golden **test wiring is not added**; the PNGs must be produced by the Linux `update_goldens` workflow | This environment can only render on macOS, and committing a macOS-rendered PNG is explicitly forbidden. Adding names without PNGs would fail the always-on existence guard. **Release blocker:** add the two names + renders and commit Linux PNGs before merge. |
| D3 | Device evidence for the large-fixture check and TalkBack | The 20 000-row decode/query budget test and a lazy-build widget test ship here; device measurement and TalkBack walk are documented in `docs/RELEASING.md` §6.1 | No Android device is attached to this environment; the automated guards are in place and the manual steps are tracked in the release checklist. |
| D4 | Cover decode off the UI isolate in the adapter | `ImageDownscaler.downscaleJpegAsync` is the production default and injectable for tests | Unchanged behaviour; the injection seam keeps the "only downscaled bytes" test cheap. |
| D5 | "Read the existing publish schema 1; do not change the writer" | `PublishedCatalogueCodec` is instance-based with constructor caps (defaults = production values) | Lets boundary tests inject tiny caps instead of allocating 64 MiB; production always uses the defaults. |

---

## A.3 Explicit non-goals for this branch

- Deep links, custom schemes, Android App Links, or opening links from outside Pitak.
- Cloudflare publishing implementation.
- Offline/persistent remote-catalogue caching, background sync, ETags, or conditional requests.
- Importing, merging, editing, lending, or copying a remote item into the local catalogue.
- A WebView or execution of the published JavaScript viewer.
- Native events, contact details, logo, map, or membership screens. These are not all present in `books.json`; do not scrape HTML to obtain them.
- Reproducing the website's table/cards/covers layout switcher. Native v1 has one adaptive, lazy list plus item detail.
- Persistent layout/query preferences for remote libraries.
- Removing `url_launcher`; it remains for the explicit browser action and other existing flows.
- Changes to `books.json`, `library.json`, QR/card payloads, publish redaction, or the HTML viewer, except shared contract tests that prove the native reader agrees with them.

Deferred work needs a new trigger and, where architectural, a new ADR. In particular, persistent caching requires an explicit freshness/eviction/delete-on-remove/restore policy before any table is added.

---

# Part B — Target behavior and technical design

## B.1 Navigation and ownership

### Entry

Change `NetworkLibraryTile` from owning `launchUrl` to accepting an optional `onOpen` callback, following its existing callback style. `NetworkPage` supplies the callback and pushes `PublishedCataloguePage(row: row)` with ordinary `Navigator` navigation.

- A null `onOpen` is allowed for previews/goldens and renders no normal tap action.
- Remove HTTP/browser behavior from the tile; it remains a thin display widget.
- The page passes the canonical `row.siteUrl` to providers, not the whole `NetworkLibrary` object. The URL is the stable family key; changing row names or badges does not restart a fetch.
- The page may use the row for the initial title and current identity-conflict badge. Blank names fall back to the site URL.
- No repository read is needed to “check bookmark status”: this route can only be reached from the saved row.

### Browser fallback

Extract one presentation-side helper for opening a published site externally. It must:

1. Re-run `BookmarkUrl.sanitize` on the exact saved site URL.
2. Refuse a null result without launching anything.
3. Use `LaunchMode.externalApplication`.
4. Show the existing safe “Couldn't open that link.” message on failure; never show platform exception text.

Put the helper behind a small injectable seam in widget tests so tests can prove the normal row tap makes **zero** external launches and only the explicit browser action makes one.

### Existing app shell

`MaterialApp.builder` already wraps the whole Navigator in `AppGate`; the new route therefore inherits splash/app-lock coverage automatically. Do not add a second lock, a second Navigator, or viewer-specific screenshot blocking. Remote catalogue data is public, while the existing app-lock policy remains app-wide.

## B.2 Screen contract

`PublishedCataloguePage` contains:

- App bar: library name (or URL), **Reload**, and **Open in browser**.
- Optional current identity-conflict warning; it never offers an automatic merge or fingerprint update.
- A small “Published catalogue” context line and, when valid, the `exportedAt` display date.
- A note that availability is the coarse snapshot from publish time, not a live loan query.
- Search field, kind filter, language filter, and sort menu.
- Result count in the form `shown of total items` and a safe partial-read warning when applicable.
- One lazy list with cover/thumbnail, title, optional transliteration/author/year, kind badge, age badge, and coarse availability badge.
- Series headers only when at least one visible issue resolves to a valid public series entry.
- A read-only item-detail page or bottom route showing all decoded public fields and a larger cover. It has no local-library actions.

Use the production light/dark themes, lazy builders, narrow rebuild scopes, and `select` for per-cover state. Long titles and Indic text wrap; controls wrap rather than overflow. Interactive targets and semantics must pass the existing accessibility trio.

### State mapping

- **Initial loading:** spinner/skeleton and browser action; exactly one fetch.
- **Reloading:** one in-flight load maximum; a second reload request is ignored or queued nowhere.
- **Success with items:** catalogue and controls.
- **Success with a newer declared schema:** keep the readable items and controls visible, with a persistent banner: “This catalogue was published by a newer Pitak. Some details may not be shown. Update Pitak when an update is available.” The banner is not overwritten by result counts; the browser action remains.
- **Successful empty payload:** “This published catalogue is empty.”
- **No filter matches:** “No matches.” Clear-search/filter action; do not refetch.
- **Some rows/fields rejected:** show the readable rows plus “Some entries couldn't be displayed” (and, for unknown kinds, limited-detail wording). Never print raw remote values.
- **Raw rows existed but none were readable:** a distinct “No readable items” state, not a misleading empty-library state.
- **Transport/timeout:** safe connection message, **Retry**, and browser action.
- **HTTP status refusal:** “The site didn't serve this catalogue.” Retry and browser action. The current transport result has no status code, so do not claim every such response is a 404 or that the library was never published.
- **Too large:** “This catalogue is too large to open in Pitak.” Browser action is prominent.
- **Invalid payload:** “Pitak couldn't read this published catalogue.” Browser action remains.
- **Unexpected bug:** generic safe error; log only a type/code, never URL, response body, item title, or stack in release output.

A failed reload may replace the viewing state with the typed error; it must not leave a spinner indefinitely or pretend stale data is fresh. There is no persistent stale copy to fall back to in v1.

## B.3 Published-view domain model

Add immutable, pure-Dart models under `features/network/domain/entities/published_catalogue.dart`:

- `PublishedCatalogue`: declared root schema version, nullable valid `exportedAt`, a `hasNewerSchema` flag (`declaredSchemaVersion > 1`), unmodifiable items, unmodifiable public periodicals, and structured warning counts.
- `PublishedCatalogueItem`: `sourceIndex`, title, `PublishedItemKind`, optional common public fields, optional `PublishedIssueDetails`, optional `AgeGroup`, optional `PublishedAvailability`, and a sanitized cover reference.
- `PublishedIssueDetails`: canonical periodical UID when usable, optional positive volume/issue number, normalized optional issue dates, optional bound end, and label. It carries display data only—no local ID or lending behavior.
- `PublishedPeriodical`: canonical UID, title, and only the public series metadata needed for grouping/detail.
- `PublishedItemKind`: `book`, `magazineIssue`, `other`, `unknown`. Do not reuse `ItemKind.fromToken` in a way that loses the unknown state.
- `PublishedAvailability`: `available`, `out`; every other token means absent. There is never an exact copy/loan count.
- `PublishedCatalogueWarnings`: counts such as dropped item rows, dropped periodical rows, truncated rows, duplicate series UIDs, invalid optional fields, and unknown-kind rows. Counts and enum-like reasons only—no remote strings.

`sourceIndex` is session-local and exists only for stable sorting/grouping and widget keys. It is not a published identity and is never persisted.

Reuse pure value semantics where they genuinely match: `AgeGroup.sortRank` behind a small published-token parser that accepts exactly the five current tokens and the four legacy tokens used by the HTML viewer, `PeriodicalFrequency.fromToken`, `canonicalPeriodicalUid`, `CatalogueRules` date/year/text limits, and `CalendarDate` legacy-date normalization. Do **not** use `ItemKind.fromToken` or `AgeGroup.fromToken` indiscriminately: their trimming/case folding and enum-name aliases are broader than the published display contract. Do **not** reuse strict local issue ingress validation either: a display reader can show an ungrouped issue with partial metadata, while a local lendable issue has stronger requirements.

## B.4 `books.json` read contract

Implement `PublishedCatalogueCodec` in **infrastructure** as a pure-Dart, non-throwing JSON/byte decoder returning `Either<PublishedCatalogueFailure, PublishedCatalogue>`. This keeps JSON out of feature domain, maps raw input into clean published-view entities at the infrastructure boundary, and prevents DTOs from leaking into presentation.

### Root rules

| Input | Required behavior |
|---|---|
| Bytes above the body cap | `tooLarge`, before UTF-8/JSON decoding; also enforced by transport. |
| Malformed UTF-8, malformed JSON, excessive nesting, or non-map root | `invalid`; never throw across a layer. |
| Missing/non-integer/`<= 0` `schemaVersion` | `invalid`. Numeric strings and doubles are not coerced. |
| `schemaVersion > 1` | Decode the fields this build understands, set `hasNewerSchema`, and show the persistent warning. Do not reject solely because of the version and do not interpret unknown v2+ keys. |
| Missing/non-list `books` | `invalid`; do not confuse corruption with an empty catalogue. |
| `exportedAt` | Optional display metadata. Accept a non-negative integer within `CatalogueRules.maxDateMillis`; absent or invalid means null plus a warning, not rejection of otherwise readable items. It remains an instant, unlike issue calendar days. |
| Missing `periodicals` | Empty list (additive/legacy payload). |
| Present but non-list `periodicals` | Ignore the block and count a warning; books can still be read. |
| Unknown root keys | Ignore. Never retain them in the model. |

### Row and field rules

- Stop accepted items/periodicals at **100,000 rows per collection**, matching the app's established outer interchange ceiling; record truncation visibly. Transport/body limits still apply before parsing.
- Cap any retained string at `CatalogueRules.maxFieldChars` (8,000). A missing, blank, wrong-type, or over-cap required title drops that row. An invalid optional string is omitted and counted, not stringified or partially displayed.
- Only an absent/null `kind` means `book`. Exact `book`, `magazine-issue`, and `other` tokens map to their kinds without case folding or alias acceptance; any other value, including a wrong type, becomes `unknown` and increments the limited-detail count.
- `publishedYear` must be an integer in 1–9999. Volume/issue number must be positive integers when present. Doubles, booleans, numeric strings, NaN-like values, and out-of-range integers are not coerced.
- Parse age groups with the exact published-token parser described above; parse frequencies through the existing tolerant `PeriodicalFrequency.fromToken`. Unknown values become absent.
- Availability accepts exactly `available` and `out`; anything else is absent.
- Normalize valid issue date values with the existing `CalendarDate` stored-value rule. A bound badge requires a valid start and end in order; invalid/running-backward range metadata is not presented as a bound volume.
- A `magazine-issue` without usable issue linkage remains an ungrouped issue with its composed title. It is **not** rejected as an import would be.
- Canonicalize series/issue UIDs with `canonicalPeriodicalUid`. Blank or invalid series entries are dropped. On duplicate canonical series UID, the last valid entry wins to match the HTML viewer's `Map.set` behavior, and every duplicate increments a visible warning; duplicates are never merged silently.
- A periodical with no visible matching issue does not create a standalone row.
- An issue whose UID has no valid public series entry remains a plain, ungrouped issue.
- `other` retains only title, kind, cover, language, and age group, even if a hostile payload includes author, ISBN, availability, notes, location, or book-specific fields.
- Unknown kinds retain only common display-safe fields and render with no kind badge. Unknown keys and private/interchange-only keys are never retained or searched.
- Sanitize cover references at decode time; unusable references become null and can never produce a request.

The decoder rechecks byte/depth/row limits even though the transport also checks them, because tests and future non-HTTP callers can reach it directly.

### Shared nesting guard

Extract the existing string-aware `_maxDepth` implementation from `LibraryDescriptorCodec` into a pure helper under `lib/core/text/` (already permitted by the domain-purity gate). Both descriptor and published-catalogue codecs use that one implementation. This is a behavior-preserving refactor with bracket-in-string, escape, malformed-string, and depth-boundary tests; do not copy the security code.

### Decode off the UI isolate

The pure codec remains synchronous and unit-testable. `BoundedPublishedCatalogueFetcher` invokes it with `Isolate.run` after the body arrives, because a large JSON document and object graph can otherwise stall frames. Only public bytes/models cross the isolate. A late result after route disposal is discarded; no new parse is scheduled after disposal.

## B.5 Failure and fetch design

Add a feature-specific `PublishedCatalogueFailure extends Failure` with a coarse `PublishedCatalogueFailureReason`:

- `disallowedUrl`
- `redirectRefused`
- `tooManyRedirects`
- `httpStatus`
- `tooLarge`
- `timedOut`
- `transport`
- `invalid`

A newer schema is **not** a failure; it is successful decoded data with `hasNewerSchema` and a visible warning. The failure carries no URL, host, response body, status code/text, item content, or raw exception. The UI maps it to the safe states above.

Add a domain `PublishedCatalogueFetcher` function port and `LoadPublishedCatalogueUseCase` returning `Either<Failure, PublishedCatalogue>`:

1. Re-normalize the supplied site URL with `BookmarkUrl.normalize` and require an already-canonical value; fail closed on corrupted input.
2. Resolve `books.json` with `Uri.resolve` against the trailing-slash site root.
3. Delegate to the domain fetch port. Production injects the bounded infrastructure adapter; tests inject closures. The port accepts an optional `Future<void>` caller-abort signal so route disposal can abort the actual socket, not merely stop listening.
4. Perform no repository or settings writes and no descriptor fetch.

`BoundedPublishedCatalogueFetcher` follows `BoundedDescriptorFetcher` rather than inventing another HTTP stack. First make one backward-compatible core addition: `BoundedHttpFetcher.fetch` accepts an optional caller-abort `Future<void>` and links it to the existing internal abort completer/deadline. Existing callers remain unchanged. A caller-aborted result may use the existing coarse transport reason; catalogue/cover revisions discard it rather than showing a false error.

- Shared viewer-scoped `http.Client` from DI.
- `BookmarkUrl.sanitize` on the initial URL and every redirect, preserving exact file URLs rather than normalizing them to site roots.
- A pure `PublishedSiteUrlPolicy` additionally requires the selected normalized origin and saved-site directory boundary on the initial URL and every hop; another Pages host or another library directory is never requested.
- HTTPS and Pages host allow-list; at most 3 redirects; no redirect to an unapproved host, origin, or directory.
- 30-second whole-request abortable deadline for the larger catalogue payload.
- **64 MiB** streamed catalogue-body ceiling, matching the existing interchange ceiling; an honest oversized `Content-Length` is rejected early and actual streamed bytes are still counted.
- The viewer-owned `TimeoutHttpClient` gets a deliberately larger outer transport guard (**66 MiB**) so its generic transport error cannot mask the catalogue adapter's typed 64 MiB `tooLarge` result. The extra 2 MiB is headroom only, never an accepted catalogue size.
- Existing fixed app User-Agent on every hop plus `Cache-Control: no-cache`, mirroring the web viewer's revalidation intent without adding cache-busting query parameters. Custom headers replace the core defaults, so the User-Agent must be included explicitly.
- Exact transport-refusal→domain-failure mapping and a second codec cap check.

The 100,000-row/64 MiB limits are outer ceilings, not a performance claim. The implementation must include a large-fixture performance check and lazy UI. If a minSdk-class device cannot stay within a reasonable memory/frame budget, stop and amend the ADR/plan with an explicit lower native-viewer limit and browser fallback; never silently truncate more rows or move parsing back onto the UI isolate.

## B.6 Query, sort, and grouping

Keep all query behavior pure in `PublishedCatalogueQuery` / a small query engine, separate from HTTP and widgets. Add a domain query-runner port with an infrastructure `Isolate.run` adapter for expensive filter/sort/group passes; the controller injects it and uses revisions to drop late results. This keeps large-catalogue CPU work off the UI isolate without putting `dart:isolate` in application code. Use the existing **120 ms** debounce contract for typed search, and cancel that timer on disposal.

### Search

- Trim and lowercase the query.
- Match title, title transliteration, author, genre, and ISBN—the fields used by the current web viewer.
- Because excluded/unknown/private fields were never retained, sentinel values in hostile `notes`, `location`, `source`, `addedBy`, or excluded Other fields cannot match.
- Debounce text input before recomputing a large list; filter/sort/language changes recompute locally with no HTTP request.

### Filters

- Kind: All, Books, Magazines, Others. Unknown kinds appear only under All.
- Language: distinct trimmed values, case-insensitive deduplication, deterministic labels/order; filtering is case-insensitive.
- Empty language means All languages. Blank item languages never generate a blank facet.

### Sort

- **Published order (default):** ascending `sourceIndex`; do not expose a Recently-added sort.
- **Language:** blank/null last, then deterministic A→Z comparison; ties preserve `sourceIndex`.
- **Age group:** `AgeGroup.sortRank`, unknown/unset last; ties preserve `sourceIndex`.

Every operation is stable and returns new unmodifiable output rather than mutating the decoded source list.

### Series grouping

Filter/sort items first, then group:

1. Build the canonical UID→public-series map using the HTML-compatible last-valid-wins rule, while surfacing the duplicate count as a warning.
2. The group appears where the current item order first encounters one of its issues.
3. Only visible issues appear; a series with no visible issue has no header.
4. Inside a group, sort by issue date descending, volume descending, issue number descending, missing values last, then `sourceIndex` for a total stable order.
5. Orphan/partial issues stay ungrouped; their composed title remains visible.

Mirror `IssueSorter`'s semantics without passing published models into local `CatalogueItem` APIs. Pin both with equivalent fixtures so the missing-value and tie behavior cannot drift accidentally.

## B.7 Riverpod and lifecycle

Use code-generated providers only:

- `PublishedCatalogueController`: auto-dispose family keyed by canonical `siteUrl`; `AsyncNotifier<PublishedCatalogue>`; initial build performs one load, `refresh()` uses `AsyncValue.guard`, and use-case `Left` becomes `AsyncError(Failure)` using the repo's documented `only_throw_errors` justification pattern. A monotonically increasing load revision guards every completion. `PublishedCataloguePage.initState` invalidates its own catalogue/query/cover providers once before the first watch so even a rapid close/reopen is a new mount with fresh data and default query intent, never a resurrected stale session.
- `PublishedCatalogueQueryController`: auto-dispose family keyed by `siteUrl`; synchronous `Notifier` with an immutable `freezed` UI query state (search text, kind, language, sort).
- A derived provider/selector applies the pure query engine and exposes only the visible entries/grouping to the page.
- `PublishedCatalogueCoverController`: auto-dispose screen-scoped scheduler described below; immutable/freezed externally observed states, bounded private queues/caches, and `select` per cover key.

Register concrete fetchers and use cases in `core/di/src/network_providers.dart`; application/presentation never import infrastructure. Run build runner after every annotated/freezed change and commit generated files.

### Viewer-scoped HTTP ownership

Add an auto-dispose `publishedViewerHttpClient(siteUrl)` provider that constructs the same `TimeoutHttpClient` shape as the shared platform client but owns a separate inner `http.Client`. Catalogue and cover providers `watch` it, establishing the dependency chain. On final viewer disposal, Riverpod closes this client.

This is deliberate:

- The catalogue controller is auto-disposed when the route closes. Every load captures a revision and an abort completer registered with `ref.onDispose`; disposal/invalidation completes the trigger, supersedes the revision, and prevents late bytes or isolate results from setting state.
- The cover scheduler marks itself disposed, completes every in-flight cover abort trigger, drops queued work, clears bytes, and ignores late decode completions. Manual reload performs the same cover cancellation/reset before loading the new payload.
- The DI client closes as the final backstop, aborting any remaining viewer connections without closing the app's shared Refresh/Publish client. Caller abort handles an individual request; closing the client is never used as a substitute for per-request reload cancellation.
- The 120 ms query-debounce timer is cancelled on disposal. It is the only timer and never triggers HTTP; no retry loop, polling, prefetch, or keepAlive provider is introduced.
- App-lock background/resume leaves the existing route/provider mounted and causes zero additional fetches. A genuine route close followed by a new mount causes exactly one new fetch, verified by the explicit mount invalidation.

Test this lifecycle with fake ports/clients and queued delayed work; do not assume that disposing a notifier alone aborts HTTP.

## B.8 Read-only cover pipeline

Do **not** use `ItemCover` or `RemoteCoverMaterializer`: their successful path writes files and rewrites local item/periodical rows. Do not use `Image.network`: it would bypass the required origin, byte, decode, consent, and concurrency policies.

### Pure resolution policy

Add `PublishedCoverResolver` and a sealed request type (`sameSite` / `thirdParty`) in network domain:

- Blank/invalid reference → no request and placeholder.
- Relative `covers/<leaf>` → resolve against the saved site root. Reuse the existing cover-reference sanitizer, and additionally reject query/fragment, backslashes, encoded separators/dot segments, userinfo, non-default ports, or any resolution outside the saved site's origin and directory boundary.
- Absolute HTTPS → classify through `CoverUrlAllowList.remoteHttpsOf`; anything not on the existing third-party allow-list is dropped. A Pages URL does not become an allowed absolute cover merely because it is on a Pages host.
- Same-site redirect sanitizer → HTTPS, same normalized origin, same saved-site directory boundary, no userinfo/query/fragment tricks; every hop is checked. Do not allow a redirect from one saved library into another library or another Pages host.
- Third-party redirect sanitizer → the existing `CoverUrlAllowList.sanitize` behavior on every hop, preserving the Open Library→Internet Archive path.

### Fetch and decode

`BoundedPublishedCoverFetcher` uses the same viewer client and `BoundedHttpFetcher`:

- 15-second abortable deadline, at most 3 policy-checked redirects, 8 MiB streamed cap, and the same optional caller-abort signal forwarded from the screen scheduler.
- Existing fixed User-Agent; no authentication headers or cookies.
- No raw fallback when decoding fails.
- `ImageDownscaler.downscaleJpegAsync` in a worker isolate: header dimension/pixel guards, frame 0 only, maximum 400×600 JPEG output. Only the resulting safe JPEG reaches `Image.memory`.
- A coarse sealed result or nullable placeholder outcome is acceptable for covers; no raw error reaches UI/logs. Expected failures never crash the list.

### Screen-scoped scheduler and cache

Mirror the useful parts of `RemoteCoverMaterializer` without its persistence:

- Widgets request only when visible, from a post-frame lifecycle hook; recheck the current request key after the frame.
- Deduplicate by `(siteUrl, canonical request URL)` for the viewer session, including failures so scrolling cannot hammer a host.
- One FIFO worker for download+decode; no unbounded sockets, queues, or isolates. Only visible/new requests enter the bounded queue, and disposal empties it.
- Cache only downscaled bytes in memory. Bound both entries (**100**) and total cached bytes (**16 MiB**) with simple least-recently-used eviction; never cache raw 8 MiB downloads.
- Failed/decoding-invalid/consent-denied covers show the existing-style initial placeholder. A manual catalogue reload clears the loaded catalogue data and cover session while preserving the user's query intent; visible results are recomputed from the new payload, so removed covers are not shown as current.
- **Every** cover request—same-site or third-party—requires `settings.loadRemoteCovers == true`; unknown/loading/failed settings mean no request. Opening the viewer authorizes `books.json`, not image traffic. This is a deliberate stricter-than-web choice, not an accidental reuse of the local materializer.
- Match the existing OFF→ON behavior: visible covers of either origin class may request again after consent is enabled. No request made while consent was off is queued for later.
- No writes to local covers, Drift, secure storage, preferences, backups, item rows, or periodical rows. All bytes disappear on viewer disposal and may be downloaded again on a later open; this differs from the permanent local cover materialization described by the current setting.

## B.9 File map

Names are planned boundaries, not permission to create giant catch-all files. Keep each non-generated file ≤500 lines and split row parsing/widget responsibilities sooner if needed.

### New production files

```text
lib/core/text/json_nesting_depth.dart

lib/features/network/domain/entities/published_catalogue.dart
lib/features/network/domain/published_catalogue_fetcher.dart
lib/features/network/domain/published_catalogue_query.dart
lib/features/network/domain/published_catalogue_query_runner.dart
lib/features/network/domain/published_site_url_policy.dart
lib/features/network/domain/published_cover_resolver.dart
lib/features/network/domain/published_cover_fetcher.dart
lib/features/network/domain/usecases/load_published_catalogue_use_case.dart

lib/features/network/infrastructure/published_catalogue_codec.dart
lib/features/network/infrastructure/published_catalogue_item_reader.dart
lib/features/network/infrastructure/bounded_published_catalogue_fetcher.dart
lib/features/network/infrastructure/bounded_published_cover_fetcher.dart
lib/features/network/infrastructure/published_catalogue_query_runner.dart

lib/features/network/application/published_catalogue_controller.dart
lib/features/network/application/published_catalogue_controller.g.dart
lib/features/network/application/published_catalogue_query_controller.dart
lib/features/network/application/published_catalogue_query_controller.g.dart
lib/features/network/application/published_catalogue_query_controller.freezed.dart
lib/features/network/application/published_catalogue_cover_controller.dart
lib/features/network/application/published_catalogue_cover_controller.g.dart
lib/features/network/application/published_catalogue_cover_controller.freezed.dart

lib/features/network/presentation/pages/published_catalogue_page.dart
lib/features/network/presentation/pages/published_catalogue_item_page.dart
lib/features/network/presentation/widgets/published_catalogue_controls.dart
lib/features/network/presentation/widgets/published_catalogue_list.dart
lib/features/network/presentation/widgets/published_item_cover.dart
lib/features/network/presentation/widgets/open_published_site.dart
```

If a cover result model is shared by domain and infrastructure, place it beside `published_cover_fetcher.dart`; do not import core HTTP types into feature domain. Generate only the files required by the actual Riverpod/freezed annotations; do not create placeholder generated files.

### Modified production files

```text
lib/core/error/failure.dart
lib/core/network/bounded_http_fetcher.dart
lib/core/di/src/network_providers.dart (+ regenerated .g.dart)
lib/features/network/domain/library_descriptor_codec.dart
lib/features/network/presentation/widgets/network_library_tile.dart
lib/features/network/presentation/pages/network_page.dart
lib/features/guides/domain/guide_catalog.dart
lib/features/settings/presentation/pages/settings_page.dart
pubspec.yaml                         # comments only; no dependency/version change
```

### Tests and fixtures

Mirror the production structure:

```text
test/core/text/json_nesting_depth_test.dart
test/core/network/bounded_http_fetcher_test.dart
test/features/network/infrastructure/published_catalogue_codec_test.dart
test/features/network/domain/published_catalogue_query_test.dart
test/features/network/domain/published_site_url_policy_test.dart
test/features/network/domain/published_cover_resolver_test.dart
test/features/network/domain/load_published_catalogue_use_case_test.dart
test/features/network/infrastructure/bounded_published_catalogue_fetcher_test.dart
test/features/network/infrastructure/bounded_published_cover_fetcher_test.dart
test/features/network/infrastructure/published_catalogue_query_runner_test.dart
test/features/network/application/published_catalogue_controller_test.dart
test/features/network/application/published_catalogue_query_controller_test.dart
test/features/network/application/published_catalogue_cover_controller_test.dart
test/features/network/presentation/published_catalogue_page_test.dart
test/features/network/presentation/published_catalogue_item_page_test.dart
test/features/network/presentation/network_page_test.dart
test/features/publish/published_catalogue_contract_test.dart
test/features/publish/viewer_runtime_test.dart / viewer_runtime_harness.js  # shared fixture only
test/golden/key_screens_test.dart
test/golden/golden_names.dart
test/golden/goldens/published_catalogue_populated_light.png
test/golden/goldens/published_catalogue_populated_dark.png
integration_test/published_catalogue_smoke_test.dart
```

Use a small versioned fixture directory such as `test/fixtures/published_catalogue/` for schema-1 full, legacy, unknown-kind, malformed, and hostile-privacy payloads. Inject small limits in most boundary tests; keep one realistic large-fixture performance test rather than allocating 64 MiB in every test.

---

# Part C — Implementation sessions

Each session ends with focused tests green, generation/format/analyze clean for touched files, and a small Conventional Commit. Later sessions must not “fix” an earlier session by deleting its safety tests.

## S0 — Record the architecture decision

**Work**

- Add `docs/adr/0015-native-saved-library-viewer.md` using the template and this plan's V1–V18 decisions.
- Add it to `docs/adr/README.md`.
- Explain why there is no WebView, no persistent cache, no local-entity reconstruction, no added-date sort, separate viewer HTTP ownership, forward-tolerant newer-schema rendering, one all-cover consent gate, and two cover origin policies.
- Link this plan from the ADR; do not mark feature work complete.

**Checks**

- Documentation review against ADR 0012/0013/0014.
- No code or generated-file changes.

**Commit:** `docs: record native saved-library viewer decisions`

## S1 — Defensive schema-1 reader

**Work**

- Extract the string-aware JSON nesting helper to `core/text`; refactor `LibraryDescriptorCodec` without behavior change.
- Add the failure type, pure published-view domain models, infrastructure row reader/root codec, limits, and warning counts. No JSON import enters feature domain.
- Add shared schema-1 fixtures and writer→native-reader tests using `PublishExport`/`redactForPublish` output.
- Keep reader/writer models separate; do not modify production publish output.

**Required tests**

- Existing descriptor suite remains green, including brackets/escapes in strings and exact depth boundaries.
- Full book, issue, bound volume, Other, periodical, legacy-age, legacy-missing-kind payloads.
- Unknown kind is plain/unknown, never book or skipped silently; newer root schema returns readable known fields plus `hasNewerSchema`, never a failure solely for being newer.
- Malformed UTF-8/JSON, non-map root, wrong/missing versions, missing books, non-list books, absent/invalid timestamps degrading to null without discarding readable items.
- Wrong types, blank/over-cap required titles, optional-field dropping, numeric non-coercion, date-range and positive-count boundaries.
- Orphan issues (including the valid removed-series case), partial issue blocks, duplicate/non-ASCII canonical UIDs, HTML-compatible last-valid-wins behavior plus visible duplicate warnings.
- Hostile private/excluded sentinels are absent from retained models; Other cannot gain availability/book fields.
- Exact small-injected body/row/field/depth caps and over-cap behavior; unknown keys ignored.
- Real writer output round-trips without adding `addedDate`, local IDs, notes, or other private fields.

**Commit:** `feat(network): decode published catalogues defensively`

## S2 — Bounded loading, use case, and DI lifetime

**Work**

- Add optional caller-abort support to `BoundedHttpFetcher`, then add the domain fetch port, use case, infrastructure adapter, and viewer-scoped HTTP provider. Preserve every existing caller's behavior.
- Wire providers through `network_providers.dart`; update its comment because descriptor Refresh is no longer the only network read.
- Keep normal row behavior unchanged in this session.
- Update `docs/ARCHITECTURE.md` network-egress/bounds and `PRIVACY.md` for explicit `books.json` loading as the path becomes real.

**Required tests**

- GitHub and Cloudflare roots resolve exactly to sibling `books.json`.
- Existing canonical URL is required; userinfo/http/non-Pages/custom ports never reach the client.
- 2xx success, empty success, malformed payload, newer schema succeeding with `hasNewerSchema`, non-2xx, timeout, transport.
- Exact 64 MiB cap accepted at the catalogue adapter; declared and streamed over-cap abort without draining and surface typed `tooLarge` rather than the 66 MiB outer client's transport error.
- Three redirects allowed within policy; fourth refused; off-allow-list, cross-origin Pages, and directory-escape redirects are never requested; file path is never normalized back to root.
- User-Agent and no-cache header on every catalogue hop; no auth/cookie headers.
- Use-case success and every failure returns `Either`, never throws expected failures.
- The core streaming harness proves a caller abort closes the body/socket and existing descriptor/cover callers are unchanged. Provider disposal fires caller abort and later closes only the viewer client; the shared client/Refresh remains usable.
- First mount is exactly one GET; immediate close/reopen is exactly one new GET; app-lock pause/resume is zero GETs; late pre-disposal bytes cannot land in the new session.
- No background poll, repository write, or second initial fetch on rebuild; the only timer is the later query debounce and it never performs IO.

**Commit:** `feat(network): load published catalogues through a bounded reader`

## S3 — Query engine and controllers

**Work**

- Implement pure search/filter/sort/group logic, the isolate query-runner port/adapter, and the auto-dispose catalogue/query controllers with generated/freezed state.
- Reuse the existing 120 ms debounce duration and revision pattern; cancel the timer on disposal and never add a global timer or keepAlive provider.
- Ensure reload has one in-flight operation and no stale load or query completion can overwrite a newer successful state.

**Required tests**

- Every search field, trimming/case behavior, no-match and blank-query behavior.
- Private/excluded sentinel strings cannot match.
- Kind and language filters, unknown-kind membership, case-insensitive language facets.
- Published-order stability; language blanks last; age rank and legacy tokens; no `addedDate` dependency.
- Group position, visible-only groups, orphan issues, internal newest-first order, missing values last, `sourceIndex` ties.
- Controller initial load, refresh, retry after error, no duplicate request, auto-dispose, and query-intent preservation across item-detail navigation and manual reload; late load and query revisions lose deterministically.
- `ProviderContainer(overrides: ...)` only; no real HTTP/storage.

**Commit:** `feat(network): add published catalogue viewing state`

## S4 — Native UI and internal navigation

**Work**

- Add page, controls, lazy list, read-only detail, badges, placeholders, and browser helper.
- Change tile/page normal tap to internal navigation; retain an explicit browser action in the viewer.
- Update Library network explanatory copy and the in-app guide to say normal taps browse in Pitak.
- Cover bytes may remain placeholders until S5; all other v1 behavior must work in this session.

**Required tests**

- Normal taps on bookmark/card/discovered rows push exactly one native page and make zero external launches.
- Browser action alone invokes the launcher; invalid saved URL launches nothing; launch failure shows safe copy.
- Initial/loading/success/newer-schema-with-items/empty/no-match/partial/no-readable/error states and Retry/Reload behavior; the newer warning survives count updates and generic HTTP copy makes no unsupported 404 claim.
- Search/filter/sort operate without another fetch; back from detail preserves the loaded catalogue and query.
- Availability has no counts; Other has no book-only fields; unknown kind has no misleading badge; conflict warning does not mutate the row.
- Long Indic titles and wrapped controls do not overflow at the phone test size; lazy list does not build thousands of off-screen rows.
- Existing Network page tests and accessibility trio pass; add page/detail accessibility tests in light and dark themes.

**Commit:** `feat(network): open saved catalogues inside Pitak`

## S5 — Safe, memory-only covers

**Work**

- Add resolver, request/result types, bounded fetcher+decoder, scheduler/cache, and cover widget.
- Integrate same-site and third-party covers into list and detail, both behind the existing remote-cover consent.
- Clear the cover session on manual catalogue reload while preserving query intent, and dispose it on exit.
- Update `PRIVACY.md`, `docs/ARCHITECTURE.md`, and the Settings switch copy/tests with exact ephemeral viewer downloads, permanent local materialization, both cover origin classes, and limits.

**Required tests**

- Relative-cover resolution on GitHub/Cloudflare roots, including a non-root project path.
- Traversal, encoded traversal/separators, backslash, query/fragment, userinfo, wrong port/scheme/host, nested path, and redirect-outside-site all fail before a request.
- Third-party unknown hosts fail before a request; existing Open Library→archive allow-list redirects still work when consent is on.
- Consent off/loading/error produces zero same-site **and** third-party requests; OFF→ON permits visible re-request in both classes. No second setting or same-site exception is introduced.
- Status/timeout/oversize/malformed image/huge dimensions/animated image all degrade to placeholder; frame 0 only and no raw fallback.
- Visible-request dedup, failure dedup, FIFO bound, stale-request suppression, LRU count/byte eviction, reload clearing plus actual in-flight abort, and disposal clearing/abort.
- `ItemCover`/`RemoteCoverMaterializer` and local repositories are not called; no file or Drift writes; only downscaled bytes enter the cache.
- Image widget never receives a network URL; golden fixtures use in-memory safe JPEG bytes.

**Commit:** `feat(network): display published covers without persisting them`

## S6 — Compatibility, performance, accessibility, and device proof

**Work**

- Run the realistic large-fixture check: worker decode, search/filter/sort, lazy scrolling, and cover visibility on a representative lower-powered Android device where possible.
- Add the separate integration journey with real navigation/settings/Drift but fake catalogue/cover ports; no live Internet dependency in automated tests.
- The journey adds a uniquely named bookmark through the UI, opens it, searches/filters, opens detail, returns with state intact, reloads once, verifies browser action through the injected seam, and removes the test row.
- Perform one manual real-host smoke using a disposable Pitak-published GitHub Pages site. Repeat against Cloudflare only after that publisher exists; do not create a provider-specific viewer workaround.
- Complete TalkBack checks for the new route in addition to the existing release walkthrough.
- Add populated light/dark goldens and register their names. Generate PNGs through the Linux golden workflow, never macOS renderer output.

**Required evidence**

- No UI-isolate JSON decode and no eager construction of the full row widget list.
- Bounded memory behavior at the chosen outer ceiling; any need to lower it is resolved by amending S0/this plan before release.
- Device integration journey passes twice from a cleared install and after the sibling smoke journeys, matching existing test-isolation rules.
- Golden files exist, normal existence guards pass, and Linux tagged goldens pass.

**Commit:** `test(network): harden the published catalogue viewer`

## S7 — Documentation and final release hygiene

**Work**

- Reconcile `README.md`, `CHANGELOG.md` Unreleased, `PRIVACY.md`, `docs/ARCHITECTURE.md`, `docs/RELEASING.md`, `docs/mockups/how-pitak-works.md` **and** `docs/mockups/how-pitak-works.html`, `lib/features/guides/domain/guide_catalog.dart`, and the maintained store description with the shipped behavior.
- Update the `url_launcher` comment in `pubspec.yaml`: external browser remains for untrusted web content and the explicit fallback, while native public JSON/cover reading is not a WebView.
- Update `PRIVACY.md` item numbering, the passive-exception cross-reference, and effective date before release. Explain `books.json`, all-cover consent, same-site versus third-party hosts, IP/User-Agent visibility, ephemeral repeat-on-open covers, no persistent catalogue cache, and no import.
- Update Play data-safety wording only to the extent it remains accurate: user-directed public catalogue/cover downloads, no developer server, no uploaded bookmark list, no background sync. Consider the remote parser in `SECURITY.md`'s existing parser scope.
- Record any plan deviations in this file and the ADR. Do not bump app version, overwrite the existing `29*.txt` release notes, change the CI fastlane version argument, or create release notes/versionCode files until an actual release is requested.

**Commit:** `docs: describe native saved-library viewing`

---

# Part D — Verification matrix and final gates

## D.1 Coverage expectations

Target at least 90% line/branch coverage on new domain and application code, with every use-case success and failure path exercised. Security branches are mandatory even when the overall percentage is higher.

| Area | Must be proven |
|---|---|
| Reader | Root/row/field validity, legacy compatibility, unknown kinds, schema gate, privacy exclusions, all small-injected bounds |
| Transport | Origin policy, exact URL resolution, every redirect, streamed cap, timeout, abort, safe headers, typed failure mapping |
| Query | Every search/filter/sort/group rule, stability, missing keys, no private-field search, no network on local intent changes |
| Controllers | Initial load, one-flight refresh, typed AsyncValue states, disposal, no stale completion, consent transitions |
| Covers | Origin/traversal policy, consent, safe decode, dedup, bounded queue/cache, no persistence, disposal |
| UI | Every state, internal vs external navigation, read-only detail, retry/reload, empty/error copy, accessibility, dark mode, overflow |
| Regression | Existing descriptor, publish writer/Node viewer, Network page, app gate, local cover materialization, and architecture suites remain green |

## D.2 Security/privacy review before merge

- [ ] The only entry is an existing saved row; all three sources behave alike.
- [ ] No external input reaches HTTP before `BookmarkUrl`/cover-policy validation.
- [ ] Every catalogue/cover redirect is revalidated; catalogue and same-site covers cannot change origin or escape the saved directory, even to another allow-listed Pages site.
- [ ] No custom domain, userinfo, cleartext HTTP, non-default port, or non-allow-listed host is fetched.
- [ ] JSON and images have independent transport and decode bounds; oversized bodies are aborted, not drained.
- [ ] Large JSON decode and image decode happen off the UI isolate; only visible covers enter the FIFO.
- [ ] No raw response, URL, item title, cover URL, token, exception text, or PII is logged or shown as an error.
- [ ] Unknown keys cannot smuggle private fields into display/search; Other and unknown-kind projections stay sparse.
- [ ] No `Image.network`, WebView, dynamic HTML/JavaScript, local-entity mutation, or automatic import exists.
- [ ] Same-site and third-party covers remain consent-gated; settings failure fails closed and the explicit row tap never implicitly enables images.
- [ ] Viewer disposal clears memory, drops queued work, and closes only the viewer's client.
- [ ] No new dependency, native plugin, permission, Android manifest entry, database table, backup field, or secret storage entry was added.

## D.3 Required final commands and checks

Run with the pinned FVM toolchain from the repository root:

```bash
fvm flutter pub get --enforce-lockfile
fvm dart run build_runner build --delete-conflicting-outputs
# The resulting working tree must contain no uncommitted generated-file diff.

fvm flutter analyze lib test integration_test
fvm dart format --set-exit-if-changed lib test integration_test
fvm flutter test --coverage --exclude-tags golden

(cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo deny check && cargo test --release)
```

Also complete the existing CI-equivalent checks:

- Architecture/domain-purity/layer-boundary/file-size suites; no new ratchet entry.
- Dependency and secret scans, plus OSV scans of `pubspec.lock` and `rust/Cargo.lock` (dependency files should be unchanged).
- F-Droid purity check of `fdroidReleaseRuntimeClasspath`; no Google dependency may appear.
- Linux `flutter test --tags golden`; local macOS runs exclude golden comparisons but never create the reference PNGs.
- Add the new issue-date codec/display test paths to both existing CI timezone commands and run them under `Asia/Calcutta` and `America/New_York`; UTC-midnight values must remain unchanged and legacy values must follow the shared `CalendarDate` rule.
- Manual on-device integration command from `docs/RELEASING.md`, including the new viewer journey and no live-network test dependency.

## D.4 Merge acceptance criteria

The branch is ready only when all statements are true:

1. A normal tap on every saved network row opens the native read-only catalogue; no normal tap launches a browser.
2. The browser opens only through the explicit fallback and only after URL revalidation.
3. One explicit open produces at most one catalogue load; reload is deliberate; leaving aborts and discards the session.
4. Books, issues, bound volumes, Others, series groups, legacy payloads, unknown kinds, and newer-schema known fields follow this plan without changing publish bytes; the newer warning stays visible.
5. No UI offers Recently-added sorting or otherwise relies on redacted `addedDate`.
6. Search/filter/sort/detail never edit local data or issue another catalogue request.
7. Same-site and third-party cover behavior, consent, bounds, and memory-only lifetime match `PRIVACY.md`.
8. GitHub and Cloudflare addresses share the same reader path and tests.
9. No persistent cache, background sync, deep link, WebView, new dependency, schema migration, or Cloudflare publisher work slipped into the branch.
10. All tests, generated-file checks, security/privacy checks, documentation, goldens, and device evidence above are complete.

---

# Part E — Deferred extensions and their triggers

| Deferred idea | Trigger required before planning it |
|---|---|
| Offline catalogue/cache | A concrete offline-viewing requirement; design freshness, last-good timestamps, eviction, storage caps, delete-on-remove, restore/generation behavior, and backup exclusion in a new ADR. |
| Native events/contact/logo/map | A user need and a versioned public data contract; never scrape or execute the website to fill these gaps. |
| External links opening Pitak | A separate product decision among App Links, a controlled link domain, custom scheme, or share target; bookmark checks still belong inside Pitak. |
| Import remote items | An explicit import/merge feature with identity, conflict, provenance, and zero-data-loss rules; never a side effect of viewing. |
| Richer layouts/preferences | Evidence that the single native list is insufficient; persist preferences separately from the remote cache decision. |
| Lower/higher capacity | Real device measurements and an ADR/plan amendment; never a silent truncation or unbounded read. |

The guiding constraint is deliberately small: **a saved row opens a safe native view of its current public payload, and nothing else happens.**
