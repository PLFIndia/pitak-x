/// Widget tests for the add/edit-issue form (plan S16): the series picker
/// gate, the cadence prefill, the "Bound volume" switch swapping the date
/// fields (D4), the live generated-title preview (D3), and a save that lands
/// as a PROJECTED item (title/publisher/language composed from the series).
/// Driven over the shared fakes with the REAL issue use cases — the
/// projection and the duplicate refusal are the feature under test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';

import '../../../../support/a11y.dart';
import '../../application/periodical_fakes.dart';

void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;
  late Periodical frontline;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    frontline = periodicals.seed(
      const Periodical(
        title: 'Frontline',
        publisher: 'The Hindu Group',
        language: 'English',
        location: 'Reading room',
        frequency: PeriodicalFrequency.monthly,
      ),
    );
  });

  /// Hosts the form ABOVE a home route so the pop after a successful save is
  /// observable.
  Widget app({Periodical? preselected, CatalogueItem? edit}) {
    return ProviderScope(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        nowTickProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AddIssuePage(periodical: preselected, issue: edit),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  /// The forms are taller than the default 800x600 test surface, and a
  /// sliver-backed ListView only builds children near the viewport — give
  /// every test a surface tall enough to build the whole form.
  void useBigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openForm(
    WidgetTester tester, {
    Periodical? preselected,
    CatalogueItem? edit,
  }) async {
    useBigSurface(tester);
    await tester.pumpWidget(app(preselected: preselected, edit: edit));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Picks [title] in the series dropdown.
  Future<void> pickSeries(WidgetTester tester, String title) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    // The menu overlay duplicates the selected item's text; `.last` is the
    // one inside the open menu (the add-book language tests' idiom).
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  Future<void> scrollTap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await scrollTap(tester, find.byType(FilledButton));
  }

  testWidgets('saving without a series is refused inline', (tester) async {
    await openForm(tester);
    await save(tester);

    expect(find.text('Choose a magazine title first.'), findsOneWidget);
    expect(items.rows, isEmpty);
  });

  testWidgets('picking a series prefills the next number and date from the '
      'cadence (and the shelf location), empty fields only', (tester) async {
    // The latest issue: No 3, dated 2026-08-15 → next is No 4, 2026-09-15.
    final uid = frontline.periodicalUid!;
    final latest = items.seed(
      CatalogueItem(
        title: 'Frontline — No 3',
        pageCount: 64,
        details: IssueOf(
          periodicalUid: uid,
          issueNumber: 3,
          issueDate: DateTime(2026, 8, 15).millisecondsSinceEpoch,
        ),
      ),
    );
    periodicals.issues[uid] = [latest];

    await openForm(tester);
    await pickSeries(tester, 'Frontline');

    expect(
      find.widgetWithText(TextField, '4'),
      findsOneWidget,
      reason: 'next issue number suggested',
    );
    expect(
      find.textContaining('2026-09-15'),
      findsOneWidget,
      reason: 'one monthly step after the latest cover date',
    );
    expect(find.widgetWithText(TextField, 'Reading room'), findsOneWidget);
    expect(find.widgetWithText(TextField, '64'), findsOneWidget);
  });

  testWidgets('a single issue needs a number or a date (D6)', (tester) async {
    await openForm(tester, preselected: frontline);
    // No issues yet → no cadence prefill; fields stay empty.
    await save(tester);

    expect(find.text('Add an issue number or a cover date.'), findsOneWidget);
    expect(items.rows, isEmpty);
  });

  testWidgets('the "Bound volume" switch swaps the single date for the '
      'range pickers (D4)', (tester) async {
    await openForm(tester, preselected: frontline);
    expect(find.textContaining('Cover date'), findsOneWidget);
    expect(find.textContaining('Issues from'), findsNothing);

    await scrollTap(tester, find.byType(SwitchListTile));

    expect(find.textContaining('Cover date'), findsNothing);
    expect(find.textContaining('Issues from'), findsOneWidget);
    expect(find.textContaining('Issues to'), findsOneWidget);
  });

  testWidgets('a bound volume needs both dates, ordered', (tester) async {
    await openForm(tester, preselected: frontline);
    await scrollTap(tester, find.byType(SwitchListTile));
    await save(tester);

    expect(
      find.text('A bound volume needs both "from" and "to" dates.'),
      findsOneWidget,
    );
  });

  testWidgets('the title preview tracks the fields (D3)', (tester) async {
    await openForm(tester, preselected: frontline);
    expect(find.text('Frontline'), findsWidgets); // preview: bare title

    await tester.enterText(find.widgetWithText(TextField, 'Volume'), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Issue number'), '5');
    await tester.pump();

    expect(find.text('Frontline — Vol 2 No 5'), findsOneWidget);
  });

  testWidgets('add: the saved row is the PROJECTED item (title, publisher, '
      'language from the series) and the page pops', (tester) async {
    await openForm(tester, preselected: frontline);
    await tester.enterText(find.widgetWithText(TextField, 'Issue number'), '5');
    await tester.pump();

    // The preview shows what will be composed.
    expect(find.text('Frontline — No 5'), findsOneWidget);

    await save(tester);

    expect(find.text('open'), findsOneWidget, reason: 'popped after save');
    final stored = items.rows.values.single;
    expect(stored.title, 'Frontline — No 5');
    expect(stored.publisher, 'The Hindu Group');
    expect(stored.language, 'English');
    expect(stored.location, 'Reading room', reason: 'prefilled from series');
    expect(stored.kind.name, 'magazineIssue');
    expect(stored.issue?.issueNumber, 5);
  });

  testWidgets('a duplicate issue shows the typed refusal wording (D6)', (
    tester,
  ) async {
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        details: IssueOf(periodicalUid: uid, issueNumber: 5),
      ),
    );
    periodicals.issues[uid] = [existing];

    await openForm(tester, preselected: frontline);
    await tester.enterText(find.widgetWithText(TextField, 'Issue number'), '5');
    await save(tester);

    expect(
      find.text("'Frontline — No 5' is already in your library."),
      findsOneWidget,
    );
    expect(items.rows, hasLength(1), reason: 'the duplicate was refused');
  });

  testWidgets('edit: prefilled from the issue, saves on top of the current '
      'row (N03)', (tester) async {
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        copyCount: 2,
        notes: 'Signed copy',
        details: IssueOf(periodicalUid: uid, issueNumber: 5),
      ),
    );
    periodicals.issues[uid] = [existing];

    await openForm(tester, edit: existing);

    expect(find.text('Edit issue'), findsOneWidget);
    expect(find.widgetWithText(TextField, '5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Signed copy'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Re-read');
    await save(tester);

    expect(find.text('open'), findsOneWidget);
    final stored = items.rows[existing.id]!;
    expect(stored.notes, 'Re-read');
    expect(stored.issue?.issueNumber, 5, reason: 'untouched fields kept');
    expect(stored.kind.name, 'magazineIssue', reason: 'kind never changes');
    expect(stored.itemUid, existing.itemUid);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await openForm(tester, preselected: frontline);
    await expectMeetsA11yGuidelines(tester);
  });
}
