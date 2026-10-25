import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';
import 'package:pitaka/features/publish/domain/publish_redaction.dart';

/// The writer→reader contract (ADR 0015 decision 3, viewer plan S1).
///
/// The trusted writer models (`PublishExport`/`PublishItem`, built by
/// `redactForPublish`) and the hostile reader models are deliberately
/// SEPARATE classes. This suite is the pin that keeps them agreeing: bytes the
/// app itself would publish must decode back into the same public fields, and
/// nothing private may reappear on the reading side.
void main() {
  const codec = PublishedCatalogueCodec();

  List<int> bytesOf(PublishExport export) =>
      utf8.encode(jsonEncode(export.toJson()));

  PublishedCatalogue decode(PublishExport export) {
    final result = codec.decode(bytesOf(export));
    expect(
      result.isRight(),
      isTrue,
      reason: 'the writer output must be readable',
    );
    return result.toNullable()!;
  }

  test('the writer and reader agree on the schema version', () {
    expect(
      PublishedCatalogueCodec.schemaVersion,
      PublishExport.schemaVersionValue,
    );
  });

  test(
    'redacted books, issues and Others round-trip with public fields only',
    () {
      const book = CatalogueItem(
        title: 'The Water Margin',
        titleTransliteration: 'Shuihu Zhuan',
        author: "Shi Nai'an",
        isbn: '9780140447194',
        publisher: 'Penguin',
        publishedYear: 1976,
        genre: 'Classics',
        language: 'English',
        coverUrl: 'covers/water-margin.jpg',
        ageGroup: AgeGroup.above15,
        // Private fields that must never reach the payload:
        notes: 'SENTINEL-NOTES',
        location: 'SENTINEL-LOCATION',
        sourceDetail: 'SENTINEL-SOURCE',
        addedBy: 'SENTINEL-ADDED-BY',
        addedDate: 1700000000000,
        copyCount: 4,
      );
      const issue = CatalogueItem(
        title: 'Chandamama — Vol 249 No 10',
        details: IssueOf(
          periodicalUid: 'chandamama',
          volume: 249,
          issueNumber: 10,
          issueDate: 1791072000000,
          label: 'Dasara special',
        ),
        language: 'Telugu',
        notes: 'SENTINEL-ISSUE-NOTES',
      );
      const other = CatalogueItem(
        title: 'Picture Dictionary',
        author: 'SENTINEL-OTHER-AUTHOR',
        details: OtherItemOf(),
        language: 'Kannada',
        coverUrl: 'covers/dictionary.jpg',
        ageGroup: AgeGroup.above6,
      );
      const periodical = Periodical(
        title: 'Chandamama',
        periodicalUid: 'chandamama',
        publisher: 'Chandamama',
        language: 'Telugu',
        frequency: PeriodicalFrequency.monthly,
        issn: '0009-4838',
        notes: 'SENTINEL-PERIODICAL-NOTES',
      );

      final export = PublishExport(
        exportedAt: 1760000000000,
        books: [
          redactForPublish(
            book,
            resolveCoverUrl: (item) => item.coverUrl,
            availability: PublishItem.available,
          ),
          redactForPublish(
            issue,
            resolveCoverUrl: (item) => item.coverUrl,
            availability: PublishItem.out,
          ),
          redactForPublish(
            other,
            resolveCoverUrl: (item) => item.coverUrl,
            // ADR 0013 O2: an Other never carries availability.
            availability: PublishItem.available,
          ),
        ],
        periodicals: [
          redactPeriodicalForPublish(
            periodical,
            resolveCoverUrl: (item) => item.coverUrl,
          ),
        ],
      );

      // The writer bytes themselves must not contain a single private sentinel.
      final raw = utf8.decode(bytesOf(export));
      expect(raw, isNot(contains('SENTINEL')));
      expect(raw, isNot(contains('addedDate')));
      expect(raw, isNot(contains('copyCount')));

      final decoded = decode(export);
      expect(decoded.exportedAt, 1760000000000);
      expect(decoded.hasNewerSchema, isFalse);
      expect(decoded.warnings.hasPartialRead, isFalse);
      expect(decoded.items, hasLength(3));

      final readBook = decoded.items[0];
      expect(readBook.kind, PublishedItemKind.book);
      expect(readBook.title, 'The Water Margin');
      expect(readBook.titleTransliteration, 'Shuihu Zhuan');
      expect(readBook.author, "Shi Nai'an");
      expect(readBook.isbn, '9780140447194');
      expect(readBook.publisher, 'Penguin');
      expect(readBook.publishedYear, 1976);
      expect(readBook.genre, 'Classics');
      expect(readBook.language, 'English');
      expect(readBook.coverUrl, 'covers/water-margin.jpg');
      expect(readBook.ageGroup, AgeGroup.above15);
      expect(readBook.availability, PublishedAvailability.available);

      final readIssue = decoded.items[1];
      expect(readIssue.kind, PublishedItemKind.magazineIssue);
      expect(readIssue.availability, PublishedAvailability.out);
      expect(readIssue.issue!.periodicalUid, 'chandamama');
      expect(readIssue.issue!.volume, 249);
      expect(readIssue.issue!.issueNumber, 10);
      expect(readIssue.issue!.label, 'Dasara special');
      expect(readIssue.issue!.isBound, isFalse);

      final readOther = decoded.items[2];
      expect(readOther.kind, PublishedItemKind.other);
      expect(readOther.author, isNull);
      expect(readOther.availability, isNull);
      expect(readOther.language, 'Kannada');
      expect(readOther.ageGroup, AgeGroup.above6);

      final readPeriodical = decoded.periodicals.single;
      expect(readPeriodical.periodicalUid, 'chandamama');
      expect(readPeriodical.title, 'Chandamama');
      expect(readPeriodical.issn, '0009-4838');
      expect(readPeriodical.publisher, 'Chandamama');
      expect(readPeriodical.language, 'Telugu');
      expect(readPeriodical.frequency, PeriodicalFrequency.monthly);
      // The grouping key of the issue resolves to this series entry.
      expect(readPeriodical.periodicalUid, readIssue.issue!.periodicalUid);
    },
  );

  test('an empty export still writes a readable catalogue', () {
    final decoded = decode(const PublishExport(exportedAt: 0, books: []));
    expect(decoded.items, isEmpty);
    expect(decoded.periodicals, isEmpty);
    // `periodicals` is omitted when empty (additive-key rule) — the reader
    // treats that as "no series", never as corruption.
    expect(decoded.hasNoReadableItems, isFalse);
  });

  test('the writer never emits a legacy-missing-kind row', () {
    final export = PublishExport(
      exportedAt: 1,
      books: [
        redactForPublish(
          const CatalogueItem(title: 'Book'),
          resolveCoverUrl: (_) => null,
        ),
      ],
    );
    final json = export.toJson();
    final row = (json['books']! as List).single as Map<String, dynamic>;
    expect(row['kind'], ItemKind.book.token);
  });

  test('the bundled web viewer and the native engine agree on the SHARED '
      'fixture (grouping, order, titles)', () async {
    // The compatibility contract users actually see: the same payload rendered
    // by the published site and by the native viewer must show the same rows,
    // groups and order. The fixture is `test/fixtures/published_catalogue/
    // full_v1.json`; the Node harness executes the REAL inline viewer script.
    final fixture = File('test/fixtures/published_catalogue/full_v1.json');
    final decoded = codec.decode(fixture.readAsBytesSync()).toNullable()!;
    final native = PublishedQueryEngine.apply(
      decoded,
      const PublishedCatalogueQuery(),
    );
    final nativeRows = [
      for (final entry in native.entries)
        switch (entry) {
          PublishedItemEntry(:final item) => {'item': item.title},
          PublishedSeriesGroup(:final series, :final issues) => {
            'group': series.title,
            'issues': [for (final issue in issues) issue.title],
          },
        },
    ];

    final result = await Process.run('node', [
      'test/features/publish/published_catalogue_parity_harness.js',
      fixture.path,
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'viewer harness failed:\n${result.stdout}\n${result.stderr}',
    );
    expect(jsonDecode(result.stdout as String), nativeRows);
  });
}
