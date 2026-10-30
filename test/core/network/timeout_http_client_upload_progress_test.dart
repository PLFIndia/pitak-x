import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';

import '../../features/publish/support/paced_body.dart';

/// A request whose body is produced by a paced stream, so `fakeAsync` decides
/// exactly when the "network" pulls the next chunk.
final class _PacedRequest extends http.BaseRequest {
  _PacedRequest(super.method, super.url, this._body, this._length);

  final Stream<List<int>> _body;
  final int _length;

  @override
  int get contentLength => _length;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

void main() {
  final url = Uri.parse('https://api.cloudflare.com/client/v4/upload');
  const chunk = 64 * 1024;

  /// Builds the client under test with upload mode on.
  TimeoutHttpClient uploadClient(
    http.Client inner, {
    required Duration connect,
    required Duration idle,
    required Duration headers,
    required Duration total,
    void Function(int sent)? onProgress,
  }) => TimeoutHttpClient(
    inner,
    timeout: connect,
    totalDeadline: total,
    requestBodyIdleTimeout: idle,
    responseHeadersTimeout: headers,
    onRequestBodyProgress: onProgress,
  );

  /// A mock that drains the body at the paced rate, then answers.
  MockClient draining({
    Duration beforeHeaders = Duration.zero,
    void Function()? onAbort,
  }) => MockClient.streaming((request, body) async {
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) => onAbort?.call()));
    }
    await body.drain<void>();
    if (beforeHeaders > Duration.zero) {
      await Future<void>.delayed(beforeHeaders);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  });

  test('a slow but steadily pulled body outlives the per-phase timeout', () {
    fakeAsync((async) {
      final progress = <int>[];
      final client = uploadClient(
        draining(),
        connect: const Duration(seconds: 1),
        idle: const Duration(seconds: 5),
        headers: const Duration(seconds: 5),
        total: const Duration(seconds: 60),
        onProgress: progress.add,
      );
      addTearDown(client.close);

      Object? error;
      var done = false;
      client
          .send(
            _PacedRequest(
              'POST',
              url,
              pacedBody(
                totalBytes: 8 * chunk,
                pause: const Duration(seconds: 1),
              ),
              8 * chunk,
            ),
          )
          .then(
            (response) {
              done = true;
              unawaited(response.stream.drain<void>());
            },
            onError: (Object e) {
              error = e;
            },
          );

      // Eight seconds of body, far past the 1 s per-phase bound.
      async.elapse(const Duration(seconds: 9));

      expect(error, isNull);
      expect(done, isTrue);
      expect(progress, isNotEmpty);
      expect(progress.last, 8 * chunk, reason: 'progress is cumulative');
    });
  });

  test('no pull for the idle time is a stall, and the abort fires', () {
    fakeAsync((async) {
      var aborted = false;
      // Pull two chunks, then stop reading: the socket stops draining.
      final client = uploadClient(
        MockClient.streaming((request, body) async {
          if (request case http.Abortable(:final abortTrigger?)) {
            unawaited(abortTrigger.then((_) => aborted = true));
          }
          await body.take(2).drain<void>();
          await Completer<void>().future;
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
        connect: const Duration(seconds: 1),
        idle: const Duration(seconds: 5),
        headers: const Duration(seconds: 5),
        total: const Duration(minutes: 5),
      );
      addTearDown(client.close);

      Object? error;
      client
          .send(
            _PacedRequest(
              'POST',
              url,
              pacedBody(
                totalBytes: 20 * chunk,
                pause: const Duration(seconds: 1),
              ),
              20 * chunk,
            ),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );

      async.elapse(const Duration(seconds: 20));

      expect(error, isA<http.ClientException>());
      expect((error! as http.ClientException).message, 'Upload stalled for 5s');
      expect(aborted, isTrue, reason: 'the socket must be closed');
    });
  });

  test('the response-header wait starts only after the body ends', () {
    fakeAsync((async) {
      final client = uploadClient(
        draining(beforeHeaders: const Duration(seconds: 6)),
        connect: const Duration(seconds: 1),
        idle: const Duration(seconds: 5),
        headers: const Duration(seconds: 5),
        total: const Duration(seconds: 60),
      );
      addTearDown(client.close);

      Object? error;
      client
          .send(
            _PacedRequest(
              'POST',
              url,
              pacedBody(
                totalBytes: 2 * chunk,
                pause: const Duration(seconds: 1),
              ),
              2 * chunk,
            ),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );

      async.elapse(const Duration(seconds: 20));

      expect(error, isA<http.ClientException>());
      expect(
        (error! as http.ClientException).message,
        'Response headers timed out after 5s',
      );
    });
  });

  test('the total deadline still ends a trickle that always progresses', () {
    fakeAsync((async) {
      final client = uploadClient(
        draining(),
        connect: const Duration(seconds: 1),
        idle: const Duration(seconds: 5),
        headers: const Duration(seconds: 5),
        total: const Duration(seconds: 4),
      );
      addTearDown(client.close);

      Object? error;
      client
          .send(
            _PacedRequest(
              'POST',
              url,
              pacedBody(
                totalBytes: 20 * chunk,
                pause: const Duration(seconds: 1),
              ),
              20 * chunk,
            ),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );

      async.elapse(const Duration(seconds: 30));

      expect(error, isA<http.ClientException>());
      expect(
        (error! as http.ClientException).message,
        'Request exceeded 4s',
        reason: 'a trickle is bounded by the total, not the idle timer',
      );
    });
  });

  test('without the upload parameters the old behaviour is unchanged', () {
    fakeAsync((async) {
      final progress = <int>[];
      final client = TimeoutHttpClient(
        draining(),
        timeout: const Duration(seconds: 1),
        totalDeadline: const Duration(seconds: 1),
        onRequestBodyProgress: progress.add,
      );
      addTearDown(client.close);

      Object? error;
      client
          .send(
            _PacedRequest(
              'POST',
              url,
              pacedBody(
                totalBytes: 8 * chunk,
                pause: const Duration(seconds: 1),
              ),
              8 * chunk,
            ),
          )
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );

      async.elapse(const Duration(seconds: 10));

      expect(error, isA<http.ClientException>());
      expect(
        (error! as http.ClientException).message,
        'Request timed out after 1s',
        reason: 'the per-phase bound still covers the whole body',
      );
      expect(progress, isEmpty, reason: 'no upload mode, no progress watch');
    });
  });
}
