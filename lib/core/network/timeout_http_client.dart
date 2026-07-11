/// Timeout-bounded HTTP client (closes audit finding m1).
///
/// The shared `http.Client` had no timeout, so a dropped socket (e.g. OEM
/// app freezers like OnePlus HansManager suspending the process mid-request)
/// left callers awaiting forever — an infinite "Publishing…" spinner.
///
/// This decorator bounds BOTH phases of every request:
///  1. connect + response headers (`send()` future), and
///  2. the response body stream (per-chunk idle timeout — a stalled body
///     errors instead of hanging).
///
/// Timeouts surface as [http.ClientException], the same family callers
/// already handle (e.g. `HttpGitHubApi._guard` maps it to
/// `GitHubApiException`), so every flow fails closed with its existing
/// safe error message instead of spinning.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// Wraps an inner [http.Client], failing any request that stalls longer
/// than [timeout] (connection or between body chunks).
final class TimeoutHttpClient extends http.BaseClient {
  /// Creates the client. 60 s default: generous enough for a cover-blob
  /// upload on slow mobile data, short enough to end a dead-socket hang.
  TimeoutHttpClient(this._inner, {this.timeout = const Duration(seconds: 60)});

  final http.Client _inner;

  /// Per-phase limit (connect/headers, then per body chunk).
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse resp;
    try {
      resp = await _inner.send(request).timeout(timeout);
    } on TimeoutException {
      throw http.ClientException(
        'Request timed out after ${timeout.inSeconds}s',
        request.url,
      );
    }
    // Stream.timeout is an IDLE timeout: it re-arms on every chunk, so slow
    // but progressing downloads survive; only a stall errors out.
    final bounded = resp.stream.timeout(
      timeout,
      onTimeout: (sink) {
        sink
          ..addError(
            http.ClientException(
              'Response stalled for ${timeout.inSeconds}s',
              request.url,
            ),
          )
          ..close();
      },
    );
    return http.StreamedResponse(
      http.ByteStream(bounded),
      resp.statusCode,
      contentLength: resp.contentLength,
      request: resp.request,
      headers: resp.headers,
      isRedirect: resp.isRedirect,
      persistentConnection: resp.persistentConnection,
      reasonPhrase: resp.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
