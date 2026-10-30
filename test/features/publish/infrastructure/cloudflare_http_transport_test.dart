import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';

void main() {
  final delays = <Duration>[];

  CloudflareHttpTransport transportFor(
    http.Client client, {
    Future<void> Function(Duration)? sleep,
  }) {
    final transport = CloudflareHttpTransport(
      client: client,
      sleep: sleep ?? (delay) async => delays.add(delay),
    );
    addTearDown(transport.close);
    return transport;
  }

  http.Response envelope({int status = 200}) => http.Response(
    jsonEncode({
      'success': status == 200,
      'errors': <Object?>[],
      'messages': <Object?>[],
      'result': null,
    }),
    status,
  );

  Future<CloudflareHttpResponse?> send(CloudflareHttpTransport transport) =>
      transport.send(
        path: '/test',
        bearer: 'secret-token',
        requestBuilder: cloudflareJsonRequest('GET', null),
      );

  setUp(delays.clear);

  test('a redirect is refused without forwarding credentials', () async {
    final calls = <http.Request>[];
    final transport = transportFor(
      MockClient((request) async {
        calls.add(request);
        return http.Response(
          'redirect body must not be read',
          302,
          headers: {'location': 'https://evil.example/steal'},
        );
      }),
    );

    await expectLater(
      send(transport),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.kind,
          'kind',
          CloudflareApiExceptionKind.redirect,
        ),
      ),
    );
    expect(calls, hasLength(1));
    expect(calls.single.followRedirects, isFalse);
    expect(calls.single.headers['authorization'], 'Bearer secret-token');
  });

  test('error results and raw messages are discarded immediately', () async {
    const rawMessage = 'raw response and token material';
    final transport = transportFor(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'code': 10000, 'message': rawMessage},
            ],
            'messages': [rawMessage],
            'result': {'unexpected': rawMessage},
          }),
          400,
        ),
      ),
    );
    final response = await send(transport);
    expect(response?.result, isNull);
    expect(response?.errorCodes, [10000]);
    expect(response.toString(), isNot(contains(rawMessage)));
  });

  test('a streamed over-cap response is aborted and cancelled', () async {
    var aborted = false;
    var cancelled = false;
    Timer? timer;
    late StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        timer = Timer.periodic(const Duration(milliseconds: 2), (_) {
          if (!body.isClosed) body.add(List<int>.filled(600 * 1024, 7));
        });
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    final transport = transportFor(
      MockClient.streaming((request, _) async {
        if (request case http.Abortable(:final abortTrigger?)) {
          unawaited(abortTrigger.whenComplete(() => aborted = true));
        }
        return http.StreamedResponse(body.stream, 200, request: request);
      }),
    );

    await expectLater(
      send(transport),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.kind,
          'kind',
          CloudflareApiExceptionKind.responseTooLarge,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(aborted, isTrue);
    expect(cancelled, isTrue);
  });

  test('an oversized declared body is cancelled before any chunks', () async {
    var chunks = 0;
    var cancelled = false;
    Timer? timer;
    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
          chunks++;
          if (!controller.isClosed) controller.add([1]);
        });
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    final transport = transportFor(
      MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          controller.stream,
          200,
          contentLength: CloudflareLimits.maxApiBodyBytes + 1,
          request: request,
        ),
      ),
    );

    await expectLater(
      send(transport),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.kind,
          'kind',
          CloudflareApiExceptionKind.responseTooLarge,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(chunks, 0);
    expect(cancelled, isTrue);
  });

  test('excess JSON depth is a typed malformed response', () async {
    final body =
        '{"success":true,"errors":[],"result":'
        '${'[' * 16}${']' * 16}}';
    final transport = transportFor(
      MockClient((_) async => http.Response(body, 200)),
    );
    await expectLater(
      send(transport),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.kind,
          'kind',
          CloudflareApiExceptionKind.malformedResponse,
        ),
      ),
    );
  });

  test('429 Retry-After is honored once and capped at 60 seconds', () async {
    var calls = 0;
    final transport = transportFor(
      MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'success': false,
            'errors': <Object?>[],
            'messages': <Object?>[],
            'result': null,
          }),
          429,
          headers: {'retry-after': '120'},
        );
      }),
    );
    final response = await send(transport);
    expect(response?.statusCode, 429);
    expect(calls, 2);
    expect(delays, [const Duration(seconds: 60)]);
  });

  test('5xx retries stop after three total attempts', () async {
    var calls = 0;
    final transport = transportFor(
      MockClient((_) async {
        calls++;
        return envelope(status: 500);
      }),
    );
    final response = await send(transport);
    expect(response?.statusCode, 500);
    expect(calls, CloudflareLimits.maxAttempts);
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test('network retries stay bounded and redact the platform error', () async {
    var calls = 0;
    const rawError = 'raw socket and credential text';
    final transport = transportFor(
      MockClient((_) async {
        calls++;
        throw http.ClientException(rawError);
      }),
    );
    await expectLater(
      send(transport),
      throwsA(
        isA<CloudflareApiException>()
            .having((e) => e.kind, 'kind', CloudflareApiExceptionKind.network)
            .having((e) => e.toString(), 'redacted', isNot(contains(rawError))),
      ),
    );
    expect(calls, CloudflareLimits.maxAttempts);
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  test('a non-idempotent write is never blindly retried', () async {
    var calls = 0;
    final transport = transportFor(
      MockClient((_) async {
        calls++;
        throw http.ClientException('connection lost');
      }),
    );
    await expectLater(
      transport.send(
        path: '/deploy',
        bearer: 'secret-token',
        requestBuilder: cloudflareJsonRequest('PUT', {'x': true}),
        idempotent: false,
      ),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.uncertain,
          'uncertain',
          isTrue,
        ),
      ),
    );
    expect(calls, 1);
    expect(delays, isEmpty);
  });

  group('upload timing and retry policy (H2)', () {
    /// A request whose body is [bytes] zeros, produced lazily in 64 KiB pieces.
    CloudflareRequestBuilder bodyOf(int bytes) =>
        (uri) => _BodyRequest('POST', uri, bytes: bytes);

    test(
      'a connect failure with no bytes sent still retries three times',
      () async {
        var calls = 0;
        final transport = transportFor(
          MockClient.streaming((request, body) async {
            calls++;
            throw http.ClientException('connection lost', request.url);
          }),
        );
        await expectLater(
          transport.send(
            path: '/upload',
            bearer: 'secret-token',
            requestBuilder: bodyOf(4 * 1024 * 1024),
            timing: const CloudflareRequestTiming.upload(),
          ),
          throwsA(
            isA<CloudflareApiException>().having(
              (e) => e.kind,
              'kind',
              CloudflareApiExceptionKind.network,
            ),
          ),
        );
        expect(calls, CloudflareLimits.maxAttempts);
      },
    );

    test('a stall after more than 1 MiB is not re-sent', () async {
      var calls = 0;
      final transport = transportFor(
        MockClient.streaming((request, body) async {
          calls++;
          // Drain past the blind-resend limit, then report a stall.
          var sent = 0;
          await for (final chunk in body) {
            sent += chunk.length;
            if (sent > CloudflareLimits.blindResendMaxBytes) break;
          }
          throw http.ClientException('Upload stalled for 60s', request.url);
        }),
      );
      await expectLater(
        transport.send(
          path: '/upload',
          bearer: 'secret-token',
          requestBuilder: bodyOf(4 * 1024 * 1024),
          timing: const CloudflareRequestTiming.upload(),
        ),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.uploadStalled,
          ),
        ),
      );
      expect(calls, 1, reason: 're-sending 4 MiB would spend the data twice');
      expect(delays, isEmpty);
    });

    test('a 5xx after a large body is re-sent at most once', () async {
      var calls = 0;
      final transport = transportFor(
        MockClient.streaming((request, body) async {
          calls++;
          await body.drain<void>();
          return http.StreamedResponse(const Stream.empty(), 500);
        }),
      );
      final response = await transport.send(
        path: '/upload',
        bearer: 'secret-token',
        requestBuilder: bodyOf(4 * 1024 * 1024),
        timing: const CloudflareRequestTiming.upload(),
      );
      expect(calls, 2, reason: 'one resend, not three');
      expect(
        () => requireCloudflareSuccess(response!),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.server,
          ),
        ),
      );
    });

    test('a 5xx after a small body still retries three times', () async {
      var calls = 0;
      final transport = transportFor(
        MockClient.streaming((request, body) async {
          calls++;
          await body.drain<void>();
          return http.StreamedResponse(const Stream.empty(), 500);
        }),
      );
      await transport.send(
        path: '/upload',
        bearer: 'secret-token',
        requestBuilder: bodyOf(64 * 1024),
        timing: const CloudflareRequestTiming.upload(),
      );
      expect(calls, CloudflareLimits.maxAttempts);
    });

    test('an artifact that changes mid-upload is never retried', () async {
      var calls = 0;
      final transport = transportFor(
        MockClient.streaming((request, body) async {
          calls++;
          await body.drain<void>();
          throw const CloudflareAssetHashException();
        }),
      );
      await expectLater(
        transport.send(
          path: '/upload',
          bearer: 'secret-token',
          requestBuilder: bodyOf(64 * 1024),
          timing: const CloudflareRequestTiming.upload(),
        ),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.artifactChanged,
          ),
        ),
      );
      expect(calls, 1);
      expect(delays, isEmpty);
    });
  });

  group('status-first classification (L8)', () {
    /// Sends [response] and returns the transport's own result.
    Future<(int, CloudflareHttpResponse?)> sendStatus(
      http.Response response,
    ) async {
      var calls = 0;
      final transport = transportFor(
        MockClient((_) async {
          calls++;
          return response;
        }),
      );
      final result = await transport.send(
        path: '/test',
        bearer: 'secret-token',
        requestBuilder: cloudflareJsonRequest('GET', null),
      );
      return (calls, result);
    }

    test(
      'a non-JSON 502 is a server failure, not an unreadable response',
      () async {
        final (calls, response) = await sendStatus(
          http.Response('<html>bad gateway</html>', 502),
        );
        expect(calls, CloudflareLimits.maxAttempts);
        expect(response!.statusCode, 502);
        expect(
          () => requireCloudflareSuccess(response),
          throwsA(
            isA<CloudflareApiException>().having(
              (e) => e.kind,
              'kind',
              CloudflareApiExceptionKind.server,
            ),
          ),
        );
      },
    );

    test('a non-JSON second 429 is rate-limited', () async {
      final (calls, response) = await sendStatus(
        http.Response('<html>slow down</html>', 429),
      );
      expect(calls, 2, reason: 'one Retry-After retry, then stop');
      expect(
        () => requireCloudflareSuccess(response!),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.rateLimited,
          ),
        ),
      );
    });

    test('a non-JSON 403 stays malformed so setup cannot act on it', () async {
      var calls = 0;
      final transport = transportFor(
        MockClient((_) async {
          calls++;
          return http.Response('<html>forbidden</html>', 403);
        }),
      );
      await expectLater(
        send(transport),
        throwsA(
          isA<CloudflareApiException>().having(
            (e) => e.kind,
            'kind',
            CloudflareApiExceptionKind.malformedResponse,
          ),
        ),
      );
      expect(calls, 1);
    });
  });
}

/// A streamed request body of [bytes] zeros, produced lazily.
final class _BodyRequest extends http.BaseRequest {
  _BodyRequest(super.method, super.url, {required this.bytes});

  final int bytes;

  @override
  int get contentLength => bytes;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body());
  }

  Stream<List<int>> _body() async* {
    const chunk = 64 * 1024;
    var sent = 0;
    while (sent < bytes) {
      final size = bytes - sent < chunk ? bytes - sent : chunk;
      sent += size;
      yield List<int>.filled(size, 0);
    }
  }
}
