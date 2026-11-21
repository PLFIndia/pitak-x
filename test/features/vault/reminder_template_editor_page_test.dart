/// What the reminder-template form does when the user leaves it (review
/// finding P4-M1): Back must not throw away what was typed without asking.
///
/// The form stands ABOVE a home page here, as in the app; "the form is
/// gone" means the home page shows again. The template store is kept in
/// memory, and a test can hold its write open or make it fail.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/reminder_template.dart';
import 'package:pitaka/features/vault/domain/reminder_template_store.dart';
import 'package:pitaka/features/vault/presentation/pages/reminder_template_editor_page.dart';

import '../../support/form_back_harness.dart';

/// A template store in memory whose write can be held open or refused.
class _HeldStore implements ReminderTemplateStore {
  ReminderTemplateSettings? stored;

  /// While set, `save` waits for it before it stores anything.
  Completer<void>? hold;

  /// When set, `save` answers this failure and stores nothing.
  Failure? failure;

  int saves = 0;

  @override
  Either<Failure, ReminderTemplateSettings?> load() => right(stored);

  @override
  Future<Either<Failure, Unit>> save(ReminderTemplateSettings settings) async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return left(failed);
    stored = settings;
    saves++;
    return right(unit);
  }
}

void main() {
  late _HeldStore store;

  setUp(() => store = _HeldStore());

  final page = find.byType(ReminderTemplateEditorPage);
  final name = find.byKey(const ValueKey('reminder-template-name'));
  final overdue = find.byKey(const ValueKey('reminder-template-overdue'));
  final upcoming = find.byKey(const ValueKey('reminder-template-upcoming'));
  final noDue = find.byKey(const ValueKey('reminder-template-no-due'));
  final saveButton = find.byKey(const ValueKey('reminder-template-save'));

  const existing = ReminderTemplate(
    id: 'hi',
    name: 'Polite',
    overdueBody: '{{itemTitle}} {{dueDate}} overdue',
    upcomingBody: '{{itemTitle}} {{dueDate}} upcoming',
    noDueDateBody: '{{itemTitle}} open',
  );

  Future<void> openForm(WidgetTester tester, {ReminderTemplate? edit}) async {
    // Tall enough to have every field and the Save button on the screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFormAboveHome(
      tester,
      ReminderTemplateEditorPage(existing: edit),
      overrides: [
        reminderTemplateStoreProvider.overrideWith((ref) async => store),
      ],
    );
  }

  /// Fills the form with a template that passes its own check.
  Future<void> fillValidTemplate(WidgetTester tester) async {
    await tester.enterText(name, 'Polite');
    await tester.enterText(overdue, '{{itemTitle}} {{dueDate}} overdue');
    await tester.enterText(upcoming, '{{itemTitle}} {{dueDate}} upcoming');
    await tester.enterText(noDue, '{{itemTitle}} open');
    await tester.pump();
  }

  void expectGoneWithoutQuestion() {
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsNothing);
    expect(findFormBackHome(), findsOneWidget);
  }

  void expectAsked() {
    expect(findDiscardQuestion(), findsOneWidget);
    expect(page, findsOneWidget);
  }

  /// Taps Save without waiting for the screen to come to rest: while a save
  /// is held open the button shows a spinner that never rests.
  Future<void> tapSaveAndHold(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('untouched, Back: the form leaves at once', (tester) async {
    await openForm(tester);
    expect(find.text('Add template'), findsOneWidget);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('an edit form opened and left as it was: Back leaves', (
    tester,
  ) async {
    await openForm(tester, edit: existing);
    expect(find.text('Edit template'), findsOneWidget);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('a name typed, Back: the question. "Keep editing" keeps the '
      'form and the text; Back again and "Discard" leaves', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Polite');
    await pressSystemBack(tester);
    expectAsked();
    expect(
      find.text('What you entered on this page has not been saved.'),
      findsOneWidget,
    );

    await tester.tap(findKeepEditing());
    await tester.pumpAndSettle();
    expect(findDiscardQuestion(), findsNothing);
    expect(find.widgetWithText(TextField, 'Polite'), findsOneWidget);

    await pressSystemBack(tester);
    await tester.tap(findDiscard());
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(store.saves, 0, reason: 'discarded, not saved');
  });

  testWidgets('the arrow of the app bar asks as well', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Polite');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expectAsked();
  });

  testWidgets('typed and put back, Back: leaves', (tester) async {
    await openForm(tester, edit: existing);
    await tester.enterText(name, 'Firm');
    await tester.enterText(name, 'Polite');
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  // Every text field the form shows, by its key. A field that is added to
  // the page has to be added here (the count below fails otherwise), and
  // then its own test says whether the guard knows of it.
  final textFields = {
    'Template name': name,
    'Overdue message': overdue,
    'Upcoming dated message': upcoming,
    'No-due-date message': noDue,
  };

  testWidgets('the form shows exactly the text fields these tests know', (
    tester,
  ) async {
    await openForm(tester);

    expect(find.byType(TextField), findsNWidgets(textFields.length));
    for (final field in textFields.entries) {
      expect(field.value, findsOneWidget);
      expect(find.widgetWithText(TextField, field.key), findsOneWidget);
    }
  });

  for (final field in textFields.entries) {
    testWidgets('"${field.key}" changed, Back: the question', (tester) async {
      await openForm(tester);
      await tester.enterText(field.value, '7');
      await pressSystemBack(tester);

      expectAsked();
    });
  }

  testWidgets('a placeholder chip tapped, nothing typed: the question (the '
      'chip wrote into a message)', (tester) async {
    await openForm(tester);
    await tester.tap(find.widgetWithText(ActionChip, '{{itemTitle}}').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '{{itemTitle}}'), findsOneWidget);
    await pressSystemBack(tester);

    expectAsked();
  });

  testWidgets('Back while the save runs does nothing; the form then leaves '
      'by itself, with no question (D95)', (tester) async {
    await openForm(tester);
    await fillValidTemplate(tester);
    store.hold = Completer<void>();
    await tapSaveAndHold(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pressSystemBack(tester, settle: false);
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsOneWidget, reason: 'Back waits for the save');

    store.hold!.complete();
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(store.stored!.customTemplates.single.name, 'Polite');
  });

  testWidgets('after a save the store refused, Back asks', (tester) async {
    store.failure = const StorageFailure('synthetic');
    await openForm(tester);
    await fillValidTemplate(tester);
    await tapSaveAndHold(tester);
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't save the template. Please try again."),
      findsOneWidget,
    );
    await pressSystemBack(tester);

    expectAsked();
  });

  testWidgets('after a Save the form itself refused (a template that fails '
      'its own check; no save started), Back asks', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Only a name');
    await tapSaveAndHold(tester);
    await tester.pumpAndSettle();
    expect(store.saves, 0);
    expect(page, findsOneWidget);
    await pressSystemBack(tester);

    expectAsked();
  });
}
