import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/publish/application/restore/recover_published_identity.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import 'restore_use_case_harness.dart';

Future<RestoreFromPublishedSiteSummary> _success(
  RestoreUseCaseHarness h, {
  bool covers = true,
}) async {
  final result = await h.useCase.call(h.siteUrl, downloadCovers: covers);
  final outcome = result.toNullable();
  expect(outcome, isA<RestoreFromPublishedSiteSuccess>(), reason: '$result');
  return (outcome! as RestoreFromPublishedSiteSuccess).summary;
}

void main() {
  late RestoreUseCaseHarness h;
  setUp(() => h = RestoreUseCaseHarness());
  tearDown(() => h.dispose());

  test(
    'success imports real rows and jpg covers, then stores fingerprint',
    () async {
      final summary = await _success(h);

      expect(summary.itemsAdded, 1);
      expect(summary.coversRestored, 1);
      expect(summary.identityPending, isFalse);
      final rows = (await h.fixture.books.getAll()).toNullable()!;
      expect(rows.single.title, 'Restored book');
      expect(rows.single.itemUid, isNotNull);
      expect(rows.single.coverUrl, endsWith('.jpg'));
      expect(rows.single.coverUrl, isNot('covers/source.png'));
      expect(h.fixture.images, hasLength(1));
      expect(h.writtenFingerprint, h.fingerprint);
      expect(h.fingerprintWrites, 1);
      expect(h.journal.value, isNull);
    },
  );

  test(
    'non-empty preflight refuses before any network or identity write',
    () async {
      await h.fixture.books.insert(const CatalogueItem(title: 'Existing'));

      final result = await h.useCase.call(h.siteUrl);

      expect(result.swap().toNullable(), isA<ValidationFailure>());
      expect(h.catalogueCalls, 0);
      expect(h.fingerprintWrites, 0);
      expect(
        (await h.fixture.books.getAll()).toNullable()!.single.title,
        'Existing',
      );
    },
  );

  test(
    'absent descriptor continues with an explicit identity warning',
    () async {
      h.reader.outcome = const PublishedSiteReadAbsent();

      final summary = await _success(h);

      expect(summary.identityMissing, isTrue);
      expect(summary.identityPending, isFalse);
      expect(h.writtenFingerprint, isNull);
      expect(h.fingerprintWrites, 1);
    },
  );

  test('unreadable descriptor aborts before catalogue or rows', () async {
    h.reader.outcome = const PublishedSiteReadUnreadable();

    final result = await h.useCase.call(h.siteUrl);

    expect(result.swap().toNullable(), isA<ValidationFailure>());
    expect(h.catalogueCalls, 0);
    expect(h.fingerprintWrites, 0);
    expect((await h.fixture.books.getAll()).toNullable(), isEmpty);
  });

  test(
    'catalogue refusal writes nothing and leaves identity untouched',
    () async {
      h.catalogueFailure = const PublishedCatalogueFailure(
        PublishedCatalogueFailureReason.transport,
      );

      final result = await h.useCase.call(h.siteUrl);

      expect(result.swap().toNullable(), isA<PublishedCatalogueFailure>());
      expect(h.fingerprintWrites, 0);
      expect(h.journal.value, isNull);
      expect((await h.fixture.books.getAll()).toNullable(), isEmpty);
    },
  );

  test(
    'failed cover download nulls the reference and counts the skip',
    () async {
      h.coverResults['source.png'] = const PublishedCoverDownload(
        bytes: null,
        sourceByteCount: 10,
      );

      final summary = await _success(h);

      expect(summary.coversSkipped, 1);
      final rows = (await h.fixture.books.getAll()).toNullable()!;
      expect(rows.single.coverUrl, isNull);
    },
  );

  test('covers disabled makes no requests and nulls same-site refs', () async {
    final summary = await _success(h, covers: false);

    expect(h.coverCalls, 0);
    expect(summary.coversSkipped, 1);
    expect(summary.downloadCovers, isFalse);
    expect(
      (await h.fixture.books.getAll()).toNullable()!.single.coverUrl,
      isNull,
    );
  });

  test('cancellation before writing imports nothing', () async {
    final result = await h.useCase.call(h.siteUrl, isCancelled: () => true);

    expect(result.toNullable(), isA<RestoreFromPublishedSiteCancelled>());
    expect(h.catalogueCalls, 0);
    expect(h.fingerprintWrites, 0);
    expect((await h.fixture.books.getAll()).toNullable(), isEmpty);
  });

  test(
    'a mutation during downloads is refused inside the import transaction',
    () async {
      h.onCover = (_) async {
        await h.fixture.books.insert(const CatalogueItem(title: 'Concurrent'));
      };

      final result = await h.useCase.call(h.siteUrl);

      expect(result.swap().toNullable(), isA<ValidationFailure>());
      expect(h.fingerprintWrites, 0);
      expect(h.journal.value, isNull);
      final rows = (await h.fixture.books.getAll()).toNullable()!;
      expect(rows.single.title, 'Concurrent');
    },
  );

  test(
    'fingerprint failure stays pending and identity-only recovery finishes',
    () async {
      h.fingerprintFailure = const StorageFailure('synthetic write failure');

      final summary = await _success(h);

      expect(summary.identityPending, isTrue);
      expect(h.journal.value?.fingerprint, h.fingerprint);
      expect((await h.fixture.books.getAll()).toNullable(), hasLength(1));
      h.fingerprintFailure = null;
      final recovered = await h.recover.call();
      expect(
        recovered.toNullable(),
        PublishedIdentityRecoveryOutcome.recovered,
      );
      expect(h.writtenFingerprint, h.fingerprint);
      expect(h.journal.value, isNull);
    },
  );

  test('duplicate ISBN input is added once and reported once', () async {
    h.catalogue = PublishedCatalogue(
      declaredSchemaVersion: 1,
      items: const [
        PublishedCatalogueItem(
          sourceIndex: 0,
          title: 'First',
          kind: PublishedItemKind.book,
          isbn: 'same',
        ),
        PublishedCatalogueItem(
          sourceIndex: 1,
          title: 'Duplicate',
          kind: PublishedItemKind.book,
          isbn: 'same',
        ),
      ],
      periodicals: const [],
    );

    final summary = await _success(h);

    expect(summary.itemsAdded, 1);
    expect(summary.import.booksSkipped, 1);
    expect((await h.fixture.books.getAll()).toNullable(), hasLength(1));
  });

  test('journal write failure prevents the database write', () async {
    h.journal.writeFailure = const StorageFailure('journal failed');

    final result = await h.useCase.call(h.siteUrl);

    expect(result.swap().toNullable(), isA<StorageFailure>());
    expect(h.fingerprintWrites, 0);
    expect((await h.fixture.books.getAll()).toNullable(), isEmpty);
  });

  test(
    'raw cover bytes are passed to the budget without exposing source bytes',
    () async {
      h.coverResults['source.png'] = PublishedCoverDownload(
        bytes: Uint8List.fromList([9, 8, 7]),
        sourceByteCount: 1000,
      );

      final summary = await _success(h);

      expect(summary.coversRestored, 1);
      expect(h.fixture.images.single.readAsBytesSync(), [9, 8, 7]);
    },
  );
}
