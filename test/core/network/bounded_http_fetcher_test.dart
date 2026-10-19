import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';

/// Generic-fetcher ports of the cover-fetcher security cases (docs/ARCHITECTURE.md
/// §5.6): allow-list, redirect re-validation, byte cap, timeout ABORT and
/// never draining rejected bodies. The allow-list here is a test-local
/// https+host rule — the same SHAPE `CoverUrlAllowList.sanitize` and
/// `BookmarkUrl.normalize` have.

const _allowedHosts = {
  'covers.openlibrary.org',
  'books.google.com',
  'books.googleusercontent.com',
};

String? _sanitize(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (!_allowedHosts.contains(uri.host.toLowerCase())) return null;
  return trimmed;
}

/// Ten 3-byte chunks — a body long enough for a deadline to cut it short.
List<List<int>> tenChunks() => List.generate(10, (_) => [1, 2, 3]);

BoundedHttpFetcher _fetcher(
  http.Client client, {
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = BoundedHttpFetcher.defaultMaxBytes,
}) => BoundedHttpFetcher(
  client: client,
  sanitize: _sanitize,
  timeout: timeout,
  maxBytes: maxBytes,
);

/// Builds a streaming MockClient whose body is [chunks], emitted in order,
/// one per [chunkDelay] tick (same harness as bounded_cover_fetcher_test).
/// [recordHosts] captures every host asked for, so a test can assert a
/// rejected URL never produced a network call. [probe] records the SERVER side.
MockClient _streaming(
  List<List<int>> chunks, {
  int status = 200,
  int? contentLength,
  List<String>? recordHosts,
  Duration chunkDelay = Duration.zero,
  _BodyProbe? probe,
}) {
  return MockClient.streaming((request, _) async {
    recordHosts?.add(request.url.host);
    var next = 0;
    Timer? timer;
    late StreamController<List<int>> body;
    void emit() {
      if (body.isClosed) return;
      if (next >= chunks.length) {
        timer?.cancel();
        unawaited(body.close());
        return;
      }
      probe?.chunksPulled++;
      body.add(chunks[next++]);
    }

    body = StreamController<List<int>>(
      onListen: () {
        if (chunkDelay == Duration.zero) {
          while (!body.isClosed) {
            emit();
          }
        } else {
          timer = Timer.periodic(chunkDelay, (_) => emit());
        }
      },
      onCancel: () {
        timer?.cancel();
        probe?.bodyClosed = true;
      },
    );
    // Honour abortTrigger the way IOClient does (inject the abort error, close
    // the body) — MockClient itself never aborts.
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          probe?.aborted = true;
          timer?.cancel();
          if (!body.isClosed) {
            body
              ..addError(http.RequestAbortedException(request.url))
              ..close();
          }
        }),
      );
    }
    return http.StreamedResponse(
      body.stream,
      status,
      contentLength: contentLength,
      request: request,
    );
  });
}

/// What the SERVER side observed.
class _BodyProbe {
  int chunksPulled = 0;
  bool bodyClosed = false;
  bool aborted = false;
}

List<int>? _bytesOf(BoundedFetchOutcome r) => switch (r) {
  FetchedBytes(:final bytes) => bytes,
  FetchRefused() => null,
};

FetchRefusal? _reasonOf(BoundedFetchOutcome r) => switch (r) {
  FetchedBytes() => null,
  FetchRefused(:final reason) => reason,
};

void main() {
  const allowed = 'https://covers.openlibrary.org/b/id/123-L.jpg';

  group('origin allow-list (defence 1)', () {
    test('rejects a non-allow-listed host WITHOUT any network call', () async {
      final hosts = <String>[];
      final fetcher = _fetcher(
        _streaming([
          [1, 2, 3],
        ], recordHosts: hosts),
      );

      final result = await fetcher.fetch('https://evil.example.com/track.jpg');

      expect(_reasonOf(result), FetchRefusal.disallowedUrl);
      expect(hosts, isEmpty, reason: 'poisoned URL must not leave the device');
    });

    test('rejects http (non-https) without a call', () async {
      final hosts = <String>[];
      final fetcher = _fetcher(
        _streaming([
          [1],
        ], recordHosts: hosts),
      );

      expect(
        _reasonOf(
          await fetcher.fetch('http://covers.openlibrary.org/b/id/1-L.jpg'),
        ),
        FetchRefusal.disallowedUrl,
      );
      expect(hosts, isEmpty);
    });

    test('rejects userinfo smuggling without a call', () async {
      final hosts = <String>[];
      final fetcher = _fetcher(
        _streaming([
          [1],
        ], recordHosts: hosts),
      );

      expect(
        _reasonOf(
          await fetcher.fetch('https://x@covers.openlibrary.org/1.jpg'),
        ),
        FetchRefusal.disallowedUrl,
      );
      expect(hosts, isEmpty);
    });
  });

  group('byte cap (defence 3)', () {
    test('aborts a body that streams past maxBytes', () async {
      final fetcher = _fetcher(
        _streaming([
          List<int>.filled(4, 7),
          List<int>.filled(4, 7), // 8 bytes total, cap is 5
        ]),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.tooLarge);
    });

    test('rejects on an honest oversized Content-Length', () async {
      final fetcher = _fetcher(
        _streaming([
          [1, 2, 3],
        ], contentLength: 1000),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.tooLarge);
    });

    test('accepts a body exactly at the cap', () async {
      final fetcher = _fetcher(
        _streaming([
          [1, 2, 3, 4, 5],
        ], contentLength: 5),
        maxBytes: 5,
      );

      expect(_bytesOf(await fetcher.fetch(allowed)), equals([1, 2, 3, 4, 5]));
    });
  });

  group('status + timeout', () {
    test('refuses non-2xx', () async {
      final fetcher = _fetcher(
        _streaming([
          [1, 2, 3],
        ], status: 404),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.httpStatus);
    });

    test('refuses when the request exceeds the timeout', () async {
      final fetcher = _fetcher(
        _streaming([
          [1, 2, 3],
        ], chunkDelay: const Duration(milliseconds: 200)),
        timeout: const Duration(milliseconds: 20),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.timedOut);
    });
  });

  test('happy path returns the full allow-listed body', () async {
    final fetcher = _fetcher(
      _streaming([
        [10, 20],
        [30, 40],
      ], contentLength: 4),
    );

    expect(_bytesOf(await fetcher.fetch(allowed)), equals([10, 20, 30, 40]));
  });

  group('redirects (re-validated per hop)', () {
    MockClient router(
      Map<String, http.StreamedResponse Function(http.BaseRequest)> routes, {
      List<String>? hits,
    }) {
      return MockClient.streaming((request, _) async {
        hits?.add('${request.url.host}${request.url.path}');
        final handler = routes[request.url.toString()];
        if (handler == null) {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            404,
            request: request,
          );
        }
        return handler(request);
      });
    }

    http.StreamedResponse redirect(http.BaseRequest req, String location) =>
        http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: {'location': location},
          request: req,
        );

    http.StreamedResponse ok(http.BaseRequest req, List<int> body) =>
        http.StreamedResponse(
          Stream.value(body),
          200,
          contentLength: body.length,
          request: req,
        );

    test('a redirect to a NON-allow-listed host is not followed', () async {
      final hits = <String>[];
      final fetcher = _fetcher(
        router({
          allowed: (req) => redirect(req, 'https://evil.example.com/track.jpg'),
          'https://evil.example.com/track.jpg': (req) => ok(req, [1]),
        }, hits: hits),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        FetchRefusal.redirectRefused,
      );
      expect(hits, ['covers.openlibrary.org/b/id/123-L.jpg']);
    });

    test('a redirect to another ALLOW-LISTED host is followed', () async {
      const start = 'https://books.google.com/books/content?vid=1';
      const end = 'https://books.googleusercontent.com/cover/1.jpg';
      final fetcher = _fetcher(
        router({
          start: (req) => redirect(req, end),
          end: (req) => ok(req, [9, 9]),
        }),
      );

      expect(_bytesOf(await fetcher.fetch(start)), equals([9, 9]));
    });

    test('IDENTIFICATION (M2): the app User-Agent rides on the initial '
        'request AND on every redirect hop', () async {
      const start = 'https://books.google.com/books/content?vid=1';
      const end = 'https://books.googleusercontent.com/cover/1.jpg';
      final userAgents = <String?>[];
      final fetcher = _fetcher(
        MockClient.streaming((request, _) async {
          userAgents.add(request.headers['User-Agent']);
          return request.url.toString() == start
              ? redirect(request, end)
              : ok(request, [1]);
        }),
      );

      expect(_bytesOf(await fetcher.fetch(start)), equals([1]));
      expect(userAgents, hasLength(2));
      expect(
        userAgents,
        everyElement(AppUserAgent.value),
        reason: 'a bare package:http request would say "Dart/3.x (dart:io)"',
      );
    });

    test('custom headers replace the default set', () async {
      String? seen;
      final fetcher = BoundedHttpFetcher(
        client: MockClient.streaming((request, _) async {
          seen = request.headers['X-Probe'];
          return ok(request, [1]);
        }),
        sanitize: _sanitize,
        headers: const {'X-Probe': 'yes'},
      );
      await fetcher.fetch(allowed);
      expect(seen, 'yes');
    });

    test('a relative Location resolves against the current URL', () async {
      final fetcher = _fetcher(
        router({
          allowed: (req) => redirect(req, '/b/id/999-L.jpg'),
          'https://covers.openlibrary.org/b/id/999-L.jpg': (req) =>
              ok(req, [7]),
        }),
      );

      expect(_bytesOf(await fetcher.fetch(allowed)), equals([7]));
    });

    test('a redirect to plain http is refused', () async {
      final fetcher = _fetcher(
        router({
          allowed: (req) =>
              redirect(req, 'http://covers.openlibrary.org/b/1-L.jpg'),
        }),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        FetchRefusal.redirectRefused,
      );
    });

    test('a redirect loop is abandoned after maxRedirects hops', () async {
      final hits = <String>[];
      final fetcher = _fetcher(
        router({allowed: (req) => redirect(req, allowed)}, hits: hits),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        FetchRefusal.tooManyRedirects,
      );
      expect(hits, hasLength(1 + BoundedHttpFetcher.defaultMaxRedirects));
    });

    test('a redirect without a Location header is dropped', () async {
      final fetcher = _fetcher(
        MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            302,
            request: request,
          ),
        ),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        FetchRefusal.redirectRefused,
      );
    });
  });

  group('rejected responses are cancelled, not drained (N08)', () {
    test('a non-2xx body is not read past the status line', () async {
      final probe = _BodyProbe();
      final fetcher = _fetcher(
        _streaming(
          tenChunks(),
          status: 404,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.httpStatus);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0, reason: 'nothing drained');
      expect(probe.bodyClosed, isTrue, reason: 'source cancelled');
    });

    test('an oversized Content-Length body is not read at all', () async {
      final probe = _BodyProbe();
      final fetcher = _fetcher(
        _streaming(
          tenChunks(),
          contentLength: 1000,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.tooLarge);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0);
      expect(probe.bodyClosed, isTrue);
    });

    test('a redirect hop body is cancelled, not drained', () async {
      final probe = _BodyProbe();
      final fetcher = _fetcher(
        _streaming(
          tenChunks(),
          status: 302,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        FetchRefusal.redirectRefused,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0);
      expect(probe.bodyClosed, isTrue);
    });

    test('an over-cap body stops at the crossing chunk and aborts', () async {
      final probe = _BodyProbe();
      final fetcher = _fetcher(
        _streaming(
          tenChunks(),
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
        maxBytes: 5, // chunk 2 crosses (6 > 5)
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.tooLarge);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 2, reason: 'no chunk pulled after the cap');
      expect(probe.bodyClosed, isTrue);
      expect(probe.aborted, isTrue, reason: 'socket torn down, not just left');
    });

    test('the timeout ABORTS the request and stops the body', () async {
      final probe = _BodyProbe();
      final fetcher = _fetcher(
        _streaming(
          tenChunks(),
          chunkDelay: const Duration(milliseconds: 30),
          probe: probe,
        ),
        timeout: const Duration(milliseconds: 50),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.timedOut);
      final pulledAtTimeout = probe.chunksPulled;
      expect(probe.aborted, isTrue, reason: 'abortTrigger must fire');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(probe.chunksPulled, pulledAtTimeout);
      expect(probe.bodyClosed, isTrue);
    });

    test('a transport error is a typed refusal', () async {
      final fetcher = _fetcher(
        MockClient.streaming(
          (request, _) async => throw http.ClientException('reset'),
        ),
      );
      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.transport);
    });
  });

  group('COMPOSITION (H2): through the production TimeoutHttpClient', () {
    // In production the fetcher runs over `httpClientProvider`, which is a
    // TimeoutHttpClient (60 s bounds). The decorator re-wraps every request
    // with its own abort trigger; before H2 that silently DROPPED the
    // fetcher's trigger, so its 15 s deadline stopped nothing and the real
    // bound was 60 s per hop. These tests drive the fetcher through the
    // decorator exactly as DI does.
    test(
      "the fetcher's deadline still ABORTS the socket under the decorator",
      () async {
        final probe = _BodyProbe();
        final decorated = TimeoutHttpClient(
          _streaming(
            tenChunks(),
            chunkDelay: const Duration(milliseconds: 30),
            probe: probe,
          ),
          // Production default (60 s): deliberately far looser than the
          // fetcher's own deadline, so only the fetcher's timer can fire.
        );
        final fetcher = _fetcher(
          decorated,
          timeout: const Duration(milliseconds: 50),
        );

        final stopwatch = Stopwatch()..start();
        expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.timedOut);
        stopwatch.stop();
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: "the FETCHER's 50 ms deadline must govern, not the 60 s",
        );
        final pulledAtTimeout = probe.chunksPulled;
        expect(probe.aborted, isTrue, reason: 'the abort reached the server');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(probe.chunksPulled, pulledAtTimeout, reason: 'body stopped');
        expect(probe.bodyClosed, isTrue);
      },
    );

    test("a connection that never answers is aborted by the fetcher's "
        "deadline, not the decorator's", () async {
      var abortReachedServer = false;
      // A host that never answers — on an honest `Abortable` transport: like
      // the real IOClient, the pending send fails with
      // RequestAbortedException the moment the trigger fires.
      final hanging = MockClient.streaming((request, _) {
        final pending = Completer<http.StreamedResponse>();
        if (request case http.Abortable(:final abortTrigger?)) {
          unawaited(
            abortTrigger.whenComplete(() {
              abortReachedServer = true;
              if (!pending.isCompleted) {
                pending.completeError(
                  http.RequestAbortedException(request.url),
                );
              }
            }),
          );
        }
        return pending.future;
      });
      final fetcher = _fetcher(
        TimeoutHttpClient(hanging), // production default: 60 s
        timeout: const Duration(milliseconds: 30),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), FetchRefusal.timedOut);
      expect(abortReachedServer, isTrue);
    });

    test("the decorator's own tighter limit still wins when it is the "
        'shorter one', () async {
      final fetcher = _fetcher(
        TimeoutHttpClient(
          _streaming([
            [1, 2, 3],
          ], chunkDelay: const Duration(milliseconds: 200)),
          timeout: const Duration(milliseconds: 20),
        ),
      );
      // Either bound tripping is a refusal — never a hang or a throw. The
      // decorator reports its trip as a ClientException, which the fetcher
      // maps to `transport` (its OWN timer did not expire).
      final outcome = await fetcher.fetch(allowed);
      expect(
        _reasonOf(outcome),
        anyOf(FetchRefusal.transport, FetchRefusal.timedOut),
      );
    });
  });
}
