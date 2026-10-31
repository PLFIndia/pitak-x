import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_events_use_case.dart';

import '../../../support/published_file_fakes.dart';

void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  PublishedEvents noEvents() =>
      PublishedEvents(declaredSchemaVersion: 1, posters: const []);

  late InMemoryPublishedFileCache cache;

  setUp(() => cache = InMemoryPublishedFileCache());

  LoadPublishedEventsUseCase useCase(PublishedEventsFetcher fetch) =>
      LoadPublishedEventsUseCase(
        fetch: fetch,
        decode: (bytes) async => Right(noEvents()),
        cache: cache,
        clock: () => 1000,
      );

  test(
    'resolves the independent events.json sibling before fetching',
    () async {
      final calls = <String>[];
      final load = useCase((url, {validator, abortTrigger}) async {
        calls.add(url);
        return const PublishedFileMissing();
      });
      final result = await load(site);
      expect(result.isRight(), isTrue);
      expect(result.toNullable(), isNull, reason: 'no events file');
      expect(calls, ['https://kadugodi.github.io/pitak/events.json']);
    },
  );

  test('events are saved in their own slot, apart from the '
      'catalogue', () async {
    final load = useCase(
      (url, {validator, abortTrigger}) async =>
          fetchedValue(noEvents(), bytes: [7]),
    );
    final content = (await load(site)).toNullable()!;
    expect(content.isSavedCopy, isFalse);
    expect(cache.bytesOf(site, PublishedFileKind.events), [7]);
    expect(cache.bytesOf(site, PublishedFileKind.catalogue), isNull);
  });

  test('a library that stopped publishing events loses the saved '
      'copy', () async {
    cache.seed(site, PublishedFileKind.events, [7], checkedAt: 1);
    final load = useCase(
      (url, {validator, abortTrigger}) async => const PublishedFileMissing(),
    );
    expect((await load(site)).toNullable(), isNull);
    expect(cache.bytesOf(site, PublishedFileKind.events), isNull);
  });

  test('a non-canonical saved URL fails before any request', () async {
    var calls = 0;
    final load = useCase((url, {validator, abortTrigger}) async {
      calls++;
      return fetchedValue(noEvents());
    });
    for (final raw in ['http://kadugodi.github.io/pitak/', 'not a url']) {
      final result = await load(raw);
      expect(result.isLeft(), isTrue);
      expect(result.swap().toNullable(), isA<ValidationFailure>());
    }
    expect(calls, 0);
    expect(cache.calls, isEmpty);
  });
}
