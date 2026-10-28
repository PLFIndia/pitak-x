import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
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
}
