import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_projection.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';

import '../library/replacement_test_guard.dart';
import 'bundle_test_fixture.dart';

const _libraryId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final class _MatchingNamespace implements LibraryNamespace {
  const _MatchingNamespace();

  @override
  Future<Either<Failure, LibraryIdentity>> current() async =>
      right(const LibraryIdentity(id: _libraryId, name: 'Local'));

  @override
  Future<Either<Failure, Unit>> adopt({
    required String id,
    required String name,
  }) async => right(unit);
}

T _ok<T>(Either<Failure, T> result) =>
    result.getOrElse((failure) => fail('unexpected failure: $failure'));

String _incomingJson() => jsonEncode({
  'schemaVersion': 4,
  'libraryId': _libraryId,
  'periodicals': [
    {
      'periodicalUid': 'incoming-series',
      'title': 'Shared Title',
      'issn': '0027-9358',
      'addedDate': 2,
    },
  ],
  'books': [
    for (final number in [1, 2])
      {
        'bookUid': 'incoming-issue-$number',
        'title': 'Shared Title — No $number',
        'kind': 'magazine-issue',
        'addedDate': 2,
        'issue': {'periodicalUid': 'incoming-series', 'issueNumber': number},
      },
  ],
  'wishlist': <Object>[],
});

void main() {
  test(
    'S6: real Drift keeps different-ISSN series and both issue sets distinct',
    () async {
      final fixture = BundleTestFixture();
      addTearDown(fixture.dispose);
      const localSeries = Periodical(
        periodicalUid: 'local-series',
        title: 'Shared Title',
        issn: '0976-3279',
        addedDate: 1,
      );
      final storedLocal = _ok(await fixture.periodicals.insert(localSeries));
      for (final number in [1, 2]) {
        final row = CatalogueItem(
          itemUid: 'local-issue-$number',
          title: 'Unprojected',
          addedDate: 1,
          details: IssueOf(
            periodicalUid: storedLocal.periodicalUid!,
            issueNumber: number,
          ),
        );
        _ok(
          await fixture.books.insert(IssueProjection.apply(row, storedLocal)),
        );
      }
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: fixture.books,
        periodicalRepo: fixture.periodicals,
        namespace: const _MatchingNamespace(),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final outcome = _ok(await useCase.call(_incomingJson()));
      final result = (outcome as MergeMerged).result;

      expect(result.periodicalsAdded, 1);
      expect(result.added, 2);
      expect(result.periodicalConflicts, isEmpty);
      expect(result.conflicts, isEmpty);
      expect(result.possibleDuplicates, isEmpty);
      expect(
        result.hasReviewItems,
        isFalse,
        reason: 'an expected series add is not an unresolved conflict',
      );

      final storedSeries = [
        for (final summary in _ok(await fixture.periodicals.listAll()))
          summary.periodical,
      ];
      expect(storedSeries, hasLength(2));
      final seriesByUid = {
        for (final series in storedSeries) series.periodicalUid!: series,
      };
      expect(
        seriesByUid.keys,
        unorderedEquals(['local-series', 'incoming-series']),
      );
      expect(seriesByUid['local-series']?.issn, '0976-3279');
      expect(seriesByUid['incoming-series']?.issn, '0027-9358');
      expect(
        storedSeries.map((series) => series.title),
        everyElement('Shared Title'),
      );

      final storedItems = _ok(await fixture.books.getAllForInterchange());
      expect(storedItems, hasLength(4));
      final issueLinks = {
        for (final item in storedItems)
          item.itemUid!: item.issue?.periodicalUid,
      };
      expect(issueLinks, {
        'local-issue-1': 'local-series',
        'local-issue-2': 'local-series',
        'incoming-issue-1': 'incoming-series',
        'incoming-issue-2': 'incoming-series',
      });
    },
  );

  test('S11: real Drift merge keeps rich identities, bound and removed rows, '
      'and series covers', () async {
    final fixture = BundleTestFixture();
    addTearDown(fixture.dispose);
    _ok(
      await fixture.periodicals.insert(
        const Periodical(
          periodicalUid: 'removed-series',
          title: 'Archive',
          coverUrl: 'covers/archive.jpg',
          removed: true,
          removedAt: 99,
        ),
      ),
    );
    const unicodeUid = 'పత్రిక-१';
    const paddedUnicodeUid = '  పత్రిక-१  ';
    const remoteCover = 'https://covers.openlibrary.org/b/id/1-L.jpg';
    final firstDay = DateTime.utc(2026).millisecondsSinceEpoch;
    final lastDay = DateTime.utc(2026, 2).millisecondsSinceEpoch;
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: fixture.books,
      periodicalRepo: fixture.periodicals,
      namespace: const _MatchingNamespace(),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );
    final incoming = jsonEncode({
      'schemaVersion': 4,
      'libraryId': _libraryId,
      'periodicals': [
        {
          'periodicalUid': paddedUnicodeUid,
          'title': 'పత్రిక',
          'coverUrl': remoteCover,
        },
        {
          'periodicalUid': 'removed-series',
          'title': 'Archive',
          'coverUrl': 'covers/archive.jpg',
          'removed': true,
          'removedAt': 99,
        },
      ],
      'books': [
        {
          'bookUid': 'bound-volume',
          'title': 'Unprojected bound volume',
          'kind': 'magazine-issue',
          'issue': {
            'periodicalUid': paddedUnicodeUid,
            'issueDate': firstDay,
            'boundUntil': lastDay,
            'label': 'Annual bound volume',
          },
        },
        {
          'bookUid': 'removed-issue',
          'title': 'Unprojected removed issue',
          'kind': 'magazine-issue',
          'removed': true,
          'removedAt': 100,
          'issue': {'periodicalUid': ' removed-series ', 'issueNumber': 3},
        },
      ],
      'wishlist': <Object>[],
    });

    final outcome = _ok(await useCase.call(incoming));
    final result = (outcome as MergeMerged).result;
    expect(result.periodicalsAdded, 1);
    expect(result.periodicalsIdentical, 1);
    expect(result.added, 2);

    final storedSeries = [
      for (final summary in _ok(await fixture.periodicals.listAll()))
        summary.periodical,
    ];
    final seriesByUid = {
      for (final series in storedSeries) series.periodicalUid!: series,
    };
    expect(seriesByUid.keys, unorderedEquals([unicodeUid, 'removed-series']));
    expect(seriesByUid[unicodeUid]?.coverUrl, remoteCover);
    expect(seriesByUid['removed-series']?.coverUrl, 'covers/archive.jpg');
    expect(seriesByUid['removed-series']?.removed, isTrue);
    expect(seriesByUid['removed-series']?.removedAt, 99);

    final storedItems = _ok(await fixture.books.getAllForInterchange());
    expect(storedItems, hasLength(2));
    final itemsByUid = {for (final item in storedItems) item.itemUid!: item};
    final bound = itemsByUid['bound-volume']!;
    expect(bound.issue?.periodicalUid, unicodeUid);
    expect(bound.issue?.issueDate, firstDay);
    expect(bound.issue?.boundUntil, lastDay);
    expect(bound.issue?.isBound, isTrue);
    expect(bound.issue?.label, 'Annual bound volume');
    final removed = itemsByUid['removed-issue']!;
    expect(removed.issue?.periodicalUid, 'removed-series');
    expect(removed.issue?.issueNumber, 3);
    expect(removed.removed, isTrue);
    expect(removed.removedAt, 100);
    expect(
      await fixture.database.select(fixture.database.magazineIssues).get(),
      hasLength(2),
      reason: 'both kind-specific detail rows survived the real merge',
    );
  });
}
