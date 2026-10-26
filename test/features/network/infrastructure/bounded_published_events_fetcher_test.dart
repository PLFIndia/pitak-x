import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
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

  test(
    'loads the exact sibling file with no-cache and app User-Agent',
    () async {
      late http.BaseRequest observed;
      final fetcher = BoundedPublishedEventsFetcher(
        client: MockClient((request) async {
          observed = request;
          return http.Response(payload, 200);
        }),
        siteUrl: site,
      );
      final result = await fetcher.fetch(url);
      expect(result.isRight(), isTrue);
      expect(result.toNullable()!.posters.single.description, 'Story');
      expect(observed.url.toString(), url);
      expect(observed.headers['User-Agent'], AppUserAgent.value);
      expect(observed.headers['Cache-Control'], 'no-cache');
      expect(observed.headers.containsKey('Cookie'), isFalse);
      expect(observed.headers.containsKey('Authorization'), isFalse);
    },
  );

  test('404 alone means no published events', () async {
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async => http.Response('not found', 404)),
      siteUrl: site,
    );
    final result = await fetcher.fetch(url);
    expect(result.isRight(), isTrue);
    expect(result.toNullable(), isNull);
  });

  test('other HTTP and payload failures stay typed failures', () async {
    for (final response in [
      http.Response('server error', 500),
      http.Response('{not json', 200),
    ]) {
      final fetcher = BoundedPublishedEventsFetcher(
        client: MockClient((_) async => response),
        siteUrl: site,
      );
      expect((await fetcher.fetch(url)).isLeft(), isTrue);
    }
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
    expect(result.isLeft(), isTrue);
    expect(calls, 0);
  });

  test('the streamed body cap fails closed', () async {
    final fetcher = BoundedPublishedEventsFetcher(
      client: MockClient((_) async => http.Response(payload, 200)),
      siteUrl: site,
      maxBytes: 16,
    );
    expect((await fetcher.fetch(url)).isLeft(), isTrue);
  });
}
