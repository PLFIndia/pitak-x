/// Bounded, allow-listed remote cover fetcher (infra, #32, F-09/M1).
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
///     returns null (cover dropped; the viewer falls back to a placeholder).
///  2. TIMEOUT: connect + whole-response deadline, so a slow-loris host can't
///     stall the publish indefinitely.
///  3. BYTE CAP: the body is read as a STREAM and aborted the moment it exceeds
///     `maxBytes`, so an attacker-declared (or chunked, length-omitted) body
///     can never be fully buffered. We never trust Content-Length; we count
///     actual bytes.
///
/// Bounded-streaming approach borrowed from the same size-accounting idea as
/// `BoundedZipExtractor` (Signal Android's BackupImporter): never allocate
/// attacker-controlled output; verify the real length as you go.
///
/// Pure-ish seam: the `http.Client` is injected so this is unit-testable with a
/// `MockClient` and overridable via DI, matching the repo's thin-seam style.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
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

  /// Whole-request deadline (connect + headers + body). On expiry the fetch is
  /// aborted and null is returned (no cover rather than a hung publish).
  final Duration timeout;

  /// Hard cap on bytes read from the body. Streaming stops and the request is
  /// abandoned the instant this is exceeded.
  final int maxBytes;

  /// Default body cap: 8 MiB. A book cover is downscaled to a ~tens-of-KB JPEG
  /// downstream, so 8 MiB is a generous ceiling that still bounds memory.
  static const int maxCoverBytes = 8 * 1024 * 1024;

  /// Fetches the cover bytes for [rawUrl], or null when the URL is not an
  /// allow-listed https cover, the host errors, the request times out, or the
  /// body exceeds [maxBytes]. Never throws for these expected cases.
  Future<List<int>?> fetch(String rawUrl) async {
    // (1) ORIGIN: host allow-list, not just https. Drops poisoned URLs before
    // a single packet leaves the device.
    final safe = CoverUrlAllowList.sanitize(rawUrl);
    if (safe == null) return null;

    try {
      return await _fetchBounded(Uri.parse(safe)).timeout(timeout);
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on Exception {
      return null;
    }
  }

  /// Streams the response body, enforcing [maxBytes] as it reads. Returns null
  /// on non-2xx, an over-cap body, or any stream error.
  Future<List<int>?> _fetchBounded(Uri uri) async {
    final request = http.Request('GET', uri);
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain so the connection can be reused/closed cleanly, then drop.
      unawaited(response.stream.drain<void>().catchError((_) {}));
      return null;
    }

    // Early reject on an honest Content-Length; still verified byte-by-byte
    // below because the header is attacker-controlled and may be absent/lying.
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      unawaited(response.stream.drain<void>().catchError((_) {}));
      return null;
    }

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > maxBytes) {
        // Over cap: abandon. Returning here cancels our subscription; the
        // underlying socket is closed by the client when the stream is dropped.
        return null;
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
