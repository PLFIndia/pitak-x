/// Deadline- and size-bounded HTTP client (audit m1; hardened for N08).
///
/// The shared `http.Client` had no timeout, so a dropped socket (e.g. OEM
/// app freezers like OnePlus HansManager suspending the process mid-request)
/// left callers awaiting forever — an infinite "Publishing…" spinner.
///
/// N08 (astra-review) found that the first version only stopped *waiting*:
/// `Future.timeout` completes the caller's future and leaves the request,
/// the socket and the body stream running. A slow host could hold a
/// connection and keep streaming into memory long after the UI had given up,
/// a body trickling one byte at a time never hit the idle timeout, and a
/// response of any size was buffered in full. This decorator now bounds four
/// things and, when any bound trips, TEARS THE REQUEST DOWN:
///
///  1. **Connect + headers** — `timeout` from send to the first byte of the
///     response. On expiry the request is aborted (socket closed), not
///     abandoned.
///  2. **Idle body** — `timeout` between body chunks. A stall errors out; a
///     slow but progressing download survives.
///  3. **Total deadline** — `totalDeadline` from send to the last body byte,
///     regardless of how healthy each chunk looks. Ends a trickle.
///  4. **Body size** — `maxResponseBytes` counted as actual bytes received
///     (Content-Length is never trusted). Ends an oversized body before it
///     is buffered.
///
/// Abortion uses `package:http`'s [http.Abortable] contract (1.5.0+): every
/// request is re-sent as an [http.AbortableRequest] whose `abortTrigger` we
/// complete. `IOClient` then calls `HttpClientRequest.abort()` before the
/// response arrives, or injects the error and cancels the socket subscription
/// while the body streams. Cancelling our body subscription closes the
/// underlying socket as well.
///
/// Every limit surfaces as [http.ClientException], the family callers already
/// handle (e.g. `HttpGitHubApi._guard` → `GitHubApiException`, the lookup
/// services → a fixed safe message), so every flow fails closed with its
/// existing copy instead of spinning or buffering.
///
/// Request-copy shape borrowed from `package:http`'s own `RetryClient`
/// (dart-lang/http, BSD-3), which re-sends a `BaseRequest` the same way.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// Wraps an inner [http.Client] with connect/idle/total deadlines and a body
/// byte cap, aborting the underlying request when any of them trips.
final class TimeoutHttpClient extends http.BaseClient {
  /// Creates the client.
  ///
  /// * [timeout] — per-phase limit (connect/headers, then between body
  ///   chunks). 60 s default: generous for a cover-blob upload on slow mobile
  ///   data, short enough to end a dead-socket hang.
  /// * [totalDeadline] — whole-request limit, defaults to [timeout]. Must be
  ///   at least [timeout] (a shorter total would make the per-phase limit
  ///   meaningless).
  /// * [maxResponseBytes] — hard cap on body bytes actually received.
  ///   Defaults to [defaultMaxResponseBytes].
  TimeoutHttpClient(
    this._inner, {
    this.timeout = const Duration(seconds: 60),
    Duration? totalDeadline,
    this.maxResponseBytes = defaultMaxResponseBytes,
  }) : totalDeadline = totalDeadline ?? timeout,
       assert(
         (totalDeadline ?? timeout) >= timeout,
         'totalDeadline must not be shorter than timeout',
       ),
       assert(maxResponseBytes > 0, 'maxResponseBytes must be positive');

  final http.Client _inner;

  /// Per-phase limit (connect/headers, then per body chunk).
  final Duration timeout;

  /// Whole-request limit from send to the last body byte.
  final Duration totalDeadline;

  /// Hard cap on response body bytes; counted as received, never declared.
  final int maxResponseBytes;

  /// 64 MiB. Matches the app's own "far beyond a legitimate catalogue"
  /// ceiling (`ImportLimits.maxTextChars`): a 100 000-row `books.json`
  /// read-back still fits, while a hostile body can no longer exhaust memory.
  static const int defaultMaxResponseBytes = 64 * 1024 * 1024;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // One clock per request: the total timer plus the abort signal that every
    // limit completes. Completing the signal is what makes the inner client
    // close the socket; each limit ALSO reports its own error to the caller
    // so the message names the bound that tripped.
    final deadline = _RequestDeadline(totalDeadline);

    final http.StreamedResponse resp;
    try {
      // (1) Connect + headers. `Future.timeout` alone would only stop
      // waiting; the abort trigger is what stops the request.
      resp = await _inner
          .send(_abortable(request, deadline.abortTrigger))
          .timeout(
            timeout,
            onTimeout: () {
              deadline.abort();
              throw http.ClientException(
                'Request timed out after ${timeout.inSeconds}s',
                request.url,
              );
            },
          );
    } on http.RequestAbortedException {
      deadline.cancel();
      throw http.ClientException(
        deadline.expired
            ? 'Request exceeded ${totalDeadline.inSeconds}s'
            : 'Request aborted',
        request.url,
      );
    } on Object {
      deadline
        ..cancel()
        ..abort();
      rethrow;
    }

    // (3) fired while headers were still in flight: the abort is already
    // requested; drop the body rather than start reading it.
    if (deadline.expired) {
      unawaited(resp.stream.listen(null).cancel());
      throw http.ClientException(
        'Request exceeded ${totalDeadline.inSeconds}s',
        request.url,
      );
    }

    return http.StreamedResponse(
      http.ByteStream(_boundedBody(resp.stream, request.url, deadline)),
      resp.statusCode,
      contentLength: resp.contentLength,
      request: resp.request,
      headers: resp.headers,
      isRedirect: resp.isRedirect,
      persistentConnection: resp.persistentConnection,
      reasonPhrase: resp.reasonPhrase,
    );
  }

  /// Re-issues [original] as an [http.AbortableRequest] wired to [trigger].
  /// `BaseClient.get/post/patch` build plain `Request`s the caller cannot make
  /// abortable, so the decorator does it here. Only `Request` bodies exist in
  /// this app (no multipart/streamed uploads), so copying `bodyBytes` is
  /// lossless; anything else is passed through unchanged (bounded but not
  /// abortable) rather than silently mangled.
  http.BaseRequest _abortable(http.BaseRequest original, Future<void> trigger) {
    if (original is! http.Request) return original;
    return http.AbortableRequest(
        original.method,
        original.url,
        abortTrigger: trigger,
      )
      ..headers.addAll(original.headers)
      ..bodyBytes = original.bodyBytes
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
  }

  /// Forwards [source] enforcing (2) idle, (3) total and (4) size. On any
  /// trip: cancel the source (closes the socket), request the abort, error
  /// the caller with a [http.ClientException] naming the bound, close.
  Stream<List<int>> _boundedBody(
    Stream<List<int>> source,
    Uri url,
    _RequestDeadline deadline,
  ) {
    late StreamController<List<int>> out;
    StreamSubscription<List<int>>? sub;
    Timer? idle;
    var received = 0;

    void stopTimers() {
      idle?.cancel();
      deadline.cancel();
    }

    void failWith(String message) {
      stopTimers();
      unawaited(sub?.cancel());
      sub = null;
      deadline.abort();
      if (!out.isClosed) {
        out
          ..addError(http.ClientException(message, url))
          ..close();
      }
    }

    void armIdle() {
      idle?.cancel();
      idle = Timer(timeout, () {
        failWith('Response stalled for ${timeout.inSeconds}s');
      });
    }

    out = StreamController<List<int>>(
      onListen: () {
        if (deadline.expired) {
          failWith('Request exceeded ${totalDeadline.inSeconds}s');
          return;
        }
        // From here on the total deadline must error THIS stream, not only
        // request the abort.
        deadline.onExpire = () {
          failWith('Request exceeded ${totalDeadline.inSeconds}s');
        };
        armIdle();
        sub = source.listen(
          (chunk) {
            received += chunk.length;
            if (received > maxResponseBytes) {
              failWith('Response exceeded $maxResponseBytes bytes');
              return;
            }
            armIdle();
            out.add(chunk);
          },
          onError: (Object e, StackTrace s) {
            stopTimers();
            if (!out.isClosed) {
              out
                ..addError(e, s)
                ..close();
            }
          },
          onDone: () {
            stopTimers();
            sub = null;
            if (!out.isClosed) unawaited(out.close());
          },
          cancelOnError: true,
        );
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () {
        // The caller dropped the body (e.g. our own cover fetcher rejecting
        // a 404): stop the clock AND the socket, never keep reading.
        stopTimers();
        deadline.abort();
        final s = sub;
        sub = null;
        return s?.cancel();
      },
    );
    return out.stream;
  }

  @override
  void close() => _inner.close();
}

/// The clock one request runs against: a total timer plus the abort signal
/// every limit completes. Kept separate so `send()` (headers phase) and the
/// body stream can share it without re-creating timers.
final class _RequestDeadline {
  _RequestDeadline(Duration total) {
    _timer = Timer(total, () {
      expired = true;
      abort();
      onExpire?.call();
    });
  }

  final Completer<void> _abort = Completer<void>();
  late final Timer _timer;

  /// Extra work to do if the total deadline fires while the body streams
  /// (error the reader's stream). Null during the headers phase, where the
  /// awaiting `send()` observes [expired] instead.
  void Function()? onExpire;

  /// True once the total deadline has fired.
  bool expired = false;

  /// Completes when any limit trips; handed to the inner request.
  Future<void> get abortTrigger => _abort.future;

  /// Requests the abort (idempotent).
  void abort() {
    if (!_abort.isCompleted) _abort.complete();
  }

  /// Stops the total timer (body finished or caller dropped it).
  void cancel() => _timer.cancel();
}
