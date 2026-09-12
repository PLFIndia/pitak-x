# PLAN.md — Session 22: N08 — network deadlines that actually stop the work

## Understanding

`astra-review.md` N08: "Network deadlines do not reliably stop the underlying
work." Every cited pattern is LIVE in current code (re-read this session; the
review's line numbers are stale, the code is not):

1. **`bounded_cover_fetcher.dart:73`** — `_fetchBounded(uri).timeout(timeout)`.
   `Future.timeout` (SDK `future_impl.dart:1032-1075`) only stops *waiting*:
   when the timer fires it completes the outer future with `TimeoutException`
   and does nothing to the inner future. The socket stays open, the body keeps
   streaming into the `BytesBuilder`, and the redirect loop keeps hopping
   until the inner `_fetchBounded` finishes on its own. A slow-loris host
   holds a connection + memory for as long as it likes; the caller merely
   stopped watching.
2. **`bounded_cover_fetcher.dart:116-140`** — rejected responses (redirect
   hops, non-2xx, oversized Content-Length) are `drain()`ed **without a byte
   bound**: `unawaited(response.stream.drain<void>())` reads the whole body
   to /dev/null. An attacker's 404 page can be gigabytes; we download all of
   it. The cap only protects the ACCEPTED path.
3. **`lookup_http_client.dart:63-76`** — the retry decorator gets `first`
   (429/5xx), backs off, sends the retry and returns it. `first.stream` is
   **never listened to or cancelled** — a dangling connection per retried
   request (the `http` package's own `RetryClient` explicitly cancels it,
   `retry.dart:139-141`).
4. **`timeout_http_client.dart:38-61`** — the shared client bounds connect
   (`send().timeout`) and per-chunk idle (`Stream.timeout`) but has **no total
   deadline** and **no body byte cap**. A body trickling one byte every 59 s
   never times out; a `Response.fromStream` (`BaseClient.get` → `toBytes()`)
   buffers an unbounded body. Every JSON call (`HttpGitHubApi`, both lookup
   services) and the publish read-back (`providers.dart:457-468`
   `client.get(...).bodyBytes`) go through this path unbounded. And the
   connect timeout is again `Future.timeout` — the dead-socket request is
   abandoned, not aborted.
5. The read-back budget in `publish_library_use_case.dart:139-145` counts 12
   × 5 s sleeps only; each poll's own HTTP time (up to 60 s connect + 60 s
   idle chunks × N) is unbounded on top — "60 s budget" is not what happens.
   (Bounding each request with a total deadline at the shared client fixes
   the arithmetic without touching the use case.)

**What the platform offers (verified in pub-cache source, not memory):**

- `http` **1.6.0** is what `pubspec.lock:579-586` resolves (constraint
  `^1.2.2`). 1.5.0 added `Abortable` (`CHANGELOG.md:11-15`):
  `AbortableRequest(method, url, {abortTrigger})` (`request.dart:216-220`);
  `IOClient.send` (`io_client.dart:141-147, 165-173`) calls
  `HttpClientRequest.abort()` before headers arrive and injects
  `RequestAbortedException` + cancels the socket subscription while the body
  streams. **No new package is needed.** `MockClient` does not abort by
  itself (`mock_client.dart:31-33`) — tests use a hand-rolled inner client
  that honours `abortTrigger`, plus one real loopback `HttpServer` test to
  prove the socket really closes.
- `BaseClient.get/post/patch` build a plain `Request` (`base_client.dart:77`)
  — callers cannot pass an abortable one. So the abort has to be added INSIDE
  our decorator: `TimeoutHttpClient.send` wraps the incoming request in an
  `AbortableRequest` whose trigger is our deadline timer. Body bytes of a
  finalised `Request` are copyable (`bodyBytes`), so the copy is lossless for
  every request type this app sends (no `MultipartRequest`/`StreamedRequest`
  anywhere in `lib/` — grep confirmed).
- `Stream.timeout`'s `onTimeout` sink close → `controller.close()` →
  `onCancel` → `subscription.cancel()` (`stream.dart:2094-2102`), so the idle
  path already cancels its source; the **connect** path and the **caller-side
  `Future.timeout`** do not.

## Privacy & threat notes

No new data leaves the device; no new hosts; no storage change; no secrets
touched. The change REDUCES exposure:

- **Who could act:** any host we talk to — GitHub (auth'd), Open Library,
  Google Books, the allow-listed cover hosts, and a GitHub Pages origin for
  the read-back — or a network middlebox on the path.
- **What they could do today:** hold a connection open indefinitely (battery,
  data, a wedged publish that the 60 s "budget" does not actually bound);
  make the device download an unbounded rejected body (data, memory); make
  a retried lookup leak one open connection per retry.
- **What stops them after this session:** a per-request total deadline that
  aborts the socket; a body byte cap on every response, accepted or rejected;
  cancellation of every discarded stream. Fail closed: over-cap/over-deadline
  → `ClientException` (same family callers already map to safe messages —
  `HttpGitHubApi._guard`, lookup `on Object` → fixed copy, fetcher → null).
- **Diagnostic (N11 D4-b):** a refused cover download currently vanishes
  silently. Adding a typed refusal reason to the fetcher's return and a
  debug-only `debugPrint` in `RemoteCoverMaterializer` (book id + reason
  enum, NEVER the URL — S17 precedent: `ClientException.toString()` embeds
  the URL) keeps AGENTS.md §6.2 (no URLs/PII in logs) and §3.4 (no
  telemetry). `debugPrint` is a no-op in release builds only if wrapped in
  `kDebugMode`; `screen_security.dart:69` is the existing precedent.
  **Layer check:** `RemoteCoverMaterializer` is `application/`;
  `package:flutter/foundation.dart` is NOT on the N14 forbidden list
  (`domain_purity_test.dart:142-150`) but no application file imports Flutter
  today except via riverpod. Decision D4 below.

## Investigation notes

- Consumers of the shared client (`providers.dart`): `httpClient` (60 s) →
  `HttpGitHubApi`, `remoteCoverFetcher` (→ `BoundedCoverFetcher`),
  `publishedFileFetcher`; `lookupHttpClient` (10 s, + `LookupHttpClient`) →
  `OpenLibraryLookupService`, `GoogleBooksLookupService`.
- `BoundedCoverFetcher` (S12) is the single cover path for publish AND
  display (`materialize_remote_cover_use_case.dart:75`). Both typedefs
  (`RemoteCoverFetcher`, `BoundedCoverDownload`) are `Future<List<int>?>
  Function(String)`; 7 test call sites construct fakes for them.
- Largest legitimate responses through the shared client: GitHub
  `/git/trees/…?recursive=1` for a big library (≈150 B/entry; 100 k covers ≈
  15 MiB — GitHub truncates at 100 k entries/7 MB anyway), the publish
  read-back of `books.json` (the app's own file; a 100 k-row catalogue ≈
  30–50 MiB), lookup JSON (KBs). GitHub blob uploads are REQUEST bodies (not
  capped by this change; the fetcher's 8 MiB cap already bounds their
  source).
- Existing tests: `timeout_http_client_test.dart` (3, hand-rolled inner
  clients), `lookup_http_client_test.dart` (9, `MockClient`),
  `bounded_cover_fetcher_test.dart` (17, `MockClient.streaming`). None
  observes whether the SOURCE stopped — exactly the gap the review names.
- Baseline (this session, pinned SDK): analyzer 0; format 401/0; Flutter
  **1441 passed / 0 failed** (`/tmp/pitak-s22-flutter-baseline.txt`, 0
  `[E]`); cargo **32 passed**, 2 expected ignored. HEAD = `origin/main` =
  `da540a8`; tracked tree clean.

## Proposed approach

Fix the foundation once, at the shared client, so every consumer inherits
it; then remove the caller-side `Future.timeout` that hid the problem.

### A. `TimeoutHttpClient` → real deadlines + byte cap (core/network)

Rename nothing (one blessed way; the DI wiring stays). New behaviour:

1. **Abortable send.** Wrap the incoming request in an `AbortableRequest`
   (copy method/url/headers/bodyBytes/followRedirects/maxRedirects/
   persistentConnection — same copy the `http` `RetryClient` does,
   `retry.dart:151-176`). The `abortTrigger` is a `Completer` we complete
   when EITHER the connect timer, the idle timer, or the total-deadline
   timer fires. `IOClient` then tears down the socket. Replaces
   `send().timeout(...)` (which only abandoned the future).
2. **Total deadline** (`Duration totalDeadline`, default: 60 s shared /
   30 s lookup — D1 below) — a single timer armed before `send`, cancelled on
   stream done/cancel/error; on expiry completes the abort trigger AND
   errors the response stream with `ClientException('Request exceeded …')`.
3. **Body byte cap** (`int maxResponseBytes`, default 64 MiB — D2 below):
   counted in a `StreamTransformer` on the body; on overflow → cancel the
   source subscription, complete the abort trigger, `addError(ClientException
   ('Response exceeded N bytes'))`, close. `Response.fromStream` then throws
   instead of buffering — callers already handle `ClientException`.
4. Wire all three timers to ONE `_Deadline` helper so a body that completes
   normally cancels every timer (no leaked timers — the widget-test "pending
   timer" invariant, S19 lesson).

Reference: `package:http` `RetryClient` request copy + stream cancel
(BSD-3, dart-lang/http); `IOClient` abort semantics (same package).

### B. `LookupHttpClient` — cancel the discarded first response

On the retry path, `unawaited(first.stream.listen((_) {}).cancel())` before
sending the retry — verbatim the `RetryClient` idiom (`retry.dart:139-141`).
Also cancel the retry's stream when we fall back to `first` after the retry
throws (nothing to cancel — the throw means no response — noted for
completeness).

### C. `BoundedCoverFetcher` — no caller-side `Future.timeout`; bounded
rejects; typed refusal

1. Drop `.timeout(timeout)` around `_fetchBounded`. Instead pass the
   deadline INTO the request via `AbortableRequest` + a per-fetch
   `Completer` — the fetcher's own 15 s stays (it is tighter than the shared
   60 s) but now aborts the socket. (The fetcher builds its own
   `http.Request` at `:112`, so it can make it abortable directly.)
2. Every rejected response (redirect hop, non-2xx, oversized declared
   length): **cancel** the stream (`listen((_){}).cancel()`) instead of
   `drain()`. Connection reuse is not worth an unbounded read; `IOClient`
   closes the socket on cancel (`io_client.dart:198 onCancel`).
3. The accepted path's over-cap `return null` inside `await for` already
   cancels the subscription (Dart semantics) — keep, but ALSO complete the
   abort trigger so `IOClient` tears the socket down immediately rather than
   on GC.
4. **Typed refusal (N11 D4-b):** `fetch` returns `CoverFetchResult` — sealed:
   `CoverFetched(bytes)` | `CoverRefused(CoverRefusal reason)` with
   `enum CoverRefusal { disallowedUrl, redirectRefused, tooManyRedirects,
   httpStatus, tooLarge, timedOut, transport, notAnImage }`. The `List<int>?`
   port typedefs (`RemoteCoverFetcher`, `BoundedCoverDownload`) stay as they
   are (publish only needs bytes-or-null) — the DI adapter in `providers.dart`
   maps the result and, for the materialise path, feeds the reason to the
   diagnostic. D3 decides how far the type travels.

### D. `RemoteCoverMaterializer` — debug-only refusal diagnostic

On a `Left`: `if (kDebugMode) debugPrint('remote cover: book <id> refused
(<reason>)')`. No URL, no host. Needs the reason to reach the materializer —
D3.

### E. Tests (regression first, red on HEAD)

- `test/core/timeout_http_client_test.dart` +N08 group:
  (a) **connect timeout aborts the request**: inner client records whether
  `request is Abortable && abortTrigger completed` — red on HEAD (plain
  `Request`, never aborted);
  (b) **total deadline** — a body that emits one byte every 30 ms with a
  40 ms idle timeout but a 100 ms total deadline errors out — red on HEAD
  (no total deadline; the idle timer keeps re-arming);
  (c) **byte cap** — a 3-chunk body over `maxResponseBytes` → `get()` throws
  `ClientException`, source subscription cancelled (inner `onCancel` flag) —
  red on HEAD (buffers all);
  (d) timers: a normal completion leaves no pending timers (`fakeAsync`).
  (e) **loopback proof**: a real `HttpServer` on 127.0.0.1 that never
  answers; assert the server's connection count drops to 0 after the
  timeout (the review explicitly asks for cancellation to be tested, not
  just the returned error) — red on HEAD (socket stays open until test
  teardown).
- `test/core/lookup_http_client_test.dart` +1: the discarded 429 response's
  stream is cancelled (`MockClient.streaming` with an `onCancel` hook) — red
  on HEAD.
- `test/features/publish/bounded_cover_fetcher_test.dart` +N08 group:
  a rejected 404 body is NOT read past the first chunk (chunk counter) — red;
  a redirect hop body is cancelled — red; the timeout completes the abort
  trigger — red (no trigger exists); each `CoverRefusal` variant is returned
  for its case — compile-red.
- `test/features/library/remote_cover_materializer_test.dart` +1: a refused
  download emits exactly one debug line containing the book id and reason
  and NOT the URL (capture via `debugPrint = …` override).

## Decision points

- **D1 — total-deadline defaults:** (a) shared client 60 s total, lookup
  client 30 s total (interactive; 3× its 10 s connect/idle so a healthy slow
  response still finishes); (b) equal to the existing per-phase timeout
  (60/10) — simpler but makes a legitimately slow 8 MiB cover on 2G fail.
  **Recommend (a).**
- **D2 — shared response byte cap:** (a) 64 MiB (matches
  `ImportLimits.maxTextChars`; covers a 100 k-row `books.json` read-back with
  headroom); (b) 16 MiB (tighter; a >~30 k-book read-back would then fail
  "not live" every time — a silent false negative). **Recommend (a)**; the
  cover path keeps its own 8 MiB.
- **D3 — how far the typed refusal travels:** (a) the fetcher returns the
  sealed result; `providers.dart` maps it to bytes-or-null for publish, and
  the `MaterializeRemoteCoverUseCase` port becomes
  `Future<Either<CoverRefusal, List<int>>>` so the use case's `Left` carries
  the reason (`NetworkFailure` stays the outward `Failure`; the reason rides
  in a new `CoverDownloadFailure(reason) extends Failure`… **or** simpler)
  (b) keep both ports `List<int>?`; the fetcher exposes the reason via a
  second, optional `onRefused` callback injected only on the materialise
  path — smaller diff, no `Failure` hierarchy change, publish untouched.
  **Recommend (b)** — the reason is a developer diagnostic, not a domain
  outcome (M09 decision: "a missing thumbnail is not an error the user can
  act on" stands).
- **D4 — where `debugPrint` lives:** (a) in `RemoteCoverMaterializer`
  (application) importing `package:flutter/foundation.dart` — first Flutter
  import in an application file; allowed by the N14 gate, but a precedent;
  (b) inject a `void Function(String)? log` port from `providers.dart`
  (composition root already imports Flutter) — keeps application Flutter-
  free, one more ctor param. **Recommend (b)** (AGENTS.md §3.1 spirit).
- **D5 — execution:** end-to-end, or pause at each decision point?

**Answers (2026-09-12):** D1 **(a)** 60 s / 30 s total · D2 **(a)** 64 MiB ·
D3 **(b)**, refined to **(a)**: the library-side port `BoundedCoverDownload`
returns the sealed `CoverFetchResult` so the use case (which knows the book
id) can call an injected `onRefused(bookId, reason)`; the publish port
`RemoteCoverFetcher` and the `Failure` hierarchy stay untouched · D4 **(b)**
log port injected from `providers.dart` · D5 **(a)** end-to-end.

## Steps

- [x] 1. Baseline recorded (above). Tracked tree clean at `da540a8`.
- [x] 2. Regression tests for `TimeoutHttpClient` — 4 compile-red (new
  params), 2 behaviour-red on HEAD: abort-on-connect (`abortTriggered`
  false) and the LOOPBACK socket test ("server still holds 1 connection 2 s
  after the client deadline"). Probe: a HEAD-shaped `Future.timeout`
  decorator left the raw server socket OPEN at 2209 ms; the new client
  closed it at 218 ms.
- [x] 3. Implemented A (`timeout_http_client.dart`): `_RequestDeadline`
  (total timer + shared abort completer), `AbortableRequest` re-issue,
  `_boundedBody` (idle / total / size, cancel + abort on any trip,
  `onCancel` aborts when the caller drops the body). 12 tests green.
- [x] 4. `LookupHttpClient`: cancel-before-retry — red on HEAD
  (`firstBodyCancelled` false) → green. Retry-failed fallback returns the
  first STATUS with an empty body (the real body was cancelled).
- [x] 5. `BoundedCoverFetcher`: sealed `CoverFetchResult` (moved to
  `publish/domain/cover_fetch_result.dart` so application code can name it
  without importing infrastructure), `AbortableRequest` per hop wired to one
  15 s deadline, `_discard` = cancel-not-drain, over-cap completes the abort.
  5 N08 tests proved red against a HEAD-behaviour graft (rejected bodies
  drained all 10 chunks; abort never fired). 21 tests green.
- [x] 6. `MaterializeRemoteCoverUseCase`: `BoundedCoverDownload` returns the
  typed result; optional `onRefused(bookId, reason)` port. `providers.dart`:
  new `boundedCoverDownload` (single implementation, downscale → typed
  `notAnImage`), `remoteCoverFetcher` maps to bytes-or-null for publish,
  `materializeRemoteCoverUseCase` injects the `kDebugMode`+`debugPrint` port.
  New `test/core/di/remote_cover_diagnostic_test.dart` drives the REAL
  provider and asserts the line has id + reason and NOT the URL/host.
- [x] 7. D1/D2 values + beginner comments on both client providers.
- [x] 8. `build_runner` last: only the expected hash diffs + the new
  provider in `providers.g.dart`; `.fvmrc`/`.gitignore` untouched; warm
  re-run = no diff.
- [x] 9. Gates green (see Result). Lib-diff privacy scan: the ONLY new log
  line is `debugPrint('remote cover: book $bookId refused (${reason.name})')`
  behind `kDebugMode`; no URL/host/exception text reaches any log or
  message; new `ClientException` messages carry a duration/byte count only.
- [ ] 10. fix-schedule.md §1/§3/§5; commit approval with explicit paths.

## Out-of-scope observations

1. `HttpGitHubApi` `_excerpt(resp.body)` still puts up to 200 chars of a
   GitHub response body into `GitHubApiException`/`PublishCommitHttpError`
   messages; the publish use case already drops it for the user-facing copy
   (S4). Unchanged.
2. `TimeoutHttpClient._abortable` passes a non-`Request` (`MultipartRequest`
   / `StreamedRequest`) through unchanged — bounded but not abortable. None
   exists in `lib/` today; if one is ever added it should become abortable
   too (a test asserting "every request the app sends is `Abortable`" would
   catch it — not added, no producer to test).
3. The publish read-back budget (`readBackAttempts × readBackInterval`) is
   now bounded per poll by the shared 60 s total, i.e. worst case ≈ 12 × (5 s
   + 60 s) — still finite, but the "60 s budget" comment in
   `publish_library_use_case.dart:139-141` understates it. Wording only.
4. GitHub token and lookup key remain `String` (recorded on the N08 row;
   README narrowed in S7). Untouched.
5. `flutter_test`'s `TestWidgetsFlutterBinding` makes `HttpClient()` a
   400-only stub for the whole suite; the one loopback test opts out via
   `HttpOverrides.runWithHttpOverrides` + a bare `HttpOverrides` subclass.
   Worth a `test/support/` helper if a second real-socket test appears.
6. 16 test files now hand-roll repository/settings fakes (this session added
   `_OneBookRepo`/`_NoWishlist`/`_NoSettings` in the new DI test) — the
   S14–S21 shared-fake hygiene note keeps growing.

## Result

**N08 implemented end-to-end; uncommitted pending approval.**

- Gates: analyzer **0**; format **403 / 0 changed**; Flutter `--coverage`
  **1463 passed / 0 failed** (`/tmp/pitak-s22-flutter-final.txt`, 0 `[E]`;
  baseline 1441, +22); cargo **32 passed**, 2 expected ignored; `git diff
  --check` clean; `build_runner` warm re-run = no diff. Coverage **71.13%**
  (+0.22): `timeout_http_client.dart` 89/102 (misses: pause/resume
  forwarding, the headers-phase abort branch), `lookup_http_client.dart` 30/32, `bounded_cover_fetcher.dart`
  44/46, `materialize_remote_cover_use_case.dart` 21/21,
  `cover_fetch_result.dart` 3/3.
- Red evidence: 2 behaviour-red + 4 compile-red (`TimeoutHttpClient`);
  1 behaviour-red (`LookupHttpClient`); 5 behaviour-red against a HEAD graft
  + compile-red typed results (`BoundedCoverFetcher`); 3 compile-red
  (`onRefused`, typed port) + the DI diagnostic test (compile-red — no
  `boundedCoverDownloadProvider` on HEAD).
- Verified on the wire, not just by return value: a raw loopback
  `ServerSocket` sees the client's FIN 18 ms after the 200 ms deadline; a
  HEAD-shaped decorator left it open past 2 s.
- No device verification (network-layer finding; deterministic in tests).
  Remote CI not checked (nothing pushed).

Files for the commit (14): `lib/core/network/timeout_http_client.dart`,
`lib/core/network/lookup_http_client.dart`,
`lib/features/publish/domain/cover_fetch_result.dart` (new),
`lib/features/publish/infrastructure/bounded_cover_fetcher.dart`,
`lib/features/library/application/materialize_remote_cover_use_case.dart`,
`lib/core/di/providers.dart`, `lib/core/di/providers.g.dart`,
`test/core/timeout_http_client_test.dart`,
`test/core/lookup_http_client_test.dart`,
`test/core/di/remote_cover_diagnostic_test.dart` (new),
`test/features/publish/bounded_cover_fetcher_test.dart`,
`test/features/library/materialize_remote_cover_use_case_test.dart`,
`test/features/library/remote_cover_materializer_test.dart`, `PLAN.md`.
