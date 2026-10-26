import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_events_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';

void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/events.json';

  late _FakeEventsFetcher fake;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeEventsFetcher();
    container = ProviderContainer(
      overrides: [
        publishedEventsFetcherProvider(site).overrideWithValue(fake.call),
      ],
    );
    addTearDown(container.dispose);
  });

  ProviderSubscription<AsyncValue<PublishedEvents?>> listen() =>
      container.listen(
        publishedEventsControllerProvider(site),
        (_, _) {},
        fireImmediately: true,
      );

  PublishedEvents events(String caption) => PublishedEvents(
    declaredSchemaVersion: 1,
    posters: [
      PublishedEventPoster(imageRef: 'posters/a.jpg', description: caption),
    ],
  );

  test('first mount loads once and refresh adds exactly one load', () async {
    final sub = listen();
    expect(fake.calls, [url]);
    fake.completeLatest(events('First'));
    expect(
      (await container.read(
        publishedEventsControllerProvider(site).future,
      ))!.posters.single.description,
      'First',
    );

    final notifier = container.read(
      publishedEventsControllerProvider(site).notifier,
    );
    final first = notifier.refresh();
    final second = notifier.refresh();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(events('Second'));
    await Future.wait([first, second]);
    expect(
      container
          .read(publishedEventsControllerProvider(site))
          .valueOrNull!
          .posters
          .single
          .description,
      'Second',
    );
    sub.close();
  });

  test('a 404 null is successful data, not an error', () async {
    final sub = listen();
    fake.completeLatest(null);
    final result = await container.read(
      publishedEventsControllerProvider(site).future,
    );
    expect(result, isNull);
    final state = container.read(publishedEventsControllerProvider(site));
    expect(state.hasError, isFalse);
    expect(state, isA<AsyncData<PublishedEvents?>>());
    sub.close();
  });

  test('a typed failure becomes AsyncError and Retry can recover', () async {
    final sub = listen();
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
    fake.completeLatest(events('Recovered'));
    await refresh;
    expect(
      container
          .read(publishedEventsControllerProvider(site))
          .valueOrNull!
          .posters
          .single
          .description,
      'Recovered',
    );
    sub.close();
  });

  test('refresh during initial load is ignored', () async {
    final sub = listen();
    await container
        .read(publishedEventsControllerProvider(site).notifier)
        .refresh();
    expect(fake.calls, hasLength(1));
    fake.completeLatest(events('First'));
    await container.read(publishedEventsControllerProvider(site).future);
    sub.close();
  });

  test('route disposal aborts the in-flight request', () async {
    final sub = listen();
    expect(fake.aborts.single.isCompleted, isFalse);
    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(fake.aborts.single.isCompleted, isTrue);
  });
}

final class _FakeEventsFetcher {
  final calls = <String>[];
  final aborts = <Completer<void>>[];
  final _pending = <Completer<Either<Failure, PublishedEvents?>>>[];

  Future<Either<Failure, PublishedEvents?>> call(
    String url, {
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
    final completer = Completer<Either<Failure, PublishedEvents?>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedEvents? events) =>
      _pending.last.complete(Right(events));

  void failLatest() => _pending.last.complete(const Left(NetworkFailure()));
}
