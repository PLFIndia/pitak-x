import 'dart:async';

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
}
