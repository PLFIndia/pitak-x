import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_availability_merge.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/infrastructure/published_availability_codec.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

/// The availability contract between the writer and BOTH readers (ADR 0019
/// Decision 4 and its S7 clarification; ADR 0015 decision 5).
///
/// 1. Writer → native reader: the bytes a publish writes decode back into
///    exactly the tags the writer meant, bound by the same `keySet`.
/// 2. Web ↔ native parity: the bundled web viewer (run by a Node harness over
///    the REAL inline script) and the native reader agree on every tag, the
///    summary counts, the "updated" time and the Available-now list, for
///    every shared fixture in `test/fixtures/published_availability/` and
///    for generated hostile files.
void main() {
  const fixtures = 'test/fixtures/published_availability';
  const harness =
      'test/features/publish/published_availability_parity_harness.js';

  /// What the native viewer shows for [catalogueBytes] plus [availability]
  /// (null = the site answers 404), in the harness's JSON shape.
  Map<String, Object?> nativeView(
    List<int> catalogueBytes,
    List<int>? availability,
  ) {
    final catalogue = const PublishedCatalogueCodec()
        .decode(catalogueBytes)
        .toNullable()!;
    // A refused file is "treated as missing", exactly like a 404.
    final file = availability == null
        ? null
        : const PublishedAvailabilityCodec().decode(availability).toNullable();
    final merged = PublishedAvailabilityMerge.apply(
      catalogue: catalogue,
      file: file,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    final payload =
        jsonDecode(utf8.decode(catalogueBytes)) as Map<String, dynamic>;
    final rows = payload['books'] as List;
    final bySourceIndex = {
      for (final item in merged.catalogue.items) item.sourceIndex: item,
    };
    final view = PublishedQueryEngine.apply(
      merged.catalogue,
      const PublishedCatalogueQuery(availableNow: true),
    );
    return {
      'tags': [
        for (var i = 0; i < rows.length; i++)
          {
            'title': (rows[i] as Map)['title'],
            'tag': switch (bySourceIndex[i]?.availability) {
              PublishedAvailability.available => 'available',
              PublishedAvailability.out => 'out',
              null => null,
            },
          },
      ],
      'summary': {
        'available': merged.availableCount,
        'tagged': merged.taggedCount,
        'asOf': merged.updatedAt,
      },
      'availableNow': [
        for (final entry in view.entries)
          ...switch (entry) {
            PublishedItemEntry(:final item) => [item.title],
            PublishedSeriesGroup(:final issues) => [
              for (final issue in issues) issue.title,
            ],
          },
      ],
    };
  }

  Future<Object?> webView(
    String cataloguePath,
    String? availabilityPath,
  ) async {
    final result = await Process.run('node', [
      harness,
      cataloguePath,
      availabilityPath ?? '-',
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'viewer harness failed:\n${result.stdout}\n${result.stderr}',
    );
    return jsonDecode(result.stdout as String);
  }

  group('web ↔ native parity on the shared fixtures', () {
    final availabilityFiles = [
      for (final entity in Directory(fixtures).listSync())
        if (entity is File &&
            entity.path.endsWith('.json') &&
            !entity.path.split('/').last.startsWith('catalogue'))
          entity.path,
    ]..sort();

    test('the fixture set is the one documented here', () {
      // A new fixture must be added deliberately (and is then compared).
      expect(availabilityFiles.map((p) => p.split('/').last), [
        'asof_in_future.json',
        'asof_missing.json',
        'asof_not_a_number.json',
        'asof_too_early.json',
        'bad_key.json',
        'empty_out.json',
        'malformed_key_set.json',
        'missing_key_set.json',
        'newer_schema.json',
        'no_schema_version.json',
        'not_json.json',
        'other_key_set.json',
        'out_has_number.json',
        'out_not_a_list.json',
        'root_is_list.json',
        'valid.json',
      ]);
    });

    for (final catalogue in [
      'catalogue.json',
      'catalogue_no_key_set.json',
      'catalogue_bad_key_set.json',
    ]) {
      final cataloguePath = '$fixtures/$catalogue';
      for (final availabilityPath in [null, ...availabilityFiles]) {
        final name = availabilityPath?.split('/').last ?? '404';
        test('$catalogue + $name', () async {
          final native = nativeView(
            File(cataloguePath).readAsBytesSync(),
            availabilityPath == null
                ? null
                : File(availabilityPath).readAsBytesSync(),
          );
          expect(await webView(cataloguePath, availabilityPath), native);
        });
      }
    }

    test('the expected tags of the main fixture are pinned', () {
      final native = nativeView(
        File('$fixtures/catalogue.json').readAsBytesSync(),
        File('$fixtures/valid.json').readAsBytesSync(),
      );
      expect(
        [for (final row in native['tags']! as List) (row as Map)['tag']],
        [
          'out', // keyed, listed: the file overrides the inline "available"
          'available', // keyed, not listed: overrides the inline "out"
          'available', // keyed, no inline tag
          'out', // no key: the inline tag
          'available', // malformed key: the inline tag
          'out', // keyed issue, listed
          null, // Other: never tagged
          null, // unknown kind: never tagged
          null, // nothing to go on
          null, // upper-case key is not a key; no inline tag
          'out', // legacy row without kind counts as a book
        ],
      );
      expect(native['summary'], {
        'available': 3,
        'tagged': 7,
        'asOf': 1761984300000,
      });
    });
  });

  group('web ↔ native parity on generated hostile files', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pitak-avail-'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<void> compare(List<int> bytes) async {
      final file = File('${temp.path}/availability.json')
        ..writeAsBytesSync(bytes);
      const cataloguePath = '$fixtures/catalogue.json';
      final native = nativeView(File(cataloguePath).readAsBytesSync(), bytes);
      expect(await webView(cataloguePath, file.path), native);
    }

    List<int> padded(int totalBytes) {
      const head =
          '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",'
          '"asOf":1761984300000,"out":["aaaaaaaaaaaaaaa2"],"pad":"';
      const tail = '"}';
      final pad = totalBytes - head.length - tail.length;
      return utf8.encode('$head${'x' * pad}$tail');
    }

    test('exactly 1 MiB is read; one byte more is ignored', () async {
      await compare(padded(PublishedAvailabilityFile.maxBytes));
      await compare(padded(PublishedAvailabilityFile.maxBytes + 1));
      final atCap = nativeView(
        File('$fixtures/catalogue.json').readAsBytesSync(),
        padded(PublishedAvailabilityFile.maxBytes),
      );
      expect((atCap['summary']! as Map)['asOf'], 1761984300000);
    });

    test('nesting at the cap is read; one level more is ignored', () async {
      String nested(int depth) =>
          '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68","out":[],"x":'
          '${'[' * (depth - 1)}${']' * (depth - 1)}}';
      await compare(
        utf8.encode(nested(PublishedAvailabilityFile.maxJsonDepth)),
      );
      await compare(
        utf8.encode(nested(PublishedAvailabilityFile.maxJsonDepth + 1)),
      );
    });

    test('invalid UTF-8 is ignored by both', () async {
      await compare([
        ...utf8.encode(
          '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",'
          '"out":[],"x":"',
        ),
        0xff,
        ...utf8.encode('"}'),
      ]);
    });

    test('a whole number written as 1.0 is a whole number in both', () async {
      await compare(
        utf8.encode(
          '{"schemaVersion":1.0,"keySet":"5e0c1d2b3a497f68",'
          '"asOf":1761984300000.0,"out":["aaaaaaaaaaaaaaa2"]}',
        ),
      );
    });
  });

  group('writer → reader (the bytes a publish writes)', () {
    final salt = ascii.encode('salt-1234567890');
    final items = [
      const CatalogueItem(id: 1, title: 'Lent book'),
      const CatalogueItem(id: 2, title: 'Shelf book'),
      const CatalogueItem(id: 3, title: 'Board game', details: OtherItemOf()),
    ];
    final keys = PublishItemKeys.keysWithSalt(
      salt: salt,
      itemIds: [for (final item in items) item.id],
    ).toNullable()!;

    List<int> booksJson() => encodeBooksJsonBytes(
      PublishExport(
        exportedAt: 1761900000000,
        keySet: keys.id,
        books: [
          for (final item in items)
            redactForPublish(
              item,
              resolveCoverUrl: (_) => null,
              resolveKey: (i) => keys.keysById[i.id],
            ),
        ],
      ),
    );

    List<int> availabilityJson(PublishKeySet keySet) =>
        encodeAvailabilityJsonBytes(
          AvailabilityDocument(
            AvailabilitySnapshot.fromIds(
              ids: const [1],
              keySet: keySet,
              asOfMillis: 1761984359999,
            )!,
          ),
        );

    test('a combined publish binds: the reader shows what the writer '
        'meant', () {
      final view = nativeView(booksJson(), availabilityJson(keys));
      expect(
        [for (final row in view['tags']! as List) (row as Map)['tag']],
        ['out', 'available', null],
      );
      // asOf was floored to the minute by the writer and is shown as such.
      expect((view['summary']! as Map)['asOf'], 1761984300000);
    });

    test('a file written with another salt is never applied (J10)', () {
      final otherSalt = PublishItemKeys.keysWithSalt(
        salt: ascii.encode('a previous install'),
        itemIds: const [1, 2, 3],
      ).toNullable()!;
      final view = nativeView(booksJson(), availabilityJson(otherSalt));
      // No inline tags were written (vault locked), so nothing is shown —
      // never "everything Available".
      expect(
        [for (final row in view['tags']! as List) (row as Map)['tag']],
        [null, null, null],
      );
    });

    test('the writer and the reader agree on the limits', () {
      expect(
        AvailabilityDocument.readerMaxBytes,
        PublishedAvailabilityFile.maxBytes,
      );
      expect(
        AvailabilityDocument.readerMaxKeys,
        PublishedAvailabilityFile.maxKeys,
      );
      expect(
        AvailabilityDocument.schemaVersion,
        PublishedAvailabilityFile.schemaVersion,
      );
      expect(PublishedAvailabilityFile.isKey(keys.id), isTrue);
      expect(PublishItemKeys.isValidKey('5e0c1d2b3a497f68'), isTrue);
    });
  });
}
