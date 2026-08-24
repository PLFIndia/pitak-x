import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/lookup_http_client.dart';

void main() {
  Future<void> noSleep(Duration _) async {}
  final url = Uri.parse('https://api.test/books');

  LookupHttpClient client(Future<http.Response> Function(http.Request) h) =>
      LookupHttpClient(MockClient(h), sleep: noSleep);

  test('adds the descriptive User-Agent to every request', () async {
    String? seenUa;
    final c = client((req) async {
      seenUa = req.headers['User-Agent'] ?? req.headers['user-agent'];
      return http.Response('{}', 200);
    });
    await c.get(url);
    expect(seenUa, LookupHttpClient.userAgent);
    expect(seenUa, contains('Pitaka'));
  });

  test('does not clobber a caller-set User-Agent', () async {
    String? seenUa;
    final c = client((req) async {
      seenUa = req.headers['User-Agent'] ?? req.headers['user-agent'];
      return http.Response('{}', 200);
    });
    await c.get(url, headers: {'User-Agent': 'custom/1.0'});
    expect(seenUa, 'custom/1.0');
  });

  test('retries a GET once on 429 and returns the retry response', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      return calls == 1 ? http.Response('', 429) : http.Response('ok', 200);
    });
    final resp = await c.get(url);
    expect(calls, 2);
    expect(resp.statusCode, 200);
    expect(resp.body, 'ok');
  });

  test('retries a GET once on 503', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      return calls == 1 ? http.Response('', 503) : http.Response('ok', 200);
    });
    expect((await c.get(url)).statusCode, 200);
    expect(calls, 2);
  });

  test('retries at most once — second 429 is surfaced', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      return http.Response('', 429);
    });
    expect((await c.get(url)).statusCode, 429);
    expect(calls, 2);
  });

  test('does not retry deterministic 4xx', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      return http.Response('', 404);
    });
    expect((await c.get(url)).statusCode, 404);
    expect(calls, 1);
  });

  test('retries a GET once on a transport exception', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      if (calls == 1) throw http.ClientException('reset', req.url);
      return http.Response('ok', 200);
    });
    expect((await c.get(url)).statusCode, 200);
    expect(calls, 2);
  });

  test('surfaces the first response when the retry also throws', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      if (calls == 2) throw http.ClientException('reset', req.url);
      return http.Response('', 503);
    });
    expect((await c.get(url)).statusCode, 503);
    expect(calls, 2);
  });

  test('never retries POST (non-idempotent)', () async {
    var calls = 0;
    final c = client((req) async {
      calls++;
      return http.Response('', 503);
    });
    expect((await c.post(url)).statusCode, 503);
    expect(calls, 1);
  });
}
