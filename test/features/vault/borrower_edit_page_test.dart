/// What the borrower form does when the user leaves it (review finding
/// P4-M1): Back must not throw away what was typed without asking.
///
/// The form stands ABOVE a home page here, as in the app; "the form is
/// gone" means the home page shows again. The vault session is a stand-in:
/// the form only reads the session's state and calls its add and update,
/// which a test can hold open or make fail.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_edit_page.dart';

import '../../support/fake_vault_session.dart';
import '../../support/form_back_harness.dart';

/// An unlocked session whose writes a test can hold open or make fail.
/// Nothing is encrypted or stored: the writes are only written down.
class _HeldVaultSession extends FixedVaultSession {
  _HeldVaultSession(super.initial);

  /// While set, a borrower write waits for it.
  Completer<void>? hold;

  /// When set, a borrower write answers this failure.
  Failure? failure;

  final List<Borrower> added = [];
  final List<Borrower> updated = [];
  final List<Loan> updatedLoans = [];

  @override
  Future<Either<Failure, int>> addBorrower(Borrower borrower) async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return left(failed);
    added.add(borrower);
    return right(added.length);
  }

  @override
  Future<Either<Failure, Unit>> updateBorrower(Borrower borrower) async {
    await hold?.future;
    final failed = failure;
    if (failed != null) return left(failed);
    updated.add(borrower);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateLoan(Loan loan) async {
    updatedLoans.add(loan);
    return right(unit);
  }
}

void main() {
  // An existing borrower with every field of the form filled in, and one
  // loan that is still out. All of it made up.
  const existing = Borrower(
    id: 2,
    name: 'Asha',
    contact: 'Phone: 5550100\nEmail: asha@example.org\nask at the desk',
    notes: 'Returns on Mondays',
  );
  const data = VaultData(
    borrowers: [existing],
    loans: [Loan(id: 1, itemId: 7, borrowerId: 2, lentDate: 1)],
  );

  late _HeldVaultSession session;

  setUp(() => session = _HeldVaultSession(const VaultUnlocked(data)));

  final name = find.widgetWithText(TextField, 'Name');
  final page = find.byType(BorrowerEditPage);

  Future<void> openForm(WidgetTester tester, {Borrower? edit}) async {
    // Tall enough to build every field and the loan rows under them.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpFormAboveHome(
      tester,
      BorrowerEditPage(existing: edit),
      overrides: [vaultSessionControllerProvider.overrideWith(() => session)],
    );
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

  /// Taps the Save button without waiting for the screen to come to rest:
  /// while a save is held open the button shows a spinner that never rests.
  Future<void> tapSaveAndHold(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('untouched, Back: the form leaves at once', (tester) async {
    await openForm(tester);
    expect(find.text('Add borrower'), findsOneWidget);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('an edit form opened and left as it was: Back leaves', (
    tester,
  ) async {
    await openForm(tester, edit: existing);
    expect(find.text('Edit borrower'), findsOneWidget);
    // The stored contact was taken apart into the three fields.
    expect(find.widgetWithText(TextField, '5550100'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'asha@example.org'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ask at the desk'), findsOneWidget);
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('a name typed, Back: the question. "Keep editing" keeps the '
      'form and the text; Back again and "Discard" leaves', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Meera');
    await pressSystemBack(tester);
    expectAsked();
    expect(
      find.text('What you entered on this page has not been saved.'),
      findsOneWidget,
    );

    await tester.tap(findKeepEditing());
    await tester.pumpAndSettle();
    expect(findDiscardQuestion(), findsNothing);
    expect(find.widgetWithText(TextField, 'Meera'), findsOneWidget);

    await pressSystemBack(tester);
    await tester.tap(findDiscard());
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(session.added, isEmpty, reason: 'discarded, not saved');
  });

  testWidgets('the question shows nothing that was typed', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Meera Private');
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone (optional)'),
      '5550199',
    );
    await pressSystemBack(tester);
    expectAsked();

    final dialog = find.byType(AlertDialog);
    for (final typed in ['Meera', '5550199']) {
      expect(
        find.descendant(of: dialog, matching: find.textContaining(typed)),
        findsNothing,
      );
    }
  });

  testWidgets('the arrow of the app bar asks as well', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Meera');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expectAsked();
  });

  testWidgets('typed and put back, Back: leaves', (tester) async {
    await openForm(tester, edit: existing);
    await tester.enterText(name, 'Asha K');
    await tester.enterText(name, 'Asha');
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  // Every text field the form shows. A field that is added to the page has
  // to be added here (the count below fails otherwise), and then its own
  // test says whether the guard knows of it.
  const textFields = [
    'Name',
    'Phone (optional)',
    'Email (optional)',
    'Other contact (optional)',
    'Notes (optional)',
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
      await tester.enterText(find.widgetWithText(TextField, label), '7');
      await pressSystemBack(tester);

      expectAsked();
    });
  }

  testWidgets('"Return" on a loan row acts at once and is no change of the '
      'form: Back leaves', (tester) async {
    await openForm(tester, edit: existing);
    await tester.tap(find.widgetWithText(TextButton, 'Return'));
    await tester.pumpAndSettle();
    expect(session.updatedLoans, hasLength(1));
    await pressSystemBack(tester);

    expectGoneWithoutQuestion();
  });

  testWidgets('Back while the save runs does nothing; the form then leaves '
      'by itself, with no question (D95)', (tester) async {
    await openForm(tester);
    await tester.enterText(name, 'Meera');
    session.hold = Completer<void>();
    await tapSaveAndHold(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await pressSystemBack(tester, settle: false);
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsOneWidget, reason: 'Back waits for the save');

    session.hold!.complete();
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(session.added.single.name, 'Meera');
  });

  testWidgets('edit: the same while an update runs', (tester) async {
    await openForm(tester, edit: existing);
    await tester.enterText(name, 'Asha K');
    session.hold = Completer<void>();
    await tapSaveAndHold(tester);

    await pressSystemBack(tester, settle: false);
    expect(findDiscardQuestion(), findsNothing);
    expect(page, findsOneWidget, reason: 'Back waits for the save');

    session.hold!.complete();
    await tester.pumpAndSettle();
    expectGoneWithoutQuestion();
    expect(session.updated.single.name, 'Asha K');
  });

  testWidgets('after a save that failed, Back asks', (tester) async {
    session.failure = const StorageFailure('synthetic');
    await openForm(tester);
    await tester.enterText(name, 'Meera');
    await tapSaveAndHold(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please try again.'), findsOneWidget);
    await pressSystemBack(tester);

    expectAsked();
  });

  testWidgets('after a Save the form itself refused (no name), Back asks '
      'about the rest that was typed', (tester) async {
    await openForm(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes (optional)'),
      'Met at the fair',
    );
    await tapSaveAndHold(tester);
    await tester.pumpAndSettle();
    expect(find.text('A name is required.'), findsOneWidget);
    expect(session.added, isEmpty);
    await pressSystemBack(tester);

    expectAsked();
  });
}
