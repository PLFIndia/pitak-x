/// Deadline- and size-bounded HTTP client (audit m1; hardened for N08).
///
/// The shared `http.Client` had no timeout, so a dropped socket (e.g. OEM
/// app freezers like OnePlus HansManager suspending the process mid-request)
/// left callers awaiting forever — an infinite "Publishing…" spinner.
///
/// Review finding N08 found that the first version only stopped *waiting*:
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
/// Request bodies are not copied or buffered by this decorator. A thin
/// abortable wrapper delegates `finalize()` to the original request, so plain,
/// streamed and multipart uploads all keep their existing streaming behavior.
///
/// **Upload mode (fix-plan H2).** When `requestBodyIdleTimeout` is set, the
/// per-phase `timeout` bounds ONLY the wait for the first pulled body chunk,
/// and the body itself is bounded by an idle timer: no progress for that long
/// aborts. Once the body ends, `responseHeadersTimeout` bounds the response
/// headers. The total deadline still applies, so a trickle cannot live
/// forever.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/request_body_progress.dart';

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
    this.requestBodyIdleTimeout,
    this.responseHeadersTimeout,
    this.onRequestBodyProgress,
  }) : totalDeadline = totalDeadline ?? timeout,
       assert(
         (totalDeadline ?? timeout) >= timeout,
         'totalDeadline must not be shorter than timeout',
       ),
       assert(maxResponseBytes > 0, 'maxResponseBytes must be positive'),
       assert(
         responseHeadersTimeout == null || requestBodyIdleTimeout != null,
         'responseHeadersTimeout only applies to upload mode',
       );

  final http.Client _inner;

  /// Per-phase limit.
  ///
  /// Outside upload mode: connect/headers, then between response body chunks.
  /// In upload mode ([requestBodyIdleTimeout] set): only the wait for the
  /// first pulled request-body chunk.
  final Duration timeout;

  /// Whole-request limit from send to the last body byte.
  final Duration totalDeadline;

  /// Hard cap on response body bytes; counted as received, never declared.
  final int maxResponseBytes;

  /// Upload mode: how long the request body may make no progress.
  ///
  /// Null (the default) keeps the original behaviour, where [timeout] bounds
  /// connect AND the whole body upload. Every non-Cloudflare caller is in that
  /// mode, so this change cannot silently alter GitHub, lookup or viewer
  /// traffic.
  final Duration? requestBodyIdleTimeout;

  /// Upload mode: how long the response headers may take after the body ends.
  ///
  /// Defaults to [timeout] when upload mode is on and this is null.
  final Duration? responseHeadersTimeout;

  /// Upload mode: receives cumulative pulled request-body bytes.
  final void Function(int sent)? onRequestBodyProgress;

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

    // A caller that handed us an ABORTABLE request keeps its own abort
    // authority: its trigger completes OUR signal, so the inner request sees
    // one trigger that fires for either reason (our limits or theirs).
    // `_abortable` below re-wraps every request with our signal only — before
    // this line the caller's trigger was simply dropped, and e.g. the bounded
    // fetcher's 15 s deadline stopped nothing (review finding H2).
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) => deadline.abort()));
    }

    // Upload mode watches the REQUEST body, which only exists once the inner
    // client pulls it. Null means the unchanged connect+headers behaviour.
    final progress = requestBodyIdleTimeout == null
        ? null
        : RequestBodyProgress(
            url: request.url,
            connectTimeout: timeout,
            idleTimeout: requestBodyIdleTimeout!,
            headersTimeout: responseHeadersTimeout ?? timeout,
            onProgress: onRequestBodyProgress,
          );

    final http.StreamedResponse resp;
    try {
      final sending = _inner.send(
        _abortable(request, deadline.abortTrigger, progress),
      );
      if (progress == null) {
        // (1) Connect + headers. `Future.timeout` alone would only stop
        // waiting; the abort trigger is what stops the request.
        resp = await sending.timeout(
          timeout,
          onTimeout: () {
            deadline.abort();
            throw http.ClientException(
              'Request timed out after ${timeout.inSeconds}s',
              request.url,
            );
          },
        );
      } else {
        // The first phase timer is started here so a request that never
        // reaches `finalize()` still errors instead of hanging.
        progress.start();
        resp = await Future.any<http.StreamedResponse>([
          sending,
          progress.failed,
        ]);
      }
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
    } finally {
      // Success ends all upload phase timers; the response body has its own.
      progress?.stop();
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

  /// Re-issues [original] behind an abortable wrapper wired to [trigger].
  ///
  /// `BaseClient.get/post/patch` build plain requests the caller cannot make
  /// abortable, so the decorator does it here. Delegating `finalize()` instead
  /// of copying a body is important: multipart and streamed requests must keep
  /// streaming, and their boundaries/content lengths must remain untouched.
  /// A caller's own `abortTrigger` is not lost: `send` chains it into [trigger]
  /// before calling this.
  http.BaseRequest _abortable(
    http.BaseRequest original,
    Future<void> trigger,
    RequestBodyProgress? progress,
  ) => _AbortableRequest(original, trigger, progress);

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

/// Adds an abort signal to any request without changing how its body is made.
///
/// Beginner note: `package:http` already knows how to stream each concrete
/// request type. Rebuilding only `http.Request` here used to leave multipart
/// uploads outside the deadline. This wrapper keeps the original request as
/// the body authority and adds exactly one new capability: [abortTrigger].
final class _AbortableRequest extends http.BaseRequest with http.Abortable {
  _AbortableRequest(this._original, this.abortTrigger, this._progress)
    : super(_original.method, _original.url) {
    headers.addAll(_original.headers);
    followRedirects = _original.followRedirects;
    maxRedirects = _original.maxRedirects;
    persistentConnection = _original.persistentConnection;
  }

  final http.BaseRequest _original;
  final RequestBodyProgress? _progress;

  @override
  final Future<void> abortTrigger;

  /// Multipart requests calculate their length from their parts; forwarding
  /// the getter preserves that calculation instead of freezing a second copy.
  @override
  int? get contentLength => _original.contentLength;

  @override
  http.ByteStream finalize() {
    super.finalize();
    final body = _original.finalize();
    // MultipartRequest adds its generated boundary header during finalize.
    // Copy final headers AFTER finalizing so IOClient sends that exact header.
    headers.addAll(_original.headers);
    // Upload mode counts pulled chunks; the bytes themselves are untouched.
    final progress = _progress;
    return progress == null ? body : http.ByteStream(progress.watch(body));
  }
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
