/// Bounded, allow-listed remote cover fetcher (infra, #32, F-09/M1; N08).
///
/// Why this exists (security audit M1): publishing fetches each book's
/// `coverUrl` from the *publisher's* device. A poisoned `coverUrl` (planted via
/// a hostile import or a lookup) would otherwise make the device issue a GET to
/// an arbitrary host — leaking the publisher's IP / User-Agent / "publishing
/// now" timing — and, with an unbounded buffered read, let that host hang the
/// publish or stream gigabytes into memory (DoS).
///
/// Three defences, fail-closed:
///  1. ORIGIN: the URL must pass [CoverUrlAllowList.sanitize] — https only, no
///     userinfo, exact host match against the publish allow-list. Anything else
///     is refused (cover dropped; the viewer falls back to a placeholder).
///  2. TIMEOUT: connect + whole-response deadline, so a slow-loris host can't
///     stall the publish indefinitely. N08: the deadline ABORTS the request
///     (`package:http` `Abortable`), it does not merely stop waiting — the
///     socket is closed and no further byte is read.
///  3. BYTE CAP: the body is read as a STREAM and aborted the moment it exceeds
///     `maxBytes`, so an attacker-declared (or chunked, length-omitted) body
///     can never be fully buffered. We never trust Content-Length; we count
///     actual bytes. N08: REJECTED responses (redirect hops, non-2xx,
///     oversized declared length) are cancelled, never drained — a hostile
///     404 page of any size costs us nothing past its status line.
///
/// Redirects are followed MANUALLY (automatic following disabled): every
/// hop's Location is re-validated against the same allow-list, so a
/// redirect can never carry the request to a non-allow-listed host
/// (REVIEW_FINDINGS_2 S6).
///
/// The result is a sealed [CoverFetchResult] (publish domain): bytes, or a
/// [CoverRefusal] naming WHICH defence refused. The reason is a developer
/// diagnostic (M09: a missing thumbnail is not an error the user can act on)
/// and never carries the URL.
///
/// Bounded-streaming approach borrowed from the same size-accounting idea as
/// `BoundedZipExtractor` (Signal Android's BackupImporter): never allocate
/// attacker-controlled output; verify the real length as you go. Abort and
/// stream-cancel idioms from `package:http`'s `RetryClient`/`IOClient`.
///
/// Pure-ish seam: the `http.Client` is injected so this is unit-testable with a
/// `MockClient` and overridable via DI, matching the repo's thin-seam style.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';

/// Fetches a remote cover under strict origin / time / size limits.
final class BoundedCoverFetcher {
  /// Creates the fetcher over an injected [client].
  const BoundedCoverFetcher({
    required http.Client client,
    this.timeout = const Duration(seconds: 15),
    this.maxBytes = maxCoverBytes,
  }) : _client = client;

  final http.Client _client;

  /// Whole-request deadline (connect + headers + body, across all redirect
  /// hops). On expiry the in-flight request is ABORTED and
  /// [CoverRefusal.timedOut] is returned.
  final Duration timeout;

  /// Hard cap on bytes read from the body. Streaming stops and the request is
  /// aborted the instant this is exceeded.
  final int maxBytes;

  /// Default body cap: 8 MiB. A book cover is downscaled to a ~tens-of-KB JPEG
  /// downstream, so 8 MiB is a generous ceiling that still bounds memory.
  static const int maxCoverBytes = 8 * 1024 * 1024;

  /// Max redirect hops followed per fetch. Each hop's `Location` is
  /// re-validated against the allow-list before any packet is sent.
  static const int maxRedirects = 3;

  /// Fetches the cover for [rawUrl]. Never throws for expected failures: every
  /// refusal, timeout or transport fault is a [CoverRefused].
  Future<CoverFetchResult> fetch(String rawUrl) async {
    // (1) ORIGIN: host allow-list, not just https. Drops poisoned URLs before
    // a single packet leaves the device.
    final safe = CoverUrlAllowList.sanitize(rawUrl);
    if (safe == null) return const CoverRefused(CoverRefusal.disallowedUrl);

    // (2) TIMEOUT: one deadline for the whole fetch. Completing `abort` is
    // what tears the socket down (`IOClient` honours `Abortable`); the timer
    // also flips `expired` so the catch below can name the reason.
    final abort = Completer<void>();
    var expired = false;
    final deadline = Timer(timeout, () {
      expired = true;
      abort.complete();
    });
    try {
      return await _fetchBounded(Uri.parse(safe), abort);
    } on http.ClientException {
      // RequestAbortedException is a ClientException; distinguish our own
      // deadline from a genuine transport fault.
      return CoverRefused(
        expired ? CoverRefusal.timedOut : CoverRefusal.transport,
      );
    } on Exception {
      return CoverRefused(
        expired ? CoverRefusal.timedOut : CoverRefusal.transport,
      );
    } finally {
      deadline.cancel();
      // Whatever happened, make sure nothing is still streaming for us.
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Redirect statuses considered (301/302/303/307/308). 304 Not-Modified is
  /// never applicable here (no conditional headers sent) and falls into the
  /// non-2xx drop like any other unexpected status.
  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  /// Cancels a response body we will not read (N08). `drain()` would READ it
  /// to the end — unbounded — merely to keep the connection reusable; a
  /// hostile host makes that a download of arbitrary size. Cancelling closes
  /// the socket instead (`IOClient` cancels its subscription on ours).
  static void _discard(http.StreamedResponse response) {
    unawaited(response.stream.listen(null).cancel().catchError((_) {}));
  }

  /// Streams the response body, enforcing [maxBytes] as it reads. Throws
  /// [http.ClientException] on transport faults or abort (mapped by [fetch]).
  Future<CoverFetchResult> _fetchBounded(Uri uri, Completer<void> abort) async {
    // Manual redirect loop (REVIEW_FINDINGS_2 S6): `http.Request` defaults to
    // followRedirects = true, which would silently carry the fetch to ANY
    // host — outside the allow-list (an allow-listed host 302ing elsewhere
    // would defeat the ORIGIN defence). Automatic following is disabled and
    // every hop's Location is re-validated with the same sanitize() as the
    // initial URL, so no packet ever leaves for a non-allow-listed host. A
    // redirect to another ALLOW-LISTED host (e.g. books.google.com →
    // books.googleusercontent.com) keeps working.
    var current = uri;
    http.StreamedResponse response;
    var hops = 0;
    while (true) {
      final request = http.AbortableRequest(
        'GET',
        current,
        abortTrigger: abort.future,
      )..followRedirects = false;
      response = await _client.send(request);
      if (!_isRedirect(response.statusCode)) break;
      _discard(response);
      if (hops >= maxRedirects) {
        return const CoverRefused(CoverRefusal.tooManyRedirects);
      }
      final location = response.headers['location'];
      if (location == null) {
        return const CoverRefused(CoverRefusal.redirectRefused);
      }
      // Relative Locations resolve against the current URL per RFC 7231;
      // sanitize() then enforces absolute https + allow-listed host.
      final target = CoverUrlAllowList.sanitize(
        current.resolve(location).toString(),
      );
      if (target == null) {
        return const CoverRefused(CoverRefusal.redirectRefused);
      }
      current = Uri.parse(target);
      hops++;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _discard(response);
      return const CoverRefused(CoverRefusal.httpStatus);
    }

    // Early reject on an honest Content-Length; still verified byte-by-byte
    // below because the header is attacker-controlled and may be absent/lying.
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      _discard(response);
      return const CoverRefused(CoverRefusal.tooLarge);
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
        return const CoverRefused(CoverRefusal.tooLarge);
      }
      builder.add(chunk);
    }
    return CoverFetched(builder.takeBytes());
  }
}
