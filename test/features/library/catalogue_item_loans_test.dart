/// The item's page says who has the item and offers "Mark returned": one
/// line for each loan of the item that is still out (review finding P4-M3;
/// D103, D104).
///
/// The privacy rule these tests hold (D104): a borrower's name is on this
/// page ONLY while the vault is unlocked NOW. Locked, not set up, or a
/// session that still carries an earlier unlock while it loads again: no
/// name, no line, no button.
///
/// What the gesture itself does (the bar, "Undo", the failure sentences) is
/// held by `test/features/vault/loan_return_action_test.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

import '../../support/a11y.dart';
import '../../support/fake_vault_session.dart';
import '../../support/text_lines.dart';

/// The one row the page reads.
class _Items implements CatalogueItemRepository {
  _Items(this.item);
  final CatalogueItem item;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      right(id == item.id ? item : null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _now = 1700000000000;
final _due12 = DateTime(2026, 11, 12).millisecondsSinceEpoch;
final _due20 = DateTime(2026, 11, 20).millisecondsSinceEpoch;

const _oneCopy = CatalogueItem(id: 7, itemUid: 'uid-7', title: 'Godaan');
const _threeCopies = CatalogueItem(
  id: 7,
  itemUid: 'uid-7',
  title: 'Godaan',
  copyCount: 3,
);

const _asha = Borrower(id: 1, name: 'Asha');
const _ravi = Borrower(id: 2, name: 'Ravi');

/// Loan 10: the item, with Asha, due on 12 November 2026.
Loan _ashasLoan() =>
    Loan(id: 10, itemId: 7, borrowerId: 1, lentDate: 1000, dueDate: _due12);

/// Loan 11: the item, with Ravi, no due date.
const _ravisLoan = Loan(id: 11, itemId: 7, borrowerId: 2, lentDate: 1000);

VaultUnlocked _unlocked(List<Loan> loans) =>
    VaultUnlocked(VaultData(borrowers: const [_asha, _ravi], loans: loans));

const _ashasLine = 'Lent to Asha · due 12 November 2026';
const _ravisLine = 'Lent to Ravi · no due date';
const _allOutSentence =
    'This item is already out on loan. Mark it returned before lending it '
    'again.';

final _markReturned = find.widgetWithText(TextButton, 'Mark returned');
final _undo = find.widgetWithText(SnackBarAction, 'Undo');

/// "Mark returned" on the line of the loan [loanId].
Finder _markReturnedOn(int loanId) => find.descendant(
  of: find.byKey(ValueKey('item-loan-$loanId')),
  matching: _markReturned,
);

bool _lendEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lend'))
        .onPressed !=
    null;

/// Opens the page of [item] over a vault in the state [vault]. The screen
/// is tall, so that the whole page is built (it is a lazy list).
Future<ReturnsVaultSession> _openItem(
  WidgetTester tester, {
  required VaultSessionState vault,
  CatalogueItem item = _oneCopy,
  Size size = const Size(412, 2400),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = ReturnsVaultSession(vault);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => _Items(item),
        ),
        coversDirProvider.overrideWith((ref) async => '.'),
        vaultSessionControllerProvider.overrideWith(() => session),
        clockProvider.overrideWithValue(() => _now),
      ],
      child: MaterialApp(
        home: CatalogueItemDetailPage(bookId: item.id, initialBook: item),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  group('who has the item:', () {
    testWidgets('no loan of this item is out: no line and no button', (
      tester,
    ) async {
      await _openItem(
        tester,
        vault: _unlocked(const [
          // Another item's loan, and a loan of this item that came back.
          Loan(id: 20, itemId: 8, borrowerId: 1, lentDate: 1000),
          Loan(
            id: 21,
            itemId: 7,
            borrowerId: 2,
            lentDate: 1000,
            returnedDate: 2000,
          ),
        ]),
      );

      expect(find.textContaining('Lent'), findsNothing);
      expect(_markReturned, findsNothing);
      expect(_lendEnabled(tester), isTrue);
    });

    testWidgets('one copy, out: the line names the borrower and the due '
        'date and has the button; Lend waits, with its sentence', (
      tester,
    ) async {
      await _openItem(tester, vault: _unlocked([_ashasLoan()]));

      expect(find.text(_ashasLine), findsOneWidget);
      expect(_markReturned, findsOneWidget);
      expect(_lendEnabled(tester), isFalse);
      expect(find.text(_allOutSentence), findsOneWidget);
      // The line stands under the Lend button and its sentence.
      expect(
        tester.getTopLeft(find.text(_ashasLine)).dy,
        greaterThan(tester.getBottomLeft(find.text(_allOutSentence)).dy),
      );
    });

    testWidgets('three copies, two out: two lines, the one with the earlier '
        'due date first, each with its own button; Lend is ready', (
      tester,
    ) async {
      await _openItem(
        tester,
        item: _threeCopies,
        vault: _unlocked([_ravisLoan, _ashasLoan()]),
      );

      expect(find.text(_ashasLine), findsOneWidget);
      expect(find.text(_ravisLine), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(_ashasLine)).dy,
        lessThan(tester.getTopLeft(find.text(_ravisLine)).dy),
        reason: 'a loan with a due date stands before one without',
      );
      expect(_markReturned, findsNWidgets(2));
      expect(_lendEnabled(tester), isTrue);
    });

    testWidgets('a loan whose borrower the vault does not hold says so and '
        'can still be marked returned', (tester) async {
      final session = await _openItem(
        tester,
        vault: _unlocked(const [
          Loan(id: 12, itemId: 7, borrowerId: 99, lentDate: 1000),
        ]),
      );
      const line = 'Lent, borrower not found · no due date';
      expect(find.text(line), findsOneWidget);

      await tester.tap(_markReturnedOn(12));
      await tester.pumpAndSettle();

      expect(session.calls, [(12, _now)]);
      expect(find.text(line), findsNothing);
    });

    testWidgets('a stored due date that cannot be a date gets a safe word', (
      tester,
    ) async {
      await _openItem(
        tester,
        vault: _unlocked(const [
          Loan(
            id: 10,
            itemId: 7,
            borrowerId: 1,
            lentDate: 1000,
            dueDate: 8640000000000001,
          ),
        ]),
      );

      expect(find.text('Lent to Asha · due date unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('only an unlocked vault names a borrower (D104):', () {
    testWidgets('locked: no name, no line, no button', (tester) async {
      await _openItem(tester, vault: const VaultLocked());

      expect(
        find.text('Unlock the borrowers vault to lend this item.'),
        findsOneWidget,
      );
      expect(find.textContaining('Lent'), findsNothing);
      expect(_markReturned, findsNothing);
    });

    testWidgets('not set up: no line, no button', (tester) async {
      await _openItem(tester, vault: const VaultUninitialized());

      expect(
        find.text('Set up the borrowers vault to start lending.'),
        findsOneWidget,
      );
      expect(find.textContaining('Lent'), findsNothing);
      expect(_markReturned, findsNothing);
    });

    testWidgets('a lock while the page is open takes the lines away', (
      tester,
    ) async {
      final session = await _openItem(tester, vault: _unlocked([_ashasLoan()]));
      expect(find.text(_ashasLine), findsOneWidget);

      session.show(const VaultLocked());
      await tester.pumpAndSettle();

      expect(find.textContaining('Asha'), findsNothing);
      expect(find.textContaining('Lent'), findsNothing);
      expect(_markReturned, findsNothing);
    });

    for (final (how, change) in [
      ('loads again', (ReturnsVaultSession s) => s.showLoadingWithPrevious()),
      ('has failed', (ReturnsVaultSession s) => s.showErrorWithPrevious()),
    ]) {
      testWidgets('a session that $how and still carries the earlier unlock '
          'names nobody', (tester) async {
        final session = await _openItem(
          tester,
          vault: _unlocked([_ashasLoan()]),
        );
        expect(find.text(_ashasLine), findsOneWidget);

        change(session);
        await tester.pump();

        expect(find.textContaining('Asha'), findsNothing);
        expect(find.textContaining('Lent to'), findsNothing);
        expect(_markReturned, findsNothing);
      });
    }
  });

  group('Mark returned on the item page:', () {
    testWidgets('a tap marks that loan returned: its line goes, "Undo" is '
        'offered, and Lend is ready again', (tester) async {
      final session = await _openItem(tester, vault: _unlocked([_ashasLoan()]));

      await tester.tap(_markReturned);
      await tester.pumpAndSettle();

      expect(session.calls, [(10, _now)]);
      expect(find.text(_ashasLine), findsNothing);
      expect(_markReturned, findsNothing);
      expect(find.text('Marked returned.'), findsOneWidget);
      expect(_undo, findsOneWidget);
      expect(_lendEnabled(tester), isTrue);
      expect(find.text(_allOutSentence), findsNothing);
    });

    testWidgets('"Undo" puts the line back, and Lend waits again', (
      tester,
    ) async {
      final session = await _openItem(tester, vault: _unlocked([_ashasLoan()]));
      await tester.tap(_markReturned);
      await tester.pumpAndSettle();

      await tester.tap(_undo);
      await tester.pumpAndSettle();

      expect(session.calls, [(10, _now), (10, null)]);
      expect(find.text(_ashasLine), findsOneWidget);
      expect(_lendEnabled(tester), isFalse);
    });

    testWidgets('two copies out: the tap marks the loan of ITS line', (
      tester,
    ) async {
      final session = await _openItem(
        tester,
        item: _threeCopies,
        vault: _unlocked([_ashasLoan(), _ravisLoan]),
      );

      await tester.tap(_markReturnedOn(11));
      await tester.pumpAndSettle();

      expect(session.calls, [(11, _now)]);
      expect(find.text(_ravisLine), findsNothing);
      expect(find.text(_ashasLine), findsOneWidget);
    });

    testWidgets('two returns under way at once: when the first line goes, '
        "the second line's button still waits for its own write", (
      tester,
    ) async {
      final session = await _openItem(
        tester,
        item: _threeCopies,
        vault: _unlocked([_ashasLoan(), _ravisLoan]),
      );
      final first = Completer<void>();
      final second = Completer<void>();

      session.hold = first;
      await tester.tap(_markReturnedOn(10));
      await tester.pump();
      session.hold = second;
      await tester.tap(_markReturnedOn(11));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

      // Asha's return is written; Ravi's is not yet.
      first.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text(_ashasLine), findsNothing);
      expect(find.text(_ravisLine), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason:
            "Ravi's line still waits: a button's busy state belongs to "
            'its loan, not to its place in the list',
      );
      expect(_markReturned, findsNothing);

      second.complete();
      await tester.pumpAndSettle();
      expect(find.text(_ravisLine), findsNothing);
      expect(session.calls, [(10, _now), (11, _now)]);
    });
  });

  group('the page with two loan lines', () {
    testWidgets('meets the accessibility guidelines', (tester) async {
      await _openItem(
        tester,
        item: _threeCopies,
        vault: _unlocked([_ashasLoan(), _ravisLoan]),
      );

      expect(_markReturned, findsNWidgets(2));
      await expectMeetsA11yGuidelines(tester);
    });

    // What a widget test can say about the narrow, large-text case is in
    // `test/support/text_lines.dart`: one line at the usual text size is
    // held here; one line at twice the size is looked at on the phone (D111).
    testWidgets('does not overflow at 320 pixels, also at twice the text '
        'size; at the usual size the words of the button stand on one line', (
      tester,
    ) async {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox());
        await _openItem(
          tester,
          item: _threeCopies,
          vault: _unlocked([
            _ashasLoan(),
            Loan(
              id: 13,
              itemId: 7,
              borrowerId: 2,
              lentDate: 1000,
              dueDate: _due20,
            ),
          ]),
          size: const Size(320, 4000),
          textScaler: TextScaler.linear(scale),
        );

        expect(tester.takeException(), isNull, reason: 'scale $scale');
        expect(_markReturned, findsNWidgets(2));
        for (final loanId in [10, 13]) {
          final words = find.descendant(
            of: _markReturnedOn(loanId),
            matching: find.text('Mark returned'),
          );
          expect(
            liesWithinScreenWidth(tester, words),
            isTrue,
            reason: 'scale $scale: the button is not pushed off the screen',
          );
          if (scale == 1.0) {
            expect(
              standsOnOneLine(tester, words),
              isTrue,
              reason: '"Mark returned" stands on one line',
            );
          }
        }
      }
    });
  });
}
