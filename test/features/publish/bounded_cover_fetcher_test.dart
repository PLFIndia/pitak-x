import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/features/publish/infrastructure/bounded_cover_fetcher.dart';

/// Builds a streaming MockClient whose body is [chunks], emitted in order.
/// [recordHosts] captures every host the client was asked to hit, so a test can
/// assert that a rejected URL never produced a network call.
MockClient _streaming(
  List<List<int>> chunks, {
  int status = 200,
  int? contentLength,
  List<String>? recordHosts,
  Duration chunkDelay = Duration.zero,
}) {
  return MockClient.streaming((request, _) async {
    recordHosts?.add(request.url.host);
    Stream<List<int>> body() async* {
      for (final c in chunks) {
        if (chunkDelay != Duration.zero) await Future<void>.delayed(chunkDelay);
        yield c;
      }
    }

    return http.StreamedResponse(
      body(),
      status,
      contentLength: contentLength,
      request: request,
    );
  });
}

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

      expect(result, isNull);
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
        await fetcher.fetch('http://covers.openlibrary.org/b/id/1-L.jpg'),
        isNull,
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
        await fetcher.fetch('https://x@covers.openlibrary.org/1.jpg'),
        isNull,
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

      expect(await fetcher.fetch(allowed), isNull);
    });

    test('rejects on an honest oversized Content-Length', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], contentLength: 1000),
        maxBytes: 5,
      );

      expect(await fetcher.fetch(allowed), isNull);
    });

    test('accepts a body exactly at the cap', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3, 4, 5],
        ], contentLength: 5),
        maxBytes: 5,
      );

      expect(await fetcher.fetch(allowed), equals([1, 2, 3, 4, 5]));
    });
  });

  group('status + timeout', () {
    test('returns null on non-2xx', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming([
          [1, 2, 3],
        ], status: 404),
      );

      expect(await fetcher.fetch(allowed), isNull);
    });

    test('returns null when the request exceeds the timeout', () async {
      final fetcher = BoundedCoverFetcher(
        client: _streaming(
          [
            [1, 2, 3],
          ],
          chunkDelay: const Duration(milliseconds: 200),
        ),
        timeout: const Duration(milliseconds: 20),
      );

      expect(await fetcher.fetch(allowed), isNull);
    });
  });

  test('happy path returns the full allow-listed body', () async {
    final fetcher = BoundedCoverFetcher(
      client: _streaming([
        [10, 20],
        [30, 40],
      ], contentLength: 4),
    );

    expect(await fetcher.fetch(allowed), equals([10, 20, 30, 40]));
  });
}
