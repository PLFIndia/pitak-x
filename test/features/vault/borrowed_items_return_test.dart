/// "Mark returned" on the loan card of Borrowed Items, as a list row (a
/// phone) and as a grid card (a wide screen): review finding P4-M3; D103,
/// D105 and D109.
///
/// What the gesture itself does (the bar, "Undo", the failure sentences) is
/// held by `loan_return_action_test.dart`. These tests hold what the CARD
/// adds: the button is there, the card leaves the list after a return, and
/// the card's one busy state covers the new action as it covers the others.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_grid_card.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_row.dart';
// Transitive test seam for the existing url_launcher dependency.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../support/a11y.dart';
import 'borrowed_items_test_harness.dart';

class _Launcher extends UrlLauncherPlatform {
  final urls = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

/// A phone: Borrowed Items draws a list of rows.
const _phone = Size(412, 915);

/// A wide screen: Borrowed Items draws a grid of cards.
const _wide = Size(900, 900);

/// Two loans that are out: loan 1 (with a phone number, so its card has
/// all three icon buttons) and loan 2.
List<BorrowedLoan> _twoLoans() => [
  testEntry(coverUrl: 'covers/a.jpg'),
  testEntry(
    loanId: 2,
    itemId: 5,
    title: 'Other book',
    borrowerId: 4,
    borrowerName: 'Ravi',
    coverUrl: 'covers/b.jpg',
  ),
];

Finder _cardOf(int loanId) => find.byKey(ValueKey('borrowed-loan-$loanId'));

Finder _markReturnedOn(int loanId) => find.descendant(
  of: _cardOf(loanId),
  matching: find.widgetWithText(TextButton, 'Mark returned'),
);

Finder _on(int loanId, String tooltip) =>
    find.descendant(of: _cardOf(loanId), matching: find.byTooltip(tooltip));

final _undo = find.widgetWithText(SnackBarAction, 'Undo');

/// Opens Borrowed Items over an unlocked vault that holds the loans of
/// [entries]; the cards follow that vault, as in the app.
Future<({TestVaultSession session, TestShare share})> _open(
  WidgetTester tester, {
  List<BorrowedLoan>? entries,
  Size viewport = _phone,
  TextScaler? textScaler,
  TestShare? share,
}) async {
  final shown = entries ?? _twoLoans();
  final session = TestVaultSession(
    VaultUnlocked(
      VaultData(
        borrowers: [for (final entry in shown) entry.borrower],
        loans: [for (final entry in shown) entry.loan],
      ),
    ),
  );
  final harness = await pumpBorrowedItems(
    tester,
    session: session,
    share: share,
    followSession: true,
    viewport: viewport,
    textScaler: textScaler,
    snapshot: BorrowedItemsSnapshot(entries: shown, unresolvedCount: 0),
    extraOverrides: [clockProvider.overrideWithValue(() => testNow)],
  );
  return (session: session, share: harness.share);
}

void main() {
  for (final (layout, size, cardType) in [
    ('list', _phone, BorrowedLoanRow),
    ('grid', _wide, BorrowedLoanGridCard),
  ]) {
    group('Mark returned on the loan card, $layout:', () {
      testWidgets('every card has a button with the words', (tester) async {
        await _open(tester, viewport: size);

        expect(find.byType(cardType), findsNWidgets(2));
        expect(_markReturnedOn(1), findsOneWidget);
        expect(_markReturnedOn(2), findsOneWidget);
      });

      testWidgets("a tap marks that loan returned at the time of the app's "
          'clock; its card leaves the list, the other card stays, and "Undo" '
          'is offered', (tester) async {
        final harness = await _open(tester, viewport: size);

        await tester.tap(_markReturnedOn(1));
        await tester.pumpAndSettle();

        expect(harness.session.calls, [(1, testNow)]);
        expect(_cardOf(1), findsNothing);
        expect(_cardOf(2), findsOneWidget);
        expect(find.text('Marked returned.'), findsOneWidget);
        expect(_undo, findsOneWidget);
        expect(
          find.byType(CatalogueItemDetailPage),
          findsNothing,
          reason: 'a tap on the button is not a tap on the card',
        );
      });

      testWidgets('"Undo" brings the card back', (tester) async {
        final harness = await _open(tester, viewport: size);
        await tester.tap(_markReturnedOn(1));
        await tester.pumpAndSettle();

        await tester.tap(_undo);
        await tester.pumpAndSettle();

        expect(harness.session.calls, [(1, testNow), (1, null)]);
        expect(_cardOf(1), findsOneWidget);
        expect(find.text('The loan is open again.'), findsOneWidget);
      });

      testWidgets('while the vault writes, more taps write nothing, the '
          "card's other actions wait, no tap on them opens the item, and "
          'the other card is not held up', (tester) async {
        final previous = UrlLauncherPlatform.instance;
        final launcher = _Launcher();
        UrlLauncherPlatform.instance = launcher;
        addTearDown(() => UrlLauncherPlatform.instance = previous);
        final harness = await _open(tester, viewport: size);
        harness.session.hold = Completer<void>();

        // Two taps before the screen is drawn again: the button still looks
        // ready for the second one, and the page has to turn it away.
        await tester.tap(_markReturnedOn(1));
        await tester.tap(_markReturnedOn(1));
        await tester.pump();
        expect(harness.session.calls, hasLength(1), reason: 'one write');
        expect(
          tester.widget<TextButton>(_markReturnedOn(1)).enabled,
          isFalse,
          reason: 'the button shows that it waits',
        );

        await tester.tap(_markReturnedOn(1), warnIfMissed: false);
        await tester.pump();
        expect(harness.session.calls, hasLength(1), reason: 'still one write');
        await tester.tap(_on(1, 'Share loan reminder'), warnIfMissed: false);
        await tester.tap(
          _on(1, 'WhatsApp borrower (text only)'),
          warnIfMissed: false,
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        expect(harness.share.byteCalls, isEmpty);
        expect(harness.share.textCalls, isEmpty);
        expect(launcher.urls, isEmpty);
        expect(
          find.byType(CatalogueItemDetailPage),
          findsNothing,
          reason: 'a tap on a button that waits must not open the item',
        );

        // The busy state is one card's, not the page's.
        await tester.tap(_on(2, 'Share loan reminder'));
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        expect(harness.share.byteCalls, hasLength(1));

        harness.session.hold!.complete();
        await tester.pumpAndSettle();
        expect(_cardOf(1), findsNothing);
        expect(_cardOf(2), findsOneWidget);
      });

      testWidgets('while a reminder is prepared for a card, its "Mark '
          'returned" waits too, and a tap on it does not open the item', (
        tester,
      ) async {
        final share = TestShare()..nextBytesGate = Completer<void>();
        final harness = await _open(tester, viewport: size, share: share);

        await tester.tap(_on(1, 'Share loan reminder'));
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        expect(share.byteCalls, hasLength(1), reason: 'the share is held open');

        await tester.tap(_markReturnedOn(1), warnIfMissed: false);
        await tester.pump();
        expect(harness.session.calls, isEmpty);
        expect(find.byType(CatalogueItemDetailPage), findsNothing);

        share.nextBytesGate!.complete();
        await tester.pumpAndSettle();
        await tester.tap(_markReturnedOn(1));
        await tester.pumpAndSettle();
        expect(harness.session.calls, [(1, testNow)]);
      });

      testWidgets('at twice the text size nothing overflows', (tester) async {
        await _open(
          tester,
          viewport: size,
          textScaler: const TextScaler.linear(2),
        );

        expect(tester.takeException(), isNull);
        expect(_markReturnedOn(1), findsOneWidget);
      });
    });
  }

  group('Mark returned on the loan card:', () {
    testWidgets('the only loan: the page then says that nothing is borrowed '
        'and still offers "Undo"', (tester) async {
      await _open(tester, entries: [testEntry()]);

      await tester.tap(_markReturnedOn(1));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is currently borrowed.'), findsOneWidget);
      expect(_undo, findsOneWidget);

      await tester.tap(_undo);
      await tester.pumpAndSettle();
      expect(_cardOf(1), findsOneWidget);
    });

    testWidgets('a failure gets a safe sentence, the card stays, and its '
        'button works again', (tester) async {
      final harness = await _open(tester);
      harness.session.failure = const StorageFailure('db locked at /x');

      await tester.tap(_markReturnedOn(1));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not mark this item returned. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('db locked'), findsNothing);
      expect(_undo, findsNothing);
      expect(_cardOf(1), findsOneWidget);

      harness.session.failure = null;
      await tester.tap(_markReturnedOn(1));
      await tester.pumpAndSettle();
      expect(_cardOf(1), findsNothing, reason: 'the card was not left busy');
    });

    testWidgets('a locked vault shows no card and no button', (tester) async {
      await pumpBorrowedItems(
        tester,
        viewport: _phone,
        session: TestVaultSession(const VaultLocked()),
        snapshot: BorrowedItemsSnapshot(
          entries: _twoLoans(),
          unresolvedCount: 0,
        ),
      );

      expect(find.text('Mark returned'), findsNothing);
    });

    testWidgets('a lock takes the cards and the bar with "Undo" away', (
      tester,
    ) async {
      final harness = await _open(tester);
      await tester.tap(_markReturnedOn(1));
      await tester.pumpAndSettle();
      expect(_undo, findsOneWidget);

      harness.session.show(const VaultLocked());
      await tester.pumpAndSettle();

      expect(
        find.text('Unlock the vault to see borrowed items.'),
        findsOneWidget,
      );
      expect(find.text('Mark returned'), findsNothing);
      expect(find.text('Marked returned.'), findsNothing);
      expect(_undo, findsNothing);
    });

    testWidgets('a tap that arrives after the vault was locked, before the '
        'screen has caught up, asks nothing of the vault and says nothing', (
      tester,
    ) async {
      final harness = await _open(tester);

      // No pump between the lock and the tap: the card is still drawn.
      harness.session.show(const VaultLocked());
      await tester.tap(_markReturnedOn(1));
      await tester.pumpAndSettle();

      expect(harness.session.calls, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('at 320 pixels, also at twice the text size, the row with '
        'the button does not overflow', (tester) async {
      await _open(tester, viewport: const Size(320, 900));
      expect(tester.takeException(), isNull);
      expect(_markReturnedOn(1), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await _open(
        tester,
        viewport: const Size(320, 900),
        textScaler: const TextScaler.linear(2),
      );
      expect(tester.takeException(), isNull);
      expect(_markReturnedOn(1), findsOneWidget);
    });

    testWidgets('in the grid, at the usual text size, the button is on the '
        'card without scrolling inside it', (tester) async {
      await _open(tester, viewport: _wide);

      final card = tester.getRect(_cardOf(1));
      final button = tester.getRect(_markReturnedOn(1));
      expect(button.bottom, lessThanOrEqualTo(card.bottom));
      expect(button.top, greaterThanOrEqualTo(card.top));
    });

    testWidgets('the list with its buttons meets the accessibility '
        'guidelines', (tester) async {
      await _open(tester);

      expect(_markReturnedOn(1), findsOneWidget);
      await expectMeetsA11yGuidelines(tester);
    });
  });
}
