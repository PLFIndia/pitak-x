import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/timeout_http_client.dart';

/// An inner client whose send() never completes — a dead socket.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// An inner client that responds instantly with [body].
class _OkClient extends http.BaseClient {
  _OkClient(this.body);
  final String body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        http.ByteStream.fromBytes(body.codeUnits),
        200,
        request: request,
      );
}

/// An inner client whose response BODY stalls forever after the headers
/// (a StreamController that never emits and never closes).
class _StalledBodyClient extends http.BaseClient {
  final _controller = StreamController<List<int>>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        http.ByteStream(_controller.stream),
        200,
        request: request,
      );
}

void main() {
  final url = Uri.parse('https://api.github.test/user');

  test('a connection that never completes fails with ClientException', () {
    final client = TimeoutHttpClient(
      _HangingClient(),
      timeout: const Duration(milliseconds: 50),
    );
    expect(() => client.get(url), throwsA(isA<http.ClientException>()));
  });

  test('a healthy response passes through unchanged', () async {
    final client = TimeoutHttpClient(
      _OkClient('{"login":"x"}'),
      timeout: const Duration(seconds: 5),
    );
    final resp = await client.get(url);
    expect(resp.statusCode, 200);
    expect(resp.body, '{"login":"x"}');
  });

  test('a stalled response body fails instead of hanging', () {
    final client = TimeoutHttpClient(
      _StalledBodyClient(),
      timeout: const Duration(milliseconds: 50),
    );
    // Reading the body forces the stream; the idle timeout must fire.
    expect(() => client.get(url), throwsA(isA<http.ClientException>()));
  });

  // N08 (astra-review): a deadline that only stops WAITING is not a deadline.
  // These tests observe the SOURCE side — did the inner request get aborted,
  // did the body subscription get cancelled, did the socket really close —
  // not just the exception the caller receives.
  group('N08 — deadlines stop the underlying work', () {
    // `testWidgets` runs the body under FakeAsync: `tester.pump(d)` advances
    // the clock deterministically, and the binding asserts at the end that
    // no timer is still pending (the leak check the review asks for).
    testWidgets('a connection that never completes is ABORTED, not abandoned', (
      tester,
    ) async {
      final inner = _AbortAwareHangingClient();
      final client = TimeoutHttpClient(
        inner,
        timeout: const Duration(milliseconds: 50),
      );
      Object? error;
      unawaited(
        client
            .get(url)
            .then<void>(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(error, isA<http.ClientException>());
      expect(
        inner.abortTriggered,
        isTrue,
        reason: 'the inner request must carry an abortTrigger that fires',
      );
    });

    testWidgets('a body that trickles forever is cut by the TOTAL deadline '
        'even though every chunk beats the idle timeout', (tester) async {
      // One byte every 30 ms: never idle for 40 ms, never finished.
      final inner = _TricklingClient(
        interval: const Duration(milliseconds: 30),
      );
      final client = TimeoutHttpClient(
        inner,
        timeout: const Duration(milliseconds: 40),
        totalDeadline: const Duration(milliseconds: 100),
      );
      Object? error;
      var completed = false;
      unawaited(
        client
            .get(url)
            .then<void>(
              (_) => completed = true,
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(completed, isFalse);
      expect(error, isA<http.ClientException>());
      expect(inner.cancelled, isTrue, reason: 'source cancelled');
      expect(inner.abortTriggered, isTrue, reason: 'socket torn down');
      expect(
        inner.chunksEmitted,
        lessThan(6),
        reason: 'nothing was read after the deadline (100 ms / 30 ms ≈ 3)',
      );
    });

    testWidgets('a body over maxResponseBytes fails closed and stops reading', (
      tester,
    ) async {
      final inner = _TricklingClient(
        interval: const Duration(milliseconds: 1),
        chunk: List<int>.filled(100, 7),
      );
      final client = TimeoutHttpClient(
        inner,
        timeout: const Duration(seconds: 1),
        totalDeadline: const Duration(seconds: 10),
        maxResponseBytes: 250,
      );
      Object? error;
      var completed = false;
      unawaited(
        client
            .get(url)
            .then<void>(
              (_) => completed = true,
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(completed, isFalse);
      expect(error, isA<http.ClientException>());
      expect(inner.cancelled, isTrue);
      expect(inner.abortTriggered, isTrue);
      expect(
        inner.chunksEmitted,
        3,
        reason: 'the 3rd chunk crosses 250 bytes; no 4th is ever pulled',
      );
    });

    test('a body exactly at maxResponseBytes is accepted', () async {
      final client = TimeoutHttpClient(_OkClient('abcd'), maxResponseBytes: 4);
      expect((await client.get(url)).body, 'abcd');
    });

    testWidgets('a healthy response leaves no pending timers behind', (
      tester,
    ) async {
      final client = TimeoutHttpClient(
        _OkClient('ok'),
        totalDeadline: const Duration(seconds: 90),
      );
      final resp = await client.get(url);
      expect(resp.body, 'ok');
      // The binding's end-of-test invariant fails this test if any of the
      // connect / idle / total timers is still armed here.
    });

    testWidgets('a stalled body under a longer total deadline is cut by the '
        'IDLE timer and the source is cancelled', (tester) async {
      final inner = _TricklingClient(interval: const Duration(seconds: 30));
      final client = TimeoutHttpClient(
        inner,
        timeout: const Duration(milliseconds: 50),
        totalDeadline: const Duration(seconds: 5),
      );
      Object? error;
      unawaited(
        client
            .get(url)
            .then<void>(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(error, isA<http.ClientException>());
      expect((error! as http.ClientException).message, contains('stalled'));
      expect(inner.cancelled, isTrue);
      expect(inner.abortTriggered, isTrue);
    });

    testWidgets('a source error mid-body is forwarded and stops the timers', (
      tester,
    ) async {
      final client = TimeoutHttpClient(
        _ErroringBodyClient(),
        totalDeadline: const Duration(seconds: 90),
      );
      Object? error;
      unawaited(
        client
            .get(url)
            .then<void>(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            ),
      );
      await tester.pump();
      expect(error, isA<http.ClientException>());
      expect((error! as http.ClientException).message, 'boom');
      // No pending-timer assertion needed here: the binding fails the test
      // if any timer survives.
    });

    test('totalDeadline must not be shorter than the per-phase timeout', () {
      expect(
        () => TimeoutHttpClient(
          _OkClient(''),
          timeout: const Duration(seconds: 10),
          totalDeadline: const Duration(seconds: 5),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('LOOPBACK: a real socket to a server that never answers is closed '
        'when the deadline fires (not left open until GC)', () async {
      // flutter_test replaces the global HttpClient with a 400-only stub.
      // A bare HttpOverrides subclass inherits the SDK's real factory, and
      // runWithHttpOverrides scopes it to this test's zone only.
      await HttpOverrides.runWithHttpOverrides(() async {
        // A raw ServerSocket, not HttpServer: it reports the peer's FIN the
        // moment it arrives, so this observes the wire, not a parser state.
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final accepted = Completer<void>();
        final peerClosed = Completer<void>();
        server.listen((socket) {
          accepted.complete();
          // Read and discard forever; never write a byte back.
          socket.listen(
            (_) {},
            onDone: peerClosed.complete,
            onError: (Object _) => peerClosed.complete(),
          );
        });

        final client = TimeoutHttpClient(
          http.Client(),
          timeout: const Duration(milliseconds: 200),
        );
        addTearDown(client.close);
        final target = Uri.http('127.0.0.1:${server.port}', '/hang');

        await expectLater(
          client.get(target),
          throwsA(isA<http.ClientException>()),
        );
        await accepted.future;

        // Verified with a HEAD-shaped `Future.timeout` decorator in the same
        // harness: the server still saw the socket OPEN 2 s later. The
        // abortable request closes it within milliseconds of the deadline.
        final closed = await peerClosed.future
            .then((_) => true)
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        expect(
          closed,
          isTrue,
          reason:
              'server still holds the connection 2 s after the client '
              'deadline — the request was abandoned, not aborted',
        );
      }, _RealSockets());
    });
  });
}

/// Inherits [HttpOverrides.createHttpClient] unchanged — i.e. the SDK's real
/// `HttpClient` — so one test can open a genuine loopback socket under
/// flutter_test's global mock.
class _RealSockets extends HttpOverrides {}

/// A dead socket that also reports whether the request it received was an
/// [http.Abortable] whose trigger fired — the observable difference between
/// "stopped waiting" and "tore the connection down".
class _AbortAwareHangingClient extends http.BaseClient {
  bool abortTriggered = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() => abortTriggered = true));
    }
    return Completer<http.StreamedResponse>().future;
  }
}

/// Headers arrive instantly; the body emits one chunk, then errors.
class _ErroringBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> body() async* {
      yield [1];
      throw http.ClientException('boom', request.url);
    }

    return http.StreamedResponse(
      http.ByteStream(body()),
      200,
      request: request,
    );
  }
}

/// Headers arrive instantly; the body then emits [chunk] every [interval]
/// forever. Records how much the consumer actually pulled and whether the
/// consumer cancelled — a leak looks like an ever-growing [chunksEmitted].
class _TricklingClient extends http.BaseClient {
  _TricklingClient({required this.interval, this.chunk = const [1]});
  final Duration interval;
  final List<int> chunk;
  int chunksEmitted = 0;
  bool cancelled = false;
  bool abortTriggered = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() => abortTriggered = true));
    }
    Timer? timer;
    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        timer = Timer.periodic(interval, (_) {
          chunksEmitted++;
          controller.add(chunk);
        });
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return http.StreamedResponse(
      http.ByteStream(controller.stream),
      200,
      request: request,
    );
  }
}
