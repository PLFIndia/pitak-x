import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_catalogue_use_case.dart';

/// The catalogue load use case (ADR 0015, viewer plan S2): it owns the URL
/// policy and delegates the actual fetch through an injected port. Every
/// failure path must be a `Left`, never a throw, and a corrupted saved URL must
/// never reach the fetcher.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const catalogueUrl = 'https://kadugodi.github.io/pitak/books.json';

  PublishedCatalogue emptyCatalogue() => PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: const [],
    periodicals: const [],
  );

  test('resolves the sibling books.json and delegates once', () async {
    final calls = <String>[];
    final useCase = LoadPublishedCatalogueUseCase(
      fetch: (url, {abortTrigger}) async {
        calls.add(url);
        return Right(emptyCatalogue());
      },
    );

    final result = await useCase(site);
    expect(calls, [catalogueUrl]);
    expect(result.isRight(), isTrue);
    expect(result.toNullable()!.items, isEmpty);
  });

  test('forwards the caller abort signal to the port', () async {
    final caller = Completer<void>();
    Future<void>? received;
    final useCase = LoadPublishedCatalogueUseCase(
      fetch: (url, {abortTrigger}) async {
        received = abortTrigger;
        return Right(emptyCatalogue());
      },
    );
    await useCase(site, abortTrigger: caller.future);
    expect(received, same(caller.future));
  });

  test('a non-canonical or non-Pages URL never reaches the port', () async {
    var called = false;
    final useCase = LoadPublishedCatalogueUseCase(
      fetch: (url, {abortTrigger}) async {
        called = true;
        return Right(emptyCatalogue());
      },
    );
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
      final result = await useCase(bad);
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
  });

  test('a fetch failure passes through unchanged', () async {
    final useCase = LoadPublishedCatalogueUseCase(
      fetch: (url, {abortTrigger}) async => const Left(
        PublishedCatalogueFailure(PublishedCatalogueFailureReason.httpStatus),
      ),
    );
    final result = await useCase(site);
    expect(result.isLeft(), isTrue);
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
      final useCase = LoadPublishedCatalogueUseCase(
        fetch: (url, {abortTrigger}) async => Right(newer),
      );
      final result = await useCase(site);
      expect(result.toNullable()!.hasNewerSchema, isTrue);
    },
  );
}
