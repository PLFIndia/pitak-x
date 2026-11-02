import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/published_availability_fetcher.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/load_published_availability_use_case.dart';

import '../../../support/published_file_fakes.dart';

/// The `availability.json` use case (ADR 0019, ADR 0015 and ADR 0018
/// amendments). The shared "check first, then the saved copy" algorithm is
/// pinned by `published_file_loader_test.dart`; this suite pins what is
/// specific to the third file: the URL guard, the exact sibling address, its
/// own saved-copy slot, and "missing removes the old copy".
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const availability = PublishedFileKind.availability;

  /// What the fake decoder returns for a saved copy.
  final savedFile = PublishedAvailabilityFile(
    keySet: '5e0c1d2b3a497f68',
    outKeys: const {'aaaaaaaaaaaaaaa1'},
    asOf: 1761984300000,
  );

  /// What the fake fetcher returns for a fresh download.
  final freshFile = PublishedAvailabilityFile(
    keySet: '5e0c1d2b3a497f68',
    outKeys: const {'bbbbbbbbbbbbbbb2'},
  );

  late InMemoryPublishedFileCache cache;

  setUp(() => cache = InMemoryPublishedFileCache());

  LoadPublishedAvailabilityUseCase useCase(
    PublishedAvailabilityFetcher fetch,
  ) => LoadPublishedAvailabilityUseCase(
    fetch: fetch,
    decode: (bytes) async => Right(savedFile),
    cache: cache,
    clock: () => 1000,
  );

  test('a non-canonical saved URL is refused before any request or cache '
      'touch', () async {
    var calls = 0;
    final load = useCase((url, {validator, abortTrigger}) async {
      calls++;
      return fetchedValue(freshFile);
    });
    for (final raw in [
      'http://kadugodi.github.io/pitak/', // not https
      'https://kadugodi.github.io/pitak', // no trailing slash
      'https://Kadugodi.github.io/pitak/', // not normalize()'s spelling
      'https://kadugodi.github.io/pitak/?utm=1',
      'https://evil.example/',
      'not a url',
      '',
    ]) {
      final result = await load(raw);
      expect(result.isLeft(), isTrue, reason: raw);
      expect(result.swap().toNullable(), isA<ValidationFailure>());
    }
    expect(calls, 0);
    expect(cache.calls, isEmpty);
  });

  test(
    'a canonical spelling the URL policy cannot resolve is refused too',
    () async {
      // `normalize()` keeps an empty interior path segment, so this string IS
      // its own canonical form; the site policy still refuses a doubled slash
      // (servers may normalize it unpredictably). Second guard in the use case.
      var calls = 0;
      final load = useCase((url, {validator, abortTrigger}) async {
        calls++;
        return fetchedValue(freshFile);
      });
      final result = await load('https://kadugodi.github.io/pitak//kannada/');
      expect(result.swap().toNullable(), isA<ValidationFailure>());
      expect(calls, 0);
      expect(cache.calls, isEmpty);
    },
  );

  test('requests exactly <site>availability.json in its own slot', () async {
    final requested = <String>[];
    final load = useCase((url, {validator, abortTrigger}) async {
      requested.add(url);
      return const PublishedFileMissing();
    });
    await load(site);
    expect(requested, ['https://kadugodi.github.io/pitak/availability.json']);
    // The saved-copy slot it consults is the availability one, never the
    // catalogue or events copy.
    expect(cache.calls, [
      'markOpened',
      'info availability',
      'remove availability',
    ]);
  });

  test('a sub-directory site keeps its prefix', () async {
    final requested = <String>[];
    final load = useCase((url, {validator, abortTrigger}) async {
      requested.add(url);
      return const PublishedFileMissing();
    });
    await load('https://kadugodi.github.io/pitak/kannada/');
    expect(requested, [
      'https://kadugodi.github.io/pitak/kannada/availability.json',
    ]);
  });

  test('the saved tag is sent and the abort trigger is passed on', () async {
    cache.seed(site, availability, [1], checkedAt: 5, validator: '"e1"');
    String? sentValidator;
    Future<void>? sentTrigger;
    final trigger = Future<void>.value();
    final load = useCase((url, {validator, abortTrigger}) async {
      sentValidator = validator;
      sentTrigger = abortTrigger;
      return fetchedValue(freshFile, bytes: [2]);
    });
    await load(site, abortTrigger: trigger);
    expect(sentValidator, '"e1"');
    expect(sentTrigger, same(trigger));
  });

  test('a fresh file is saved in the availability slot and shown', () async {
    final load = useCase(
      (url, {validator, abortTrigger}) async =>
          fetchedValue(freshFile, bytes: [7, 8], validator: '"e2"'),
    );
    final content = (await load(site)).toNullable()!;
    expect(content.value, same(freshFile));
    expect(content.isSavedCopy, isFalse);
    expect(cache.bytesOf(site, availability), [7, 8]);
    expect(cache.peek(site, availability)!.validator, '"e2"');
    expect(cache.peek(site, availability)!.checkedAt, 1000);
    expect(cache.bytesOf(site, PublishedFileKind.catalogue), isNull);
    expect(cache.bytesOf(site, PublishedFileKind.events), isNull);
  });

  test('a missing (or refused) file removes the earlier saved copy and '
      'returns Right(null)', () async {
    cache
      ..seed(site, availability, [1], checkedAt: 5)
      // The catalogue copy of the same library is not touched.
      ..seed(site, PublishedFileKind.catalogue, [9], checkedAt: 5);
    final load = useCase(
      (url, {validator, abortTrigger}) async => const PublishedFileMissing(),
    );
    final result = await load(site);
    expect(result.isRight(), isTrue);
    expect(result.toNullable(), isNull);
    expect(cache.bytesOf(site, availability), isNull);
    expect(cache.bytesOf(site, PublishedFileKind.catalogue), [9]);
  });

  test('304 re-decodes the saved copy and shows it as current', () async {
    cache.seed(site, availability, [1], checkedAt: 5, validator: '"e1"');
    final load = useCase(
      (url, {validator, abortTrigger}) async => const PublishedFileUnchanged(),
    );
    final content = (await load(site)).toNullable()!;
    expect(content.value, same(savedFile));
    expect(content.isSavedCopy, isFalse);
    expect(cache.peek(site, availability)!.checkedAt, 1000);
  });

  test(
    'a transport failure with a saved copy shows it with its notice',
    () async {
      cache.seed(site, availability, [1], checkedAt: 5);
      final load = useCase(
        (url, {validator, abortTrigger}) async =>
            failedFetch(const NetworkFailure()),
      );
      final content = (await load(site)).toNullable()!;
      expect(content.value, same(savedFile));
      expect(content.isSavedCopy, isTrue);
      expect(content.savedCopy!.checkedAt, 5);
      expect(content.savedCopy!.problem, PublishedFileProblem.unreachable);
      expect(cache.bytesOf(site, availability), [1], reason: 'kept');
    },
  );

  test(
    'a transport failure without a saved copy returns the failure',
    () async {
      const offline = NetworkFailure();
      final load = useCase(
        (url, {validator, abortTrigger}) async => failedFetch(offline),
      );
      final result = await load(site);
      expect(result.swap().toNullable(), same(offline));
    },
  );

  test('a saved copy that no longer decodes is dropped; the failure is '
      'returned', () async {
    cache.seed(site, availability, [1], checkedAt: 5);
    const offline = NetworkFailure();
    final load = LoadPublishedAvailabilityUseCase(
      fetch: (url, {validator, abortTrigger}) async => failedFetch(offline),
      decode: (bytes) async => const Left(ValidationFailure('unreadable')),
      cache: cache,
      clock: () => 1000,
    );
    final result = await load(site);
    expect(result.swap().toNullable(), same(offline));
    expect(cache.bytesOf(site, availability), isNull);
  });
}
