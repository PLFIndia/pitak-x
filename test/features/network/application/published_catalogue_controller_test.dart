import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

import '../../../support/published_file_fakes.dart';

/// The catalogue controller's lifecycle (ADR 0015 V12, viewer plan S3):
/// one GET per mount, one in-flight refresh, typed AsyncValue states, caller
/// abort on disposal, and no stale session resurrection. No real HTTP:
/// `publishedCatalogueFetcherProvider` is replaced with a fake port, and the
/// saved copies (ADR 0018) live in an in-memory store.
///
/// The load reads the saved copy's info BEFORE it asks the host (to send its
/// tag), so the fetch starts a few microtasks after the listen/refresh:
/// `start()` and `pumpEventQueue()` let it begin before a test inspects it.
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
  late InMemoryPublishedFileCache cache;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeFetcher();
    cache = InMemoryPublishedFileCache();
    container = ProviderContainer(
      overrides: [
        publishedCatalogueFetcherProvider(site).overrideWithValue(fake.call),
        publishedFileCacheProvider.overrideWithValue(cache),
        // Every saved copy in this suite decodes to the same marker title.
        publishedCatalogueDecoderProvider.overrideWithValue(
          (bytes) async => Right(catalogueWith('Saved')),
        ),
        clockProvider.overrideWithValue(() => 1000),
      ],
    );
    addTearDown(container.dispose);
  });

  ProviderSubscription<AsyncValue<PublishedContent<PublishedCatalogue>>>
  listen() => container.listen(
    publishedCatalogueControllerProvider(site),
    (_, _) {},
    fireImmediately: true,
  );

  /// Listens and lets the initial load reach the fetcher.
  Future<ProviderSubscription<AsyncValue<PublishedContent<PublishedCatalogue>>>>
  start() async {
    final sub = listen();
    await pumpEventQueue();
    return sub;
  }

  String? shownTitle() => container
      .read(publishedCatalogueControllerProvider(site))
      .valueOrNull
      ?.value
      .items
      .single
      .title;

  test('the first mount performs exactly one fetch', () async {
    final sub = await start();
    expect(fake.calls, [catalogueUrl]);

    fake.completeLatest(catalogueWith('First'));
    final loaded = await container.read(
      publishedCatalogueControllerProvider(site).future,
    );
    expect(loaded.value.items.single.title, 'First');
    expect(loaded.isSavedCopy, isFalse);
    expect(fake.calls, hasLength(1), reason: 'a rebuild must not refetch');
    sub.close();
  });

  test('a typed failure becomes AsyncError with the typed Failure', () async {
    final sub = await start();
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
    final sub = await start();
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
    await pumpEventQueue();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(catalogueWith('Recovered'));
    await refresh;
    expect(shownTitle(), 'Recovered');
    sub.close();
  });

  test('a refresh while the initial load is in flight is ignored', () async {
    final sub = await start();
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
      final sub = await start();
      fake.completeLatest(catalogueWith('First'));
      await container.read(publishedCatalogueControllerProvider(site).future);

      final notifier = container.read(
        publishedCatalogueControllerProvider(site).notifier,
      );
      final first = notifier.refresh();
      final second = notifier.refresh();
      await pumpEventQueue();
      expect(fake.calls, hasLength(2), reason: 'only one reload request');
      fake.completeLatest(catalogueWith('Second'));
      await Future.wait([first, second]);
      expect(shownTitle(), 'Second');
      sub.close();
    },
  );

  test('canRefresh is the one reload decision (V12)', () async {
    // Nothing is saved, so the final failed reload is a real error state.
    cache.failWrites = true;
    final sub = await start();
    final notifier = container.read(
      publishedCatalogueControllerProvider(site).notifier,
    );

    // The initial load owns the GET.
    expect(notifier.canRefresh, isFalse);

    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);
    expect(notifier.canRefresh, isTrue, reason: 'idle after data');

    // …and a manual reload closes the door again, synchronously.
    final refresh = notifier.refresh();
    expect(notifier.canRefresh, isFalse, reason: 'reload in flight');
    await pumpEventQueue();
    fake.completeLatest(catalogueWith('Second'));
    await refresh;
    expect(notifier.canRefresh, isTrue);

    // A typed error leaves the Retry path available.
    final failed = notifier.refresh();
    await pumpEventQueue();
    fake.failLatest(failure);
    await failed;
    expect(
      container.read(publishedCatalogueControllerProvider(site)).hasError,
      isTrue,
    );
    expect(notifier.canRefresh, isTrue, reason: 'a typed error is retryable');
    sub.close();
  });

  test('refresh() refuses exactly when canRefresh is false', () async {
    final sub = await start();
    final notifier = container.read(
      publishedCatalogueControllerProvider(site).notifier,
    );
    // Initial load: refresh must not add a GET.
    expect(notifier.canRefresh, isFalse);
    await notifier.refresh();
    expect(fake.calls, hasLength(1));

    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);
    expect(notifier.canRefresh, isTrue);
    final refresh = notifier.refresh();
    await pumpEventQueue();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(catalogueWith('Second'));
    await refresh;
    sub.close();
  });

  test('disposal completes the caller abort so the socket closes', () async {
    final sub = await start();
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
    final firstSub = await start();
    expect(fake.calls, hasLength(1));
    firstSub.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The aborted first request never completes; the new session must not
    // inherit its result.
    fake.completeLatest(catalogueWith('Abandoned'));

    final secondSub = await start();
    expect(fake.calls, hasLength(2));
    fake.completeLatest(catalogueWith('Fresh'));
    final loaded = await container.read(
      publishedCatalogueControllerProvider(site).future,
    );
    expect(loaded.value.items.single.title, 'Fresh');
    secondSub.close();
  });

  test('a failed reload with NO saved copy replaces the viewing state with '
      'the error', () async {
    cache.failWrites = true; // the first load could not be saved
    final sub = await start();
    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);

    final refresh = container
        .read(publishedCatalogueControllerProvider(site).notifier)
        .refresh();
    await pumpEventQueue();
    fake.failLatest(failure);
    await refresh;
    final state = container.read(publishedCatalogueControllerProvider(site));
    expect(state.hasError, isTrue);
    expect(state.error, same(failure));
    // No stale data is presented as fresh.
    expect(state.isLoading, isFalse);
    sub.close();
  });

  test('a failed reload WITH a saved copy shows it, labelled as saved '
      '(ADR 0018)', () async {
    final sub = await start();
    fake.completeLatest(catalogueWith('First'));
    await container.read(publishedCatalogueControllerProvider(site).future);
    expect(cache.peek(site, PublishedFileKind.catalogue), isNotNull);

    final refresh = container
        .read(publishedCatalogueControllerProvider(site).notifier)
        .refresh();
    await pumpEventQueue();
    fake.failLatest(failure);
    await refresh;
    final state = container.read(publishedCatalogueControllerProvider(site));
    expect(state.hasError, isFalse);
    final content = state.requireValue;
    expect(content.value.items.single.title, 'Saved');
    expect(content.savedCopy!.checkedAt, 1000);
    expect(content.savedCopy!.problem, PublishedFileProblem.unreachable);
    sub.close();
  });

  test('the next open sends the saved copy tag', () async {
    final first = await start();
    fake.completeLatest(catalogueWith('First'), validator: '"v1"');
    await container.read(publishedCatalogueControllerProvider(site).future);
    first.close();
    await pumpEventQueue();

    final second = await start();
    expect(fake.validators, [null, '"v1"']);
    fake.unchangedLatest();
    final loaded = await container.read(
      publishedCatalogueControllerProvider(site).future,
    );
    expect(loaded.value.items.single.title, 'Saved');
    expect(loaded.isSavedCopy, isFalse, reason: 'the host confirmed it');
    second.close();
  });

  test('reading the state repeatedly does not refetch', () async {
    final sub = await start();
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
  final List<String?> validators = [];
  final List<Future<void>> aborts = [];
  final List<Completer<PublishedFileFetch<PublishedCatalogue>>> _pending = [];

  Future<PublishedFileFetch<PublishedCatalogue>> call(
    String url, {
    String? validator,
    Future<void>? abortTrigger,
  }) {
    calls.add(url);
    validators.add(validator);
    if (abortTrigger != null) aborts.add(abortTrigger);
    final completer = Completer<PublishedFileFetch<PublishedCatalogue>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedCatalogue catalogue, {String? validator}) =>
      _pending.last.complete(
        fetchedValue(catalogue, bytes: [1], validator: validator),
      );

  void unchangedLatest() =>
      _pending.last.complete(const PublishedFileUnchanged());

  void failLatest(PublishedCatalogueFailure failure) =>
      _pending.last.complete(failedFetch(failure));
}
