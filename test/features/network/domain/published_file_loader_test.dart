import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/published_file_loader.dart';

import '../../../support/published_file_fakes.dart';

/// The shared "check first, then the saved copy" algorithm (ADR 0018). Every
/// branch the user can end up in is pinned here: fresh download, confirmed
/// copy (`304`), damaged/unreadable copy, removed file, failures with and
/// without a saved copy, cache failures, and an abandoned load.
///
/// The decoded type is a plain String: the loader is generic, and the
/// decoder below turns bytes into text so a test can see WHICH bytes were
/// shown.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';
  const url = 'https://kadugodi.github.io/pitak/books.json';
  const kind = PublishedFileKind.catalogue;
  const offline = NetworkFailure();

  late InMemoryPublishedFileCache cache;
  late List<({String url, String? validator})> requests;
  late List<PublishedFileFetch<String>> responses;
  var now = 0;

  setUp(() {
    cache = InMemoryPublishedFileCache();
    requests = [];
    responses = [];
    now = 5000;
  });

  /// Decodes bytes to text; the byte 0xFF means "unreadable".
  Future<Either<Failure, String>> decode(Uint8List bytes) async =>
      bytes.contains(0xFF)
      ? const Left(ValidationFailure('unreadable'))
      : Right(String.fromCharCodes(bytes));

  PublishedFileLoader<String> loader() => PublishedFileLoader<String>(
    kind: kind,
    fetch: (requested, {validator, abortTrigger}) async {
      requests.add((url: requested, validator: validator));
      return responses.removeAt(0);
    },
    decode: decode,
    cache: cache,
    clock: () => now,
  );

  PublishedFileFetched<String> fresh(String text, {String? tag}) =>
      fetchedValue(text, bytes: text.codeUnits, validator: tag);

  group('host reachable', () {
    test(
      'first open: no tag sent, the file is saved and shown as current',
      () async {
        responses = [fresh('v1', tag: '"a"')];
        final content = (await loader()(siteUrl: site, url: url)).toNullable()!;
        expect(content.value, 'v1');
        expect(content.isSavedCopy, isFalse);
        expect(requests.single.validator, isNull);
        final saved = cache.peek(site, kind)!;
        expect(saved.validator, '"a"');
        expect(saved.checkedAt, 5000);
      },
    );

    test(
      'unchanged (304): the tag is sent, the saved bytes are re-decoded '
      'and the confirmation time moves forward — nothing is re-saved',
      () async {
        cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1, validator: '"a"');
        responses = [const PublishedFileUnchanged()];
        final content = (await loader()(siteUrl: site, url: url)).toNullable()!;
        expect(content.value, 'v1');
        expect(content.isSavedCopy, isFalse, reason: 'the host confirmed it');
        expect(requests.single.validator, '"a"');
        expect(cache.peek(site, kind)!.checkedAt, 5000);
        expect(cache.calls, isNot(contains('save catalogue')));
      },
    );

    test('changed (200): the new version replaces the saved copy', () async {
      cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1, validator: '"a"');
      responses = [fresh('v2', tag: '"b"')];
      final content = (await loader()(siteUrl: site, url: url)).toNullable()!;
      expect(content.value, 'v2');
      expect(cache.bytesOf(site, kind), 'v2'.codeUnits);
      expect(cache.peek(site, kind)!.validator, '"b"');
    });

    test('a saved copy without a tag sends no tag (full download)', () async {
      cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1);
      responses = [fresh('v1')];
      await loader()(siteUrl: site, url: url);
      expect(requests.single.validator, isNull);
    });

    test(
      '304 but the saved copy is gone: asks once more WITHOUT a tag',
      () async {
        cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1, validator: '"a"');
        // The copy disappears between the info read and the byte read (the OS
        // purged it): simulate by removing it when the fetch runs.
        responses = [const PublishedFileUnchanged(), fresh('v1', tag: '"a"')];
        final load = PublishedFileLoader<String>(
          kind: kind,
          fetch: (requested, {validator, abortTrigger}) async {
            requests.add((url: requested, validator: validator));
            await cache.remove(site, kind);
            return responses.removeAt(0);
          },
          decode: decode,
          cache: cache,
          clock: () => now,
        );
        final content = (await load(siteUrl: site, url: url)).toNullable()!;
        expect(content.value, 'v1');
        expect(requests.map((r) => r.validator), ['"a"', null]);
      },
    );

    test('304 but the saved copy no longer decodes: it is deleted and the '
        'file is downloaded again', () async {
      cache.seed(site, kind, [0xFF], checkedAt: 1, validator: '"a"');
      responses = [const PublishedFileUnchanged(), fresh('v1', tag: '"a"')];
      final content = (await loader()(siteUrl: site, url: url)).toNullable()!;
      expect(content.value, 'v1');
      expect(requests.map((r) => r.validator), ['"a"', null]);
      expect(cache.calls, contains('remove catalogue'));
      expect(cache.bytesOf(site, kind), 'v1'.codeUnits);
    });

    test('a host that answers 304 to a tagless request twice is an '
        'unexpected failure, never an empty screen', () async {
      responses = [
        const PublishedFileUnchanged(),
        const PublishedFileUnchanged(),
      ];
      final result = await loader()(siteUrl: site, url: url);
      expect(result.swap().toNullable(), isA<UnexpectedFailure>());
      expect(requests, hasLength(2));
    });

    test(
      '404 (missing file) deletes the saved copy and returns null',
      () async {
        cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1);
        responses = [const PublishedFileMissing()];
        final result = await loader()(siteUrl: site, url: url);
        expect(result.isRight(), isTrue);
        expect(result.toNullable(), isNull);
        expect(cache.bytesOf(site, kind), isNull);
      },
    );
  });

  group('host not usable', () {
    test('no saved copy: the typed failure is returned', () async {
      responses = [failedFetch(offline)];
      final result = await loader()(siteUrl: site, url: url);
      expect(result.swap().toNullable(), same(offline));
    });

    test(
      'saved copy: shown with its last-confirmed time and the reason',
      () async {
        cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1234);
        for (final problem in PublishedFileProblem.values) {
          responses = [failedFetch(offline, problem: problem)];
          final content = (await loader()(
            siteUrl: site,
            url: url,
          )).toNullable()!;
          expect(content.value, 'v1');
          expect(content.savedCopy!.checkedAt, 1234);
          expect(content.savedCopy!.problem, problem);
        }
      },
    );

    test('an unreadable NEW version keeps the old copy and says so', () async {
      cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1, validator: '"a"');
      responses = [
        failedFetch(
          const ValidationFailure('bad'),
          problem: PublishedFileProblem.unreadable,
        ),
      ];
      final content = (await loader()(siteUrl: site, url: url)).toNullable()!;
      expect(content.value, 'v1');
      expect(content.savedCopy!.problem, PublishedFileProblem.unreadable);
      expect(cache.bytesOf(site, kind), 'v1'.codeUnits, reason: 'kept');
    });

    test('a saved copy that no longer decodes is deleted, and the original '
        'failure is returned', () async {
      cache.seed(site, kind, [0xFF], checkedAt: 1);
      responses = [failedFetch(offline)];
      final result = await loader()(siteUrl: site, url: url);
      expect(result.swap().toNullable(), same(offline));
      expect(cache.bytesOf(site, kind), isNull);
    });
  });

  group('bookkeeping', () {
    test('the open is recorded BEFORE the request (eviction order)', () async {
      responses = [fresh('v1')];
      await loader()(siteUrl: site, url: url);
      expect(cache.openedAt[site], 5000);
      expect(cache.calls.first, 'markOpened');
    });

    test('cache write failures never turn into a viewing failure', () async {
      cache
        ..seed(site, kind, 'v1'.codeUnits, checkedAt: 1, validator: '"a"')
        ..failWrites = true;
      responses = [const PublishedFileUnchanged()];
      expect(
        (await loader()(siteUrl: site, url: url)).toNullable()!.value,
        'v1',
      );
      responses = [fresh('v2')];
      expect(
        (await loader()(siteUrl: site, url: url)).toNullable()!.value,
        'v2',
      );
    });

    test('an abandoned load never decodes the saved copy', () async {
      cache.seed(site, kind, 'v1'.codeUnits, checkedAt: 1);
      final abort = Completer<void>();
      final load = PublishedFileLoader<String>(
        kind: kind,
        fetch: (requested, {validator, abortTrigger}) async {
          abort.complete();
          await Future<void>.delayed(Duration.zero);
          return failedFetch(offline);
        },
        decode: decode,
        cache: cache,
        clock: () => now,
      );
      final result = await load(
        siteUrl: site,
        url: url,
        abortTrigger: abort.future,
      );
      expect(result.isLeft(), isTrue);
      expect(cache.calls, isNot(contains('readBytes catalogue')));
    });
  });
}
