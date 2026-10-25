/// On-device integration smoke test for catalogue item kinds (ADR 0013 /
/// 0014), run by hand before a release — the sibling of
/// `vault_smoke_test.dart` (same commands, same rules; see its header and
/// `smoke_support.dart`).
///
/// Besides the original kind/vault journey, this exercises the S11 magazine
/// remediation against real SQLite, FFI and app-private files:
///
///   launch → series with a local cover and a subscription ending today →
///   two issues (series-cover fallback and own-cover-wins) → same-UID JSON
///   re-import preserving the cover and reprojecting both issues → Other →
///   lend an issue → backup → targeted clear → full restore → soft-remove
///   the series and prove its barcode cannot open an add-issue flow.
///
/// The destructive interval happens only AFTER a complete backup. The full
/// restore also brings back any rows and loans left by a sibling journey, so
/// file order in `flutter test integration_test` remains safe.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/form_rows.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/main.dart' as app;

import 'smoke_support.dart';

/// The Magazines list row titled [title], scoped so sibling runs cannot match.
Finder _seriesRow(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

/// The "N issues" summary of the Magazines row titled [title].
Finder issueSummaryOf(String title, [int count = 1]) => find.descendant(
  of: _seriesRow(title),
  matching: find.textContaining(count == 1 ? '1 issue' : '$count issues'),
);

String _coverLeaf(String coverRef) {
  final leaf = CoverPaths.leafOf(coverRef);
  expect(leaf, isNotNull, reason: 'not a local cover reference: $coverRef');
  return leaf!;
}

Future<Periodical> _storedSeries(WidgetTester tester, String title) async {
  final repository = await appContainer(
    tester,
  ).read(periodicalRepositoryProvider.future);
  final result = await repository.listAll();
  final summaries = result.toNullable();
  expect(summaries, isNotNull, reason: 'could not read series: $result');
  final matches = summaries!
      .where((summary) => summary.periodical.title == title)
      .toList();
  expect(matches, hasLength(1), reason: 'expected one series named $title');
  return matches.single.periodical;
}

Future<List<CatalogueItem>> _storedIssues(
  WidgetTester tester,
  String seriesUid,
) async {
  final repository = await appContainer(
    tester,
  ).read(periodicalRepositoryProvider.future);
  final result = await repository.issuesOf(seriesUid);
  final issues = result.toNullable();
  expect(issues, isNotNull, reason: 'could not read issues: $result');
  return issues!;
}

Future<CatalogueItem> _storedItem(WidgetTester tester, String title) async {
  final repository = await appContainer(
    tester,
  ).read(catalogueItemRepositoryProvider.future);
  final result = await repository.getAll();
  final items = result.toNullable();
  expect(items, isNotNull, reason: 'could not read catalogue: $result');
  final matches = items!.where((item) => item.title == title).toList();
  expect(matches, hasLength(1), reason: 'expected one item named $title');
  return matches.single;
}

CatalogueItem _issueNumber(Iterable<CatalogueItem> issues, int number) =>
    issues.singleWhere((issue) => issue.issue?.issueNumber == number);

Future<void> _expectDetailCover(WidgetTester tester, String expectedRef) async {
  final coverFinder = find.byType(ItemCover);
  await reveal(tester, coverFinder);
  expect(tester.widget<ItemCover>(coverFinder).coverUrl, expectedRef);
  // ItemCover only builds an Image when the local file really exists.
  expect(
    find.descendant(of: coverFinder, matching: find.byType(Image)),
    findsOneWidget,
  );
}

Future<String?> _addIssue(
  WidgetTester tester, {
  required int volume,
  required int number,
  required String expectedPreview,
  bool withOwnCover = false,
}) async {
  await tapFilledButton(tester, 'Add issue');
  await enterInField(tester, 'Volume', '$volume');
  await enterInField(tester, 'Issue number', '$number');
  await reveal(tester, find.text(expectedPreview));
  expect(find.text(expectedPreview), findsOneWidget);
  final coverRef = withOwnCover ? await attachSmokeCover(tester) : null;
  await tapFilledButton(tester, 'Add issue');
  return coverRef;
}

Future<int> _selectSubscriptionEndToday(WidgetTester tester) async {
  final row = find.ancestor(
    of: find.textContaining('Subscription end:'),
    matching: find.byType(DatePickerRow),
  );
  await reveal(tester, row);
  await tester.tap(find.descendant(of: row, matching: find.text('Change')));
  await tester.pumpAndSettle();

  // Use the real device day, not a fake clock or a changed device setting.
  // Calling the picker's public callback avoids locale-specific month/day
  // navigation while still exercising the real form conversion and save.
  final selected = DateTime.now();
  tester
      .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
      .onDateChanged(selected);
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  return CalendarDate.fromPickerDate(selected).epochMillis;
}

Future<void> _openSettingsDataEntry(WidgetTester tester, String label) async {
  await openDrawerEntry(tester, 'Settings');
  await tester.tap(find.text('Data'));
  await tester.pumpAndSettle();
  await tapSmokeTextVisible(tester, label);
}

Future<void> _clearForRestore(
  WidgetTester tester, {
  required int loanItemId,
  required List<String> coverRefs,
}) async {
  final container = appContainer(tester);
  final session = container.read(vaultSessionControllerProvider).valueOrNull;
  if (session is! VaultUnlocked) {
    fail('The vault must be unlocked before the restore clear: $session');
  }
  final loans = session.data.loans
      .where((loan) => loan.itemId == loanItemId && loan.returnedDate == null)
      .toList();
  expect(loans, hasLength(1), reason: 'expected one active loan to clear');
  final deleted = await container
      .read(vaultSessionControllerProvider.notifier)
      .deleteLoan(loans.single.id);
  expect(deleted.isRight(), isTrue, reason: 'could not clear loan: $deleted');

  // The complete backup was already created. Clear only now, then restore
  // every row (including any sibling journey's rows) from that archive.
  final items = await container.read(catalogueItemRepositoryProvider.future);
  final clearedItems = await items.replaceAll(const []);
  expect(clearedItems.isRight(), isTrue, reason: 'could not clear catalogue');
  final periodicals = await container.read(periodicalRepositoryProvider.future);
  final clearedSeries = await periodicals.replaceAll(const []);
  expect(clearedSeries.isRight(), isTrue, reason: 'could not clear series');

  // Deleting only the references is insufficient: when an archive has no
  // covers, restore deliberately carries live files forward. Remove these two
  // files so their return can only have come from the archive.
  final covers = await container.read(coverStoreProvider.future);
  for (final coverRef in coverRefs) {
    await covers.deleteFile(coverRef);
  }
  final remainingLeaves = covers.listLeaves();
  for (final coverRef in coverRefs) {
    expect(remainingLeaves, isNot(contains(_coverLeaf(coverRef))));
  }

  final clearedSession = container
      .read(vaultSessionControllerProvider)
      .valueOrNull;
  if (clearedSession is! VaultUnlocked) {
    fail('The vault locked unexpectedly during the clear: $clearedSession');
  }
  expect(
    clearedSession.data.loans.where((loan) => loan.itemId == loanItemId),
    isEmpty,
  );
  expect((await items.getAll()).toNullable(), isEmpty);
  expect((await periodicals.listAll()).toNullable(), isEmpty);
}

Future<void> _expectRemovedSeriesScan(
  WidgetTester tester,
  String seriesUid,
  String barcode,
) async {
  final useCase = await appContainer(
    tester,
  ).read(routeScannedBarcodeUseCaseProvider.future);
  final context = tester.element(find.byType(LibraryPage));
  final navigation = routeScannedBarcode(context, useCase, barcode);
  await tester.pumpAndSettle();

  expect(find.byType(PeriodicalDetailPage), findsOneWidget);
  expect(find.byType(AddIssuePage), findsNothing);
  expect(find.text('Removed'), findsOneWidget);
  expect(find.text('Add issue'), findsNothing);
  await goBack(tester);
  await navigation;
  expect(await _storedIssues(tester, seriesUid), hasLength(2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'kinds smoke: magazine title, issue, other item, lend, backup, restore',
    (tester) async {
      await app.main();
      await waitForLibrary(tester);

      final stamp = smokeStamp();
      final magazineIdentity = magazineIdentityForSmoke(stamp);
      final seriesTitle = 'Smoke Monthly $stamp';
      final originalIssue1Title = '$seriesTitle — Vol 1 No 1';
      final originalIssue2Title = '$seriesTitle — Vol 1 No 2';
      final otherTitle = 'Smoke Board Game $stamp';
      final borrowerName = 'Smoke Reader $stamp';

      // --- 1. Series: local cover, ISSN and subscription ending today ------
      await tester.tap(find.byTooltip('Add to library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New magazine title'));
      await tester.pumpAndSettle();
      await enterInField(tester, 'Title *', seriesTitle);
      await enterInField(tester, 'ISSN', magazineIdentity.issn);
      final seriesCoverRef = await attachSmokeCover(tester);
      final trackSubscription = find.widgetWithText(
        SwitchListTile,
        'Track subscription',
      );
      await reveal(tester, trackSubscription);
      await tester.tap(trackSubscription);
      await tester.pumpAndSettle();
      final expectedSubscriptionEnd = await _selectSubscriptionEndToday(tester);
      await tapFilledButton(tester, 'Add magazine title');
      // A series is not a Library row.
      expect(find.text(seriesTitle), findsNothing);
      final createdSeries = await _storedSeries(tester, seriesTitle);
      expect(createdSeries.coverUrl, seriesCoverRef);
      expect(createdSeries.issn, magazineIdentity.issn);
      expect(createdSeries.subscriptionStart, isNotNull);
      expect(createdSeries.subscriptionEnd, expectedSubscriptionEnd);
      final seriesUid = createdSeries.periodicalUid!;
      final covers = await appContainer(tester).read(coverStoreProvider.future);
      expect(covers.listLeaves(), contains(_coverLeaf(seriesCoverRef)));

      // --- 2. Two issues: one inherits, one has its own cover ---------------
      await openDrawerEntry(tester, 'Magazines');
      await reveal(tester, _seriesRow(seriesTitle));
      expect(
        find.descendant(
          of: _seriesRow(seriesTitle),
          matching: find.text('Expiring soon'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(seriesTitle));
      await tester.pumpAndSettle();
      expect(
        await _addIssue(
          tester,
          volume: 1,
          number: 1,
          expectedPreview: originalIssue1Title,
        ),
        isNull,
      );
      await expectSmokeTextVisible(tester, originalIssue1Title);
      final issueCoverRef = await _addIssue(
        tester,
        volume: 1,
        number: 2,
        expectedPreview: originalIssue2Title,
        withOwnCover: true,
      );
      expect(issueCoverRef, isNotNull);
      await expectSmokeTextVisible(tester, originalIssue2Title);
      await goBack(tester);
      await reveal(tester, _seriesRow(seriesTitle));
      expect(issueSummaryOf(seriesTitle, 2), findsOneWidget);
      await goBack(tester);
      await expectLibraryTextVisible(tester, originalIssue1Title);
      await expectLibraryTextVisible(tester, originalIssue2Title);

      // --- 3. Add an other item --------------------------------------------
      await tester.tap(find.byTooltip('Add to library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add other item'));
      await tester.pumpAndSettle();
      await enterInField(tester, 'Title *', otherTitle);
      await enterInField(tester, 'Description', 'A board game for rainy days');
      await tapFilledButton(tester, 'Add item');
      await expectLibraryTextVisible(tester, otherTitle);

      // --- 4. Vault, detail cover rules, and lending ------------------------
      await openVaultUnlocked(tester);
      await goBack(tester);

      await tapLibraryTextVisible(tester, originalIssue1Title);
      await _expectDetailCover(tester, seriesCoverRef);
      await lendToNewBorrower(tester, borrowerName);
      await goBack(tester);

      await tapLibraryTextVisible(tester, originalIssue2Title);
      await _expectDetailCover(tester, issueCoverRef!);
      await goBack(tester);

      // --- 5. Same-UID JSON: preserve cover, reproject BOTH issues ---------
      final renamedSeriesTitle = 'Smoke Monthly Reimported $stamp';
      final renamedPublisher = 'Smoke Publisher $stamp';
      final issue1Title = '$renamedSeriesTitle — Vol 1 No 1';
      final issue2Title = '$renamedSeriesTitle — Vol 1 No 2';
      final json = jsonEncode({
        'schemaVersion': 4,
        'exportedAt': 0,
        'periodicals': [
          {
            'periodicalUid': seriesUid,
            'title': renamedSeriesTitle,
            'issn': createdSeries.issn,
            'publisher': renamedPublisher,
            'subscriptionStart': createdSeries.subscriptionStart,
            'subscriptionEnd': createdSeries.subscriptionEnd,
            // A local cover must beat this incoming remote reference.
            'coverUrl': 'https://covers.openlibrary.org/b/id/1-L.jpg',
          },
        ],
        // Deliberately empty: issues absent from the file must still follow
        // the same-UID series update.
        'books': <Object>[],
        'wishlist': <Object>[],
      });
      await _openSettingsDataEntry(tester, 'Import');
      await enterInField(tester, 'Paste export text', json);
      await tapFilledButton(tester, 'Import text');
      await expectSmokeTextVisible(tester, 'Import complete');
      await expectSmokeTextVisible(
        tester,
        'Magazine titles updated (same identity): 1',
      );
      await goBack(tester);
      await goBack(tester);

      final importedSeries = await _storedSeries(tester, renamedSeriesTitle);
      expect(importedSeries.periodicalUid, seriesUid);
      expect(importedSeries.issn, magazineIdentity.issn);
      expect(importedSeries.subscriptionStart, createdSeries.subscriptionStart);
      expect(importedSeries.subscriptionEnd, expectedSubscriptionEnd);
      expect(importedSeries.coverUrl, seriesCoverRef);
      final importedIssues = await _storedIssues(tester, seriesUid);
      expect(importedIssues, hasLength(2));
      expect(
        importedIssues.map((issue) => issue.issue?.issueNumber),
        unorderedEquals([1, 2]),
      );
      for (final issue in importedIssues) {
        final number = issue.issue!.issueNumber!;
        expect(issue.title, '$renamedSeriesTitle — Vol 1 No $number');
        expect(issue.publisher, renamedPublisher);
        expect(issue.issue!.periodicalUid, seriesUid);
      }
      expect(_issueNumber(importedIssues, 1).coverUrl, isNull);
      expect(_issueNumber(importedIssues, 2).coverUrl, issueCoverRef);
      await expectLibraryTextVisible(tester, issue1Title);
      await expectLibraryTextVisible(tester, issue2Title);

      // --- 6. Backup, targeted clear, then FULL restore ---------------------
      final loanedIssue = await _storedItem(tester, issue1Title);
      final backup = await createSmokeBackup(tester);
      await _clearForRestore(
        tester,
        loanItemId: loanedIssue.id,
        coverRefs: [seriesCoverRef, issueCoverRef],
      );
      await restoreSmokeBackup(tester, backup);

      final restoredSeries = await _storedSeries(tester, renamedSeriesTitle);
      expect(restoredSeries.periodicalUid, seriesUid);
      expect(restoredSeries.coverUrl, seriesCoverRef);
      expect(restoredSeries.subscriptionEnd, expectedSubscriptionEnd);
      final restoredIssues = await _storedIssues(tester, seriesUid);
      expect(restoredIssues, hasLength(2));
      final restoredIssue1 = _issueNumber(restoredIssues, 1);
      final restoredIssue2 = _issueNumber(restoredIssues, 2);
      expect(restoredIssue1.kind, ItemKind.magazineIssue);
      expect(restoredIssue2.kind, ItemKind.magazineIssue);
      expect(restoredIssue1.issue!.periodicalUid, seriesUid);
      expect(restoredIssue2.issue!.periodicalUid, seriesUid);
      expect(restoredIssue1.coverUrl, isNull);
      expect(restoredIssue2.coverUrl, issueCoverRef);
      expect((await _storedItem(tester, otherTitle)).kind, ItemKind.other);
      final restoredCovers = await appContainer(
        tester,
      ).read(coverStoreProvider.future);
      expect(
        restoredCovers.listLeaves(),
        containsAll([_coverLeaf(seriesCoverRef), _coverLeaf(issueCoverRef)]),
      );

      // --- 7. Restored UI: kinds, covers and the actual loan link -----------
      await openDrawerEntry(tester, 'Magazines');
      await reveal(tester, _seriesRow(renamedSeriesTitle));
      expect(find.text(renamedSeriesTitle), findsOneWidget);
      expect(issueSummaryOf(renamedSeriesTitle, 2), findsOneWidget);
      await waitForMagazineRowId(tester, renamedSeriesTitle, restoredSeries.id);
      await tester.tap(find.text(renamedSeriesTitle));
      await tester.pumpAndSettle();
      await tapSmokeTextVisible(tester, issue1Title);
      await expectSmokeTextVisible(tester, 'Magazine issue');
      await expectSmokeTextVisible(tester, 'Open series');
      await _expectDetailCover(tester, seriesCoverRef);
      await goBack(tester);
      await goBack(tester);
      await goBack(tester);

      await expectLibraryTextVisible(tester, otherTitle);
      await tapLibraryTextVisible(tester, issue2Title);
      await _expectDetailCover(tester, issueCoverRef);
      await goBack(tester);

      await openVaultUnlocked(tester);
      await expectSmokeTextVisible(tester, borrowerName);
      await tapSmokeTextVisible(tester, borrowerName);
      // The borrower alone would survive even with no loan. The profile must
      // resolve the restored loan to the restored issue's current title.
      await expectSmokeTextVisible(tester, issue1Title);
      await goBack(tester);
      await goBack(tester);

      // --- 8. Removed series: scan cannot create a new issue ----------------
      await openDrawerEntry(tester, 'Magazines');
      await reveal(tester, _seriesRow(renamedSeriesTitle));
      await tester.tap(find.text(renamedSeriesTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from library'));
      await tester.pumpAndSettle();
      await tapFilledButton(tester, 'Remove');
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Add issue'), findsNothing);
      await goBack(tester);
      await goBack(tester);
      await _expectRemovedSeriesScan(
        tester,
        seriesUid,
        magazineIdentity.barcode,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
