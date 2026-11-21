/// "Mark returned" with "Undo": the gesture every screen shares (review
/// finding P4-M3; D105, D109, D114).
///
/// The button stands on a page B that was opened from a page A, because
/// the point of half of these tests is what happens once B is gone: the
/// bar lives above the pages, and "Undo" must still work from A.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';
import 'package:pitaka/features/vault/presentation/widgets/loan_return_action.dart';

import '../../support/fake_vault_session.dart';

const _now = 1700000000000;

class _PageA extends StatelessWidget {
  const _PageA();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Page A')),
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const _PageB())),
        child: const Text('open B'),
      ),
    ),
  );
}

class _PageB extends StatelessWidget {
  const _PageB();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Page B')),
    body: const Column(
      children: [
        MarkReturnedButton(key: Key('loan-10'), loanId: 10),
        MarkReturnedButton(key: Key('loan-11'), loanId: 11),
      ],
    ),
  );
}

void main() {
  const data = VaultData(
    borrowers: [Borrower(id: 1, name: 'Asha Private')],
    loans: [
      Loan(id: 10, itemId: 7, borrowerId: 1, lentDate: 1000),
      Loan(id: 11, itemId: 8, borrowerId: 1, lentDate: 1000),
    ],
  );

  late ReturnsVaultSession session;

  setUp(() => session = ReturnsVaultSession(const VaultUnlocked(data)));

  final first = find.byKey(const Key('loan-10'));
  final second = find.byKey(const Key('loan-11'));
  final undo = find.widgetWithText(SnackBarAction, 'Undo');

  /// Opens page B above page A, with the session unlocked.
  Future<void> openB(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultSessionControllerProvider.overrideWith(() => session),
          clockProvider.overrideWithValue(() => _now),
        ],
        child: const MaterialApp(home: _PageA()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open B'));
    await tester.pumpAndSettle();
  }

  Loan loanOf(int id) => (session.state.value! as VaultUnlocked).data.loans
      .firstWhere((loan) => loan.id == id);

  group('the button', () {
    testWidgets('says "Mark returned" and marks its loan at the time of the '
        "app's clock", (tester) async {
      await openB(tester);
      expect(find.text('Mark returned'), findsNWidgets(2));

      await tester.tap(first);
      await tester.pumpAndSettle();

      expect(session.calls, [(10, _now)]);
      expect(loanOf(10).returnedDate, _now);
      expect(loanOf(11).isReturned, isFalse);
    });

    testWidgets('while the vault writes it shows a spinner and takes no '
        'second tap', (tester) async {
      await openB(tester);
      session.hold = Completer<void>();

      await tester.tap(first);
      await tester.pump();
      expect(
        find.descendant(
          of: first,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(first, warnIfMissed: false);
      await tester.pump();
      expect(session.calls, hasLength(1), reason: 'one write for two taps');

      session.hold!.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: first,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });
  });

  group('the bar', () {
    testWidgets('says "Marked returned." and offers "Undo", and names '
        'nobody and nothing', (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();

      expect(find.text('Marked returned.'), findsOneWidget);
      expect(undo, findsOneWidget);
      final bar = find.byType(SnackBar);
      for (final secret in ['Asha', 'Private', '10', '7']) {
        expect(
          find.descendant(of: bar, matching: find.textContaining(secret)),
          findsNothing,
          reason: 'the bar can outlive the page and must not name "$secret"',
        );
      }
    });

    testWidgets('goes by itself after 6 seconds, so that no other message '
        'of the app waits behind it for longer (D114)', (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      expect(undo, findsOneWidget, reason: 'still there at 5 seconds');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(undo, findsNothing, reason: 'gone after 6 seconds');
      expect(loanOf(10).isReturned, isTrue, reason: 'the return stands');
    });

    testWidgets('does not hold up a message of other code for longer than '
        'its own time', (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      // Any other part of the app shows a message while the bar is up.
      ScaffoldMessenger.of(
        tester.element(first),
      ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp.')));
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();

      expect(find.text('Could not open WhatsApp.'), findsOneWidget);
    });

    testWidgets('"Undo" takes the return back, once, and says so', (
      tester,
    ) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(session.calls, [(10, _now), (10, null)]);
      expect(loanOf(10).isReturned, isFalse);
      expect(find.text('The loan is open again.'), findsOneWidget);
      expect(undo, findsNothing);
    });

    testWidgets('"Undo" still works when the page that showed it is gone', (
      tester,
    ) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Page B'), findsNothing);
      expect(undo, findsOneWidget, reason: 'the bar followed to page A');

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(session.calls.last, (10, null));
      expect(loanOf(10).isReturned, isFalse);
      expect(find.text('The loan is open again.'), findsOneWidget);
    });

    testWidgets('goes at once when the vault is locked: a locked vault says '
        'nothing about a loan (D84)', (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(undo, findsOneWidget);

      session.show(const VaultLocked());
      await tester.pumpAndSettle();

      expect(find.text('Marked returned.'), findsNothing);
      expect(undo, findsNothing);
    });

    testWidgets('goes at a lock also when the page that showed it is gone', (
      tester,
    ) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(undo, findsOneWidget);

      session.show(const VaultLocked());
      await tester.pumpAndSettle();

      expect(find.text('Marked returned.'), findsNothing);
    });

    testWidgets('a second return takes the place of the first bar at once, '
        'and its "Undo" is for the second loan', (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();

      expect(find.text('Marked returned.'), findsOneWidget);
      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(session.calls.last, (11, null));
      expect(loanOf(11).isReturned, isFalse);
      expect(loanOf(10).isReturned, isTrue, reason: 'the first return stands');
    });
  });

  group('when it fails', () {
    Future<void> tapWithFailure(WidgetTester tester, Failure failure) async {
      await openB(tester);
      session.failure = failure;
      await tester.tap(first);
      await tester.pumpAndSettle();
    }

    testWidgets('a loan that is gone: its own sentence, no "Undo"', (
      tester,
    ) async {
      await tapWithFailure(tester, const NotFoundFailure());

      expect(find.text('That loan no longer exists.'), findsOneWidget);
      expect(undo, findsNothing);
    });

    testWidgets('a storage failure: a safe sentence, never its reason', (
      tester,
    ) async {
      await tapWithFailure(tester, const StorageFailure('db locked at /x'));

      expect(
        find.text('Could not mark this item returned. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('db locked'), findsNothing);
      expect(undo, findsNothing);
    });

    testWidgets('a validation text that is not one of ours is not shown '
        '(the vault core writes such texts for developers)', (tester) async {
      await tapWithFailure(
        tester,
        const ValidationFailure('returned_date is out of range'),
      );

      expect(find.textContaining('returned_date'), findsNothing);
      expect(
        find.text('Could not mark this item returned. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('the button can be tapped again after a failure', (
      tester,
    ) async {
      await tapWithFailure(tester, const StorageFailure('synthetic'));
      session.failure = null;
      // The failure message is still up; the tap is on the button.
      await tester.tap(first);
      await tester.pumpAndSettle();

      expect(loanOf(10).isReturned, isTrue);
      expect(undo, findsOneWidget);
    });

    testWidgets('"Undo" refused because the copy was lent again: the '
        "rule's sentence; the return stands", (tester) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      session.failure = const ValidationFailure(reopenRefusedNoCopyFreeMessage);

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(find.text(reopenRefusedNoCopyFreeMessage), findsOneWidget);
      expect(find.text('The loan is open again.'), findsNothing);
      expect(loanOf(10).isReturned, isTrue);
    });

    testWidgets('"Undo" that fails for another reason: a safe sentence', (
      tester,
    ) async {
      await openB(tester);
      await tester.tap(first);
      await tester.pumpAndSettle();
      session.failure = const StorageFailure('db locked at /x');

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(
        find.text('Could not take the return back. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('db locked'), findsNothing);
    });
  });
}
