import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/published_cover_fetcher.dart';
import 'package:pitaka/features/network/domain/published_cover_resolver.dart';
import 'package:pitaka/features/publish/application/restore/published_catalogue_mapper_result.dart';
import 'package:pitaka/features/publish/application/restore/published_cover_restorer.dart';

const _site = 'https://me.github.io/lib/';

PublishedCatalogueMapperResult _mapped() =>
    const PublishedCatalogueMapperResult(
      payload: ImportPayload(items: [CatalogueItem(title: 'Book')]),
      coverSources: {
        'restore-0.jpg': 'covers/a.png',
        'restore-1.jpg': 'covers/b.png',
      },
      droppedRows: 0,
      droppedFields: 0,
      issuesFiledAsBooks: 0,
      thirdPartyCoverLinks: 0,
    );

PublishedCoverDownload _bytes(int length, {int? raw}) => PublishedCoverDownload(
  bytes: Uint8List(length),
  sourceByteCount: raw ?? length,
);

void main() {
  test(
    'request budget skips the remainder and preserves progress counts',
    () async {
      var calls = 0;
      final restorer = PublishedCoverRestorer(
        requestLimit: 1,
        clock: () => 0,
        fetch: (request, {abortTrigger}) async {
          calls++;
          return _bytes(2);
        },
      );

      final result = await restorer.download(_site, _mapped(), enabled: true);

      expect(calls, 1);
      expect(result.covers, hasLength(1));
      expect(result.skippedByBudget, 1);
    },
  );

  test('raw-byte budget includes completed source downloads', () async {
    var calls = 0;
    final restorer = PublishedCoverRestorer(
      rawByteLimit: 8 * 1024 * 1024 + 6,
      clock: () => 0,
      fetch: (request, {abortTrigger}) async {
        calls++;
        return _bytes(2, raw: 6);
      },
    );

    final result = await restorer.download(_site, _mapped(), enabled: true);

    expect(calls, 1);
    expect(result.skippedByBudget, 1);
  });

  test('retained-byte budget drops oversized output but continues', () async {
    final restorer = PublishedCoverRestorer(
      retainedByteLimit: 3,
      clock: () => 0,
      fetch: (request, {abortTrigger}) async =>
          _bytes(request.uri.path.endsWith('a.png') ? 4 : 2),
    );

    final result = await restorer.download(_site, _mapped(), enabled: true);

    expect(result.covers.keys, ['restore-1.jpg']);
    expect(result.skippedByBudget, 1);
  });

  test('overall time budget stops later requests', () async {
    final times = [0, 0, 20];
    var calls = 0;
    final restorer = PublishedCoverRestorer(
      durationLimitMilliseconds: 10,
      clock: () => times.removeAt(0),
      fetch: (request, {abortTrigger}) async {
        calls++;
        return _bytes(1);
      },
    );

    final result = await restorer.download(_site, _mapped(), enabled: true);

    expect(calls, 1);
    expect(result.skippedByBudget, 1);
  });

  test(
    'cancellation after an in-flight request discards all retained bytes',
    () async {
      final restorer = PublishedCoverRestorer(
        clock: () => 0,
        fetch: (request, {abortTrigger}) async => _bytes(2),
      );

      final result = await restorer.download(
        _site,
        _mapped(),
        enabled: true,
        isCancelled: () => true,
      );

      expect(result.cancelled, isTrue);
      expect(result.covers, isEmpty);
    },
  );

  test(
    'fetch and decode are sequential, never four decoders at once',
    () async {
      var active = 0;
      var maximum = 0;
      final restorer = PublishedCoverRestorer(
        clock: () => 0,
        fetch: (request, {abortTrigger}) async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          return _bytes(1);
        },
      );

      await restorer.download(_site, _mapped(), enabled: true);

      expect(maximum, 1);
    },
  );

  test('disabled covers make no request', () async {
    var calls = 0;
    final restorer = PublishedCoverRestorer(
      clock: () => 0,
      fetch: (PublishedCoverRequest request, {abortTrigger}) async {
        calls++;
        return _bytes(1);
      },
    );

    final result = await restorer.download(_site, _mapped(), enabled: false);

    expect(calls, 0);
    expect(result.covers, isEmpty);
  });
}
