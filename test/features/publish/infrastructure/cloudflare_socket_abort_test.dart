import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
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

    test('native connect timeout matches the operation deadline', () async {
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
        const deadline = Duration(milliseconds: 123);
        await transport.send(
          path: '/deadline',
          bearer: 'operation-secret',
          requestBuilder: cloudflareJsonRequest('GET', null),
          deadline: deadline,
        );
        expect(overrides.clients, hasLength(1));
        expect(overrides.clients.single.connectionTimeout, deadline);
      }, overrides);
    });
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
        deadline: const Duration(milliseconds: 100),
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
