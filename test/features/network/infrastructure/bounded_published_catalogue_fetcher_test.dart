import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';

/// End-to-end tests for [BoundedPublishedCatalogueFetcher] (ADR 0015, viewer
/// plan S2). The rules under test are exactly the ones a refactor breaks:
///
///  1. the allow-list is the SITE policy (origin + directory), applied to the
///     initial URL AND every redirect hop, and never rewriting a file URL back
///     to the site root;
///  2. the adapter — not the outer 66 MiB transport guard — reports `tooLarge`;
///  3. every transport refusal maps to its typed catalogue reason;
///  4. the app User-Agent + `no-cache` ride on every hop, with no auth/cookie;
///  5. (ADR 0018) a saved copy's tag rides as `If-None-Match`, a `304` is
///     "unchanged", and a fresh body carries its bytes + validated `ETag`.
///
/// The harness mirrors `bounded_descriptor_fetcher_test.dart`.

/// The decoded catalogue of a fresh result (fails the test otherwise).
PublishedCatalogue valueOf(PublishedFileFetch<PublishedCatalogue> result) =>
    switch (result) {
      PublishedFileFetched(:final value) => value,
      _ => fail('expected a fetched catalogue, got $result'),
    };

/// The typed catalogue reason of a failed result (fails the test otherwise).
PublishedCatalogueFailureReason reasonOf(
  PublishedFileFetch<PublishedCatalogue> result,
) => switch (result) {
  PublishedFileFailed(failure: PublishedCatalogueFailure(:final reason)) =>
    reason,
  _ => fail('expected a typed catalogue failure, got $result'),
};

final Matcher isFetched = isA<PublishedFileFetched<PublishedCatalogue>>();

void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const fileUrl = 'https://kadugodi.github.io/pitak/books.json';

  String payload({int schemaVersion = 1, String title = 'A Book'}) =>
      jsonEncode({
        'schemaVersion': schemaVersion,
        'books': [
          {'title': title},
        ],
        'periodicals': [
          {'periodicalUid': 'series', 'title': 'Series'},
        ],
      });

  BoundedPublishedCatalogueFetcher fetcher(
    http.Client client, {
    String siteUrl = site,
    Duration timeout = const Duration(seconds: 30),
    int? maxBytes,
    int maxRedirects = 3,
    PublishedCatalogueCodec codec = const PublishedCatalogueCodec(),
    PublishedCatalogueBodyDecoder? decode,
  }) => BoundedPublishedCatalogueFetcher(
    client: client,
    siteUrl: siteUrl,
    timeout: timeout,
    maxBytes: maxBytes ?? codec.maxBodyBytes,
    maxRedirects: maxRedirects,
    codec: codec,
    decode: decode,
  );

  /// A streaming MockClient emitting [chunks], honouring the abort trigger the
  /// way IOClient does. [onRequest] records what the server side observed.
  MockClient streaming(
    List<List<int>> chunks, {
    int status = 200,
    int? contentLength,
    Duration chunkDelay = Duration.zero,
    void Function(http.BaseRequest request)? onRequest,
    void Function()? onAbort,
    void Function()? onBodyClosed,
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

  group('happy path', () {
    test(
      'a 2xx payload decodes through the DEFAULT worker-isolate decoder',
      () async {
        final adapter = fetcher(
          streaming([utf8.encode(payload(title: 'The Water Margin'))]),
        );
        final result = await adapter.fetch(fileUrl);
        expect(result, isFetched);
        expect(valueOf(result).items.single.title, 'The Water Margin');
        expect(valueOf(result).periodicals.single.title, 'Series');
      },
    );

    test('an empty catalogue is a success, not an error', () async {
      final adapter = fetcher(
        streaming([
          utf8.encode(jsonEncode({'schemaVersion': 1, 'books': <Object?>[]})),
        ]),
      );
      final result = await adapter.fetch(fileUrl);
      expect(valueOf(result).items, isEmpty);
    });

    test('a newer schema succeeds with the warning flag', () async {
      final adapter = fetcher(
        streaming([utf8.encode(payload(schemaVersion: 7))]),
      );
      final result = await adapter.fetch(fileUrl);
      expect(valueOf(result).hasNewerSchema, isTrue);
      expect(valueOf(result).items, hasLength(1));
    });

    test('an injected decoder is used instead of the isolate', () async {
      List<int>? seen;
      final adapter = fetcher(
        streaming([utf8.encode(payload())]),
        decode: (bytes) async {
          seen = bytes;
          return const PublishedCatalogueCodec().decode(bytes);
        },
      );
      final result = await adapter.fetch(fileUrl);
      expect(result, isFetched);
      expect(seen, isNotNull);
    });
  });

  group('typed transport failures', () {
    Future<PublishedCatalogueFailureReason> failureReason(
      BoundedPublishedCatalogueFetcher adapter,
    ) async {
      return reasonOf(await adapter.fetch(fileUrl));
    }

    test('malformed JSON is invalid', () async {
      final adapter = fetcher(
        streaming([utf8.encode('{"schemaVersion": 1, "books": [}')]),
      );
      expect(
        await failureReason(adapter),
        PublishedCatalogueFailureReason.invalid,
      );
    });

    test('a non-2xx response is httpStatus', () async {
      final adapter = fetcher(streaming([], status: 404));
      expect(
        await failureReason(adapter),
        PublishedCatalogueFailureReason.httpStatus,
      );
    });

    test('a transport fault is transport', () async {
      final adapter = fetcher(
        MockClient.streaming(
          (request, _) async => throw http.ClientException('reset'),
        ),
      );
      expect(
        await failureReason(adapter),
        PublishedCatalogueFailureReason.transport,
      );
    });

    test('the 30 s deadline is the typed timedOut, and aborts', () async {
      var aborted = false;
      final adapter = fetcher(
        streaming(
          List.generate(10, (_) => [1, 2, 3]),
          chunkDelay: const Duration(milliseconds: 30),
          onAbort: () => aborted = true,
        ),
        timeout: const Duration(milliseconds: 50),
      );
      expect(
        await failureReason(adapter),
        PublishedCatalogueFailureReason.timedOut,
      );
      expect(aborted, isTrue);
    });

    test('a caller abort is a coarse transport failure', () async {
      final caller = Completer<void>();
      final adapter = fetcher(
        streaming(
          List.generate(10, (_) => [1, 2, 3]),
          chunkDelay: const Duration(milliseconds: 30),
        ),
      );
      final pending = adapter.fetch(fileUrl, abortTrigger: caller.future);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      caller.complete();
      final result = await pending;
      expect(reasonOf(result), PublishedCatalogueFailureReason.transport);
    });
  });

  group('byte cap', () {
    test('a body exactly at the injected cap is accepted', () async {
      final bytes = utf8.encode(payload());
      final adapter = fetcher(
        streaming([bytes]),
        maxBytes: bytes.length,
        codec: PublishedCatalogueCodec(maxBodyBytes: bytes.length),
      );
      expect(await adapter.fetch(fileUrl), isFetched);
    });

    test('one byte over the cap is tooLarge', () async {
      final bytes = utf8.encode(payload());
      final adapter = fetcher(
        streaming([bytes]),
        maxBytes: bytes.length - 1,
        codec: PublishedCatalogueCodec(maxBodyBytes: bytes.length - 1),
      );
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.tooLarge);
    });

    test(
      'an honest oversized Content-Length is refused without reading',
      () async {
        var pulled = false;
        final adapter = fetcher(
          MockClient.streaming((request, _) async {
            pulled = true;
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              200,
              contentLength: 1000,
            );
          }),
          maxBytes: 100,
          codec: const PublishedCatalogueCodec(maxBodyBytes: 100),
        );
        // The server did answer (headers), but the body is never read: the
        // declared length alone refuses it.
        final result = await adapter.fetch(fileUrl);
        expect(pulled, isTrue);
        expect(reasonOf(result), PublishedCatalogueFailureReason.tooLarge);
      },
    );

    test('a streamed over-cap body aborts instead of draining', () async {
      var bodyClosed = false;
      final adapter = fetcher(
        streaming(
          List.generate(20, (_) => List<int>.filled(64, 0x20)),
          onBodyClosed: () => bodyClosed = true,
        ),
        maxBytes: 100,
        codec: const PublishedCatalogueCodec(maxBodyBytes: 100),
      );
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.tooLarge);
      expect(bodyClosed, isTrue);
    });

    test('the production cap is the documented 64 MiB', () {
      expect(
        BoundedPublishedCatalogueFetcher.defaultMaxBytes,
        64 * 1024 * 1024,
      );
      expect(BoundedPublishedCatalogueFetcher.defaultTimeout.inSeconds, 30);
      expect(BoundedPublishedCatalogueFetcher.defaultMaxRedirects, 3);
    });

    test('the outer transport guard never masks the typed tooLarge', () async {
      // Production wraps this adapter in the viewer TimeoutHttpClient (66 MiB
      // outer guard). A body over the adapter's cap but under the guard must
      // still surface as `tooLarge`, not as a generic transport error.
      final body = List<int>.filled(4096, 0x20);
      final outer = TimeoutHttpClient(
        streaming([body]),
        timeout: const Duration(seconds: 30),
        totalDeadline: const Duration(seconds: 60),
        maxResponseBytes: 66 * 1024 * 1024,
      );
      final adapter = fetcher(
        outer,
        maxBytes: 1024,
        codec: const PublishedCatalogueCodec(maxBodyBytes: 1024),
      );
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.tooLarge);
    });
  });

  group('redirects', () {
    MockClient redirecting(
      Map<String, String> locations, {
      List<String>? requested,
      void Function(http.BaseRequest request)? onRequest,
    }) => MockClient.streaming((request, _) async {
      requested?.add(request.url.toString());
      onRequest?.call(request);
      final location = locations[request.url.toString()];
      if (location == null) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(payload())),
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

    test('three in-policy redirects are followed', () async {
      final requested = <String>[];
      final adapter = fetcher(
        redirecting({
          fileUrl: 'a.json',
          'https://kadugodi.github.io/pitak/a.json': 'b.json',
          'https://kadugodi.github.io/pitak/b.json': 'c.json',
        }, requested: requested),
      );
      final result = await adapter.fetch(fileUrl);
      expect(result, isFetched);
      expect(requested, hasLength(4));
      // Every hop stayed inside the saved library.
      expect(
        requested.every(
          (url) => url.startsWith('https://kadugodi.github.io/pitak/'),
        ),
        isTrue,
      );
    });

    test('a fourth redirect is refused', () async {
      final adapter = fetcher(
        redirecting({
          fileUrl: 'a.json',
          'https://kadugodi.github.io/pitak/a.json': 'b.json',
          'https://kadugodi.github.io/pitak/b.json': 'c.json',
          'https://kadugodi.github.io/pitak/c.json': 'd.json',
        }),
      );
      final result = await adapter.fetch(fileUrl);
      expect(
        reasonOf(result),
        PublishedCatalogueFailureReason.tooManyRedirects,
      );
    });

    test('a cross-origin Pages redirect is never requested', () async {
      final requested = <String>[];
      final adapter = fetcher(
        redirecting({
          fileUrl: 'https://someone-else.github.io/pitak/books.json',
        }, requested: requested),
      );
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.redirectRefused);
      expect(requested, [fileUrl]);
    });

    test('a directory-escape redirect is never requested', () async {
      final requested = <String>[];
      final adapter = fetcher(
        redirecting({
          fileUrl: 'https://kadugodi.github.io/other/books.json',
          'https://kadugodi.github.io/pitak/trap.json':
              'https://kadugodi.github.io/pitak/../other/books.json',
        }, requested: requested),
      );
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.redirectRefused);
      expect(requested, [fileUrl]);
    });

    test('a redirect to plain http is refused', () async {
      final adapter = fetcher(
        redirecting({fileUrl: 'http://kadugodi.github.io/pitak/books.json'}),
      );
      expect(
        reasonOf(await adapter.fetch(fileUrl)),
        PublishedCatalogueFailureReason.redirectRefused,
      );
    });

    test(
      'the exact file URL is requested, never normalized to the root',
      () async {
        final requested = <String>[];
        final adapter = fetcher(redirecting({}, requested: requested));
        await adapter.fetch(fileUrl);
        expect(requested, [fileUrl]);
      },
    );
  });

  group('request headers', () {
    test(
      'the User-Agent and no-cache ride on every hop, with no auth',
      () async {
        final headers = <Map<String, String>>[];
        final adapter = fetcher(
          MockClient.streaming((request, _) async {
            headers.add(Map.of(request.headers));
            if (request.url.toString() == fileUrl) {
              return http.StreamedResponse(
                const Stream<List<int>>.empty(),
                302,
                headers: {'location': 'next.json'},
                request: request,
              );
            }
            return http.StreamedResponse(
              Stream.value(utf8.encode(payload())),
              200,
              request: request,
            );
          }),
        );
        expect(await adapter.fetch(fileUrl), isFetched);
        expect(headers, hasLength(2));
        for (final sent in headers) {
          expect(sent['User-Agent'], AppUserAgent.value);
          expect(sent['Cache-Control'], 'no-cache');
          for (final forbidden in <String>[
            'authorization',
            'cookie',
            'referer',
            'proxy-authorization',
          ]) {
            expect(
              sent.keys.map((k) => k.toLowerCase()),
              isNot(contains(forbidden)),
            );
          }
        }
      },
    );
  });

  group('initial origin policy', () {
    test('a call for another library is refused before any request', () async {
      var requested = false;
      final adapter = fetcher(
        MockClient.streaming((request, _) async {
          requested = true;
          return http.StreamedResponse(
            Stream.value(utf8.encode(payload())),
            200,
            request: request,
          );
        }),
      );
      final result = await adapter.fetch(
        'https://kadugodi.github.io/another-library/books.json',
      );
      expect(reasonOf(result), PublishedCatalogueFailureReason.disallowedUrl);
      expect(requested, isFalse);
    });
  });

  group('conditional requests (ADR 0018)', () {
    MockClient answering({
      required int status,
      Map<String, String> headers = const {},
      List<Map<String, String>>? sent,
    }) => MockClient.streaming((request, _) async {
      sent?.add(Map.of(request.headers));
      return http.StreamedResponse(
        status == 200
            ? Stream.value(utf8.encode(payload()))
            : const Stream<List<int>>.empty(),
        status,
        headers: headers,
        request: request,
      );
    });

    test('a fresh body carries its exact bytes and validated ETag', () async {
      final adapter = fetcher(
        answering(status: 200, headers: {'etag': '"689c7eef-386e"'}),
      );
      final result = await adapter.fetch(fileUrl);
      final fetched = result as PublishedFileFetched<PublishedCatalogue>;
      expect(fetched.validator, '"689c7eef-386e"');
      expect(fetched.bytes, utf8.encode(payload()));
    });

    test(
      'a malformed ETag is dropped (the copy is saved without a tag)',
      () async {
        final adapter = fetcher(
          answering(status: 200, headers: {'etag': 'no-quotes'}),
        );
        final fetched =
            await adapter.fetch(fileUrl)
                as PublishedFileFetched<PublishedCatalogue>;
        expect(fetched.validator, isNull);
      },
    );

    test(
      'the saved tag rides as If-None-Match and 304 means unchanged',
      () async {
        final sent = <Map<String, String>>[];
        final adapter = fetcher(answering(status: 304, sent: sent));
        final result = await adapter.fetch(fileUrl, validator: '"abc"');
        expect(result, isA<PublishedFileUnchanged<PublishedCatalogue>>());
        expect(sent.single['If-None-Match'], '"abc"');
        expect(sent.single['Cache-Control'], 'no-cache');
      },
    );

    test('no tag: no If-None-Match, and a stray 304 is a refusal', () async {
      final sent = <Map<String, String>>[];
      final adapter = fetcher(answering(status: 304, sent: sent));
      final result = await adapter.fetch(fileUrl);
      expect(reasonOf(result), PublishedCatalogueFailureReason.httpStatus);
      expect(sent.single.containsKey('If-None-Match'), isFalse);
    });

    test('a tag that could inject headers is never sent', () async {
      final sent = <Map<String, String>>[];
      final adapter = fetcher(answering(status: 200, sent: sent));
      await adapter.fetch(fileUrl, validator: '"a"\r\nCookie: x');
      expect(sent.single.containsKey('If-None-Match'), isFalse);
    });

    test(
      'a 404 is a failure, never "missing" (the catalogue is required)',
      () async {
        final result = await fetcher(answering(status: 404)).fetch(fileUrl);
        expect(result, isA<PublishedFileFailed<PublishedCatalogue>>());
        expect(
          (result as PublishedFileFailed).problem,
          PublishedFileProblem.notServed,
        );
      },
    );

    test('failures carry the saved-copy note reason', () async {
      Future<PublishedFileProblem> problemOf(http.Client client) async =>
          (await fetcher(client).fetch(fileUrl) as PublishedFileFailed).problem;
      expect(
        await problemOf(
          MockClient.streaming(
            (request, _) async => throw http.ClientException('offline'),
          ),
        ),
        PublishedFileProblem.unreachable,
      );
      expect(
        await problemOf(answering(status: 500)),
        PublishedFileProblem.notServed,
      );
      expect(
        await problemOf(streaming([utf8.encode('{not json')])),
        PublishedFileProblem.unreadable,
      );
    });

    test(
      'the shared isolate decoder reads saved bytes like a download',
      () async {
        final decoded = await decodePublishedCatalogueInIsolate(
          utf8.encode(payload(title: 'Saved')),
        );
        expect(decoded.toNullable()!.items.single.title, 'Saved');
      },
    );
  });
}
