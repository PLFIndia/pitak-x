/// Widget tests for the magazine-title form (plan S16): add saves through
/// the REAL use case over the fakes (gate + ISSN pre-check included), the
/// ISSN is validated inline, the "Track subscription" switch drives the
/// window fields (D5), a duplicate ISSN shows its typed wording (D7), and
/// edit mode saves on top of the CURRENT row (N03).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/presentation/pages/periodical_form_page.dart';

import '../../../../support/a11y.dart';
import '../../application/periodical_fakes.dart';

void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
  });

  /// Hosts the form ABOVE a home route so the pop after a successful save is
  /// observable.
  Widget app({Periodical? edit, String? initialIssn}) {
    return ProviderScope(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        // Deterministic language list for the shared field.
        libraryLanguagesProvider.overrideWith((ref) async => ['English']),
        nowTickProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PeriodicalFormPage(
                    periodical: edit,
                    initialIssn: initialIssn,
                  ),
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

  Future<void> openForm(WidgetTester tester, {Periodical? edit}) async {
    useBigSurface(tester);
    await tester.pumpWidget(app(edit: edit));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Scrolls the lazy form until [finder] is built, then taps it.
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

  testWidgets('add: a valid new title is persisted and the page pops', (
    tester,
  ) async {
    await openForm(tester);
    expect(find.text('New magazine title'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Frontline',
    );
    await tester.enterText(find.widgetWithText(TextField, 'ISSN'), '1234-5679');
    // Frequency dropdown → Monthly (targeted by label: the shared language
    // field is another DropdownButtonFormField on the same page).
    await scrollTap(
      tester,
      find.widgetWithText(
        DropdownButtonFormField<PeriodicalFrequency?>,
        'Frequency',
      ),
    );
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();

    await save(tester);

    expect(find.text('open'), findsOneWidget, reason: 'popped after save');
    final stored = periodicals.rows.values.single;
    expect(stored.title, 'Frontline');
    expect(stored.issn, '1234-5679');
    expect(stored.frequency, PeriodicalFrequency.monthly);
    expect(stored.periodicalUid, isNotNull, reason: 'uid minted at insert');
  });

  testWidgets('an invalid ISSN is flagged inline and blocks the save', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Frontline',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ISSN'),
      '1234-5678', // bad check digit
    );
    await tester.pump();

    expect(find.text('That does not look like a valid ISSN.'), findsOneWidget);

    await save(tester);
    expect(periodicals.rows, isEmpty, reason: 'save blocked by inline error');
  });

  testWidgets('a duplicate ISSN surfaces the typed wording naming the '
      'existing title (D7)', (tester) async {
    periodicals.seed(const Periodical(title: 'Outlook', issn: '1234-5679'));
    await openForm(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'A Clone',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ISSN'),
      '1234567-9', // the SAME ISSN, un-normalised
    );

    await save(tester);

    expect(find.text("'Outlook' already has this ISSN."), findsOneWidget);
    expect(
      periodicals.rows,
      hasLength(1),
      reason: 'the duplicate was refused by the use case',
    );
  });

  testWidgets('"Track subscription" reveals the window fields and saves '
      'them (D5)', (tester) async {
    await openForm(tester);
    expect(find.textContaining('Subscription start'), findsNothing);

    await scrollTap(tester, find.byType(SwitchListTile));
    expect(find.textContaining('Subscription start'), findsOneWidget);
    expect(find.textContaining('Subscription end'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Frontline',
    );
    await save(tester);

    final stored = periodicals.rows.values.single;
    expect(stored.subscriptionStart, isNotNull);
    expect(stored.subscriptionEnd, isNotNull);
    expect(stored.isSubscriptionTracked, isTrue);
  });

  testWidgets('edit: prefilled, saves on top of the current row and keeps '
      'the stored uid (N03)', (tester) async {
    final existing = periodicals.seed(
      const Periodical(
        title: 'Frontline',
        publisher: 'The Hindu Group',
        issn: '1234-5679',
      ),
    );
    await openForm(tester, edit: existing);

    expect(find.text('Edit magazine title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Frontline'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'The Hindu Group'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Publisher'),
      'THG Publishing',
    );
    await save(tester);

    expect(find.text('open'), findsOneWidget, reason: 'popped after save');
    final stored = periodicals.rows[existing.id]!;
    expect(stored.publisher, 'THG Publishing');
    expect(stored.title, 'Frontline', reason: 'untouched fields kept');
    expect(stored.issn, '1234-5679');
    expect(
      stored.periodicalUid,
      existing.periodicalUid,
      reason: 'the stored uid always wins (issues link to it)',
    );
  });

  testWidgets('the scanned-ISSN route pre-fills the ISSN field (D11)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
          catalogueItemRepositoryProvider.overrideWith((ref) async => items),
          settingsRepositoryProvider.overrideWith(
            (ref) async => FakeSettings(),
          ),
          libraryLanguagesProvider.overrideWith((ref) async => ['English']),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(
          home: PeriodicalFormPage(initialIssn: '1234-5679'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '1234-5679'), findsOneWidget);
  });

  testWidgets('the cover field offers capture (plugin steps untestable)', (
    tester,
  ) async {
    await openForm(tester);
    expect(find.text('Add cover'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await openForm(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
