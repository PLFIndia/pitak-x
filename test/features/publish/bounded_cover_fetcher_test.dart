import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_cover_fetcher.dart';

/// Builds a streaming MockClient whose body is [chunks], emitted in order,
/// one per [chunkDelay] tick. [recordHosts] captures every host the client
/// was asked to hit, so a test can assert that a rejected URL never produced
/// a network call. [probe] records what the SERVER side saw.
///
/// Honours `abortTrigger` the way `IOClient` does (inject the abort error,
/// close the body) — `MockClient` itself never aborts, it documents that the
/// handler must.
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
          // Emit everything in one go, then close.
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

/// What the SERVER side observed: how many chunks were actually pulled,
/// whether the body was torn down, and whether the request's abort trigger
/// fired. A leak looks like every chunk pulled on a rejected response.
class _BodyProbe {
  int chunksPulled = 0;
  bool bodyClosed = false;
  bool aborted = false;
}

List<int>? _bytesOf(CoverFetchResult r) => switch (r) {
  CoverFetched(:final bytes) => bytes,
  CoverRefused() => null,
};

CoverRefusal? _reasonOf(CoverFetchResult r) => switch (r) {
  CoverFetched() => null,
  CoverRefused(:final reason) => reason,
};

void main() {
  const allowed = 'https://covers.openlibrary.org/b/id/123-L.jpg';

  group('origin allow-list (defence 1)', () {
    test('rejects a non-allow-listed host WITHOUT any network call', () async {
      final hosts = <String>[];
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], recordHosts: hosts),
      );

      final result = await fetcher.fetch('https://evil.example.com/track.jpg');

      expect(_reasonOf(result), CoverRefusal.disallowedUrl);
      expect(hosts, isEmpty, reason: 'poisoned URL must not leave the device');
    });

    test('rejects http (non-https) without a call', () async {
      final hosts = <String>[];
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1],
        ], recordHosts: hosts),
      );

      expect(
        _reasonOf(
          await fetcher.fetch('http://covers.openlibrary.org/b/id/1-L.jpg'),
        ),
        CoverRefusal.disallowedUrl,
      );
      expect(hosts, isEmpty);
    });

    test('rejects userinfo smuggling without a call', () async {
      final hosts = <String>[];
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1],
        ], recordHosts: hosts),
      );

      expect(
        _reasonOf(
          await fetcher.fetch('https://x@covers.openlibrary.org/1.jpg'),
        ),
        CoverRefusal.disallowedUrl,
      );
      expect(hosts, isEmpty);
    });
  });

  group('byte cap (defence 3)', () {
    test('aborts a body that streams past maxBytes', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          List<int>.filled(4, 7),
          List<int>.filled(4, 7), // 8 bytes total, cap is 5
        ]),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.tooLarge);
    });

    test('rejects on an honest oversized Content-Length', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], contentLength: 1000),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.tooLarge);
    });

    test('accepts a body exactly at the cap', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3, 4, 5],
        ], contentLength: 5),
        maxBytes: 5,
      );

      expect(_bytesOf(await fetcher.fetch(allowed)), equals([1, 2, 3, 4, 5]));
    });
  });

  group('status + timeout', () {
    test('returns null on non-2xx', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], status: 404),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.httpStatus);
    });

    test('returns null when the request exceeds the timeout', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], chunkDelay: const Duration(milliseconds: 200)),
        timeout: const Duration(milliseconds: 20),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.timedOut);
    });
  });

  test('happy path returns the full allow-listed body', () async {
    final fetcher = BoundedCoverFetcher(
      client: _streaming([
        [10, 20],
        [30, 40],
      ], contentLength: 4),
    );

    expect(_bytesOf(await fetcher.fetch(allowed)), equals([10, 20, 30, 40]));
  });

  // REVIEW_FINDINGS_2 S6: http.Request defaults to followRedirects = true,
  // which would let an allow-listed host carry the fetch to ANY host. The
  // fetcher follows redirects manually and re-validates every hop.
  group('redirects (re-validated per hop)', () {
    /// Routes requests by full URL; records every host:path hit.
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
      final fetcher = BoundedCoverFetcher(
        client: router({
          allowed: (req) => redirect(req, 'https://evil.example.com/track.jpg'),
          'https://evil.example.com/track.jpg': (req) => ok(req, [1]),
        }, hits: hits),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        CoverRefusal.redirectRefused,
      );
      expect(hits, ['covers.openlibrary.org/b/id/123-L.jpg']);
    });

    test('a redirect to another ALLOW-LISTED host is followed', () async {
      const start = 'https://books.google.com/books/content?vid=1';
      const end = 'https://books.googleusercontent.com/cover/1.jpg';
      final fetcher = BoundedCoverFetcher(
        client: router({
          start: (req) => redirect(req, end),
          end: (req) => ok(req, [9, 9]),
        }),
      );

      expect(_bytesOf(await fetcher.fetch(start)), equals([9, 9]));
    });

    test('a relative Location resolves against the current URL', () async {
      final fetcher = BoundedCoverFetcher(
        client: router({
          allowed: (req) => redirect(req, '/b/id/999-L.jpg'),
          'https://covers.openlibrary.org/b/id/999-L.jpg': (req) =>
              ok(req, [7]),
        }),
      );

      expect(_bytesOf(await fetcher.fetch(allowed)), equals([7]));
    });

    test('a redirect to plain http is refused', () async {
      final fetcher = BoundedCoverFetcher(
        client: router({
          allowed: (req) =>
              redirect(req, 'http://covers.openlibrary.org/b/1-L.jpg'),
        }),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        CoverRefusal.redirectRefused,
      );
    });

    test('a redirect loop is abandoned after maxRedirects hops', () async {
      final hits = <String>[];
      final fetcher = BoundedCoverFetcher(
        client: router({allowed: (req) => redirect(req, allowed)}, hits: hits),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        CoverRefusal.tooManyRedirects,
      );
      // Initial request + maxRedirects follows, then the loop is cut.
      expect(hits, hasLength(1 + BoundedCoverFetcher.maxRedirects));
    });

    test('a redirect without a Location header is dropped', () async {
      final fetcher = BoundedCoverFetcher(
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            302,
            request: request,
          ),
        ),
      );

      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        CoverRefusal.redirectRefused,
      );
    });
  });

  // N08 (astra-review): "rejected oversized/non-success cover responses are
  // drained without a byte bound" and "Future.timeout stops waiting, not the
  // source request". These observe the SERVER side of each rejection.
  group('N08 — rejected responses are cancelled, not drained', () {
    // Ten chunks, but the fetcher must stop after the FIRST decision point.
    List<List<int>> tenChunks() => List.generate(10, (_) => [1, 2, 3]);

    test('a non-2xx body is not read past the status line', () async {
      final probe = _BodyProbe();
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          tenChunks(),
          status: 404,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.httpStatus);
      // Let any stray drain run before we look.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0, reason: 'nothing drained');
      expect(probe.bodyClosed, isTrue, reason: 'source cancelled');
    });

    test('an oversized Content-Length body is not read at all', () async {
      final probe = _BodyProbe();
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          tenChunks(),
          contentLength: 1000,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
        maxBytes: 5,
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.tooLarge);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0);
      expect(probe.bodyClosed, isTrue);
    });

    test('a redirect hop body is cancelled, not drained', () async {
      final probe = _BodyProbe();
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          tenChunks(),
          status: 302,
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
      );

      // No Location header → refused after the hop's status is read.
      expect(
        _reasonOf(await fetcher.fetch(allowed)),
        CoverRefusal.redirectRefused,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 0);
      expect(probe.bodyClosed, isTrue);
    });

    test('an over-cap body stops at the crossing chunk and aborts', () async {
      final probe = _BodyProbe();
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          tenChunks(),
          chunkDelay: const Duration(milliseconds: 1),
          probe: probe,
        ),
        maxBytes: 5, // chunk 2 crosses (6 > 5)
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.tooLarge);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probe.chunksPulled, 2, reason: 'no chunk pulled after the cap');
      expect(probe.bodyClosed, isTrue);
      expect(probe.aborted, isTrue, reason: 'socket torn down, not just left');
    });

    test('the timeout ABORTS the request and stops the body', () async {
      final probe = _BodyProbe();
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          tenChunks(),
          chunkDelay: const Duration(milliseconds: 30),
          probe: probe,
        ),
        timeout: const Duration(milliseconds: 50),
      );

      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.timedOut);
      final pulledAtTimeout = probe.chunksPulled;
      expect(probe.aborted, isTrue, reason: 'abortTrigger must fire');
      // HEAD kept streaming after the caller gave up; a real deadline does
      // not pull a single further chunk.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(probe.chunksPulled, pulledAtTimeout);
      expect(probe.bodyClosed, isTrue);
    });

    test('a transport error is a typed refusal', () async {
      final fetcher = BoundedCoverFetcher(
        client: MockClient.streaming(
          (request, _) async => throw http.ClientException('reset'),
        ),
      );
      expect(_reasonOf(await fetcher.fetch(allowed)), CoverRefusal.transport);
    });
  });
}
