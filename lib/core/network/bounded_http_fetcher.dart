/// Bounded, allow-listed HTTP GET fetcher (core; docs/ARCHITECTURE.md §5.6).
///
/// The generic form of the publish cover fetcher (security audit M1, N08,
/// REVIEW_FINDINGS_2 S6) — extracted so the network `library.json` descriptor
/// fetch gets the SAME three defences instead of a copy-paste:
///
///  1. ORIGIN: the URL must pass the injected [BoundedHttpFetcher.sanitize]
///     allow-list (https
///     only, no userinfo, host policy per caller). Anything else is refused
///     BEFORE a single packet leaves the device.
///  2. TIMEOUT: one deadline for the whole request that ABORTS it
///     (`package:http` `Abortable`) — the socket is closed, not merely
///     abandoned, so a slow-loris host cannot stall the caller.
///  3. BYTE CAP: the body is read as a STREAM and aborted the moment it
///     exceeds [BoundedHttpFetcher.maxBytes]. Content-Length is never
///     trusted; actual bytes are
///     counted. REJECTED responses (redirect hops, non-2xx, oversized
///     declared length) are cancelled, never drained — a hostile body of any
///     size costs nothing past its status line.
///
/// Redirects are followed MANUALLY (automatic following disabled): every hop's
/// `Location` is re-validated with the same [BoundedHttpFetcher.sanitize],
/// so a redirect can
/// never carry the request to a non-allow-listed host.
///
/// Callers may also pass their OWN abort signal (`fetch(url, abortTrigger:)`),
/// used by the published-catalogue viewer so closing the screen closes the
/// socket. It chains into the same single abort completer as the deadline.
///
/// The outcome is a sealed [BoundedFetchOutcome]: bytes, or a coarse
/// [FetchRefusal] naming WHICH defence refused. The reason is a developer
/// diagnostic and never carries the URL.
///
/// [BoundedHttpFetcher.fetchConditional] is the same fetch with one extra,
/// optional header: `If-None-Match` carrying the entity tag of a copy the
/// caller already saved (ADR 0018). Its outcome may additionally be
/// [FetchNotModified]; every defence above applies unchanged.
///
/// Pure-ish seam: the `http.Client` and the allow-list are injected, so this
/// is unit-testable with a `MockClient` and reusable by any feature that needs
/// a hostile-host-safe GET (today: publish covers, network descriptors).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/entity_tag.dart';

/// Fetches one URL under strict origin / time / size limits.
final class BoundedHttpFetcher {
  /// Creates the fetcher over an injected [client] and [sanitize] allow-list.
  const BoundedHttpFetcher({
    required http.Client client,
    required this.sanitize,
    this.timeout = const Duration(seconds: 15),
    this.maxBytes = defaultMaxBytes,
    this.maxRedirects = defaultMaxRedirects,
    this.headers = defaultHeaders,
  }) : _client = client;

  final http.Client _client;

  /// Request headers sent on the initial request AND on every redirect hop.
  /// Defaults to the app's single honest User-Agent: a bare `package:http`
  /// request goes out as `Dart/3.x (dart:io)`, which the services we read
  /// from (Pages hosts, cover CDNs) cannot attribute to this app — and which
  /// contradicts `AppUserAgent`'s "one UA everywhere" promise (review M2).
  final Map<String, String> headers;

  /// The caller's URL allow-list: returns the URL string to actually fetch, or
  /// null to refuse. Applied to the initial URL AND to every redirect hop.
  /// The nullable parameter matches the repo's sanitizer shape exactly
  /// (`CoverUrlAllowList.sanitize`, `BookmarkUrl.normalize`), so either can be
  /// torn off into a const fetcher without an adapter lambda.
  final String? Function(String? rawUrl) sanitize;

  /// Whole-request deadline (connect + headers + body, across all redirect
  /// hops). On expiry the in-flight request is ABORTED and
  /// [FetchRefusal.timedOut] is returned.
  final Duration timeout;

  /// Hard cap on bytes read from the body. Streaming stops and the request is
  /// aborted the instant this is exceeded.
  final int maxBytes;

  /// Max redirect hops followed per fetch. Each hop's `Location` is
  /// re-validated with [sanitize] before any packet is sent.
  final int maxRedirects;

  /// Default body cap: 8 MiB — generous for the largest legitimate payloads
  /// (a downscaled cover JPEG is tens of KB; a `library.json` is ≤ 64 KiB)
  /// while still bounding memory. Callers pass a tighter cap where they can.
  static const int defaultMaxBytes = 8 * 1024 * 1024;

  /// Default redirect budget.
  static const int defaultMaxRedirects = 3;

  /// Default headers: the app's User-Agent only.
  static const Map<String, String> defaultHeaders = {
    'User-Agent': AppUserAgent.value,
  };

  /// Fetches [rawUrl]. Never throws for expected failures: every refusal,
  /// timeout or transport fault is a [FetchRefused].
  ///
  /// [abortTrigger] is an optional CALLER abort signal (viewer plan S2): when
  /// the future completes, the in-flight request is torn down exactly as the
  /// internal deadline would tear it down. A screen that closes mid-fetch
  /// passes its disposal future here, so leaving the screen closes the socket
  /// instead of merely ignoring the bytes that keep arriving. The caller's
  /// trigger never completes on a normal success — the fetch finishes first —
  /// so an uncompleted trigger has no cost beyond one listener.
  Future<BoundedFetchOutcome> fetch(
    String rawUrl, {
    Future<void>? abortTrigger,
  }) async {
    final outcome = await _run(rawUrl, abortTrigger: abortTrigger);
    return switch (outcome) {
      final BoundedFetchOutcome plain => plain,
      // Cannot happen: without a tag, `_fetchBounded` treats a 304 like any
      // other non-2xx status. Mapped explicitly (not cast) so the type
      // system — not this comment — keeps plain callers free of the case.
      FetchNotModified() => const FetchRefused(
        FetchRefusal.httpStatus,
        statusCode: 304,
      ),
    };
  }

  /// Like [fetch], but asks the host to skip the body when the caller's saved
  /// copy is still current (ADR 0018).
  ///
  /// [ifNoneMatch] is the entity tag the host sent with the saved copy. It is
  /// re-checked with `EntityTag.sanitize` before use (it came from disk, and
  /// originally from an untrusted host); a null or malformed tag means a
  /// plain, unconditional request. When a tag was sent and the host answers
  /// `304`, the outcome is [FetchNotModified] and no body is read.
  Future<ConditionalFetchOutcome> fetchConditional(
    String rawUrl, {
    required String? ifNoneMatch,
    Future<void>? abortTrigger,
  }) => _run(
    rawUrl,
    abortTrigger: abortTrigger,
    ifNoneMatch: EntityTag.sanitize(ifNoneMatch),
  );

  /// The shared body of [fetch] and [fetchConditional].
  Future<ConditionalFetchOutcome> _run(
    String rawUrl, {
    Future<void>? abortTrigger,
    String? ifNoneMatch,
  }) async {
    // (1) ORIGIN: allow-list first — a poisoned URL is dropped before any
    // network call, so the device never reveals that it holds such a URL.
    final safe = sanitize(rawUrl);
    if (safe == null) return const FetchRefused(FetchRefusal.disallowedUrl);

    // (2) TIMEOUT: one deadline for the whole fetch. Completing `abort` is
    // what tears the socket down (`IOClient` honours `Abortable`); the timer
    // also flips `expired` so the catch below can name the reason.
    final abort = Completer<void>();
    var expired = false;
    // A caller's abort chains into the SAME completer: one signal, whichever
    // reason fires first, and no second cancellation path to keep in sync.
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.whenComplete(() {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final deadline = Timer(timeout, () {
      expired = true;
      abort.complete();
    });
    try {
      return await _fetchBounded(Uri.parse(safe), abort, ifNoneMatch);
    } on http.ClientException {
      // RequestAbortedException is a ClientException; distinguish our own
      // deadline from a genuine transport fault.
      return FetchRefused(
        expired ? FetchRefusal.timedOut : FetchRefusal.transport,
      );
    } on Exception {
      return FetchRefused(
        expired ? FetchRefusal.timedOut : FetchRefusal.transport,
      );
    } finally {
      deadline.cancel();
      // Whatever happened, make sure nothing is still streaming for us.
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Redirect statuses considered (301/302/303/307/308). 304 Not-Modified is
  /// not a redirect: it means "your copy is current" and is honoured ONLY
  /// when this fetch sent `If-None-Match`; otherwise it falls into the non-2xx
  /// drop like any other unexpected status.
  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Cancels a response body we will not read (N08). `drain()` would READ it
  /// to the end — unbounded — merely to keep the connection reusable; a
  /// hostile host makes that a download of arbitrary size. Cancelling closes
  /// the socket instead.
  static void _discard(http.StreamedResponse response) {
    // The empty listener exists only to cancel; a cancel-time error is the
    // transport's business and already surfaces as FetchRefusal.transport.
    unawaited(response.stream.listen(null).cancel().catchError((_) {}));
  }

  /// Streams the response body, enforcing [maxBytes] as it reads. Throws
  /// [http.ClientException] on transport faults or abort (mapped by [fetch]).
  ///
  /// [ifNoneMatch] is an already-sanitized tag or null. It rides on every
  /// hop, like the other headers: a same-site redirect lands on the file the
  /// tag describes, and the host there decides whether it still matches.
  Future<ConditionalFetchOutcome> _fetchBounded(
    Uri uri,
    Completer<void> abort,
    String? ifNoneMatch,
  ) async {
    // Manual redirect loop (REVIEW_FINDINGS_2 S6): `http.Request` defaults to
    // followRedirects = true, which would silently carry the fetch to ANY
    // host — outside the allow-list. Automatic following is disabled and
    // every hop's Location is re-validated with the same sanitize() as the
    // initial URL, so no packet ever leaves for a non-allow-listed host.
    var current = uri;
    http.StreamedResponse response;
    var hops = 0;
    while (true) {
      final request =
          http.AbortableRequest('GET', current, abortTrigger: abort.future)
            ..followRedirects = false
            ..headers.addAll(headers);
      if (ifNoneMatch != null) request.headers['If-None-Match'] = ifNoneMatch;
      response = await _client.send(request);
      if (!_isRedirect(response.statusCode)) break;
      _discard(response);
      if (hops >= maxRedirects) {
        return const FetchRefused(FetchRefusal.tooManyRedirects);
      }
      final location = response.headers['location'];
      if (location == null) {
        return const FetchRefused(FetchRefusal.redirectRefused);
      }
      // Relative Locations resolve against the current URL per RFC 7231;
      // sanitize() then enforces absolute https + allow-listed host.
      final target = sanitize(current.resolve(location).toString());
      if (target == null) {
        return const FetchRefused(FetchRefusal.redirectRefused);
      }
      current = Uri.parse(target);
      hops++;
    }

    // "Not modified" is only an answer to a question we asked. Without a tag a
    // 304 is meaningless here and is refused below like any non-2xx status.
    if (ifNoneMatch != null && response.statusCode == 304) {
      _discard(response);
      return const FetchNotModified();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _discard(response);
      return FetchRefused(
        FetchRefusal.httpStatus,
        statusCode: response.statusCode,
      );
    }

    // Early reject on an honest Content-Length; still verified byte-by-byte
    // below because the header is attacker-controlled and may be absent/lying.
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      _discard(response);
      return const FetchRefused(FetchRefusal.tooLarge);
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > maxBytes) {
        // Over cap: returning from inside `await for` cancels our
        // subscription; completing the trigger makes the client close the
        // socket now rather than whenever the stream is collected.
        if (!abort.isCompleted) abort.complete();
        return const FetchRefused(FetchRefusal.tooLarge);
      }
      builder.add(chunk);
    }
    return FetchedBytes(
      builder.takeBytes(),
      entityTag: EntityTag.sanitize(response.headers['etag']),
    );
  }
}
