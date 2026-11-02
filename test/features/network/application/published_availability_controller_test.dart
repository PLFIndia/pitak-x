import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/published_availability_controller.dart';
import 'package:pitaka/features/network/application/published_catalogue_controller.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';

import '../../../support/published_file_fakes.dart';

/// The availability controller lifecycle (mirrors the events controller) and
/// the merged catalogue the viewer renders (ADR 0019 Decision 4, ADR 0015
/// amendment). Fakes only: no HTTP, no files.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/availability.json';
  const keySet = '5e0c1d2b3a497f68';

  PublishedAvailabilityFile fileOf(Set<String> out) =>
      PublishedAvailabilityFile(
        keySet: keySet,
        outKeys: out,
        asOf: 1761984300000,
      );

  final catalogue = PublishedCatalogue(
    declaredSchemaVersion: 1,
    keySet: keySet,
    items: const [
      PublishedCatalogueItem(
        sourceIndex: 0,
        title: 'Keyed, inline available',
        kind: PublishedItemKind.book,
        key: 'aaaaaaaaaaaaaaa1',
        availability: PublishedAvailability.available,
        availabilitySource: PublishedAvailabilitySource.catalogue,
      ),
    ],
    periodicals: const [],
  );

  late _FakeAvailabilityFetcher fake;
  late Completer<PublishedFileFetch<PublishedCatalogue>> catalogueAnswer;
  late InMemoryPublishedFileCache cache;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeAvailabilityFetcher();
    catalogueAnswer = Completer();
    cache = InMemoryPublishedFileCache();
    container = ProviderContainer(
      overrides: [
        publishedAvailabilityFetcherProvider(site).overrideWithValue(fake.call),
        publishedCatalogueFetcherProvider(site).overrideWithValue(
          (url, {validator, abortTrigger}) => catalogueAnswer.future,
        ),
        publishedFileCacheProvider.overrideWithValue(cache),
        publishedAvailabilityDecoderProvider.overrideWithValue(
          (bytes) async => Right(fileOf({'aaaaaaaaaaaaaaa1'})),
        ),
        clockProvider.overrideWithValue(() => 1762000000000),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ProviderSubscription<Object?>> start() async {
    final sub = container.listen(
      publishedAvailabilityControllerProvider(site),
      (_, _) {},
      fireImmediately: true,
    );
    await pumpEventQueue();
    return sub;
  }

  group('controller lifecycle', () {
    test('first mount loads once; refresh collapses into one more', () async {
      final sub = await start();
      expect(fake.calls, [url]);
      fake.completeLatest(fileOf({}));
      final loaded = await container.read(
        publishedAvailabilityControllerProvider(site).future,
      );
      expect(loaded!.value.outKeys, isEmpty);

      final notifier = container.read(
        publishedAvailabilityControllerProvider(site).notifier,
      );
      final first = notifier.refresh();
      final second = notifier.refresh();
      await pumpEventQueue();
      expect(fake.calls, hasLength(2));
      fake.completeLatest(fileOf({'aaaaaaaaaaaaaaa1'}));
      await Future.wait([first, second]);
      expect(
        container
            .read(publishedAvailabilityControllerProvider(site))
            .valueOrNull!
            .value
            .outKeys,
        {'aaaaaaaaaaaaaaa1'},
      );
      sub.close();
    });

    test('a missing (or refused) file is null data, not an error', () async {
      final sub = await start();
      fake.missingLatest();
      expect(
        await container.read(
          publishedAvailabilityControllerProvider(site).future,
        ),
        isNull,
      );
      expect(
        container.read(publishedAvailabilityControllerProvider(site)).hasError,
        isFalse,
      );
      sub.close();
    });

    test(
      'a failure with no saved copy is an AsyncError; Retry recovers',
      () async {
        final sub = await start();
        fake.failLatest();
        await expectLater(
          container.read(publishedAvailabilityControllerProvider(site).future),
          throwsA(isA<NetworkFailure>()),
        );
        final refresh = container
            .read(publishedAvailabilityControllerProvider(site).notifier)
            .refresh();
        await pumpEventQueue();
        fake.completeLatest(fileOf({}));
        await refresh;
        expect(
          container
              .read(publishedAvailabilityControllerProvider(site))
              .hasValue,
          isTrue,
        );
        sub.close();
      },
    );

    test(
      'a refresh that fails with no saved copy becomes an AsyncError',
      () async {
        // Nothing can be saved, so no saved copy can stand in for the failure.
        cache.failWrites = true;
        final sub = await start();
        fake.completeLatest(fileOf({}));
        await container.read(
          publishedAvailabilityControllerProvider(site).future,
        );
        final refresh = container
            .read(publishedAvailabilityControllerProvider(site).notifier)
            .refresh();
        await pumpEventQueue();
        fake.failLatest();
        await refresh;
        final state = container.read(
          publishedAvailabilityControllerProvider(site),
        );
        expect(state.hasError, isTrue);
        expect(state.error, isA<NetworkFailure>());
        sub.close();
      },
    );

    test('a failure WITH a saved copy shows it with its notice', () async {
      cache.seed(site, PublishedFileKind.availability, [1], checkedAt: 700);
      final sub = await start();
      fake.failLatest();
      final loaded = await container.read(
        publishedAvailabilityControllerProvider(site).future,
      );
      expect(loaded!.value.outKeys, {'aaaaaaaaaaaaaaa1'});
      expect(loaded.savedCopy!.checkedAt, 700);
      sub.close();
    });

    test('refresh during the initial load is ignored', () async {
      final sub = await start();
      await container
          .read(publishedAvailabilityControllerProvider(site).notifier)
          .refresh();
      await pumpEventQueue();
      expect(fake.calls, hasLength(1));
      fake.missingLatest();
      sub.close();
    });

    test('route disposal aborts the in-flight request', () async {
      final sub = await start();
      expect(fake.aborts.single.isCompleted, isFalse);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fake.aborts.single.isCompleted, isTrue);
    });
  });

  group('merged catalogue (the ONE per-item rule)', () {
    Future<ProviderSubscription<Object?>> listenMerged() async {
      final sub = container.listen(
        publishedCatalogueWithAvailabilityProvider(site),
        (_, _) {},
        fireImmediately: true,
      );
      await pumpEventQueue();
      return sub;
    }

    test('the file is requested in parallel, before the catalogue '
        'arrives', () async {
      final sub = await listenMerged();
      expect(fake.calls, [url], reason: 'no wait for books.json');
      expect(catalogueAnswer.isCompleted, isFalse);
      sub.close();
    });

    test('while the file is on its way the inline tags show; when it lands '
        'the tags are re-decided', () async {
      final sub = await listenMerged();
      catalogueAnswer.complete(fetchedValue(catalogue));
      final first = await container.read(
        publishedCatalogueWithAvailabilityProvider(site).future,
      );
      expect(first.usesFile, isFalse);
      expect(
        first.catalogue.items.single.availability,
        PublishedAvailability.available,
      );

      fake.completeLatest(fileOf({'aaaaaaaaaaaaaaa1'}));
      await pumpEventQueue();
      final second = await container.read(
        publishedCatalogueWithAvailabilityProvider(site).future,
      );
      expect(second.usesFile, isTrue);
      expect(
        second.catalogue.items.single.availability,
        PublishedAvailability.out,
      );
      expect(second.updatedAt, 1761984300000);
      sub.close();
    });

    test('a failed file never blocks the catalogue', () async {
      final sub = await listenMerged();
      fake.failLatest();
      await pumpEventQueue();
      catalogueAnswer.complete(fetchedValue(catalogue));
      final merged = await container.read(
        publishedCatalogueWithAvailabilityProvider(site).future,
      );
      expect(merged.usesFile, isFalse);
      expect(merged.taggedCount, 1);
      expect(
        await container.read(publishedCatalogueControllerProvider(site).future),
        isA<PublishedContent<PublishedCatalogue>>(),
      );
      sub.close();
    });
  });
}

final class _FakeAvailabilityFetcher {
  final calls = <String>[];
  final aborts = <Completer<void>>[];
  final _pending = <Completer<PublishedFileFetch<PublishedAvailabilityFile>>>[];

  Future<PublishedFileFetch<PublishedAvailabilityFile>> call(
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
    final completer =
        Completer<PublishedFileFetch<PublishedAvailabilityFile>>();
    _pending.add(completer);
    return completer.future;
  }

  void completeLatest(PublishedAvailabilityFile file) =>
      _pending.last.complete(fetchedValue(file, bytes: [1]));

  void missingLatest() => _pending.last.complete(const PublishedFileMissing());

  void failLatest() =>
      _pending.last.complete(failedFetch(const NetworkFailure()));
}
