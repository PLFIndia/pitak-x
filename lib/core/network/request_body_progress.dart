/// Upload-progress watch for a streamed request body (fix-plan H2).
///
/// A request body is not "sent" when the call starts: `dart:io` pulls it only
/// as fast as the socket drains it, so the old single 60 s deadline covered
/// connect AND a whole 56 MB upload. A slow-but-healthy link was cut off and
/// the bucket re-sent from byte 0.
///
/// This class turns body pulls into evidence, in three phases:
///
///  1. **Connecting** — the first pulled chunk proves the connection works,
///     so the connect timer is cancelled then.
///  2. **Sending** — every pull re-arms an idle timer. No pull for the idle
///     duration means the network stopped draining the socket.
///  3. **Waiting for headers** — once the body ends, the response-header wait
///     begins (the server must first receive whatever the socket still holds).
///
/// The TOTAL deadline stays with `TimeoutHttpClient`, so a trickle that
/// always makes a little progress is still bounded. Any timer here completes
/// `failed` with a `ClientException` whose message names the bound that
/// tripped; the caller aborts the request and maps that message to a typed
/// failure.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// Counts pulled body bytes and bounds each upload phase.
final class RequestBodyProgress {
  /// Creates the watch for one request. Call [start] just before sending.
  RequestBodyProgress({
    required this.url,
    required this.connectTimeout,
    required this.idleTimeout,
    required this.headersTimeout,
    this.onProgress,
  });

  /// The request URL, used only to build the (redacted) exception URI.
  final Uri url;

  /// How long the first pulled body byte may take.
  final Duration connectTimeout;

  /// How long the body may make no progress while the network drains it.
  final Duration idleTimeout;

  /// How long the response headers may take after the body has ended.
  final Duration headersTimeout;

  /// Receives the cumulative number of body bytes pulled so far.
  ///
  /// This is how the transport decides whether a failed attempt sent enough
  /// bytes to be worth re-sending (fix-plan H2 step 4).
  final void Function(int sent)? onProgress;

  final Completer<Never> _failed = Completer<Never>();
  Timer? _timer;
  int _sent = 0;
  bool _bodyDone = false;

  /// Cumulative body bytes the inner client has pulled.
  int get sent => _sent;

  /// Completes with the [http.ClientException] for the bound that tripped.
  ///
  /// It never completes normally: an upload either finishes (and the caller
  /// stops watching) or fails through one of the three timers.
  Future<Never> get failed => _failed.future;

  /// Arms the connect timer. Called immediately before the inner send.
  void start() {
    // A pull that somehow arrived first already proved the connection works,
    // so go straight to the idle bound instead of waiting for a connect that
    // has already happened.
    if (_sent > 0) {
      _arm(idleTimeout, 'Upload stalled for ${idleTimeout.inSeconds}s');
      return;
    }
    _arm(
      connectTimeout,
      'Request timed out after ${connectTimeout.inSeconds}s',
    );
  }

  /// Cancels every timer. Safe to call more than once.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Wraps [body] so that every chunk the client actually pulls is counted.
  ///
  /// The stream is otherwise untouched: chunk sizes, byte values and the
  /// multipart framing stay exactly what the request built.
  Stream<List<int>> watch(Stream<List<int>> body) => body.transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        _onPull(chunk.length);
        sink.add(chunk);
      },
      handleError: (error, stackTrace, sink) {
        // A local read failure is not a timing bound: stop our clocks and let
        // the caller classify the error (fix-plan L8).
        _bodyDone = true;
        stop();
        sink
          ..addError(error, stackTrace)
          ..close();
      },
      handleDone: (sink) {
        _onBodyDone();
        sink.close();
      },
    ),
  );

  void _onPull(int bytes) {
    if (_bodyDone) return;
    _sent += bytes;
    onProgress?.call(_sent);
    // Any pulled chunk means the connection works and the body is streaming.
    _arm(idleTimeout, 'Upload stalled for ${idleTimeout.inSeconds}s');
  }

  void _onBodyDone() {
    if (_bodyDone) return;
    _bodyDone = true;
    _arm(
      headersTimeout,
      'Response headers timed out after ${headersTimeout.inSeconds}s',
    );
  }

  void _arm(Duration limit, String message) {
    _timer?.cancel();
    _timer = Timer(limit, () {
      _timer = null;
      if (_failed.isCompleted) return;
      _failed.completeError(http.ClientException(message, url));
    });
  }
}
