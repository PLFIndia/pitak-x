/// Widget tests for the series detail page (plan S15): the hero header, the
/// subscription card with its derived badge (D5), the paged issue list
/// (newest-first, U2), the hidden actions on a removed title (D8), and the
/// overflow's typed delete refusal. Driven over the shared in-memory fakes
/// with the real delete use case (its refusal IS the feature under test);
/// the clock and the minute tick are pinned (N04).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/delete_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/placeholder_page.dart';

import '../../../../support/a11y.dart';
import '../../application/periodical_fakes.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 12).millisecondsSinceEpoch;
  const day = 24 * 60 * 60 * 1000;

  late FakePeriodicals periodicals;
  late FakeItems items;
  late List<String?> releasedCovers;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    releasedCovers = [];
  });

  /// The app with [home] under it; the detail page is pushed by tapping the
  /// 'open' button so a successful delete has somewhere to pop back to.
  Widget app({required int periodicalId}) {
    return ProviderScope(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        clockProvider.overrideWithValue(() => t0),
        nowTickProvider.overrideWith((ref) => 0),
        // The REAL use case over the fake store — the typed refusal (D8) is
        // its contract. The janitor hook is a recorder, not the real janitor
        // (which would touch the file system).
        deletePeriodicalUseCaseProvider.overrideWith(
          (ref) async => DeletePeriodicalUseCase(
            periodicals: periodicals,
            releaseCover: (coverRef) async => releasedCovers.add(coverRef),
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PeriodicalDetailPage(periodicalId: periodicalId),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The default 800×600 test surface cuts the lazy issue sliver off after
  /// the tall header; tests that assert on the rows get a surface tall
  /// enough to build them all.
  void useBigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Seeds a tracked monthly series and [count] issues dated a month apart,
  /// oldest first (so the newest-first order the page must show is
  /// observable).
  Periodical seedSeriesWithIssues(int count) {
    final periodical = periodicals.seed(
      Periodical(
        title: 'Frontline',
        publisher: 'The Hindu Group',
        issn: '0970-1710',
        frequency: PeriodicalFrequency.monthly,
        subscriptionStart: t0 - 200 * day,
        subscriptionEnd: t0 + 60 * day,
      ),
    );
    final uid = periodical.periodicalUid!;
    for (var i = 1; i <= count; i++) {
      final issue = items.seed(
        CatalogueItem(
          title: 'Frontline — No $i',
          details: IssueOf(
            periodicalUid: uid,
            issueNumber: i,
            issueDate: t0 - (count - i) * 30 * day,
          ),
        ),
      );
      periodicals.issues.putIfAbsent(uid, () => []).add(issue);
    }
    return periodical;
  }

  testWidgets('renders the header, the subscription card with its derived '
      'badge, and the issues newest-first', (tester) async {
    useBigSurface(tester);
    final periodical = seedSeriesWithIssues(3);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    // Header.
    expect(find.text('Frontline'), findsOneWidget);
    expect(find.text('The Hindu Group'), findsOneWidget);

    // Subscription card: status derived from the pinned clock (D5), the
    // cadence label, and the tracked dates.
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Subscribed'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.textContaining('Ends'), findsOneWidget);

    // Issues: newest first (No 3 above No 2 above No 1), each row badged.
    final y3 = tester.getTopLeft(find.text('Frontline — No 3')).dy;
    final y2 = tester.getTopLeft(find.text('Frontline — No 2')).dy;
    final y1 = tester.getTopLeft(find.text('Frontline — No 1')).dy;
    expect(y3, lessThan(y2));
    expect(y2, lessThan(y1));
    expect(find.text('Issue'), findsNWidgets(3));
  });

  testWidgets('a bound volume row is badged "Bound volume" (D4)', (
    tester,
  ) async {
    useBigSurface(tester);
    final periodical = seedSeriesWithIssues(0);
    final uid = periodical.periodicalUid!;
    items.seed(
      CatalogueItem(
        title: 'Frontline — 2024 bound',
        details: IssueOf(
          periodicalUid: uid,
          issueDate: t0 - 300 * day,
          boundUntil: t0 - 100 * day,
        ),
      ),
    );

    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    expect(find.text('Frontline — 2024 bound'), findsOneWidget);
    expect(find.text('Bound volume'), findsOneWidget);
  });

  testWidgets('"+ Add issue" pushes the add-issue placeholder carrying this '
      'series (S16 swaps the destination)', (tester) async {
    final periodical = seedSeriesWithIssues(0);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    await tester.tap(find.text('Add issue'));
    await tester.pumpAndSettle();

    final placeholder = tester.widget<PlaceholderPage>(
      find.byType(PlaceholderPage),
    );
    expect(placeholder.pageName, 'Add magazine issue');
    expect(placeholder.periodical?.id, periodical.id);
  });

  testWidgets('Edit pushes the series-form placeholder carrying the observed '
      'row (S16 swaps the destination)', (tester) async {
    final periodical = seedSeriesWithIssues(0);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    final placeholder = tester.widget<PlaceholderPage>(
      find.byType(PlaceholderPage),
    );
    expect(placeholder.pageName, 'Edit magazine title');
    expect(placeholder.periodical?.id, periodical.id);
  });

  testWidgets('a removed title hides Edit and "+ Add issue" (visible but '
      'actionless, D8)', (tester) async {
    final periodical = periodicals.seed(
      const Periodical(title: 'Old Weekly', removed: true),
    );
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    expect(find.text('Old Weekly'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.text('Add issue'), findsNothing);
    // The hard delete stays reachable.
    expect(find.byTooltip('More actions'), findsOneWidget);
  });

  testWidgets('deleting a title that still has issues shows the typed '
      'refusal and keeps the page (D8)', (tester) async {
    final periodical = seedSeriesWithIssues(2);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The use case's refusal, worded for the user — not a blanked list.
    expect(find.textContaining('still has 2 issues'), findsOneWidget);
    expect(find.text('Magazine'), findsOneWidget);
    // Nothing was deleted or released.
    expect(periodicals.rows[periodical.id], isNotNull);
    expect(releasedCovers, isEmpty);
  });

  testWidgets('deleting a title with no issues pops back to the caller', (
    tester,
  ) async {
    final periodical = seedSeriesWithIssues(0);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(periodicals.rows[periodical.id], isNull);
  });

  testWidgets('an unknown id shows the safe "gone" state', (tester) async {
    await tester.pumpWidget(app(periodicalId: 999));
    await openDetail(tester);

    expect(
      find.text('This magazine title is no longer in your library.'),
      findsOneWidget,
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    final periodical = seedSeriesWithIssues(2);
    await tester.pumpWidget(app(periodicalId: periodical.id));
    await openDetail(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
