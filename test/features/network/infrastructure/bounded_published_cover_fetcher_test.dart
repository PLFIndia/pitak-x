import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_cover_fetcher.dart';

/// End-to-end tests for [BoundedPublishedCoverFetcher] (ADR 0015 V11, viewer
/// plan S5): per-request origin policy, deadline, byte cap, redirect rules, and
/// the decode step that guarantees only a downscaled JPEG leaves this class.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  SameSiteCoverRequest sameSite([String leaf = 'a.jpg']) =>
      PublishedCoverResolver.resolve(site, 'covers/$leaf')!
          as SameSiteCoverRequest;

  ThirdPartyCoverRequest thirdParty([
    String url = 'https://covers.openlibrary.org/b/id/1-L.jpg',
  ]) => PublishedCoverResolver.resolve(site, url)! as ThirdPartyCoverRequest;

  Uint8List jpegBytes({int width = 4, int height = 6}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(10, 20, 30));
    return Uint8List.fromList(img.encodeJpg(image));
  }

  BoundedPublishedCoverFetcher fetcher(
    http.Client client, {
    Duration timeout = const Duration(seconds: 15),
    int? maxBytes,
    Future<Uint8List?> Function(List<int>)? decode,
  }) => BoundedPublishedCoverFetcher(
    client: client,
    timeout: timeout,
    maxBytes: maxBytes ?? BoundedPublishedCoverFetcher.defaultMaxBytes,
    decode: decode ?? (bytes) async => Uint8List.fromList(bytes),
  );

  MockClient streaming(
    List<List<int>> chunks, {
    int status = 200,
    int? contentLength,
    Duration chunkDelay = Duration.zero,
    Map<String, String> headers = const {},
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
        headers: headers,
        request: request,
      );
    });
  }

  group('happy path', () {
    test('only the decode result is returned', () async {
      final raw = jpegBytes();
      List<int>? decodedInput;
      final adapter = fetcher(
        streaming([raw]),
        decode: (bytes) async {
          decodedInput = bytes;
          return Uint8List.fromList(const [1, 2, 3]);
        },
      );
      final result = await adapter.fetch(sameSite());
      expect(result, [1, 2, 3]);
      expect(decodedInput, raw);
    });

    test('a real decode produces a JPEG, never a raw download', () async {
      final gif = img.encodeGif(
        img.Image(width: 8, height: 8)
          ..frameDuration = 100
          ..addFrame(img.Image(width: 8, height: 8)..frameDuration = 100),
      );
      final adapter = BoundedPublishedCoverFetcher(
        client: streaming([Uint8List.fromList(gif)]),
      );
      final result = await adapter.fetch(sameSite());
      expect(result, isNotNull);
      // JPEG SOI / GIF signature: the animated download was downscaled to a
      // still JPEG (frame 0), never passed through.
      expect(result!.sublist(0, 2), [0xFF, 0xD8]);
      expect(String.fromCharCodes(result.sublist(0, 3)), isNot('GIF'));
    });

    test('a malformed image degrades to null (no raw fallback)', () async {
      final adapter = BoundedPublishedCoverFetcher(
        client: streaming([Uint8List.fromList(List<int>.filled(64, 0x42))]),
      );
      expect(await adapter.fetch(sameSite()), isNull);
    });
  });

  group('refusals', () {
    test('a non-2xx response is null and never decoded', () async {
      var decoded = false;
      final adapter = fetcher(
        streaming([], status: 404),
        decode: (bytes) async {
          decoded = true;
          return Uint8List.fromList(bytes);
        },
      );
      expect(await adapter.fetch(sameSite()), isNull);
      expect(decoded, isFalse);
    });

    test('an oversized body is null and aborts', () async {
      var aborted = false;
      final adapter = fetcher(
        streaming(
          List.generate(10, (_) => List<int>.filled(64, 0x20)),
          onAbort: () => aborted = true,
        ),
        maxBytes: 100,
      );
      expect(await adapter.fetch(sameSite()), isNull);
      expect(aborted, isTrue);
    });

    test('an honest oversized Content-Length is refused unread', () async {
      final adapter = fetcher(
        MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            200,
            contentLength: 10 * 1024 * 1024,
          ),
        ),
        maxBytes: 1024,
      );
      expect(await adapter.fetch(sameSite()), isNull);
    });

    test('the 15 s deadline aborts and returns null', () async {
      var aborted = false;
      final adapter = fetcher(
        streaming(
          List.generate(10, (_) => [1, 2, 3]),
          chunkDelay: const Duration(milliseconds: 30),
          onAbort: () => aborted = true,
        ),
        timeout: const Duration(milliseconds: 50),
      );
      expect(await adapter.fetch(sameSite()), isNull);
      expect(aborted, isTrue);
    });

    test('a caller abort returns null and aborts the socket', () async {
      final caller = Completer<void>();
      var aborted = false;
      final adapter = fetcher(
        streaming(
          List.generate(10, (_) => [1, 2, 3]),
          chunkDelay: const Duration(milliseconds: 30),
          onAbort: () => aborted = true,
        ),
      );
      final pending = adapter.fetch(sameSite(), abortTrigger: caller.future);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      caller.complete();
      expect(await pending, isNull);
      expect(aborted, isTrue);
    });

    test('a transport error is null, never a throw', () async {
      final adapter = fetcher(
        MockClient.streaming(
          (request, _) async => throw http.ClientException('reset'),
        ),
      );
      expect(await adapter.fetch(sameSite()), isNull);
    });
  });

  group('per-request origin policy', () {
    test(
      'a same-site redirect outside the library is never requested',
      () async {
        final requested = <String>[];
        final adapter = fetcher(
          MockClient.streaming((request, _) async {
            requested.add(request.url.toString());
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              302,
              headers: {
                'location': 'https://someone-else.github.io/pitak/covers/a.jpg',
              },
              request: request,
            );
          }),
        );
        expect(await adapter.fetch(sameSite()), isNull);
        expect(requested, hasLength(1));
        expect(requested.single, contains('kadugodi.github.io/pitak/covers/'));
      },
    );

    test(
      'a third-party redirect through Internet Archive still works',
      () async {
        final requested = <String>[];
        final adapter = fetcher(
          MockClient.streaming((request, _) async {
            requested.add(request.url.toString());
            if (request.url.host == 'covers.openlibrary.org') {
              return http.StreamedResponse(
                const Stream<List<int>>.empty(),
                302,
                headers: {
                  'location':
                      'https://ia800000.us.archive.org/view_archive.php?x=1',
                },
                request: request,
              );
            }
            return http.StreamedResponse(
              Stream.value(jpegBytes()),
              200,
              request: request,
            );
          }),
        );
        expect(await adapter.fetch(thirdParty()), isNotNull);
        expect(requested, hasLength(2));
        expect(requested.last, contains('ia800000.us.archive.org'));
      },
    );

    test(
      'a third-party redirect to a non-allow-listed host is refused',
      () async {
        final requested = <String>[];
        final adapter = fetcher(
          MockClient.streaming((request, _) async {
            requested.add(request.url.toString());
            return http.StreamedResponse(
              const Stream<List<int>>.empty(),
              302,
              headers: {'location': 'https://evil.example/a.jpg'},
              request: request,
            );
          }),
        );
        expect(await adapter.fetch(thirdParty()), isNull);
        expect(requested, hasLength(1));
      },
    );

    test('a Pages cover is not requestable as an absolute third-party URL', () {
      expect(
        PublishedCoverResolver.resolve(
          site,
          'https://kadugodi.github.io/pitak/covers/a.jpg',
        ),
        isNull,
      );
    });
  });

  group('request headers', () {
    test('the app User-Agent rides along, with no cookies or auth', () async {
      Map<String, String>? sent;
      final adapter = fetcher(
        streaming([
          jpegBytes(),
        ], onRequest: (request) => sent = Map.of(request.headers)),
      );
      await adapter.fetch(sameSite());
      expect(sent, isNotNull);
      expect(sent!['User-Agent'], AppUserAgent.value);
      for (final forbidden in <String>[
        'authorization',
        'cookie',
        'referer',
        'proxy-authorization',
      ]) {
        expect(
          sent!.keys.map((k) => k.toLowerCase()),
          isNot(contains(forbidden)),
        );
      }
    });
  });

  group('limits', () {
    test('the documented defaults are 15 s, 8 MiB and 3 redirects', () {
      expect(BoundedPublishedCoverFetcher.defaultTimeout.inSeconds, 15);
      expect(BoundedPublishedCoverFetcher.defaultMaxBytes, 8 * 1024 * 1024);
      expect(BoundedPublishedCoverFetcher.defaultMaxRedirects, 3);
    });
  });
}
