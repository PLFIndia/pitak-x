import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_events_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

import '../../../support/published_file_fakes.dart';

/// The events controller lifecycle, plus the saved-copy behaviour it inherits
/// from the shared loader (ADR 0018). The load reads the saved copy's info
/// before asking the host, so `start()`/`pumpEventQueue()` let the fetch
/// begin before a test inspects it.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/events.json';

  PublishedEvents events(String caption) => PublishedEvents(
    declaredSchemaVersion: 1,
    posters: [
      PublishedEventPoster(imageRef: 'posters/a.jpg', description: caption),
    ],
  );

  late _FakeEventsFetcher fake;
  late InMemoryPublishedFileCache cache;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeEventsFetcher();
    cache = InMemoryPublishedFileCache();
    container = ProviderContainer(
      overrides: [
        publishedEventsFetcherProvider(site).overrideWithValue(fake.call),
        publishedFileCacheProvider.overrideWithValue(cache),
        publishedEventsDecoderProvider.overrideWithValue(
          (bytes) async => Right(events('Saved')),
        ),
        clockProvider.overrideWithValue(() => 1000),
      ],
    );
    addTearDown(container.dispose);
  });

  ProviderSubscription<AsyncValue<PublishedContent<PublishedEvents>?>>
  listen() => container.listen(
    publishedEventsControllerProvider(site),
    (_, _) {},
    fireImmediately: true,
  );

  Future<ProviderSubscription<AsyncValue<PublishedContent<PublishedEvents>?>>>
  start() async {
    final sub = listen();
    await pumpEventQueue();
    return sub;
  }

  String? shownCaption() => container
      .read(publishedEventsControllerProvider(site))
      .valueOrNull
      ?.value
      .posters
      .single
      .description;

  test('first mount loads once and refresh adds exactly one load', () async {
    final sub = await start();
    expect(fake.calls, [url]);
    fake.completeLatest(events('First'));
    final loaded = await container.read(
      publishedEventsControllerProvider(site).future,
    );
    expect(loaded!.value.posters.single.description, 'First');

    final notifier = container.read(
      publishedEventsControllerProvider(site).notifier,
    );
    final first = notifier.refresh();
    final second = notifier.refresh();
    await pumpEventQueue();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(events('Second'));
    await Future.wait([first, second]);
    expect(shownCaption(), 'Second');
    sub.close();
  });

  test('a 404 (missing file) is successful null data, not an error', () async {
    final sub = await start();
    fake.missingLatest();
    final result = await container.read(
      publishedEventsControllerProvider(site).future,
    );
    expect(result, isNull);
    final state = container.read(publishedEventsControllerProvider(site));
    expect(state.hasError, isFalse);
    expect(state, isA<AsyncData<PublishedContent<PublishedEvents>?>>());
    sub.close();
  });

  test('a typed failure with no saved copy becomes AsyncError and Retry can '
      'recover', () async {
    final sub = await start();
    fake.failLatest();
    await expectLater(
      container.read(publishedEventsControllerProvider(site).future),
      throwsA(isA<NetworkFailure>()),
    );
    expect(
      container.read(publishedEventsControllerProvider(site)).hasError,
      isTrue,
    );

    final refresh = container
        .read(publishedEventsControllerProvider(site).notifier)
        .refresh();
    await pumpEventQueue();
    fake.completeLatest(events('Recovered'));
    await refresh;
    expect(shownCaption(), 'Recovered');
    sub.close();
  });

  test(
    'a failure WITH a saved copy shows the saved events and the notice',
    () async {
      cache.seed(site, PublishedFileKind.events, [1], checkedAt: 700);
      final sub = await start();
      fake.failLatest();
      final loaded = await container.read(
        publishedEventsControllerProvider(site).future,
      );
      expect(loaded!.value.posters.single.description, 'Saved');
      expect(loaded.savedCopy!.checkedAt, 700);
      expect(loaded.savedCopy!.problem, PublishedFileProblem.unreachable);
      sub.close();
    },
  );

  test('refresh during initial load is ignored', () async {
    final sub = await start();
    await container
        .read(publishedEventsControllerProvider(site).notifier)
        .refresh();
    await pumpEventQueue();
    expect(fake.calls, hasLength(1));
    fake.completeLatest(events('First'));
    await container.read(publishedEventsControllerProvider(site).future);
    sub.close();
  });

  test('route disposal aborts the in-flight request', () async {
    final sub = await start();
    expect(fake.aborts.single.isCompleted, isFalse);
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.aborts.single.isCompleted, isTrue);
  });
}

final class _FakeEventsFetcher {
  final calls = <String>[];
  final aborts = <Completer<void>>[];
  final _pending = <Completer<PublishedFileFetch<PublishedEvents>>>[];

  Future<PublishedFileFetch<PublishedEvents>> call(
    String url, {
    String? validator,
    Future<void>? abortTrigger,
  }) {
    calls.add(url);
    if (abortTrigger != null) {
      final abort = Completer<void>();
      aborts.add(abort);
      unawaited(
        abortTrigger.whenComplete(() {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    final completer = Completer<PublishedFileFetch<PublishedEvents>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedEvents events) =>
      _pending.last.complete(fetchedValue(events, bytes: [1]));

  void missingLatest() => _pending.last.complete(const PublishedFileMissing());

  void failLatest() =>
      _pending.last.complete(failedFetch(const NetworkFailure()));
}
