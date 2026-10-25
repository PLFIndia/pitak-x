import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// The catalogue controller's lifecycle (ADR 0015 V12, viewer plan S3):
/// one GET per mount, one in-flight refresh, typed AsyncValue states, caller
/// abort on disposal, and no stale session resurrection. No real HTTP:
/// `publishedCatalogueFetcherProvider` is replaced with a fake port.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const catalogueUrl = 'https://kadugodi.github.io/pitak/books.json';

  PublishedCatalogue catalogueWith(String title) => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: [
      PublishedCatalogueItem(
        sourceIndex: 0,
        title: title,
        kind: PublishedItemKind.book,
      ),
    ],
    periodicals: const [],
  );

  const failure = PublishedCatalogueFailure(
    PublishedCatalogueFailureReason.httpStatus,
  );

  late _FakeFetcher fake;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeFetcher();
    container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue(fake.call),
      ],
    );
    addTearDown(container.dispose);
  });

  ProviderSubscription<AsyncValue<PublishedCatalogue>> listen() =>
      container.listen(
        publishedCatalogueControllerProvider(site),
        (_, _) {},
        fireImmediately: true,
      );

  test('the first mount performs exactly one fetch', () async {
    final sub = listen();
    expect(fake.calls, [catalogueUrl]);

    fake.completeLatest(catalogueWith('First'));
    final loaded = await container.read(
      publishedCatalogueControllerProvider(site).future,
    );
    expect(loaded.items.single.title, 'First');
    expect(fake.calls, hasLength(1), reason: 'a rebuild must not refetch');
    sub.close();
  });

  test('a typed failure becomes AsyncError with the typed Failure', () async {
    final sub = listen();
    fake.failLatest(failure);
    await expectLater(
      container.read(publishedCatalogueControllerProvider(site).future),
      throwsA(same(failure)),
    );
    final state = container.read(publishedCatalogueControllerProvider(site));
    expect(state.hasError, isTrue);
    expect(state.error, same(failure));
    expect(state.valueOrNull, isNull);
    sub.close();
  });

  test('refresh performs one more fetch and retries after an error', () async {
    final sub = listen();
    fake.failLatest(failure);
    await expectLater(
      container.read(publishedCatalogueControllerProvider(site).future),
      throwsA(same(failure)),
    );

    final refresh = container
        .read(publishedCatalogueControllerProvider(site).notifier)
        .refresh();
    expect(
      container.read(publishedCatalogueControllerProvider(site)).isLoading,
      isTrue,
    );
    expect(fake.calls, hasLength(2));
    fake.completeLatest(catalogueWith('Recovered'));
    await refresh;
    expect(
      container
          .read(publishedCatalogueControllerProvider(site))
          .valueOrNull!
          .items
          .single
          .title,
      'Recovered',
    );
    sub.close();
  });

  test('a refresh while the initial load is in flight is ignored', () async {
    final sub = listen();
    final notifier = container.read(
      publishedCatalogueControllerProvider(site).notifier,
    );
    await notifier.refresh();
    expect(fake.calls, hasLength(1), reason: 'the initial load owns the GET');

    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);
    sub.close();
  });

  test(
    'a second concurrent refresh is collapsed into the running one',
    () async {
      final sub = listen();
      fake.completeLatest(catalogueWith('First'));
      await container.read(publishedCatalogueControllerProvider(site).future);

      final notifier = container.read(
        publishedCatalogueControllerProvider(site).notifier,
      );
      final first = notifier.refresh();
      final second = notifier.refresh();
      expect(fake.calls, hasLength(2), reason: 'only one reload request');
      fake.completeLatest(catalogueWith('Second'));
      await Future.wait([first, second]);
      expect(
        container
            .read(publishedCatalogueControllerProvider(site))
            .valueOrNull!
            .items
            .single
            .title,
        'Second',
      );
      sub.close();
    },
  );

  test('disposal completes the caller abort so the socket closes', () async {
    final sub = listen();
    final abort = fake.aborts.single;
    var aborted = false;
    unawaited(abort.then((_) => aborted = true));

    sub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(aborted, isTrue);
    // The pending fetch may still complete later; a disposed controller must
    // not throw or write state.
    fake.completeLatest(catalogueWith('Late'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('a rapid close/reopen is exactly one new GET', () async {
    final firstSub = listen();
    expect(fake.calls, hasLength(1));
    firstSub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The aborted first request never completes; the new session must not
    // inherit its result.
    fake.completeLatest(catalogueWith('Abandoned'));

    final secondSub = listen();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(catalogueWith('Fresh'));
    final loaded = await container.read(
      publishedCatalogueControllerProvider(site).future,
    );
    expect(loaded.items.single.title, 'Fresh');
    secondSub.close();
  });

  test('a failed reload replaces the viewing state with the error', () async {
    final sub = listen();
    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);

    final refresh = container
        .read(publishedCatalogueControllerProvider(site).notifier)
        .refresh();
    fake.failLatest(failure);
    await refresh;
    final state = container.read(publishedCatalogueControllerProvider(site));
    expect(state.hasError, isTrue);
    expect(state.error, same(failure));
    // No stale data is presented as fresh (there is no persistent copy).
    expect(state.isLoading, isFalse);
    sub.close();
  });

  test('reading the state repeatedly does not refetch', () async {
    final sub = listen();
    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);
    for (var i = 0; i < 5; i++) {
      expect(
        container.read(publishedCatalogueControllerProvider(site)).hasValue,
        isTrue,
      );
    }
    expect(fake.calls, hasLength(1));
    sub.close();
  });
}

/// A controllable implementation of the fetcher port.
final class _FakeFetcher {
  final List<String> calls = [];
  final List<Future<void>> aborts = [];
  final List<Completer<Either<PublishedCatalogueFailure, PublishedCatalogue>>>
  _pending = [];

  Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> call(
    String url, {
    Future<void>? abortTrigger,
  }) {
    calls.add(url);
    if (abortTrigger != null) aborts.add(abortTrigger);
    final completer =
        Completer<Either<PublishedCatalogueFailure, PublishedCatalogue>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedCatalogue catalogue) =>
      _pending.last.complete(Right(catalogue));

  void failLatest(PublishedCatalogueFailure failure) =>
      _pending.last.complete(Left(failure));
}
