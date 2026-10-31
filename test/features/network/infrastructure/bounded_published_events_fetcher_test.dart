import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_events_fetcher.dart';

void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/events.json';
  final payload = jsonEncode({
    'schemaVersion': 1,
    'posters': [
      {'imageRef': 'posters/a.jpg', 'description': 'Story'},
    ],
  });

  final isFailed = isA<PublishedFileFailed<PublishedEvents>>();

  test(
    'loads the exact sibling file with no-cache and app User-Agent',
    () async {
      late http.BaseRequest observed;
      final fetcher = BoundedPublishedEventsFetcher(
        client: MockClient((request) async {
          observed = request;
          return http.Response(payload, 200, headers: {'etag': '"e1"'});
        }),
        siteUrl: site,
      );
      final result =
          await fetcher.fetch(url) as PublishedFileFetched<PublishedEvents>;
      expect(result.value.posters.single.description, 'Story');
      expect(result.bytes, utf8.encode(payload));
      expect(result.validator, '"e1"');
      expect(observed.url.toString(), url);
      expect(observed.headers['User-Agent'], AppUserAgent.value);
      expect(observed.headers['Cache-Control'], 'no-cache');
      expect(observed.headers.containsKey('If-None-Match'), isFalse);
      expect(observed.headers.containsKey('Cookie'), isFalse);
      expect(observed.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('the saved tag rides as If-None-Match; 304 means unchanged', () async {
    late http.BaseRequest observed;
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((request) async {
        observed = request;
        return http.Response('', 304);
      }),
      siteUrl: site,
    );
    final result = await fetcher.fetch(url, validator: '"e1"');
    expect(result, isA<PublishedFileUnchanged<PublishedEvents>>());
    expect(observed.headers['If-None-Match'], '"e1"');
  });

  test('404 alone means no published events', () async {
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async => http.Response('not found', 404)),
      siteUrl: site,
    );
    expect(
      await fetcher.fetch(url),
      isA<PublishedFileMissing<PublishedEvents>>(),
    );
  });

  test('other HTTP and payload failures stay typed failures', () async {
    for (final (response, problem) in [
      (http.Response('server error', 500), PublishedFileProblem.notServed),
      (http.Response('{not json', 200), PublishedFileProblem.unreadable),
    ]) {
      final fetcher = BoundedPublishedEventsFetcher(
        client: MockClient((_) async => response),
        siteUrl: site,
      );
      final result = await fetcher.fetch(url);
      expect(result, isFailed);
      expect((result as PublishedFileFailed).problem, problem);
    }
  });

  test('a transport failure is a NetworkFailure, "unreachable"', () async {
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async => throw http.ClientException('offline')),
      siteUrl: site,
    );
    final result = await fetcher.fetch(url) as PublishedFileFailed;
    expect(result.failure, isA<NetworkFailure>());
    expect(result.problem, PublishedFileProblem.unreachable);
  });

  test('an off-site URL is refused before any request', () async {
    var calls = 0;
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async {
        calls++;
        return http.Response(payload, 200);
      }),
      siteUrl: site,
    );
    final result = await fetcher.fetch('https://evil.example/events.json');
    expect(result, isFailed);
    expect(calls, 0);
  });

  test('the streamed body cap fails closed', () async {
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async => http.Response(payload, 200)),
      siteUrl: site,
      maxBytes: 16,
    );
    expect(await fetcher.fetch(url), isFailed);
  });
}
