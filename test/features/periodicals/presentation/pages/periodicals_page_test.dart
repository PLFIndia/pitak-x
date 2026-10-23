/// Widget tests for the Magazines list page (plan S15): the rows with their
/// subscription badges (every `SubscriptionStatus`), the empty and error
/// states, the FAB destination and the row push. Driven over the shared
/// in-memory fakes; the clock and the minute tick are pinned so the derived
/// badges are deterministic (N04).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_detail_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodicals_page.dart';

import '../../../../support/a11y.dart';
import '../../application/periodical_fakes.dart';

void main() {
  // A fixed "now" for the subscription windows (D5): active = +60 days,
  // expiring = +10 days, lapsed = -1 day.
  final t0 = DateTime(2026, 10, 23, 12).millisecondsSinceEpoch;
  const day = 24 * 60 * 60 * 1000;

  late FakePeriodicals periodicals;
  late FakeItems items;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        clockProvider.overrideWithValue(() => t0),
        // The controller's build arms the real 60 s timer — pin it so the
        // tests can settle (the settled S14 override).
        nowTickProvider.overrideWith((ref) => 0),
      ],
      child: const MaterialApp(home: PeriodicalsPage()),
    );
  }

  testWidgets('renders every series in (title, id) order with its issue '
      'summary and subscription badge', (tester) async {
    periodicals
      ..seed(const Periodical(title: 'Chandamama')) // untracked
      ..seed(Periodical(title: 'Outlook', subscriptionEnd: t0 + 10 * day))
      ..seed(Periodical(title: 'Sportstar', subscriptionEnd: t0 - day));
    final active = periodicals.seed(
      Periodical(title: 'Frontline', subscriptionEnd: t0 + 60 * day),
    );
    // Two issues for Frontline, the newest dated 2026-09-01.
    final uid = active.periodicalUid!;
    periodicals.issues[uid] = [
      CatalogueItem(
        id: 1,
        title: 'Frontline — No 1',
        details: _issue(uid, DateTime(2026, 8).millisecondsSinceEpoch),
      ),
      CatalogueItem(
        id: 2,
        title: 'Frontline — No 2',
        details: _issue(uid, DateTime(2026, 9).millisecondsSinceEpoch),
      ),
    ];

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Chandamama'), findsOneWidget);
    expect(find.text('Frontline'), findsOneWidget);
    expect(find.text('Outlook'), findsOneWidget);
    expect(find.text('Sportstar'), findsOneWidget);

    // Badge per status (D5); the untracked title shows none.
    expect(find.text('Subscribed'), findsOneWidget);
    expect(find.text('Expiring soon'), findsOneWidget);
    expect(find.text('Lapsed'), findsOneWidget);

    // Summary line: count + newest issue month.
    expect(find.text('2 issues · latest 2026-09'), findsOneWidget);
    expect(find.text('0 issues'), findsNWidgets(3));
  });

  testWidgets('shows the empty state when there are no titles', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No magazine titles yet'), findsOneWidget);
    // Empty-state button AND the FAB (its tooltip) both offer the add action.
    expect(find.text('New magazine title'), findsOneWidget);
    expect(find.byTooltip('New magazine title'), findsOneWidget);
  });

  testWidgets('a repository failure shows a safe error, not raw text', (
    tester,
  ) async {
    periodicals.listAllFailure = const StorageFailure('boom');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't load your magazine titles"),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('the FAB pushes the (empty) series form (S16)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final form = tester.widget<PeriodicalFormPage>(
      find.byType(PeriodicalFormPage),
    );
    expect(form.periodical, isNull);
    expect(find.text('New magazine title'), findsOneWidget);
  });

  testWidgets('tapping a row opens the series detail page observing that '
      'series (N03)', (tester) async {
    final frontline = periodicals.seed(const Periodical(title: 'Frontline'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frontline'));
    await tester.pumpAndSettle();

    final page = tester.widget<PeriodicalDetailPage>(
      find.byType(PeriodicalDetailPage),
    );
    expect(page.periodicalId, frontline.id);
    expect(find.text('Magazine'), findsOneWidget);
    // The detail body shows the series' own header and issues section.
    expect(find.text('Issues'), findsOneWidget);
    expect(find.text('No issues catalogued yet.'), findsOneWidget);
  });

  testWidgets('a removed title is dimmed and badged but still listed (D8)', (
    tester,
  ) async {
    periodicals.seed(const Periodical(title: 'Old Weekly', removed: true));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Old Weekly'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    periodicals.seed(
      Periodical(title: 'Frontline', subscriptionEnd: t0 + 10 * day),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}

/// Issue details carrying only what the fake's summary needs: the uid link
/// and a date.
IssueOf _issue(String uid, int date) =>
    IssueOf(periodicalUid: uid, issueDate: date);
