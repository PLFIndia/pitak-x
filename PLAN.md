# PLAN.md — Session 12: M09 remote covers → allow-listed one-time fetch, persisted as local covers

## Understanding

Only M09 is in scope (`fix-schedule.md` §1 NEXT). M08 stays IN PROGRESS
pending device verification (no Android device/AVD attached this session —
`flutter devices` lists macOS + Chrome only).

What the code does today (re-verified 2026-09-09; lines unchanged since review):

1. `lib/core/widgets/book_cover.dart:57–79`: a non-local cover ref passes
   `CoverPaths.remoteUrlOf` (transport-only: "starts with https://") and, if
   the Settings opt-in is on, goes straight to
   `CachedNetworkImage(imageUrl: remoteUrl)`. **No host allow-list, no redirect
   check, no byte cap, no timeout**, and a third-party disk cache
   (`flutter_cache_manager` default: `followRedirects = true`, uncapped body
   piped to `getTemporaryDirectory()/libCachedImageData`, URL index in sqflite
   — `flutter_cache_manager-3.4.1/lib/src/web/{file_service,web_helper}.dart`).
   Every scroll past the row while the cache is cold is a network hit.
2. The publish path is correct: `bounded_cover_fetcher.dart` enforces
   `CoverUrlAllowList.sanitize` on the initial URL AND on every redirect hop
   (manual following), a streamed 8 MiB cap, and a 15 s whole-fetch deadline.
3. `PRIVACY.md:68–71` promises "downloaded over https from a fixed allow-list
   of cover hosts." Only publish keeps it.
4. `CoverUrlAllowList` (`features/publish/domain/cover_url_allow_list.dart`)
   is the single source of truth for hosts (viewer CSP lockstep-tested);
   `add_book_page`/`add_wishlist_page` persist lookup covers only when it
   passes (N02).
5. Photo covers: `BookCoverController.replaceCover`
   (`features/library/application/book_cover_controller.dart:37–68`) =
   `ImageDownscaler.downscaleJpeg` → `CoverFiles.saveJpeg` → `repo.update`
   (rollback: delete new file) → `janitor.releaseReference(old)` →
   `ref.invalidate(libraryControllerProvider)`.
6. Two write paths can today replace a LOCAL photo ref with an incoming
   `https://` ref: `import_library_use_case.dart:294–296` (`_mergeIntoExisting`
   takes any non-empty incoming cover) and
   `merge_library_use_case.dart:295–297` (`takeTheirs` copies the whole
   incoming row). `add_book_page.dart:218–219` already keeps the existing
   cover (N02).
7. `library_merge_engine.dart:351` `_mergeCover` compares only https refs
   (so per-device photo refs are not phantom conflicts). Not a network path.

## Privacy & threat notes

- **Who:** anyone who can plant a `coverUrl` — hostile `.pitabundle`/JSON
  import, QR/merge payload, malicious lookup response, shared catalogue.
- **When:** opt-in on and the poisoned row scrolls into view.
- **Leaks today:** device IP/UA and "viewing this book now" to an arbitrary
  host (incl. via redirect from an allow-listed host); uncapped body = DoS;
  repeated hits while the cache is cold; a sqflite index of viewed URLs.
- **After the fix:** (1) origin check against `CoverUrlAllowList.allowedHosts`
  before any packet leaves; (2) every redirect re-validated; (3) 8 MiB
  streamed cap + timeout; (4) **each URL is contacted at most once** — the
  bytes become an ordinary local cover, so display never touches the network
  again; (5) no third-party cache, no URL index, no temp-dir trail; (6) one
  fetch implementation shared with publish.
- **Photo precedence (user decision):** a user-taken photo is never replaced
  by a remote URL on any path (fetch, import, merge). Enforced in the two
  write paths in Understanding §6 and by construction on the fetch path (a
  row with a photo has no URL to fetch).
- Data minimization: no new fields or tables. A materialised cover is a JPEG
  (EXIF-stripped by the downscaler, same as photos). No telemetry.
- Residual: a 30 s idle timeout on a hostile allow-listed host stalls one
  cover, not the UI (fetch is off the widget's build path, serialised).

## Investigation notes (verified this session)

- `CoverFiles` port (`features/library/domain/cover_files.dart`): `saveJpeg`,
  `deleteFile`, `listLeaves`. `BookRepository.getById(int)` and `update(Book)`
  exist (`domain/repositories/book_repository.dart:28,36`).
- `CoverFileJanitor.releaseReference(String?)` runs under the shared
  `CoverFileCoordinator` FIFO (`cover_file_janitor.dart:88`).
- `ImageDownscaler.downscaleJpeg(Uint8List) → Uint8List?` (`core/images`).
- `BoundedCoverFetcher(client:).fetch(String) → Future<List<int>?>` already
  returns null for non-allow-listed, redirect-escape, non-2xx, over-cap,
  timeout. The `remoteCoverFetcherProvider` (`providers.dart:396–407`) wraps
  it with the downscale — exactly the bytes a local cover needs.
- `BookCover` is a `ConsumerWidget` used by `book_row.dart:48`,
  `book_grid_card.dart:60`, `book_detail_page.dart:356` (detail passes a
  `widget.book` snapshot — N03; the `ValueKey(_coverUrl)` reload trick there
  is unaffected because we invalidate the library list, and the detail page's
  own `_coverUrl` will update when N03 lands).
- `test/core/book_cover_test.dart:66–77` asserts an attacker-shaped host
  (`https://example.com`) IS fetched when the toggle is on — this is the
  reproduction and will be inverted.
- Deps: `cached_network_image` becomes unused → remove (§6 approval; pure
  removal, no new package). `http` + `cross_file` already present.

## Proposed approach

**Principle:** a remote `https://` ref is a *pending download*, not a
displayable image. Display is local-only. With consent (Settings toggle) the
app fetches an allow-listed URL once, through the publish fetcher, and
converts the book into a photo-equivalent local cover via the existing
`replaceCover` pipeline.

1. **`CoverUrlAllowList.remoteHttpsOf(String?) → String?`** (pure, publish
   domain): the https branch of `sanitize` only (rejects `covers/…`). Shared
   by display gating, the materialiser, and the two write-path rules.

2. **`MaterializeRemoteCoverUseCase`** (library application; adapted from
   `BookCoverController.replaceCover`):
   `run(int bookId)`: `repo.getById` (fresh row, not a stale snapshot) →
   if its cover is not an allow-listed https URL → `right(unit)` (already
   local / removed / attacker URL — nothing to do, nothing sent) →
   `RemoteCoverFetcher(url)` (the existing DI port: allow-list + bounds +
   downscale) → null → `left(NetworkFailure)` (leave the URL in place, retry
   later) → `saveJpeg` → `repo.update(copyWith(coverUrl: local))`, rollback
   file on failure → `janitor.releaseReference(old)` is a no-op for https
   but called for symmetry → `ref.invalidate(libraryControllerProvider)`.
   Guarded by a per-session `Set<int>` of in-flight/failed ids so a row is
   fetched at most once per app run even if it scrolls past 50 times, and
   serialised through a small FIFO (one download at a time; bounded memory).

3. **`RemoteCoverMaterializer`** (`@Riverpod(keepAlive: true)` Notifier in
   library application): `request(int bookId)` — checks
   `settings.loadRemoteCovers`, dedups, enqueues. Exposes nothing to the UI.
   Fail-closed: settings unknown → do nothing.

4. **`BookCover`**: `leafOf == null` → placeholder, always. If
   `CoverUrlAllowList.remoteHttpsOf(coverUrl) != null` AND a `bookId` was
   supplied (new optional ctor param; callers `book_row`, `book_grid_card`,
   `book_detail_page` pass `book.id`) → `ref.read(materializerProvider
   .notifier).request(bookId)` in a post-frame callback (side effects out of
   `build`, §7). `CachedNetworkImage` import removed.

5. **Photo precedence rule** — `import_library_use_case._mergeIntoExisting`
   and `merge_library_use_case.applyResolution(takeTheirs)`: incoming cover
   lands only when (a) incoming is non-empty AND (b) existing has no cover OR
   existing is itself a remote ref OR incoming is a LOCAL bundle cover. A
   pure helper `resolveIncomingCover(existing, incoming)` in library domain
   (`cover_precedence.dart`) shared by both; unit-tested on the 3×3 matrix.

6. **Copy:** Settings subtitle names the fixed host list and the one-time
   download; PRIVACY.md/README updated (fixed allow-list now true; "fetched
   once and stored like your own covers"). `pubspec.yaml`: drop
   `cached_network_image` (§6).

OSS reference: same shape as `EventsController.addPoster` /
`BookCoverController.replaceCover` in this repo (borrow, don't invent).

## Decision points

- **D0 — consent model: (a) Settings toggle is the consent; auto-fetch on
  first display. DECIDED (user, 2026-09-09).**
- **D1 — persistence: fetched covers persist as local covers, like photos.
  DECIDED (user).**
- **D2 — photo precedence on import/merge: keep the local cover; take the
  incoming only when there is no local cover. DECIDED (user). Applies to
  merge "take theirs" as well.**
- **D3 — §6: remove `cached_network_image` from `pubspec.yaml`. APPROVED +
  done (user, 2026-09-09).**
- **D4 — execution mode: (a) end-to-end. DECIDED (user).** No pause trigger
  fired.
- Pause triggers (even under end-to-end): any need for a new package; any
  schema change (none expected); `remoteCoverFetcherProvider` proving
  unsuitable for reuse.

## Steps

- [x] 0. Baseline gates: analyze 0, format 381/0, Flutter **1267 passed**
      (`/tmp/pitak-m09-flutter-baseline.4Ip3x2`, 0 `[E]`), Rust 32 (2 ign.).
- [x] 1. Regression tests first. **Red on HEAD (verified by restoring HEAD's
      two use-case files and re-running): 2/2** — import same-uid photo kept
      (`import_library_use_case_test.dart`), merge takeTheirs photo kept
      (`merge_library_use_case_test.dart`). `book_cover_test.dart` rewritten
      (fail-to-compile red on HEAD: `remoteCoverMaterializerProvider` and the
      `bookId` param did not exist; its old "attacker host IS fetched" test
      was the reproduction and is now inverted). New:
      `cover_precedence_test.dart` (8), `materialize_remote_cover_use_case_test.dart`
      (9), `remote_cover_materializer_test.dart` (6), `remoteHttpsOf` (3).
- [x] 2. `CoverUrlAllowList.remoteHttpsOf` (shared https branch of `sanitize`).
- [x] 3. `lib/features/library/domain/cover_precedence.dart` +
      wired into `_mergeIntoExisting` and `applyResolution(takeTheirs)`.
- [x] 4. `MaterializeRemoteCoverUseCase` (plain class, injected ports) +
      `RemoteCoverMaterializer` keepAlive notifier (consent gate, once-per-book,
      FIFO) + `materializeRemoteCoverUseCaseProvider` (reuses
      `remoteCoverFetcherProvider` — the publish fetcher + downscale).
- [x] 5. `BookCover` → `ConsumerStatefulWidget`, local-only render, request
      from `initState`/`didUpdateWidget` via post-frame callback; `bookId`
      passed by `book_row`, `book_grid_card`, `book_detail_page`.
- [x] 6. D3 approved → `cached_network_image` removed from `pubspec.yaml`;
      `pub get --offline` pruned 12 transitive packages (incl.
      `flutter_cache_manager`, `sqflite*`, `rxdart`, `synchronized`); no
      additions; `macos/Flutter/GeneratedPluginRegistrant.swift` regenerated
      (drops `sqflite_darwin`). `.fvmrc`/`.gitignore` untouched.
- [x] 7. Copy: `settings_page.dart` subtitle; PRIVACY.md §2; README posture line.
- [x] 8. Gates: analyze **0**; format **388 files / 0 changed**; full Flutter
      `--no-pub --coverage` **1299 passed / 0 failed** (+32;
      `/tmp/pitak-m09-flutter-final.gucf0W`, 0 `[E]`); Rust **32 passed**,
      2 expected ignored; `git diff --check` clean; build_runner rerun → only
      the 2 expected generated files differ; `flutter build apk --debug
      --flavor fdroid --target-platform android-arm64` **succeeded**.
- [ ] 9. Commit → approval (manifest below).

## Commit manifest (27 paths; never `astra-review.md` / `fix-schedule.md` / `.fvm/`)

```
git add PLAN.md PRIVACY.md README.md pubspec.yaml pubspec.lock \
  macos/Flutter/GeneratedPluginRegistrant.swift \
  lib/core/di/providers.dart lib/core/di/providers.g.dart \
  lib/core/widgets/book_cover.dart \
  lib/features/import_export/application/import_library_use_case.dart \
  lib/features/import_export/application/merge_library_use_case.dart \
  lib/features/library/application/materialize_remote_cover_use_case.dart \
  lib/features/library/application/remote_cover_materializer.dart \
  lib/features/library/application/remote_cover_materializer.g.dart \
  lib/features/library/domain/cover_precedence.dart \
  lib/features/library/presentation/pages/book_detail_page.dart \
  lib/features/library/presentation/widgets/book_grid_card.dart \
  lib/features/library/presentation/widgets/book_row.dart \
  lib/features/publish/domain/cover_url_allow_list.dart \
  lib/features/settings/presentation/pages/settings_page.dart \
  test/core/book_cover_test.dart \
  test/features/import_export/import_library_use_case_test.dart \
  test/features/import_export/merge_library_use_case_test.dart \
  test/features/library/cover_precedence_test.dart \
  test/features/library/materialize_remote_cover_use_case_test.dart \
  test/features/library/remote_cover_materializer_test.dart \
  test/features/publish/cover_url_allow_list_test.dart
git commit -m "sec(covers): allow-listed one-time cover download stored as local cover (M09)"
```

## Out-of-scope observations

- `library_merge_engine.dart:351` `_mergeCover` compares any https ref; after
  M09 a materialised cover becomes local on this device, so two devices that
  both materialised the same URL now compare as `null == null` (equal) —
  fine; and a device that materialised vs one that did not compare
  `null != url` → conflict surfaced. Acceptable but note for N07.
- `CoverPaths.remoteUrlOf` remains transport-only; its only lib consumer after
  M09 is the merge engine. Leave for N07.
- Old `libCachedImageData` temp cache from earlier builds is not deleted
  (OS-managed temp dir). One-time purge possible later.
- `BookDetailPage` still renders a `widget.book` snapshot (N03), so a cover
  materialised while the detail page is open appears after leaving and
  re-entering. N03 fixes the observation model.
- Wishlist rows have `coverUrl` but no cover widget in the wishlist UI today;
  materialisation is library-only in this session.
- N08 (abortable HTTP/global caps) still open.

## Result

**M09 implemented; commit pending approval.**

- **What changed (plain English):** the app no longer streams book covers from
  the internet while you scroll. A web cover link is treated as "not yet
  downloaded". If you have turned on "Load cover images from the internet",
  the app downloads that cover **once**, only if the link points at Open
  Library or Google Books (the same fixed list the published website uses),
  through the same size/time/redirect-checked fetcher publishing uses, and
  then saves it as an ordinary local cover — exactly like a photo you took.
  From then on it is part of your library (backups, bundles, cleanup) and no
  request is ever made for it again. Links to any other host are never
  contacted. A photo you took yourself is never replaced by a downloaded
  cover, whether via download, import, or merge "take theirs".
- **Verification:** 1299 Flutter / 32 Rust passed; analyzer 0; format clean;
  debug fdroid APK builds. Coverage: `cover_precedence` 7/7,
  `materialize_remote_cover_use_case` 18/18, `remote_cover_materializer`
  21/21, `cover_url_allow_list` 21/21, `book_cover` 47/49 (95.9%); project
  68.51% (CI floor 64%). Narrow diff scan: no print/log/http/Uri/Platform
  added in lib. Domain purity gate passed (`cover_precedence.dart` imports
  only `cover_paths.dart`).
- **Evidence re-verified in current code:** `book_cover.dart` no longer
  references `CachedNetworkImage`/`remoteUrlOf`; the only remaining lib
  consumer of `CoverPaths.remoteUrlOf` is the merge engine's field comparison
  (not a network path). `rg cached_network_image lib test` → one comment.
- **Honest limits:** no physical-device verification (no device attached);
  the fetch path is exercised through the injected `BoundedCoverDownload`
  port, and `BoundedCoverFetcher` itself is unchanged and covered by its
  existing tests. `BookDetailPage` still shows a `widget.book` snapshot
  (N03), so a cover materialised while the page is open appears on
  re-entry. A failed download is not retried until the next app start
  (deliberate: bounds traffic to a hostile-but-allow-listed host). The
  previously cached `libCachedImageData` temp directory from older builds is
  left to the OS temp cleaner.
- **OSS credit:** pipeline adapted from this repo's
  `BookCoverController.replaceCover`; FIFO adapted from this repo's
  `CoverFileCoordinator` (synchronized BasicLock, MIT).
