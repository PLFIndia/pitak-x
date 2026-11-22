/// Widget tests for the add/edit-issue form (plan S16): the series picker
/// gate, the cadence prefill, the "Bound volume" switch swapping the date
/// fields (D4), the live generated-title preview (D3), and a save that lands
/// as a PROJECTED item (title/publisher/language composed from the series).
/// Driven over the shared fakes with the REAL issue use cases — the
/// projection and the duplicate refusal are the feature under test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/presentation/pages/add_issue_page.dart';

import '../../../../support/a11y.dart';
import '../../../../support/async_value_gate.dart';
import '../../../../support/cover_capture_fakes.dart';
import '../../../../support/form_back_harness.dart';
import '../../application/periodical_fakes.dart';

/// The item store of these tests, with one place where a test can hold a
/// save open. With nothing set it behaves like [FakeItems].
class _HeldItems extends FakeItems {
  /// While set, `insert` waits for it before it stores anything.
  Completer<void>? holdInsert;

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    await holdInsert?.future;
    return super.insert(book);
  }
}

/// Lets a test choose the completion order of each series' prefill read.
class _GatedPeriodicals extends FakePeriodicals {
  final Map<String, List<AsyncValueGate<Either<Failure, List<CatalogueItem>>>>>
  prefillGates = {};

  @override
  Future<Either<Failure, List<CatalogueItem>>> issuesOf(String periodicalUid) {
    final queued = prefillGates[periodicalUid];
    if (queued != null && queued.isNotEmpty) return queued.removeAt(0).wait();
    return super.issuesOf(periodicalUid);
  }
}

void main() {
  late _GatedPeriodicals periodicals;
  late _HeldItems items;
  late Periodical frontline;

  setUp(() {
    periodicals = _GatedPeriodicals();
    items = _HeldItems();
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
  Widget app({
    Periodical? preselected,
    CatalogueItem? edit,
    CoverCaptureFakes? coverFakes,
  }) {
    return ProviderScope(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        coversDirProvider.overrideWith((ref) async => '.'),
        if (coverFakes != null)
          formCoverControllerProvider.overrideWith(() => coverFakes.controller),
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
    CoverCaptureFakes? coverFakes,
  }) async {
    useBigSurface(tester);
    await tester.pumpWidget(
      app(preselected: preselected, edit: edit, coverFakes: coverFakes),
    );
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

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;

  AsyncValueGate<Either<Failure, List<CatalogueItem>>> prefillGate() =>
      AsyncValueGate();

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
          issueDate: DateTime.utc(2026, 8, 15).millisecondsSinceEpoch,
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
      find.textContaining('15 September 2026'),
      findsOneWidget,
      reason: 'one monthly step after the latest cover date',
    );
    expect(find.widgetWithText(TextField, 'Reading room'), findsOneWidget);
    expect(find.widgetWithText(TextField, '64'), findsOneWidget);
  });

  testWidgets('A to B prefill: a late A response cannot populate B', (
    tester,
  ) async {
    final alpha = periodicals.seed(const Periodical(title: 'Alpha'));
    final outlook = periodicals.seed(
      const Periodical(title: 'Outlook', location: 'B shelf'),
    );
    final aUid = alpha.periodicalUid!;
    final bUid = outlook.periodicalUid!;
    final a = prefillGate();
    final b = prefillGate();
    periodicals.prefillGates
      ..[aUid] = [a]
      ..[bUid] = [b];

    await openForm(tester);
    await pickSeries(tester, 'Alpha');
    await a.entered;
    await pickSeries(tester, 'Outlook');
    await b.entered;

    b.succeed(right(const []));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'Shelf location'), 'B shelf');

    a.succeed(
      right([
        CatalogueItem(
          title: 'Alpha — No 3',
          pageCount: 64,
          copyCount: 4,
          details: IssueOf(periodicalUid: aUid, issueNumber: 3),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Issue number'), isEmpty);
    expect(fieldText(tester, 'Pages'), isEmpty);
    expect(fieldText(tester, 'Copies'), '1');
    expect(fieldText(tester, 'Shelf location'), 'B shelf');
  });

  testWidgets('ABA prefill: the first A response stays stale even when A is '
      'selected again', (tester) async {
    final outlook = periodicals.seed(const Periodical(title: 'Outlook'));
    final aUid = frontline.periodicalUid!;
    final bUid = outlook.periodicalUid!;
    final firstA = prefillGate();
    final b = prefillGate();
    final secondA = prefillGate();
    periodicals.prefillGates
      ..[aUid] = [firstA, secondA]
      ..[bUid] = [b];

    await openForm(tester);
    await pickSeries(tester, 'Frontline');
    await firstA.entered;
    await pickSeries(tester, 'Outlook');
    await b.entered;
    await pickSeries(tester, 'Frontline');
    await secondA.entered;

    b.succeed(right(const []));
    await tester.pumpAndSettle();
    secondA.succeed(right(const []));
    await tester.pumpAndSettle();
    firstA.succeed(
      right([
        CatalogueItem(
          title: 'Frontline — No 3',
          details: IssueOf(periodicalUid: aUid, issueNumber: 3),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Issue number'), isEmpty);
  });

  testWidgets('an explicitly entered copies value of 1 survives prefill', (
    tester,
  ) async {
    final uid = frontline.periodicalUid!;
    final gate = prefillGate();
    periodicals.prefillGates[uid] = [gate];
    await openForm(tester);
    await pickSeries(tester, 'Frontline');
    await gate.entered;

    // Clear and retype the same default so this is a real user edit, not a
    // no-op controller write that never emits onChanged.
    await tester.enterText(find.widgetWithText(TextField, 'Copies'), '');
    await tester.enterText(find.widgetWithText(TextField, 'Copies'), '1');
    await tester.pump();
    gate.succeed(
      right([
        CatalogueItem(
          title: 'Frontline — No 3',
          copyCount: 5,
          details: IssueOf(periodicalUid: uid, issueNumber: 3),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Copies'), '1');
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

  testWidgets('edit: Save stays gated through picker, crop, and cover '
      'storage, then saves the selected reference', (tester) async {
    final coverFakes = installCoverCaptureFakes();
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        coverUrl: 'covers/old.jpg',
        details: IssueOf(periodicalUid: uid, issueNumber: 5),
      ),
    );
    periodicals.issues[uid] = [existing];
    await openForm(tester, edit: existing, coverFakes: coverFakes);
    final saveButton = find.byType(FilledButton);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await tester.tap(find.text('Replace cover'));
    await tester.pump();
    await coverFakes.pickerGate.entered;
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    coverFakes.finishPicker();
    await tester.pump();
    await coverFakes.cropperGate.entered;
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    coverFakes.finishCropper();
    await tester.pump();
    await coverFakes.storeGate.entered;
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.tap(saveButton);
    await tester.pump();
    expect(items.updated, isEmpty);
    expect(find.byType(AddIssuePage), findsOneWidget);

    coverFakes.finishStore('covers/selected.jpg');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await save(tester);

    expect(items.rows[existing.id]!.coverUrl, 'covers/selected.jpg');
    expect(coverFakes.picker.calls, 1);
    expect(coverFakes.cropper.calls, 1);
    expect(coverFakes.controller.calls, 1);
  });

  testWidgets('edit: an untouched cover follows a background replacement and '
      'Save preserves the new reference', (tester) async {
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        coverUrl: 'covers/old.jpg',
        details: IssueOf(periodicalUid: uid, issueNumber: 5),
      ),
    );
    periodicals.issues[uid] = [existing];
    await openForm(tester, edit: existing);

    items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
    ProviderScope.containerOf(
      tester.element(find.byType(AddIssuePage)),
    ).read(catalogueChangesProvider.notifier).changed();
    await tester.pumpAndSettle();

    expect(
      tester.widget<ItemCover>(find.byType(ItemCover)).coverUrl,
      'covers/new.jpg',
      reason: 'an untouched form shows the current issue cover',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'Re-read');
    await save(tester);

    expect(items.rows[existing.id]!.coverUrl, 'covers/new.jpg');
  });

  testWidgets('edit: a deliberate cover removal is not overwritten by a '
      'background replacement', (tester) async {
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — No 5',
        coverUrl: 'covers/old.jpg',
        details: IssueOf(periodicalUid: uid, issueNumber: 5),
      ),
    );
    periodicals.issues[uid] = [existing];
    await openForm(tester, edit: existing);
    await tester.tap(find.text('Remove cover'));
    await tester.pump();

    items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
    ProviderScope.containerOf(
      tester.element(find.byType(AddIssuePage)),
    ).read(catalogueChangesProvider.notifier).changed();
    await tester.pumpAndSettle();

    expect(tester.widget<ItemCover>(find.byType(ItemCover)).coverUrl, isNull);
    await save(tester);
    expect(items.rows[existing.id]!.coverUrl, isNull);
  });

  testWidgets('issue date pick/display round-trip stays on one day', (
    tester,
  ) async {
    final uid = frontline.periodicalUid!;
    final existing = items.seed(
      CatalogueItem(
        title: 'Frontline — Jan 2026',
        details: IssueOf(
          periodicalUid: uid,
          issueDate: DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
        ),
      ),
    );
    periodicals.issues[uid] = [existing];
    await openForm(tester, edit: existing);

    expect(find.textContaining('Cover date: 15 January 2026'), findsOneWidget);

    await scrollTap(tester, find.text('Change'));
    await tester.tap(find.text('20').last);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cover date: 20 January 2026'), findsOneWidget);

    await save(tester);

    expect(
      items.rows[existing.id]!.issue!.issueDate,
      DateTime.utc(2026, 1, 20).millisecondsSinceEpoch,
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await openForm(tester, preselected: frontline);
    await expectMeetsA11yGuidelines(tester);
  });

  // Review finding P4-M1: Back must not throw away what was typed without
  // asking. "The form is gone" means the home page's button shows again.
  group('leaving the form (P4-M1)', () {
    final notes = find.widgetWithText(TextField, 'Notes');
    final page = find.byType(AddIssuePage);
    final home = find.text('open');

    void expectGoneWithoutQuestion() {
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsNothing);
      expect(home, findsOneWidget);
    }

    void expectAsked() {
      expect(findDiscardQuestion(), findsOneWidget);
      expect(page, findsOneWidget);
    }

    /// Picks day [day] of the month the date picker opens on.
    Future<void> pickDay(WidgetTester tester, Finder change, String day) async {
      await scrollTap(tester, change);
      await tester.tap(find.text(day).last);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    /// Gives Frontline a latest issue (No 3, three copies, 64 pages), so
    /// that the form has something to suggest: No 4, the next cover date,
    /// the shelf, the pages and the copies.
    CatalogueItem seedLatestIssue() {
      final uid = frontline.periodicalUid!;
      final latest = items.seed(
        CatalogueItem(
          title: 'Frontline — No 3',
          pageCount: 64,
          copyCount: 3,
          details: IssueOf(
            periodicalUid: uid,
            issueNumber: 3,
            issueDate: DateTime.utc(2026, 8, 15).millisecondsSinceEpoch,
          ),
        ),
      );
      periodicals.issues[uid] = [latest];
      return latest;
    }

    /// An issue to edit: a bound volume with a cover of its own.
    CatalogueItem seedBoundVolume() {
      final uid = frontline.periodicalUid!;
      final existing = items.seed(
        CatalogueItem(
          title: 'Frontline — Jan to Mar 2026',
          coverUrl: 'covers/old.jpg',
          notes: 'Signed copy',
          details: IssueOf(
            periodicalUid: uid,
            issueDate: DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
            boundUntil: DateTime.utc(2026, 3, 15).millisecondsSinceEpoch,
          ),
        ),
      );
      periodicals.issues[uid] = [existing];
      return existing;
    }

    testWidgets('untouched, Back: the form leaves at once', (tester) async {
      await openForm(tester);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('an edit form opened and left as it was: Back leaves', (
      tester,
    ) async {
      await openForm(tester, edit: seedBoundVolume());
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    group('what the app suggests by itself', () {
      testWidgets('opened for a title, the suggestion arrives (number, date, '
          'shelf, pages, copies), Back: leaves, nobody typed anything', (
        tester,
      ) async {
        seedLatestIssue();
        await openForm(tester, preselected: frontline);
        // The suggestion is on the screen.
        expect(fieldText(tester, 'Issue number'), '4');
        expect(fieldText(tester, 'Pages'), '64');
        expect(fieldText(tester, 'Copies'), '3');
        expect(fieldText(tester, 'Shelf location'), 'Reading room');
        expect(find.textContaining('15 September 2026'), findsOneWidget);

        await pressSystemBack(tester);

        expectGoneWithoutQuestion();
      });

      testWidgets('a suggested value changed by the user: the question; put '
          'back to the suggestion: Back leaves', (tester) async {
        seedLatestIssue();
        await openForm(tester, preselected: frontline);
        final number = find.widgetWithText(TextField, 'Issue number');
        await tester.enterText(number, '5');
        await pressSystemBack(tester);
        expectAsked();

        await tester.tap(findKeepEditing());
        await tester.pumpAndSettle();
        await tester.enterText(number, '4');
        await pressSystemBack(tester);
        expectGoneWithoutQuestion();
      });

      testWidgets('notes typed BEFORE the suggestion arrives stay a change: '
          'the question; with the notes emptied again Back leaves', (
        tester,
      ) async {
        final latest = seedLatestIssue();
        final gate = prefillGate();
        periodicals.prefillGates[frontline.periodicalUid!] = [gate];
        await openForm(tester, preselected: frontline);
        await gate.entered;
        expect(fieldText(tester, 'Issue number'), isEmpty);

        await tester.enterText(notes, 'typed first');
        gate.succeed(right([latest]));
        await tester.pumpAndSettle();
        expect(fieldText(tester, 'Issue number'), '4');

        await pressSystemBack(tester);
        expectAsked();

        await tester.tap(findKeepEditing());
        await tester.pumpAndSettle();
        await tester.enterText(notes, '');
        await pressSystemBack(tester);
        expectGoneWithoutQuestion();
      });

      testWidgets('a title picked in the form: the question, although the '
          'rest was suggested', (tester) async {
        seedLatestIssue();
        await openForm(tester);
        await pickSeries(tester, 'Frontline');
        expect(fieldText(tester, 'Issue number'), '4');
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('opened for a title, another title picked: the question', (
        tester,
      ) async {
        periodicals.seed(const Periodical(title: 'Outlook'));
        await openForm(tester, preselected: frontline);
        await pickSeries(tester, 'Outlook');
        await pressSystemBack(tester);

        expectAsked();
      });
    });

    testWidgets('notes typed, Back: the question. "Keep editing" keeps the '
        'form and the text; Back again and "Discard" leaves', (tester) async {
      await openForm(tester, preselected: frontline);
      await tester.enterText(notes, 'A note');
      await pressSystemBack(tester);
      expectAsked();
      expect(
        find.text('What you entered on this page has not been saved.'),
        findsOneWidget,
      );

      await tester.tap(findKeepEditing());
      await tester.pumpAndSettle();
      expect(findDiscardQuestion(), findsNothing);
      expect(find.widgetWithText(TextField, 'A note'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.tap(findDiscard());
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(items.inserted, isEmpty, reason: 'discarded, not saved');
    });

    testWidgets('the arrow of the app bar asks as well', (tester) async {
      await openForm(tester);
      await tester.enterText(notes, 'A note');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expectAsked();
    });

    testWidgets('typed and put back, Back: leaves', (tester) async {
      await openForm(tester);
      await tester.enterText(notes, 'A note');
      await tester.enterText(notes, '');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    // Every text field the form shows. A field that is added to the page
    // has to be added here (the count below fails otherwise), and then its
    // own test says whether the guard knows of it.
    const textFields = [
      'Volume',
      'Issue number',
      'Label (e.g. Annual number)',
      'Copies',
      'Pages',
      'Shelf location',
      'Notes',
    ];

    testWidgets('the form shows exactly the text fields these tests know', (
      tester,
    ) async {
      await openForm(tester);

      expect(find.byType(TextField), findsNWidgets(textFields.length));
      for (final label in textFields) {
        expect(find.widgetWithText(TextField, label), findsOneWidget);
      }
    });

    for (final label in textFields) {
      testWidgets('"$label" changed, Back: the question', (tester) async {
        await openForm(tester);
        // A digit: the fields for numbers take nothing else.
        await tester.enterText(find.widgetWithText(TextField, label), '7');
        await pressSystemBack(tester);

        expectAsked();
      });
    }

    group('a value that is not typed text', () {
      testWidgets('"Bound volume" switched on: the question', (tester) async {
        await openForm(tester);
        await scrollTap(tester, find.byType(SwitchListTile));
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('"Bound volume" switched on and off again: Back leaves', (
        tester,
      ) async {
        await openForm(tester);
        await scrollTap(tester, find.byType(SwitchListTile));
        await scrollTap(tester, find.byType(SwitchListTile));
        await pressSystemBack(tester);

        expectGoneWithoutQuestion();
      });

      testWidgets('a cover date picked: the question', (tester) async {
        await openForm(tester);
        await pickDay(tester, find.text('Change'), '1');
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('edit, a bound volume: another "from" date picked: the '
          'question', (tester) async {
        await openForm(tester, edit: seedBoundVolume());
        await pickDay(tester, find.text('Change').at(0), '20');
        expect(find.textContaining('20 January 2026'), findsOneWidget);
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('edit, a bound volume: another "to" date picked: the '
          'question', (tester) async {
        await openForm(tester, edit: seedBoundVolume());
        await pickDay(tester, find.text('Change').at(1), '20');
        expect(find.textContaining('20 March 2026'), findsOneWidget);
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('edit, a bound volume: "Bound volume" switched off: the '
          'question (Save would drop the "to" date)', (tester) async {
        await openForm(tester, edit: seedBoundVolume());
        await scrollTap(tester, find.byType(SwitchListTile));
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('a cover photographed: the question', (tester) async {
        final coverFakes = installCoverCaptureFakes();
        await openForm(tester, coverFakes: coverFakes);
        await tester.tap(find.text('Add cover'));
        await tester.pump();
        await coverFakes.pickerGate.entered;
        coverFakes.finishPicker();
        await tester.pump();
        await coverFakes.cropperGate.entered;
        coverFakes.finishCropper();
        await tester.pump();
        await coverFakes.storeGate.entered;
        coverFakes.finishStore('covers/new.jpg');
        await tester.pumpAndSettle();
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('a cover that is still being stored: the question', (
        tester,
      ) async {
        final coverFakes = installCoverCaptureFakes();
        await openForm(tester, coverFakes: coverFakes);
        await tester.tap(find.text('Add cover'));
        await tester.pump();
        await coverFakes.pickerGate.entered;
        coverFakes.finishPicker();
        await tester.pump();
        await coverFakes.cropperGate.entered;
        coverFakes.finishCropper();
        await tester.pump();
        await coverFakes.storeGate.entered;
        await tester.pump();
        // The cover field shows a spinner now: no waiting for rest.
        await pressSystemBack(tester, settle: false);

        expectAsked();

        await tester.tap(findKeepEditing());
        coverFakes.finishStore('covers/new.jpg');
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
      });

      testWidgets('edit: the cover removed: the question', (tester) async {
        await openForm(tester, edit: seedBoundVolume());
        await tester.tap(find.text('Remove cover'));
        await tester.pump();
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('edit: a cover that arrives in the background while the '
          'form is untouched is no change: Back leaves', (tester) async {
        final existing = seedBoundVolume();
        await openForm(tester, edit: existing);
        items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
        ProviderScope.containerOf(
          tester.element(page),
        ).read(catalogueChangesProvider.notifier).changed();
        await tester.pumpAndSettle();
        expect(
          tester.widget<ItemCover>(find.byType(ItemCover)).coverUrl,
          'covers/new.jpg',
          reason: 'the form shows the cover that arrived',
        );
        await pressSystemBack(tester);

        expectGoneWithoutQuestion();
      });
    });

    testWidgets('Back while the save runs does nothing; the form then '
        'leaves by itself, with no question (D95)', (tester) async {
      await openForm(tester, preselected: frontline);
      await tester.enterText(
        find.widgetWithText(TextField, 'Issue number'),
        '5',
      );
      items.holdInsert = Completer<void>();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // No waiting for rest: the Save button shows a spinner while held.
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pressSystemBack(tester, settle: false);
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsOneWidget, reason: 'Back waits for the save');

      items.holdInsert!.complete();
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(items.rows, hasLength(1));
    });

    testWidgets('after a save that failed, Back asks', (tester) async {
      items.insertFailure = const StorageFailure('synthetic');
      await openForm(tester, preselected: frontline);
      await tester.enterText(
        find.widgetWithText(TextField, 'Issue number'),
        '5',
      );
      await save(tester);
      expect(
        find.text('Could not save the issue. Please try again.'),
        findsOneWidget,
      );
      await pressSystemBack(tester);

      expectAsked();
    });
  });
}
