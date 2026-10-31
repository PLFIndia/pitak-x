import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_catalogue_use_case.dart';

import '../../../support/published_file_fakes.dart';

/// The catalogue load use case (ADR 0015 viewer plan S2, ADR 0018): it owns
/// the URL policy, runs the shared check-then-saved-copy loader against the
/// CATALOGUE slot, and never lets a corrupted saved URL reach the fetcher or
/// the saved-copy store. The loader's own paths are pinned in
/// `published_file_loader_test.dart`.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const catalogueUrl = 'https://kadugodi.github.io/pitak/books.json';

  PublishedCatalogue emptyCatalogue() => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: const [],
    periodicals: const [],
  );

  late InMemoryPublishedFileCache cache;

  setUp(() => cache = InMemoryPublishedFileCache());

  LoadPublishedCatalogueUseCase useCase(PublishedCatalogueFetcher fetch) =>
      LoadPublishedCatalogueUseCase(
        fetch: fetch,
        decode: (bytes) async => Right(emptyCatalogue()),
        cache: cache,
        clock: () => 1000,
      );

  test('resolves the sibling books.json and delegates once', () async {
    final calls = <String>[];
    final load = useCase((url, {validator, abortTrigger}) async {
      calls.add(url);
      return fetchedValue(emptyCatalogue(), bytes: [1, 2, 3]);
    });

    final result = await load(site);
    expect(calls, [catalogueUrl]);
    final content = result.toNullable()!;
    expect(content.value.items, isEmpty);
    expect(content.isSavedCopy, isFalse);
    // Saved in the CATALOGUE slot only, keyed by the canonical site URL.
    expect(cache.bytesOf(site, PublishedFileKind.catalogue), [1, 2, 3]);
    expect(cache.bytesOf(site, PublishedFileKind.events), isNull);
  });

  test('forwards the caller abort signal to the port', () async {
    final caller = Completer<void>();
    Future<void>? received;
    final load = useCase((url, {validator, abortTrigger}) async {
      received = abortTrigger;
      return fetchedValue(emptyCatalogue());
    });
    await load(site, abortTrigger: caller.future);
    expect(received, same(caller.future));
  });

  test('a non-canonical or non-Pages URL never reaches the port or the '
      'saved copies', () async {
    var called = false;
    final load = useCase((url, {validator, abortTrigger}) async {
      called = true;
      return fetchedValue(emptyCatalogue());
    });
    for (final bad in <String>[
      'https://kadugodi.github.io/pitak', // not canonical (no trailing slash)
      'https://Kadugodi.github.io/pitak/',
      'https://kadugodi.github.io/pitak/index.html',
      'https://kadugodi.github.io/pitak/?x=1',
      'http://kadugodi.github.io/pitak/',
      'https://evil.example/pitak/',
      'https://user@kadugodi.github.io/pitak/',
      '',
    ]) {
      final result = await load(bad);
      expect(result.isLeft(), isTrue, reason: 'must refuse "$bad"');
      expect(
        result.swap().toNullable(),
        isA<PublishedCatalogueFailure>().having(
          (f) => f.reason,
          'reason',
          PublishedCatalogueFailureReason.disallowedUrl,
        ),
      );
    }
    expect(called, isFalse, reason: 'no request for an unusable URL');
    expect(cache.calls, isEmpty, reason: 'no saved-copy access either');
  });

  test('a fetch failure with no saved copy passes through unchanged', () async {
    final load = useCase(
      (url, {validator, abortTrigger}) async => failedFetch(
        const PublishedCatalogueFailure(
          PublishedCatalogueFailureReason.httpStatus,
        ),
        problem: PublishedFileProblem.notServed,
      ),
    );
    final result = await load(site);
    expect(
      (result.swap().toNullable()! as PublishedCatalogueFailure).reason,
      PublishedCatalogueFailureReason.httpStatus,
    );
  });

  test('a fetch failure WITH a saved copy shows that copy and its '
      'notice', () async {
    cache.seed(site, PublishedFileKind.catalogue, [9], checkedAt: 500);
    final load = useCase(
      (url, {validator, abortTrigger}) async => failedFetch(
        const PublishedCatalogueFailure(
          PublishedCatalogueFailureReason.transport,
        ),
      ),
    );
    final content = (await load(site)).toNullable()!;
    expect(content.isSavedCopy, isTrue);
    expect(content.savedCopy!.checkedAt, 500);
    expect(content.savedCopy!.problem, PublishedFileProblem.unreachable);
  });

  test('a misbehaving adapter that reports "missing" is still a failure '
      '(the catalogue is required)', () async {
    final load = useCase(
      (url, {validator, abortTrigger}) async => const PublishedFileMissing(),
    );
    final result = await load(site);
    expect(
      (result.swap().toNullable()! as PublishedCatalogueFailure).reason,
      PublishedCatalogueFailureReason.httpStatus,
    );
  });

  test(
    'a port that reports a newer schema is a success, not a failure',
    () async {
      final newer = PublishedCatalogue(
        declaredSchemaVersion: 2,
        items: const [],
        periodicals: const [],
      );
      final load = useCase(
        (url, {validator, abortTrigger}) async => fetchedValue(newer),
      );
      final result = await load(site);
      expect(result.toNullable()!.value.hasNewerSchema, isTrue);
    },
  );
}
