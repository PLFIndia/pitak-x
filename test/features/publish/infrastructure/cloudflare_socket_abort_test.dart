import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_transport.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_multipart_request.dart';

void main() {
  group('REAL LOOPBACK: Cloudflare deadlines close the socket', () {
    test('ordinary JSON request', () async {
      await expectSocketAbort(cloudflareJsonRequest('GET', null));
    });

    test('bucket multipart request', () async {
      const bytes = <int>[1, 2, 3];
      final assets = [
        CloudflareBucketAsset(
          hash: CloudflareAssetHash.of(bytes, 'json'),
          type: CloudflareContentType.json,
          size: bytes.length,
          openBytes: () => Stream.value(bytes),
        ),
      ];
      await expectSocketAbort(
        (uri) => cloudflareBucketMultipartRequest(url: uri, assets: assets),
      );
    });

    test('deploy multipart request', () async {
      final completion = CloudflareCompletionToken.tryParse('completion.jwt')!;
      await expectSocketAbort(
        (uri) => cloudflareDeployMultipartRequest(
          url: uri,
          completion: completion,
          kind: CloudflareDeploymentKind.live,
        ),
      );
    });

    test('one native client keeps a FIXED connect timeout, not the operation '
        'deadline (N14)', () async {
      final overrides = _RecordingOverrides();
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        server.listen((request) {
          request.response
            ..headers.contentType = ContentType.json
            ..write('{"success":true,"errors":[],"messages":[],"result":null}');
          unawaited(request.response.close());
        });
        final transport = CloudflareHttpTransport(
          apiBase: Uri.http('127.0.0.1:${server.port}', '/client/v4'),
        );
        addTearDown(transport.close);
        await transport.send(
          path: '/deadline',
          bearer: 'operation-secret',
          requestBuilder: cloudflareJsonRequest('GET', null),
          timing: const CloudflareRequestTiming(
            connect: Duration(milliseconds: 123),
            total: Duration(milliseconds: 123),
          ),
        );
        await transport.send(
          path: '/deadline',
          bearer: 'operation-secret',
          requestBuilder: cloudflareJsonRequest('GET', null),
          timing: const CloudflareRequestTiming(
            connect: Duration(minutes: 20),
            total: Duration(minutes: 20),
          ),
        );
        expect(
          overrides.clients,
          hasLength(1),
          reason: 'one pool, not per size',
        );
        expect(
          overrides.clients.single.connectionTimeout,
          CloudflareLimits.apiDeadline,
        );
      }, overrides);
    });
  });

  group('REAL LOOPBACK: upload progress bounds a large body (H2)', () {
    test(
      'a server that stops reading after 2 MiB is a stall, not a retry',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(server.close);
          var connections = 0;
          final peerClosed = Completer<void>();
          StreamSubscription<List<int>>? body;
          addTearDown(() => body?.cancel());
          server.listen((request) {
            connections++;
            var received = 0;
            var paused = false;
            body = request.listen(
              (chunk) {
                received += chunk.length;
                // Stop draining ONCE: the kernel buffer fills, TCP stops
                // accepting, and dart:io stops pulling the request body.
                if (!paused && received >= 2 * 1024 * 1024) {
                  paused = true;
                  body?.pause();
                }
              },
              onDone: () {
                if (!peerClosed.isCompleted) peerClosed.complete();
              },
              onError: (_) {
                if (!peerClosed.isCompleted) peerClosed.complete();
              },
            );
          });

          final transport = CloudflareHttpTransport(
            apiBase: Uri.http('127.0.0.1:${server.port}', '/client/v4'),
          );
          addTearDown(transport.close);

          await expectLater(
            transport.send(
              path: '/upload',
              bearer: 'operation-secret',
              requestBuilder: (uri) => _BodyRequest(
                'POST',
                uri,
                bytes: 8 * 1024 * 1024,
                chunk: 64 * 1024,
              ),
              // Short idle bound so the test is quick; the total is derived.
              timing: const CloudflareRequestTiming(
                connect: Duration(seconds: 5),
                idle: Duration(milliseconds: 400),
                responseWait: Duration(seconds: 5),
              ),
            ),
            throwsA(
              isA<CloudflareApiException>().having(
                (error) => error.kind,
                'kind',
                CloudflareApiExceptionKind.uploadStalled,
              ),
            ),
          );

          expect(connections, 1, reason: 'a stalled large body is not re-sent');
          // Resume reading so the server can observe the closed socket.
          body?.resume();
          final closed = await peerClosed.future
              .then((_) => true)
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          expect(closed, isTrue, reason: 'the server must observe the close');
        }, _RealSockets());
      },
    );

    test(
      'a slow but steadily drained body outlives the old per-phase bound',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(server.close);
          server.listen((request) async {
            await for (final _ in request) {
              // 64 KiB per 20 ms ≈ 3.2 MiB/s: healthy, but far slower than the
              // old 60 s-per-whole-body rule allowed for a large bucket.
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'success': true,
                  'errors': <Object?>[],
                  'messages': <Object?>[],
                  'result': null,
                }),
              );
            await request.response.close();
          });

          final transport = CloudflareHttpTransport(
            apiBase: Uri.http('127.0.0.1:${server.port}', '/client/v4'),
          );
          addTearDown(transport.close);

          final response = await transport.send(
            path: '/upload',
            bearer: 'operation-secret',
            requestBuilder: (uri) => _BodyRequest(
              'POST',
              uri,
              bytes: 4 * 1024 * 1024,
              chunk: 64 * 1024,
            ),
            // The old single bound (100 ms) would have aborted this upload.
            timing: const CloudflareRequestTiming(
              connect: Duration(milliseconds: 100),
              idle: Duration(seconds: 5),
              responseWait: Duration(seconds: 5),
              total: Duration(seconds: 60),
            ),
          );

          expect(response, isNotNull);
          expect(response!.statusCode, 200);
        }, _RealSockets());
      },
    );
  });
}

Future<void> expectSocketAbort(CloudflareRequestBuilder requestBuilder) async {
  await HttpOverrides.runWithHttpOverrides(() async {
    // A raw socket proves the peer received FIN/RST; merely catching a timeout
    // would not prove that the request stopped using the connection.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = Completer<void>();
    final peerClosed = Completer<void>();
    server.listen((socket) {
      if (!accepted.isCompleted) accepted.complete();
      socket.listen(
        (_) {},
        onDone: () {
          if (!peerClosed.isCompleted) peerClosed.complete();
        },
        onError: (_) {
          if (!peerClosed.isCompleted) peerClosed.complete();
        },
      );
    });

    final transport = CloudflareHttpTransport(
      apiBase: Uri.http('127.0.0.1:${server.port}', '/client/v4'),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.send(
        path: '/timeout',
        bearer: 'operation-secret',
        requestBuilder: requestBuilder,
        timing: const CloudflareRequestTiming(
          connect: Duration(milliseconds: 100),
          total: Duration(milliseconds: 100),
        ),
        idempotent: false,
      ),
      throwsA(
        isA<CloudflareApiException>().having(
          (error) => error.kind,
          'kind',
          CloudflareApiExceptionKind.timeout,
        ),
      ),
    );
    await accepted.future.timeout(const Duration(seconds: 2));
    final closed = await peerClosed.future
        .then((_) => true)
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    expect(closed, isTrue, reason: 'the server must observe the socket close');
  }, _RealSockets());
}

/// A streamed request body of [bytes] zeros, produced lazily in [chunk] pieces.
///
/// Used to prove the upload bound follows real progress instead of one
/// wall-clock number; nothing is buffered.
final class _BodyRequest extends http.BaseRequest {
  _BodyRequest(
    super.method,
    super.url, {
    required this.bytes,
    required this.chunk,
  });

  final int bytes;
  final int chunk;

  @override
  int get contentLength => bytes;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body());
  }

  Stream<List<int>> _body() async* {
    final piece = List<int>.filled(chunk, 0);
    var sent = 0;
    while (sent < bytes) {
      final size = bytes - sent < chunk ? bytes - sent : chunk;
      sent += size;
      yield size == chunk ? piece : piece.sublist(0, size);
    }
  }
}

/// Uses the SDK's real loopback HttpClient inside flutter_test's mocked zone.
final class _RealSockets extends HttpOverrides {}

/// Records real native clients so the test can inspect their configured bound.
final class _RecordingOverrides extends HttpOverrides {
  final List<HttpClient> clients = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    clients.add(client);
    return client;
  }
}
