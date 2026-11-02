import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_availability_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/published_availability_codec.dart';

/// End-to-end tests for [BoundedPublishedAvailabilityFetcher] (ADR 0019
/// Decision 4, ADR 0015 and ADR 0018 amendments). The harness mirrors
/// `bounded_published_catalogue_fetcher_test.dart` and
/// `bounded_published_events_fetcher_test.dart`.
///
/// What is special about this file (beginner note): a refused
/// `availability.json` is "treated as missing", NOT as a failure. Missing
/// means "use the inline tags and forget any older saved copy"; a failure
/// means "the host could not be asked, a saved copy may be shown". So the
/// mapping under test is:
///  - `200` + a file the codec accepts → fresh;
///  - `200` + a refused file, `404`, or a body over 1 MiB → missing;
///  - `304` to the saved tag → unchanged;
///  - every other refusal → failed (`NetworkFailure` + a coarse problem).

/// The decoded file of a fresh result (fails the test otherwise).
PublishedAvailabilityFile valueOf(
  PublishedFileFetch<PublishedAvailabilityFile> result,
) => switch (result) {
  PublishedFileFetched(:final value) => value,
  _ => fail('expected a fetched availability file, got $result'),
};

/// The problem of a failed result, after checking its failure is the typed
/// [NetworkFailure] (fails the test otherwise).
PublishedFileProblem problemOf(
  PublishedFileFetch<PublishedAvailabilityFile> result,
) => switch (result) {
  PublishedFileFailed(:final failure, :final problem)
      when failure is NetworkFailure =>
    problem,
  _ => fail('expected a NetworkFailure, got $result'),
};

final Matcher isFetched =
    isA<PublishedFileFetched<PublishedAvailabilityFile>>();
final Matcher isMissing =
    isA<PublishedFileMissing<PublishedAvailabilityFile>>();
final Matcher isUnchanged =
    isA<PublishedFileUnchanged<PublishedAvailabilityFile>>();

void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/availability.json';
  const mib = PublishedAvailabilityFile.maxBytes;

  List<int> fixture(String name) =>
      File('test/fixtures/published_availability/$name').readAsBytesSync();

  final validBody = fixture('valid.json');

  /// A valid availability document of exactly [length] bytes (padding in an
  /// unknown field, which the codec ignores).
  List<int> paddedTo(int length) {
    const head =
        '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",'
        '"out":["aaaaaaaaaaaaaaa1"],"padding":"';
    const tail = '"}';
    return utf8.encode(
      '$head${'x' * (length - head.length - tail.length)}$tail',
    );
  }

  BoundedPublishedAvailabilityFetcher fetcher(
    http.Client client, {
    Duration timeout = BoundedPublishedAvailabilityFetcher.defaultTimeout,
    int maxBytes = mib,
    int maxRedirects = BoundedPublishedAvailabilityFetcher.defaultMaxRedirects,
    PublishedAvailabilityCodec codec = const PublishedAvailabilityCodec(),
  }) => BoundedPublishedAvailabilityFetcher(
    client: client,
    siteUrl: site,
    timeout: timeout,
    maxBytes: maxBytes,
    maxRedirects: maxRedirects,
    codec: codec,
  );

  /// One fixed answer for every request. [sent] records each request's
  /// headers; [requested] each URL.
  MockClient answering({
    required int status,
    List<int> body = const [],
    Map<String, String> headers = const {},
    List<Map<String, String>>? sent,
    List<String>? requested,
  }) => MockClient.streaming((request, _) async {
    sent?.add(Map.of(request.headers));
    requested?.add(request.url.toString());
    return http.StreamedResponse(
      Stream.value(body),
      status,
      headers: headers,
      request: request,
    );
  });

  /// A streaming MockClient emitting [chunks], honouring the abort trigger the
  /// way IOClient does (copied from the catalogue fetcher suite).
  MockClient streaming(
    List<List<int>> chunks, {
    int status = 200,
    int? contentLength,
    Duration chunkDelay = Duration.zero,
    void Function()? onAbort,
    void Function()? onBodyClosed,
  }) {
    return MockClient.streaming((request, _) async {
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
          onBodyClosed?.call();
        },
      );
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(() {
            onAbort?.call();
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

  group('the request', () {
    test(
      'is the exact URL with no-cache, the app User-Agent and no credentials',
      () async {
        final sent = <Map<String, String>>[];
        final requested = <String>[];
        await fetcher(
          answering(
            status: 200,
            body: validBody,
            sent: sent,
            requested: requested,
          ),
        ).fetch(url);
        expect(requested, [url]);
        final headers = sent.single;
        expect(headers['User-Agent'], AppUserAgent.value);
        expect(headers['Cache-Control'], 'no-cache');
        expect(headers.containsKey('If-None-Match'), isFalse);
        for (final forbidden in <String>[
          'authorization',
          'cookie',
          'referer',
          'proxy-authorization',
        ]) {
          expect(
            headers.keys.map((k) => k.toLowerCase()),
            isNot(contains(forbidden)),
          );
        }
      },
    );

    test('the saved tag rides as If-None-Match; 304 means unchanged', () async {
      final sent = <Map<String, String>>[];
      final result = await fetcher(
        answering(status: 304, sent: sent),
      ).fetch(url, validator: '"e1"');
      expect(result, isUnchanged);
      expect(sent.single['If-None-Match'], '"e1"');
      expect(sent.single['Cache-Control'], 'no-cache');
    });

    test('no tag: no If-None-Match, and a stray 304 is notServed', () async {
      // "Not modified" only answers a question we asked; without a tag it is
      // an unexpected status, never "unchanged".
      final sent = <Map<String, String>>[];
      final result = await fetcher(
        answering(status: 304, sent: sent),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.notServed);
      expect(sent.single.containsKey('If-None-Match'), isFalse);
    });

    test('a tag that could inject headers is never sent', () async {
      final sent = <Map<String, String>>[];
      await fetcher(
        answering(status: 200, body: validBody, sent: sent),
      ).fetch(url, validator: '"a"\r\nCookie: x');
      expect(sent.single.containsKey('If-None-Match'), isFalse);
      expect(sent.single.containsKey('Cookie'), isFalse);
    });

    test('the headers and the tag ride on every redirect hop', () async {
      final sent = <Map<String, String>>[];
      final adapter = fetcher(
        MockClient.streaming((request, _) async {
          sent.add(Map.of(request.headers));
          if (request.url.toString() == url) {
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              302,
              headers: {'location': 'moved.json'},
              request: request,
            );
          }
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            304,
            request: request,
          );
        }),
      );
      expect(await adapter.fetch(url, validator: '"e1"'), isUnchanged);
      expect(sent, hasLength(2));
      for (final headers in sent) {
        expect(headers['User-Agent'], AppUserAgent.value);
        expect(headers['Cache-Control'], 'no-cache');
        expect(headers['If-None-Match'], '"e1"');
      }
    });

    test('an off-site URL is refused before any request', () async {
      final requested = <String>[];
      final adapter = fetcher(
        answering(status: 200, body: validBody, requested: requested),
      );
      for (final offSite in [
        'https://evil.example/availability.json',
        'https://someone-else.github.io/pitak/availability.json',
        'https://kadugodi.github.io/another-library/availability.json',
        'http://kadugodi.github.io/pitak/availability.json',
      ]) {
        final result = await adapter.fetch(offSite);
        expect(problemOf(result), PublishedFileProblem.notServed);
      }
      expect(requested, isEmpty);
    });
  });

  group('200: accepted file → fresh', () {
    test('carries the decoded file, the exact bytes and the tag', () async {
      final result = await fetcher(
        answering(status: 200, body: validBody, headers: {'etag': '"e1"'}),
      ).fetch(url);
      expect(result, isFetched);
      final fetched = result as PublishedFileFetched<PublishedAvailabilityFile>;
      expect(fetched.bytes, validBody);
      expect(fetched.validator, '"e1"');
      expect(fetched.value.keySet, '5e0c1d2b3a497f68');
      expect(fetched.value.outKeys, hasLength(6));
      expect(fetched.value.asOf, 1761984300000);
    });

    test('no ETag, or a malformed one, means no validator', () async {
      for (final headers in [
        <String, String>{},
        {'etag': 'no-quotes'},
      ]) {
        final fetched =
            await fetcher(
                  answering(status: 200, body: validBody, headers: headers),
                ).fetch(url)
                as PublishedFileFetched<PublishedAvailabilityFile>;
        expect(fetched.validator, isNull, reason: '$headers');
      }
    });

    test('an empty "nothing is out" file is fresh, not missing', () async {
      final result = await fetcher(
        answering(status: 200, body: fixture('empty_out.json')),
      ).fetch(url);
      expect(valueOf(result).outKeys, isEmpty);
    });

    test('another keySet is still fresh: the merge checks binding', () async {
      final result = await fetcher(
        answering(status: 200, body: fixture('other_key_set.json')),
      ).fetch(url);
      expect(valueOf(result).keySet, '0000000000000000');
    });
  });

  group('treated as missing', () {
    test('404 means the library has no availability file', () async {
      expect(await fetcher(answering(status: 404)).fetch(url), isMissing);
      // A 404 to a conditional request is missing too (the file was removed
      // since the copy was saved).
      expect(
        await fetcher(answering(status: 404)).fetch(url, validator: '"e1"'),
        isMissing,
      );
    });

    test('a 200 file the codec refuses is missing, never a failure', () async {
      for (final name in [
        'newer_schema.json',
        'bad_key.json',
        'missing_key_set.json',
        'malformed_key_set.json',
        'out_not_a_list.json',
        'out_has_number.json',
        'no_schema_version.json',
        'not_json.json',
        'root_is_list.json',
      ]) {
        final result = await fetcher(
          answering(
            status: 200,
            body: fixture(name),
            headers: {'etag': '"e1"'},
          ),
        ).fetch(url);
        expect(result, isMissing, reason: name);
      }
    });

    test('the codec cap refuses on its own, even under the transport cap', () {
      // Defence in depth: the codec checks the size again.
      expect(
        fetcher(
          answering(status: 200, body: validBody),
          codec: const PublishedAvailabilityCodec(maxBodyBytes: 10),
        ).fetch(url),
        completion(isMissing),
      );
    });

    test('exactly 1 MiB is fresh (streamed and declared)', () async {
      final body = paddedTo(mib);
      expect(body.length, mib);
      expect(valueOf(await fetcher(streaming([body])).fetch(url)).outKeys, {
        'aaaaaaaaaaaaaaa1',
      });
      expect(
        await fetcher(streaming([body], contentLength: mib)).fetch(url),
        isFetched,
      );
    });

    test(
      'a declared Content-Length over 1 MiB is missing, never read',
      () async {
        var bodyClosed = false;
        final result = await fetcher(
          streaming(
            [paddedTo(mib + 1)],
            contentLength: mib + 1,
            onBodyClosed: () => bodyClosed = true,
          ),
        ).fetch(url);
        expect(result, isMissing);
        expect(bodyClosed, isTrue, reason: 'cancelled, not drained');
      },
    );

    test('a streamed body over 1 MiB is missing and aborts the read', () async {
      var bodyClosed = false;
      final result = await fetcher(
        streaming(
          // 17 × 64 KiB = 1 MiB + 64 KiB, with no Content-Length.
          List.generate(17, (_) => List<int>.filled(64 * 1024, 0x20)),
          onBodyClosed: () => bodyClosed = true,
        ),
      ).fetch(url);
      expect(result, isMissing);
      expect(bodyClosed, isTrue);
    });

    test('one byte over an injected transport cap is missing', () async {
      final adapter = fetcher(
        streaming([validBody]),
        maxBytes: validBody.length - 1,
      );
      expect(await adapter.fetch(url), isMissing);
      expect(
        await fetcher(
          streaming([validBody]),
          maxBytes: validBody.length,
        ).fetch(url),
        isFetched,
      );
    });
  });

  group('failures stay failures (a saved copy may be shown)', () {
    test('any non-404 error status is notServed', () async {
      for (final status in [400, 401, 403, 410, 429, 500, 502, 503]) {
        final result = await fetcher(answering(status: status)).fetch(url);
        expect(
          problemOf(result),
          PublishedFileProblem.notServed,
          reason: 'status $status',
        );
      }
    });

    test('a transport fault is unreachable', () async {
      final result = await fetcher(
        MockClient.streaming(
          (request, _) async => throw http.ClientException('offline'),
        ),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.unreachable);
    });

    test('a non-http exception from the client is unreachable too', () async {
      final result = await fetcher(
        MockClient.streaming(
          (request, _) async => throw const SocketException('reset'),
        ),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.unreachable);
    });

    test('the deadline is unreachable and aborts the request', () async {
      var aborted = false;
      final result = await fetcher(
        streaming(
          List.generate(10, (_) => [0x20]),
          chunkDelay: const Duration(milliseconds: 30),
          onAbort: () => aborted = true,
        ),
        timeout: const Duration(milliseconds: 50),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.unreachable);
      expect(aborted, isTrue);
    });

    test('a caller abort closes the request and is unreachable', () async {
      var aborted = false;
      final caller = Completer<void>();
      final pending = fetcher(
        streaming(
          List.generate(10, (_) => [0x20]),
          chunkDelay: const Duration(milliseconds: 30),
          onAbort: () => aborted = true,
        ),
      ).fetch(url, abortTrigger: caller.future);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      caller.complete();
      expect(problemOf(await pending), PublishedFileProblem.unreachable);
      expect(aborted, isTrue);
    });
  });

  group('redirects', () {
    MockClient redirecting(
      Map<String, String> locations, {
      List<String>? requested,
    }) => MockClient.streaming((request, _) async {
      requested?.add(request.url.toString());
      final location = locations[request.url.toString()];
      if (location == null) {
        return http.StreamedResponse(
          Stream.value(validBody),
          200,
          request: request,
        );
      }
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        302,
        headers: {'location': location},
        request: request,
      );
    });

    test('in-site redirects (up to three) are followed', () async {
      final requested = <String>[];
      final result = await fetcher(
        redirecting({
          url: 'a.json',
          '${site}a.json': 'b.json',
          '${site}b.json': 'c.json',
        }, requested: requested),
      ).fetch(url);
      expect(result, isFetched);
      expect(requested, hasLength(4));
      expect(requested.every((u) => u.startsWith(site)), isTrue);
    });

    test('a fourth redirect is notServed', () async {
      final result = await fetcher(
        redirecting({
          url: 'a.json',
          '${site}a.json': 'b.json',
          '${site}b.json': 'c.json',
          '${site}c.json': 'd.json',
        }),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.notServed);
    });

    test('a redirect to another Pages host is never requested', () async {
      final requested = <String>[];
      final result = await fetcher(
        redirecting({
          url: 'https://someone-else.github.io/pitak/availability.json',
        }, requested: requested),
      ).fetch(url);
      expect(problemOf(result), PublishedFileProblem.notServed);
      expect(requested, [url]);
    });

    test('a redirect out of the site directory is never requested', () async {
      for (final escape in [
        'https://kadugodi.github.io/other/availability.json',
        '../other/availability.json',
        'https://kadugodi.github.io/pitak/%2e%2e/other/availability.json',
        'https://kadugodi.github.io/availability.json',
      ]) {
        final requested = <String>[];
        final result = await fetcher(
          redirecting({url: escape}, requested: requested),
        ).fetch(url);
        expect(
          problemOf(result),
          PublishedFileProblem.notServed,
          reason: escape,
        );
        expect(requested, [url], reason: escape);
      }
    });

    test('a redirect to plain http or without a Location is notServed', () {
      expect(
        fetcher(
          redirecting({url: 'http://kadugodi.github.io/pitak/x.json'}),
        ).fetch(url).then(problemOf),
        completion(PublishedFileProblem.notServed),
      );
      expect(
        fetcher(
          MockClient.streaming(
            (request, _) async => http.StreamedResponse(
              const Stream<List<int>>.empty(),
              302,
              request: request,
            ),
          ),
        ).fetch(url).then(problemOf),
        completion(PublishedFileProblem.notServed),
      );
    });
  });

  group('defaults', () {
    test('match the documented limits', () {
      final adapter = BoundedPublishedAvailabilityFetcher(
        client: MockClient((_) async => http.Response('', 404)),
        siteUrl: site,
      );
      expect(adapter.timeout, const Duration(seconds: 15));
      expect(adapter.maxBytes, 1024 * 1024);
      expect(adapter.maxRedirects, 3);
      expect(adapter.codec.maxBodyBytes, PublishedAvailabilityFile.maxBytes);
      expect(adapter.codec.maxKeys, PublishedAvailabilityFile.maxKeys);
      expect(BoundedPublishedAvailabilityFetcher.defaultTimeout.inSeconds, 15);
      expect(BoundedPublishedAvailabilityFetcher.defaultMaxRedirects, 3);
      expect(BoundedPublishedAvailabilityFetcher.requestHeaders, {
        'User-Agent': AppUserAgent.value,
        'Cache-Control': 'no-cache',
      });
    });
  });
}
