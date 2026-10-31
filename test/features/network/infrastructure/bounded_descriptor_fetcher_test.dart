import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/infrastructure/bounded_descriptor_fetcher.dart';

/// End-to-end tests for [BoundedDescriptorFetcher] (review L5): the adapter
/// that wires `BookmarkUrl.sanitize` + 15 s + 64 KiB into the codec. Its two
/// subtle rules are exactly the ones a refactor breaks:
///  1. the allow-list is `sanitize` (VERBATIM), not `normalize` — a redirect
///     to `…/library.json` must be fetched exactly as given, never rewritten
///     to the site root;
///  2. every transport refusal maps 1:1 onto the descriptor refusal set.
/// The harness mirrors test/core/network/bounded_http_fetcher_test.dart.

/// What the SERVER side observed of one streamed body.
class _BodyProbe {
  bool aborted = false;
  bool bodyClosed = false;
}

void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const startUrl = 'https://x.github.io/lib/';
  const fileUrl = 'https://x.github.io/lib/library.json';

  String descriptorJson({int schemaVersion = 1}) => jsonEncode({
    'schemaVersion': schemaVersion,
    'fingerprint': fp,
    'name': 'X Library',
    'siteUrl': startUrl,
    'updatedAt': 1760000000000,
  });

  /// A streaming MockClient answering [status] with [chunks] (emitted one per
  /// [chunkDelay] tick) that honours `abortTrigger` the way IOClient does —
  /// MockClient itself never aborts (same harness as the core fetcher test).
  MockClient streaming(
    List<List<int>> chunks, {
    int status = 200,
    int? contentLength,
    Duration chunkDelay = Duration.zero,
    _BodyProbe? probe,
    void Function(http.BaseRequest request)? onRequest,
  }) {
    return MockClient.streaming((request, _) async {
      onRequest?.call(request);
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

  /// Routes by exact URL; every requested URL is recorded in [hits].
  MockClient router(
    Map<String, http.StreamedResponse Function(http.BaseRequest)> routes, {
    List<String>? hits,
  }) {
    return MockClient.streaming((request, _) async {
      hits?.add(request.url.toString());
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

  BoundedDescriptorFetcher fetcherFor(
    http.Client client, {
    Duration timeout = const Duration(seconds: 15),
  }) => BoundedDescriptorFetcher(client: client, timeout: timeout);

  test('happy path: 200 + a valid library.json is parsed, with the app '
      'User-Agent on the request (M2)', () async {
    String? userAgent;
    final fetcher = fetcherFor(
      streaming([
        utf8.encode(descriptorJson()),
      ], onRequest: (request) => userAgent = request.headers['User-Agent']),
    );

    final result = await fetcher.fetch(fileUrl);

    final fetched = result as DescriptorFetched;
    expect(fetched.descriptor.fingerprint, fp);
    expect(fetched.descriptor.name, 'X Library');
    expect(fetched.descriptor.siteUrl, startUrl);
    expect(
      userAgent,
      AppUserAgent.value,
      reason: 'a bare package:http request would say "Dart/3.x (dart:io)"',
    );
  });

  test('invalid JSON ⇒ DescriptorRefused(invalid)', () async {
    final fetcher = fetcherFor(streaming([utf8.encode('{')]));
    final result = await fetcher.fetch(fileUrl);
    expect(result, isA<DescriptorRefused>());
    expect((result as DescriptorRefused).reason, DescriptorRefusal.invalid);
  });

  test('a newer schema ⇒ DescriptorRefused(schemaTooNew)', () async {
    final fetcher = fetcherFor(
      streaming([utf8.encode(descriptorJson(schemaVersion: 2))]),
    );
    final result = await fetcher.fetch(fileUrl);
    expect(
      (result as DescriptorRefused).reason,
      DescriptorRefusal.schemaTooNew,
    );
  });

  test('a body streaming past 64 KiB ⇒ tooLarge AND the read is aborted '
      '(never drained, never an httpStatus)', () async {
    final probe = _BodyProbe();
    // 9 × 8 KiB = 72 KiB, no Content-Length: the cap must catch it mid-stream.
    final fetcher = fetcherFor(
      streaming(
        List.generate(9, (_) => List<int>.filled(8 * 1024, 0x41)),
        probe: probe,
      ),
    );

    final result = await fetcher.fetch(fileUrl);

    expect((result as DescriptorRefused).reason, DescriptorRefusal.tooLarge);
    expect(probe.aborted, isTrue, reason: 'the socket is torn down (D14)');
    expect(probe.bodyClosed, isTrue);
  });

  test(
    'a failing host (5xx, 429, 403) ⇒ DescriptorRefused(httpStatus)',
    () async {
      for (final status in [500, 503, 429, 403]) {
        final fetcher = fetcherFor(
          streaming(const [
            [1],
          ], status: status),
        );
        final result = await fetcher.fetch(fileUrl);
        expect(
          (result as DescriptorRefused).reason,
          DescriptorRefusal.httpStatus,
          reason: 'HTTP $status says "try later", not "nothing here"',
        );
      }
    },
  );

  // A Pitak moved page answers 404 for library.json once a move completes.
  // "Nothing is published here" is a positive fact the refresh may act on
  // (a stale conflict badge gives way), unlike a failing host.
  test('404 and 410 ⇒ DescriptorRefused(notPublished)', () async {
    for (final status in [404, 410]) {
      final fetcher = fetcherFor(
        streaming(const [
          [1],
        ], status: status),
      );
      final result = await fetcher.fetch(fileUrl);
      expect(
        (result as DescriptorRefused).reason,
        DescriptorRefusal.notPublished,
        reason: 'HTTP $status',
      );
    }
  });

  test(
    'REGRESSION (sanitize, not normalize): a redirect to …/library.json '
    'is fetched EXACTLY as given — never rewritten to the site root',
    () async {
      final hits = <String>[];
      final userAgents = <String?>[];
      final fetcher = fetcherFor(
        router({
          startUrl: (req) {
            userAgents.add(req.headers['User-Agent']);
            return redirect(req, fileUrl);
          },
          fileUrl: (req) {
            userAgents.add(req.headers['User-Agent']);
            return ok(req, utf8.encode(descriptorJson()));
          },
        }, hits: hits),
      );

      final result = await fetcher.fetch(startUrl);

      expect(result, isA<DescriptorFetched>());
      expect(
        hits,
        [startUrl, fileUrl],
        reason:
            'normalize() would have rewritten the hop to the site root and '
            'looped; sanitize() keeps the exact address',
      );
      expect(userAgents, everyElement(AppUserAgent.value)); // UA on EVERY hop
    },
  );

  test('a redirect off the allow-list is refused and never fetched', () async {
    final hits = <String>[];
    final fetcher = fetcherFor(
      router({
        startUrl: (req) => redirect(req, 'https://evil.example/library.json'),
        'https://evil.example/library.json': (req) =>
            ok(req, utf8.encode(descriptorJson())),
      }, hits: hits),
    );

    final result = await fetcher.fetch(startUrl);

    expect(
      (result as DescriptorRefused).reason,
      DescriptorRefusal.redirectRefused,
    );
    expect(hits, [startUrl], reason: 'no packet leaves for evil.example');
  });

  test('a chain of 4 redirects ⇒ tooManyRedirects', () async {
    const a = 'https://a.github.io/';
    const b = 'https://b.github.io/';
    const c = 'https://c.github.io/';
    const d = 'https://d.github.io/';
    const e = 'https://e.github.io/';
    final hits = <String>[];
    final fetcher = fetcherFor(
      router({
        a: (req) => redirect(req, b),
        b: (req) => redirect(req, c),
        c: (req) => redirect(req, d),
        // The budget is 3 hops: the 4th redirect RESPONSE is refused…
        d: (req) => redirect(req, e),
        e: (req) => ok(req, utf8.encode(descriptorJson())),
      }, hits: hits),
    );

    final result = await fetcher.fetch(a);

    expect(
      (result as DescriptorRefused).reason,
      DescriptorRefusal.tooManyRedirects,
    );
    // …so the 5th URL is never requested (4 requests, 4 redirect responses).
    expect(hits, [a, b, c, d]);
  });

  test('a stalled body past the deadline ⇒ timedOut', () async {
    final fetcher = fetcherFor(
      streaming([
        [1, 2, 3],
      ], chunkDelay: const Duration(milliseconds: 200)),
      timeout: const Duration(milliseconds: 50),
    );
    final result = await fetcher.fetch(fileUrl);
    expect((result as DescriptorRefused).reason, DescriptorRefusal.timedOut);
  });
}
