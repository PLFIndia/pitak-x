# ADR 0018: Revalidated saved copies of a saved library's published files

- **Status:** Accepted (supersedes decision 3 of ADR 0015)
- **Date:** 2026-10-30

## Context

ADR 0015 decision 3 made the native viewer "fetch on open, no persistent
cache": every tap on a saved library downloaded its whole `books.json` (up to
64 MiB) and `events.json` again, and a library that could not be reached
showed only an error. Its Consequences, and Part E of `appViewer_plan.md`,
deferred persistent caching until a concrete requirement and an ADR covering
freshness, eviction, storage caps, delete-on-remove, restore and backup
exclusion.

The requirement arrived (2026-10-30): *keep a copy, and download only when the
remote file differs from the local one, decided by comparing hashes.* The
product owner then chose:

1. **Check first.** Ask the library's host before showing anything; a
   reachable library always shows its current version.
2. **Saved copy with a note** when the host cannot be checked.
3. **Both files:** the catalogue and the events.
4. **200 MB cap**, least recently opened libraries removed first.

How to learn "has it changed?" without downloading it: both publish hosts
already send an **entity tag** (`ETag`) with every file and honour
`If-None-Match`, answering `304 Not Modified` with no body when the tag still
matches. Verified 2026-10-30: a GitHub Pages site answered a conditional
request with `304` and 0 bytes, even with `Cache-Control: no-cache`;
Cloudflare documents its static-asset ETag as a hash of the file. Pitak's
Cloudflare deployment is assets-only and its `_headers` do not remove the tag.

The alternative — publishing our own SHA-256 next to each file — was rejected:
it changes the public wire contract, works only after every library
republishes with a new build, and still needs a request per open (two, in
fact: the hash file, then the file).

## Decision

**The viewer keeps one saved copy of each library's `books.json` and
`events.json`, and revalidates it with the host's entity tag on every open.**

1. **Algorithm (one place: `PublishedFileLoader`).** Record the open; read the
   saved copy's info; send its tag as `If-None-Match`.
   - `200` → decode; save only bytes that decoded; show as current.
   - `304` → read the saved bytes, verify, decode again, record the
     confirmation; show as current. A gone/damaged/unreadable copy is deleted
     and the file is fetched once more without a tag.
   - `404` (events only) → delete the saved copy; show no events.
   - Any failure → show the saved copy with a **note** (when it was last
     confirmed + one plain reason: unreachable / not served / unreadable);
     with no usable copy, the typed error as before.
2. **Tags are untrusted input.** `EntityTag.sanitize` accepts only the RFC
   9110 shape (`[W/]"…"`, visible ASCII, ≤ 256 chars) on the way in, on disk
   and on the way out, so a tag can never inject a header. A bad tag means
   "no tag": a full download.
3. **The core fetcher gains a conditional mode, not a new outcome for
   everyone.** `BoundedHttpFetcher.fetchConditional` returns
   `ConditionalFetchOutcome` (`FetchedBytes` with `entityTag`,
   `FetchNotModified`, `FetchRefused`); plain `fetch` keeps returning
   `BoundedFetchOutcome`, so cover, descriptor and read-back callers are
   untouched. `304` counts only when a tag was sent. Every existing defence
   (allow-list per hop, abortable deadline, streamed byte cap) is unchanged.
4. **Our own SHA-256 guards the copy on disk.** Every saved file's SHA-256 and
   size live in `index.json`; bytes are handed out only when both match, and
   a mismatch deletes the copy. The same hash skips rewriting identical bytes
   (GitHub Pages changes its tag on every deploy even when a file did not
   change). A copy is identified by its hash, so a byte read or a confirmation
   can never act on a copy that was replaced in between.
5. **Storage: the OS cache directory.**
   `<app cache>/published_copies/<sha256(site URL)>/{catalogue,events}.bin`
   plus `index.json`. Android and iOS exclude this directory from device and
   cloud backups, the OS may clear it under storage pressure (the next open
   simply downloads again), and it is outside the data generations, so the
   `.pitabak` backup never contains it. No Drift table, no schema change.
6. **Freshness is explicit.** A copy is never shown as current unless the host
   served or confirmed it during this open. There is no background refresh
   and no time-based expiry: a reachable host decides, every time.
7. **Cap and eviction.** 200 MiB for all copies together
   (`PublishedFileCache.maxTotalBytes`). After a save that goes over, whole
   libraries are removed, least recently **opened** first (ties by key), never
   the library being saved. A single file larger than the cap is not saved.
   (The largest legal library is 64 MiB + 64 KiB, so the cap holds at least
   three of the largest.)
8. **Delete-on-remove, restore and moves: one hook.** Every load of the saved
   list (`NetworkController.build`) calls `retainOnly(saved site URLs)`, which
   deletes copies of libraries no longer saved and sweeps orphan folders and
   leftover temp files. Remove, a backup restore and an accepted address move
   all end with that reload. The viewer is reachable only from a saved row,
   so an orphan copy can never be shown even before the sweep runs.
9. **Never fatal, always serialized.** Every store operation runs on one
   `SerialOpQueue` (the store is a keepAlive provider so there is exactly one
   queue); writes are tmp + flush + rename; the data file is written before
   the index that vouches for it, and the index before evicted files are
   deleted. Any IO failure is a typed result and a debug-only log line with
   the exception type (never a path); viewing continues without a copy.
10. **Covers and posters are unchanged:** still consent-gated, downscaled and
    memory-only (ADR 0015 decision 11). Only the two JSON files are saved.

## Consequences

- An unchanged catalogue costs one conditional request and no body; an
  unreachable library still opens, clearly labelled as a saved copy.
- **Privacy:** the device now stores copies of other libraries' public
  catalogues and events, and sends back the host's tag. A host that controls
  its own tags (a hand-written Cloudflare Worker, not a GitHub Pages site) can
  recognise a returning device across IP changes; the request itself was
  already observable. `PRIVACY.md` item 5 says both.
- On GitHub Pages any republish (even events-only) changes every tag, so the
  next open downloads `books.json` again — wasted data, never stale content.
- Opening now does a little file IO before the request (the saved info) and,
  on `304`, reads and hashes the saved file (off the UI isolate above 1 MiB).
- Enforcement: `published_file_loader_test.dart` (every branch),
  `file_published_file_cache_test.dart` (verification, atomic layout, path-safe
  keys, cap/eviction, never fatal), `entity_tag_test.dart`, the conditional
  cases in `bounded_http_fetcher_test.dart` and both adapter suites,
  `network_controller_test.dart` (delete-on-remove), and the viewer page
  tests for the saved-copy note.
