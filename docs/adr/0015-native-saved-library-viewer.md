# ADR 0015: Native viewer for a saved library's published catalogue

- **Status:** Accepted; decision 3 superseded by
  [ADR 0018](0018-revalidated-saved-copies-of-published-files.md)
- **Date:** 2026-10-25

## Context

A saved Library-network row (ADR 0012) could only be *opened in the browser*.
The catalogue already exists as the published `books.json` that the bundled
web viewer (`assets/publish/index.html`) reads, and the app already reads a
sibling file, `library.json`, through
`BoundedHttpFetcher` + `LibraryDescriptorCodec` (docs/ARCHITECTURE.md §5.6).

People asked to browse a library they saved *inside* Pitak. Three product
promises constrain that: **P1** no silent data downgrade (a viewer must never
imply data it does not have — `addedDate` is redacted, availability is a
coarse publish-time snapshot), **P2** hostile input and privacy (the payload
comes from anyone's public site, and reading it reveals the device's IP and
User-Agent), and **P3** no new F-Droid risk (no plugin with Google
dependencies, no WebView).

The naive options all fail:

- a WebView renders untrusted HTML/JavaScript **inside** the app process, which
  the repo has always refused;
- reconstructing local `CatalogueItem`/`Periodical` rows invents local IDs,
  lending semantics and editing behaviour that the payload does not carry,
  inviting an accidental import;
- `Image.network` for covers bypasses every existing cover policy
  (`CoverUrlAllowList`, byte caps, decode guards, the remote-cover consent);
- an `addedDate` "Recently added" sort would sort on a field that
  `redactForPublish` deliberately strips.

## Decision

**A saved network row opens a read-only, native, memory-only view of that
library's current published `books.json`.** Concretely (plan
`appViewer_plan.md`, decisions V1–V18):

1. **Every** saved row is eligible (`bookmark`, `card`, `discovered`); the
   route is reachable only from the saved list, so the row *is* the proof of
   intent — no bookmark lookup, no deep link, no custom scheme (V1, V4, V17).
2. **Native, read-only, no WebView.** Separate published-view models
   (`PublishedCatalogue`, `PublishedCatalogueItem`, …) are decoded from the
   wire at the infrastructure boundary. No local entity is reconstructed, no
   edit/lend/import/merge action exists (V2, V3).
3. **Fetch on open, no persistent cache.** One GET of `books.json` per
   explicit open; data lives only in auto-dispose, screen-scoped providers.
   No Drift table, file, backup entry, ETag or background refresh (V5).
   *Superseded 2026-10-30 by ADR 0018:* each open still asks the host first,
   but a saved copy is revalidated with its entity tag (`304` = no download)
   and is shown, with a note, when the host cannot be checked. Still no Drift
   table, backup entry or background refresh.
4. **Forward-tolerant reader.** `books.json` schema 1 is read; declared
   schema > 1 still renders the fields this build understands with a
   *persistent* visible warning. Unknown keys are ignored, never retained
   (V6).
5. **Reader and writer models stay separate.** The native reader validates
   more defensively than the publish writer constructs; a network→publish
   application dependency would create a cycle. Compatibility is pinned by
   shared fixtures (V7).
6. **"Published order" is the default sort**, preserving payload order and the
   original row index as the stable tie-break. No "Recently added" sort
   exists anywhere in the UI (V8).
7. **Tolerant display, never coercion.** Only an absent `kind` means `book`;
   the exact `book`/`magazine-issue`/`other` tokens map to their kinds; any
   other value becomes `unknown` and renders as a plain item (V9).
8. **Viewer-owned HTTP lifetime.** `publishedViewerHttpClient(siteUrl)` owns a
   separate inner client; every load carries a monotonic revision and a
   caller-abort trigger completed on dispose; the client closes as the final
   backstop and never touches the shared Refresh/Publish client (V12).
9. **Caller abort is a core capability.** `BoundedHttpFetcher.fetch` accepts an
   optional abort signal (chained to its own deadline), so disposing the route
   closes the socket instead of merely ignoring bytes.
10. **Catalogue and same-site cover redirects never leave the saved library.**
    A pure `PublishedSiteUrlPolicy` requires the normalized origin *and* the
    saved site's directory on the initial URL and on every hop; another Pages
    host, another library on the same host, or a directory escape is refused
    (V18).
11. **Two cover origin classes, one consent gate.** Relative `covers/…`
    references resolve against the saved site root; absolute covers must pass
    the existing `CoverUrlAllowList`. **Both** classes require
    `AppSettings.loadRemoteCovers == true` — the row tap authorizes
    `books.json` only, deliberately stricter than the web viewer (V11).
    Covers are downscaled in a worker isolate, cached in memory only (bounded
    by entry count and bytes), and never written to disk (V11).
12. **The browser stays a deliberate fallback** on every loading/empty/error
    state, launched only after re-running `BookmarkUrl.sanitize` on the saved
    URL with `LaunchMode.externalApplication` (V10).
13. **Identity conflicts are shown, never repaired.** Loading a catalogue
    writes no fingerprint and no network row; a current conflict keeps its
    visible warning and the browser fallback (V15).
14. **No new dependency, no schema/backup/manifest change.** Riverpod codegen,
    `fpdart`, `http`, `image`, existing value objects and test helpers only
    (V14).
15. **Every non-generated Dart file stays ≤ 500 lines.** Reader, query, controls,
    list, detail and cover scheduling are separate files; the file-size
    ratchet gains no entry (V16).

### Deliberate deviations recorded during implementation

- **Hand-written immutable UI state, not `freezed`.** The plan's file list
  named `*.freezed.dart` for the query and cover state. The repository has
  never used `freezed` in `lib/features`: `NetworkWindow`, `AppSettings`,
  `RefreshReport` and `RestoreSummary` are plain immutable classes, and
  `network_controller.dart` records the "one blessed way" reasoning
  (AGENTS §0) for keeping it that way. The query/cover state is therefore a
  plain immutable class with a small `copyWith`, so no new generated-file
  class enters the tree. Immutability — the actual requirement — is
  unchanged, and `select`-based rebuild scoping still applies.
- **Golden PNGs are a release blocker, not part of the code change.** The
  viewer's two goldens must be rendered by the Linux `update_goldens`
  workflow; a macOS-rendered PNG is forbidden, so the names/renders land with
  the PNGs rather than leaving the always-on existence guard red.
- **New-mount invalidation runs in `didChangeDependencies`, not `initState`.**
  Riverpod 2.6.1 reaches the `ProviderScope` through an inherited widget, which
  `initState` may not touch. The first `didChangeDependencies` fires before the
  first build, so the session guarantee is unchanged.
- **Device evidence is tracked, not faked.** The 20 000-row decode/query
  budget and the lazy-list assertion are automated; the real-device
  measurement and TalkBack walk are steps in `docs/RELEASING.md` §6.1.
- **Consent is discoverable without being weakened (2026-10-26).** When a
  loaded catalogue or its events contain images and the setting is off, the
  viewer explains the existing choice and offers **Load covers**. The action
  persists the same opt-in; decision 11 still applies equally to same-site and
  third-party images. Native events themselves are specified by ADR 0016.

## Consequences

- The published catalogue is readable offline-of-the-browser, but **not
  offline**: closing the route discards the catalogue, the cover cache and any
  in-flight sockets, and a later open fetches again. Persistent caching needs
  its own freshness/eviction/restore ADR before a table is added (Part E of
  the plan). *That ADR is 0018 (2026-10-30): saved copies of `books.json` and
  `events.json`, revalidated on every open; covers stay memory-only.*
- Reading a catalogue (and each visible cover) tells the library's host the
  device's IP and User-Agent. That is why consent is explicit, the payload is
  bounded (64 MiB body / 100 000 rows / 30 s for `books.json`, 8 MiB / 15 s for
  a cover), and `PRIVACY.md` states it.
- `books.json` stays the single wire contract: no writer change, no schema
  bump, no redaction change. A future field must be additive and read
  defensively here too.
- The reader must keep agreeing with the HTML viewer. Shared fixtures plus
  writer→reader tests pin the grouping/duplicate rules; a divergence is a
  failing test, not a silent behaviour change.
- `NetworkMapPage`'s pin sheet "Open site" action remains an external-browser
  action; only the saved-list row changed.
- Enforcement: `test/architecture/layer_boundaries_test.dart` (size, no
  infrastructure imports in presentation), the new codec/query/cover/fetcher
  suites, and the integration journey.
