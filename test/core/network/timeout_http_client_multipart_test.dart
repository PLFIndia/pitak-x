import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';

void main() {
  final url = Uri.parse('https://api.cloudflare.com/client/v4/test');

  test(
    'multipart bytes and generated content type survive the wrapper',
    () async {
      late String seenContentType;
      late String seenBody;
      final client = TimeoutHttpClient(
        MockClient((request) async {
          seenContentType = request.headers['content-type']!;
          seenBody = request.body;
          return http.Response('{}', 200);
        }),
      );
      final request = http.MultipartRequest('POST', url)
        ..fields['metadata'] = '{"assets":{}}'
        ..files.add(
          http.MultipartFile.fromString('hash', 'aGVsbG8=', filename: 'hash'),
        );

      final response = await client.send(request);
      await response.stream.drain<void>();

      final boundary = seenContentType.split('boundary=').last;
      expect(seenContentType, startsWith('multipart/form-data; boundary='));
      expect(seenBody, contains('--$boundary\r\n'));
      expect(seenBody, contains('name="metadata"'));
      expect(seenBody, contains('name="hash"; filename="hash"'));
      expect(seenBody, contains('aGVsbG8='));
    },
  );

  test('a stalled streamed request body is genuinely aborted', () async {
    var abortReachedTransport = false;
    final hanging = MockClient.streaming((request, _) {
      final pending = Completer<http.StreamedResponse>();
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(() {
            abortReachedTransport = true;
            if (!pending.isCompleted) {
              pending.completeError(http.RequestAbortedException(request.url));
            }
          }),
        );
      }
      return pending.future;
    });
    final client = TimeoutHttpClient(
      hanging,
      timeout: const Duration(milliseconds: 20),
    );
    final request = http.StreamedRequest('POST', url)
      ..sink.add(utf8.encode('partial'));

    await expectLater(
      client.send(request),
      throwsA(isA<http.ClientException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(abortReachedTransport, isTrue);
  });

  test('a multipart request inherits the decorator deadline', () async {
    var abortReachedTransport = false;
    final hanging = MockClient.streaming((request, _) {
      final pending = Completer<http.StreamedResponse>();
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(() {
            abortReachedTransport = true;
            if (!pending.isCompleted) {
              pending.completeError(http.RequestAbortedException(request.url));
            }
          }),
        );
      }
      return pending.future;
    });
    final client = TimeoutHttpClient(
      hanging,
      timeout: const Duration(milliseconds: 20),
    );
    final request = http.MultipartRequest('PUT', url)
      ..fields['metadata'] = '{"assets":{}}';

    await expectLater(
      client.send(request),
      throwsA(isA<http.ClientException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(abortReachedTransport, isTrue);
  });

  test('a multipart caller abort is chained through the decorator', () async {
    var abortReachedTransport = false;
    final hanging = MockClient.streaming((request, _) {
      final pending = Completer<http.StreamedResponse>();
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(() {
            abortReachedTransport = true;
            if (!pending.isCompleted) {
              pending.completeError(http.RequestAbortedException(request.url));
            }
          }),
        );
      }
      return pending.future;
    });
    final callerAbort = Completer<void>();
    final client = TimeoutHttpClient(hanging);
    final request = http.AbortableMultipartRequest(
      'POST',
      url,
      abortTrigger: callerAbort.future,
    )..fields['metadata'] = '{"assets":{}}';

    final pending = client.send(request);
    callerAbort.complete();

    await expectLater(pending, throwsA(isA<http.ClientException>()));
    expect(abortReachedTransport, isTrue);
  });
}
