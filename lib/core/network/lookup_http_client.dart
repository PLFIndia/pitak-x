/// HTTP decorator for the public book-metadata APIs (ISBN lookup).
///
/// Two jobs, both aimed at "lookup fails quite often" (REVIEW: lookup):
///
/// 1. **Identify ourselves.** Open Library's API policy requires a
///    descriptive User-Agent and throttles/blocks anonymous defaults (Dart
///    sends `Dart/x.x`). One header removes the most common 403/429 source
///    on our PRIMARY provider. Sent to every lookup host — Google Books
///    tolerates it fine.
/// 2. **Absorb single transient blips.** Public no-auth APIs shed load with
///    429/5xx bursts that clear in seconds. One short, jittered backoff
///    retry per request (GET only — idempotent by definition) converts most
///    of those bursts into successes instead of user-visible failures.
///    Approach mirrors the `http` package's own `RetryClient` defaults
///    (retry `when: 429/503`, single-digit attempts, backoff+jitter),
///    narrowed to our needs; not the package class itself so the retry
///    predicate and sleep stay injectable for fast, hermetic tests.
///
/// Deliberately NOT used for GitHub publishing: device-flow polling has its
/// own protocol-level retry policy, and blind retries there would fight it.
library;

import 'dart:math';

import 'package:http/http.dart' as http;

/// Adds a User-Agent and one transient-error retry to GET requests.
final class LookupHttpClient extends http.BaseClient {
  /// Creates the decorator over an inner client. [sleep] and [random] are
  /// injectable
  /// so tests don't wait in real time and see deterministic jitter.
  LookupHttpClient(
    this._inner, {
    Future<void> Function(Duration)? sleep,
    Random? random,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  final http.Client _inner;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  /// Descriptive UA per Open Library's API policy (app + contact point).
  static const String userAgent = 'Pitaka/1.1 (https://github.com/PLFIndia)';

  /// Base backoff before the single retry; jitter is added on top.
  static const Duration baseBackoff = Duration(milliseconds: 800);

  /// Statuses worth one retry: rate-limit shed (429) and transient server
  /// errors (5xx). 4xx client errors are deterministic — never retried.
  static bool _retryable(int status) => status == 429 || status >= 500;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.putIfAbsent('User-Agent', () => userAgent);

    // Only GETs are retried: they are idempotent and the request object of
    // a GET carries no consumed body stream, so it can be safely re-sent.
    if (request.method != 'GET') return _inner.send(request);

    final http.StreamedResponse first;
    try {
      first = await _inner.send(request);
    } on http.ClientException {
      // Transport blip (timeout, reset). One retry after backoff.
      await _backoff();
      return _inner.send(_copy(request));
    }
    if (!_retryable(first.statusCode)) return first;

    await _backoff();
    try {
      return await _inner.send(_copy(request));
    } on http.ClientException {
      // Retry also failed: surface the original response rather than a
      // thrown error so callers keep their status-code handling.
      return first;
    }
  }

  Future<void> _backoff() =>
      _sleep(baseBackoff + Duration(milliseconds: _random.nextInt(400)));

  /// Fresh request object for the retry (a BaseRequest can be sent once).
  http.Request _copy(http.BaseRequest original) {
    final r = http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    return r;
  }

  @override
  void close() => _inner.close();
}
