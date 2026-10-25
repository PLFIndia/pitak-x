import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/presentation/pages/published_catalogue_item_page.dart';

/// The read-only detail page (ADR 0015 V2, viewer plan S4): every decoded
/// public field is shown, and there is NO action that would mutate local data.
void main() {
  const site = 'https://kadugodi.github.io/pitak/';

  Future<void> pumpItem(
    WidgetTester tester,
    PublishedCatalogueItem item, {
    PublishedPeriodical? series,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PublishedCatalogueItemPage(
          item: item,
          siteUrl: site,
          series: series,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a full book shows every public field and no actions', (
    tester,
  ) async {
    const item = PublishedCatalogueItem(
      sourceIndex: 0,
      title: 'The Water Margin',
      kind: PublishedItemKind.book,
      titleTransliteration: 'Shuihu Zhuan',
      author: "Shi Nai'an",
      isbn: '9780140447194',
      publisher: 'Penguin',
      publishedYear: 1976,
      genre: 'Classics',
      language: 'English',
      ageGroup: AgeGroup.above15,
      availability: PublishedAvailability.available,
    );
    await pumpItem(tester, item);

    expect(find.text('Published item'), findsOneWidget);
    expect(find.text('The Water Margin'), findsOneWidget);
    expect(find.text('Shuihu Zhuan'), findsOneWidget);
    expect(find.text("Shi Nai'an"), findsOneWidget);
    expect(find.text('9780140447194'), findsOneWidget);
    expect(find.text('Penguin'), findsOneWidget);
    expect(find.text('1976'), findsOneWidget);
    expect(find.text('Classics'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // Badge + detail field both state the band.
    expect(find.text('Above 15'), findsNWidgets(2));
    expect(find.text('Available at publish time'), findsOneWidget);
    expect(find.textContaining('not a live loan check'), findsOneWidget);

    // No local-library action anywhere on a remote item.
    for (final forbidden in <String>[
      'Lend',
      'Edit',
      'Delete',
      'Import',
      'Remove',
      'Add to library',
    ]) {
      expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
    }
  });

  testWidgets('an Other row has no book-only fields and no availability', (
    tester,
  ) async {
    const item = PublishedCatalogueItem(
      sourceIndex: 0,
      title: 'Kannada Picture Dictionary',
      kind: PublishedItemKind.other,
      language: 'Kannada',
      ageGroup: AgeGroup.above6,
    );
    await pumpItem(tester, item);

    expect(find.text('Other'), findsWidgets);
    expect(find.text('Kannada'), findsOneWidget);
    expect(find.text('Above 6'), findsNWidgets(2));
    expect(find.text('ISBN'), findsNothing);
    expect(find.text('Author'), findsNothing);
    // No availability FIELD (the footer sentence is generic and stays).
    expect(find.text('Availability'), findsNothing);
    expect(find.textContaining('at publish time'), findsNothing);
  });

  testWidgets('an unknown kind shows common fields only, with no badge', (
    tester,
  ) async {
    const item = PublishedCatalogueItem(
      sourceIndex: 0,
      title: 'Future Thing',
      kind: PublishedItemKind.unknown,
      language: 'French',
    );
    await pumpItem(tester, item);

    expect(find.text('Future Thing'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    // No kind badge for a kind this build does not understand.
    expect(find.text('Other'), findsNothing);
    expect(find.text('Issue'), findsNothing);
  });

  testWidgets('a bound volume names both dates', (tester) async {
    final start = DateTime.utc(2025).millisecondsSinceEpoch;
    final end = DateTime.utc(2025, 12, 31).millisecondsSinceEpoch;
    final item = PublishedCatalogueItem(
      sourceIndex: 0,
      title: 'Chandamama — 2025 bound volume',
      kind: PublishedItemKind.magazineIssue,
      issue: PublishedIssueDetails(
        periodicalUid: 'chandamama',
        volume: 248,
        issueDate: start,
        boundUntil: end,
      ),
    );
    const series = PublishedPeriodical(
      periodicalUid: 'chandamama',
      title: 'Chandamama',
    );
    await pumpItem(tester, item, series: series);

    expect(find.text('Bound volume'), findsOneWidget);
    expect(find.text('Chandamama'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('248'), findsOneWidget);
    expect(find.text('First issue'), findsOneWidget);
    expect(find.text('2025-01-01'), findsOneWidget);
    expect(find.text('Last issue'), findsOneWidget);
    expect(find.text('2025-12-31'), findsOneWidget);
  });
}
