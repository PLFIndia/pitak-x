import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/import_export/application/export_library_use_case.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pdf_library_renderer.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_exporter.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'bundle_test_fixture.dart';

const s11UnicodePeriodicalUid = 'पत्रिका-१';
const s11LegacyPeriodicalUid = 'legacy-weekly';
const s11RemoteSeriesCover = 'https://covers.openlibrary.org/b/id/legacy-L.jpg';
const s11LocalSeriesCoverReference = 'covers/s11-local.jpg';
const s11LocalSeriesCoverEntry = 'cover_s11-local.jpg';
const s11LocalSeriesCoverBytes = <int>[11, 22, 33, 44];

const _bookUid = 's11-book';
const _otherUid = 's11-other';
const _numberedIssueUid = 's11-numbered';
const _boundVolumeUid = 's11-bound';
const _boundStart = 1767225600000; // 2026-01-01 at 00:00 UTC.
const _boundEnd = 1769904000000; // 2026-02-01 at 00:00 UTC.

/// Seeds the shared S11 attribute matrix through the real Drift repositories.
Future<void> seedS11InterchangeSource(BundleTestFixture fixture) async {
  for (final series in const [
    Periodical(
      periodicalUid: s11UnicodePeriodicalUid,
      title: 'साप्ताहिक',
      publisher: 'प्रकाशक',
      language: 'Hindi',
      coverUrl: s11LocalSeriesCoverReference,
      addedDate: 10,
      removed: true,
      removedAt: 11,
    ),
    Periodical(
      periodicalUid: s11LegacyPeriodicalUid,
      title: 'Legacy Weekly',
      publisher: 'Legacy Publisher',
      language: 'English',
      coverUrl: s11RemoteSeriesCover,
      addedDate: 20,
    ),
  ]) {
    (await fixture.periodicals.insert(
      series,
    )).getOrElse((failure) => fail('series seed failed: $failure'));
  }

  for (final item in const [
    CatalogueItem(
      itemUid: _bookUid,
      title: 'Plain book',
      author: 'A. Writer',
      addedDate: 30,
    ),
    CatalogueItem(
      itemUid: _otherUid,
      title: 'Carrom board',
      notes: 'Family set',
      addedDate: 40,
      details: OtherItemOf(),
    ),
    CatalogueItem(
      itemUid: _numberedIssueUid,
      title: 'साप्ताहिक — Vol 2 No 7',
      publisher: 'प्रकाशक',
      language: 'Hindi',
      addedDate: 50,
      removed: true,
      removedAt: 51,
      details: IssueOf(
        periodicalUid: s11UnicodePeriodicalUid,
        volume: 2,
        issueNumber: 7,
        label: 'विशेष',
      ),
    ),
    CatalogueItem(
      itemUid: _boundVolumeUid,
      title: 'Legacy Weekly — Jan 2026 – Feb 2026',
      publisher: 'Legacy Publisher',
      language: 'English',
      publishedYear: 2026,
      addedDate: 60,
      details: IssueOf(
        periodicalUid: s11LegacyPeriodicalUid,
        issueDate: _boundStart,
        boundUntil: _boundEnd,
        label: 'Winter bind',
      ),
    ),
  ]) {
    (await fixture.books.insert(
      item,
    )).getOrElse((failure) => fail('item seed failed: $failure'));
  }

  fixture
      .cover(s11LocalSeriesCoverReference)
      .writeAsBytesSync(s11LocalSeriesCoverBytes);
}

/// Exports the matrix with the production v4 JSON writer and real repositories.
Future<String> exportS11InterchangeJson(BundleTestFixture source) async {
  final result = await ExportLibraryUseCase(
    jsonEncoder: const PitakaJsonExporter(),
    pdfRenderer: const PdfLibraryRenderer(),
    bookRepo: source.books,
    wishlistRepo: source.wishlist,
    periodicalRepo: source.periodicals,
  )(scope: ExportScope.libraryOnly, format: ExportFormat.json, now: 999);
  final export = result.getOrElse((failure) => fail('export failed: $failure'));
  return utf8.decode(export.bytes);
}

/// Emulates a legacy v4 artifact whose series and issue spell the same UID with
/// different surrounding whitespace. The real exporter remains the source of
/// every other field, so this changes only the ingress-canonicalization input.
String padS11LegacyIdentities(String json) {
  final document = jsonDecode(json) as Map<String, dynamic>;
  final periodicals = document['periodicals']! as List<dynamic>;
  periodicals.whereType<Map<String, dynamic>>().singleWhere(
    (row) => row['periodicalUid'] == s11LegacyPeriodicalUid,
  )['periodicalUid'] = ' \t$s11LegacyPeriodicalUid\r\n';
  final books = document['books']! as List<dynamic>;
  final bound = books.whereType<Map<String, dynamic>>().singleWhere(
    (row) => row['bookUid'] == _boundVolumeUid,
  );
  final issue = bound['issue']! as Map<String, dynamic>;
  issue['periodicalUid'] = '\n$s11LegacyPeriodicalUid \t';
  return jsonEncode(document);
}

/// Imports plain JSON through the production use case and real Drift stores.
Future<ImportSummary> importS11Json(
  BundleTestFixture target,
  String json,
) async {
  final result = await ImportLibraryUseCase(
    jsonParser: const PitakaJsonImporter(),
    bookRepo: target.books,
    wishlistRepo: target.wishlist,
    periodicalRepo: target.periodicals,
  ).importText(json);
  return result.getOrElse((failure) => fail('JSON import failed: $failure'));
}

/// Checks final rows and soft links, including which row owns each cover.
Future<void> expectS11InterchangeState(
  BundleTestFixture fixture, {
  required bool localCoverPreserved,
}) async {
  final summaries = (await fixture.periodicals.listAll()).getOrElse(
    (failure) => fail('series read failed: $failure'),
  );
  expect(summaries, hasLength(2));
  final seriesByUid = {
    for (final summary in summaries) summary.periodical.periodicalUid!: summary,
  };
  expect(
    seriesByUid.keys,
    containsAll([s11UnicodePeriodicalUid, s11LegacyPeriodicalUid]),
  );

  final unicodeSummary = seriesByUid[s11UnicodePeriodicalUid]!;
  final unicodeSeries = unicodeSummary.periodical;
  expect(unicodeSummary.issueCount, 1);
  expect(unicodeSeries.removed, isTrue);
  expect(unicodeSeries.removedAt, 11);
  if (localCoverPreserved) {
    final reference = unicodeSeries.coverUrl;
    expect(reference, startsWith('covers/'));
    final cover = fixture.cover(reference!);
    expect(cover.existsSync(), isTrue);
    expect(await cover.readAsBytes(), s11LocalSeriesCoverBytes);
    expect(fixture.images, hasLength(1));
  } else {
    // Plain JSON deliberately carries no local image bytes or dangling refs.
    expect(unicodeSeries.coverUrl, isNull);
    expect(fixture.images, isEmpty);
  }

  final legacySummary = seriesByUid[s11LegacyPeriodicalUid]!;
  expect(legacySummary.issueCount, 1);
  expect(legacySummary.periodical.removed, isFalse);
  expect(legacySummary.periodical.coverUrl, s11RemoteSeriesCover);

  final items = (await fixture.books.getAll()).getOrElse(
    (failure) => fail('item read failed: $failure'),
  );
  expect(items, hasLength(4));
  final itemsByUid = {for (final item in items) item.itemUid!: item};
  expect(
    itemsByUid.keys,
    containsAll([_bookUid, _otherUid, _numberedIssueUid, _boundVolumeUid]),
  );

  final book = itemsByUid[_bookUid]!;
  expect(book.kind, ItemKind.book);
  expect(book.details, isNull);
  expect(book.author, 'A. Writer');

  final other = itemsByUid[_otherUid]!;
  expect(other.kind, ItemKind.other);
  expect(other.details, isA<OtherItemOf>());
  expect(other.notes, 'Family set');

  final numbered = itemsByUid[_numberedIssueUid]!;
  expect(numbered.kind, ItemKind.magazineIssue);
  expect(numbered.removed, isTrue);
  expect(numbered.removedAt, 51);
  expect(numbered.title, 'साप्ताहिक — Vol 2 No 7');
  expect(numbered.publisher, 'प्रकाशक');
  expect(numbered.coverUrl, isNull, reason: 'the series owns the cover');
  final numberedIssue = numbered.issue!;
  expect(numberedIssue.periodicalUid, s11UnicodePeriodicalUid);
  expect(numberedIssue.volume, 2);
  expect(numberedIssue.issueNumber, 7);
  expect(numberedIssue.boundUntil, isNull);
  expect(numberedIssue.label, 'विशेष');

  final bound = itemsByUid[_boundVolumeUid]!;
  expect(bound.kind, ItemKind.magazineIssue);
  expect(bound.removed, isFalse);
  expect(bound.title, 'Legacy Weekly — Jan 2026 – Feb 2026');
  expect(bound.publisher, 'Legacy Publisher');
  expect(bound.publishedYear, 2026);
  expect(bound.coverUrl, isNull, reason: 'the series owns the remote cover');
  final boundIssue = bound.issue!;
  expect(boundIssue.periodicalUid, s11LegacyPeriodicalUid);
  expect(boundIssue.isBound, isTrue);
  expect(boundIssue.issueDate, _boundStart);
  expect(boundIssue.boundUntil, _boundEnd);
  expect(boundIssue.label, 'Winter bind');
}
