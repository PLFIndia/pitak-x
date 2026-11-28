/// Review finding N06 widget tests: the borrower profile must resolve
/// book titles through a read model (not "Item #id"), surface per-return
/// progress and typed failures, and treat repeat returns as no-ops.
///
/// Since review finding P4-M3 (2026-11): the button says "Mark returned",
/// a return can be taken back with "Undo", and a returned loan in the
/// History can be marked "Not returned" after a question (D109, D114).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/loan_return.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_profile_page.dart';

import '../../support/a11y.dart';
import '../../support/text_lines.dart';
import 'vault_repository_write_stub.dart';

/// Vault fake with a scripted read result and a recordable, scriptable
/// `updateLoan` (the op under test).
class _ScriptedVault with VaultWriteUnsupported implements VaultRepository {
  _ScriptedVault(this.data, {this.updateResult});

  final VaultData data;
  Either<Failure, Unit>? updateResult;
  final List<Loan> updatedLoans = [];

  /// While set, a write waits for it (read when the write arrives).
  Completer<void>? holdUpdate;

  /// Re-reads apply any recorded `updateLoan` writes, mirroring how the real
  /// vault re-read returns the mutated rows after a write.
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    final loans = [
      for (final l in data.loans)
        updatedLoans.fold<Loan>(l, (current, u) => u.id == l.id ? u : current),
    ];
    return right(VaultData(borrowers: data.borrowers, loans: loans));
  }

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async => right('test-blob');

  @override
  Future<Either<Failure, Unit>> updateLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) async {
    await holdUpdate?.future;
    updatedLoans.add(loan);
    return updateResult ?? right(unit);
  }
}

/// Minimal book repo serving titles for the read model.
class _TitleBooks implements CatalogueItemRepository {
  _TitleBooks(this.byId);
  final Map<int, String> byId;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(
    byId.containsKey(id) ? CatalogueItem(id: id, title: byId[id]!) : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  const borrower = Borrower(id: 1, name: 'Asha');
  const loan = Loan(id: 10, itemId: 7, borrowerId: 1, lentDate: 1000);

  setUp(() => tmp = Directory.systemTemp.createTempSync('profile_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Builds an UNLOCKED session over [vault] and pumps the profile page.
  /// [textScale] is the size of the user's font setting (1 is the default).
  Future<ProviderContainer> pumpUnlocked(
    WidgetTester tester,
    _ScriptedVault vault, {
    Map<int, String> books = const {7: 'Godaan'},
    double textScale = 1,
  }) async {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => vault),
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => _TitleBooks(books),
        ),
        // N04: the real tick self-reschedules a 60 s timer; these tests don't
        // wait on the clock, so stub it out (a pending timer would outlive
        // the widget tree and fail the test binding's invariant check).
        nowTickProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vaultSessionControllerProvider.future);
    final enabled = await container
        .read(vaultSessionControllerProvider.notifier)
        .enable(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
    expect(enabled.isRight(), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const BorrowerProfilePage(borrowerId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  // A loan of the same borrower that came back, for the History.
  const returned = Loan(
    id: 11,
    itemId: 7,
    borrowerId: 1,
    lentDate: 1000,
    dueDate: 5000,
    returnedDate: 3000,
  );
  final markReturned = find.widgetWithText(TextButton, 'Mark returned');
  final notReturned = find.widgetWithText(TextButton, 'Not returned');

  testWidgets('N06: loan rows show the book title, not the internal id', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);

    expect(find.text('Godaan'), findsOneWidget);
    expect(find.textContaining('Item #7'), findsNothing);
  });

  testWidgets('N06: a missing book falls back to "Item #id"', (tester) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault, books: const {});

    expect(find.text('Item #7'), findsOneWidget);
  });

  testWidgets('N06: "Mark returned" writes the loan and moves it to History', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);
    expect(find.text('Return'), findsNothing, reason: 'the old word (D109)');

    await tester.tap(markReturned);
    await tester.pumpAndSettle();

    expect(vault.updatedLoans, hasLength(1));
    expect(vault.updatedLoans.single.id, 10);
    expect(vault.updatedLoans.single.returnedDate, isNotNull);
    // The row moved to History (returned label visible, the button gone).
    expect(find.textContaining('Returned'), findsOneWidget);
    expect(markReturned, findsNothing);
    expect(find.text('Nothing out right now.'), findsOneWidget);
  });

  testWidgets('P4-M3: after "Mark returned" the bar offers "Undo", and '
      '"Undo" puts the loan back under "Currently out" with its dates', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);
    await tester.tap(markReturned);
    await tester.pumpAndSettle();
    expect(find.text('Marked returned.'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();

    expect(vault.updatedLoans, hasLength(2));
    expect(vault.updatedLoans.last.id, 10);
    expect(vault.updatedLoans.last.returnedDate, isNull);
    expect(vault.updatedLoans.last.lentDate, 1000);
    expect(markReturned, findsOneWidget, reason: 'out again');
    expect(find.text('No returned loans yet.'), findsOneWidget);
    expect(find.text('The loan is open again.'), findsOneWidget);
  });

  testWidgets('P4-M3: two returns under way at once: when the first row '
      "moves to the History, the second row's button still waits for its "
      'own write', (tester) async {
    const second = Loan(id: 12, itemId: 8, borrowerId: 1, lentDate: 1000);
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan, second]),
    );
    await pumpUnlocked(tester, vault, books: const {7: 'Godaan', 8: 'Nirmala'});
    final firstWrite = Completer<void>();
    final secondWrite = Completer<void>();

    // The session writes one thing at a time: the second return waits in
    // its queue behind the first.
    vault.holdUpdate = firstWrite;
    await tester.tap(markReturned.first);
    await tester.pump();
    await tester.tap(markReturned.last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));

    vault.holdUpdate = secondWrite;
    firstWrite.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(vault.updatedLoans, hasLength(1), reason: 'one is written');
    expect(find.textContaining('Returned'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason:
          "the second row still waits: a button's busy state belongs "
          'to its loan, not to its place in the list',
    );
    expect(markReturned, findsNothing);

    secondWrite.complete();
    await tester.pumpAndSettle();
    expect(vault.updatedLoans.map((loan) => loan.id).toSet(), {10, 12});
    expect(find.text('Nothing out right now.'), findsOneWidget);
  });

  group('P4-M3, D114: "Not returned" in the History', () {
    testWidgets('asks first; "Cancel" writes nothing', (tester) async {
      final vault = _ScriptedVault(
        const VaultData(borrowers: [borrower], loans: [returned]),
      );
      await pumpUnlocked(tester, vault);

      await tester.tap(notReturned);
      await tester.pumpAndSettle();
      expect(find.text('Mark as not returned?'), findsOneWidget);
      expect(
        find.text('The loan will be out again, with the dates it had.'),
        findsOneWidget,
      );
      // The question names neither the borrower nor the item.
      final dialog = find.byType(AlertDialog);
      for (final name in ['Asha', 'Godaan']) {
        expect(
          find.descendant(of: dialog, matching: find.textContaining(name)),
          findsNothing,
        );
      }

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(vault.updatedLoans, isEmpty);
      expect(notReturned, findsOneWidget, reason: 'still in the History');
    });

    testWidgets('a yes puts the loan back under "Currently out", with the '
        'dates it had, and says so', (tester) async {
      final vault = _ScriptedVault(
        const VaultData(borrowers: [borrower], loans: [returned]),
      );
      await pumpUnlocked(tester, vault);

      await tester.tap(notReturned);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Not returned'));
      await tester.pumpAndSettle();

      final written = vault.updatedLoans.single;
      expect(written.id, 11);
      expect(written.returnedDate, isNull);
      expect(written.lentDate, 1000);
      expect(written.dueDate, 5000);
      expect(markReturned, findsOneWidget);
      expect(notReturned, findsNothing);
      expect(find.text('The loan is open again.'), findsOneWidget);
      expect(
        find.widgetWithText(SnackBarAction, 'Undo'),
        findsNothing,
        reason: 'taking THIS back is "Mark returned" on the same page',
      );
    });

    testWidgets('refused when the one copy is out with somebody else by '
        "now: the rule's sentence, nothing written", (tester) async {
      final vault = _ScriptedVault(
        const VaultData(
          borrowers: [
            borrower,
            Borrower(id: 2, name: 'Meera'),
          ],
          loans: [
            returned,
            Loan(id: 12, itemId: 7, borrowerId: 2, lentDate: 4000),
          ],
        ),
      );
      await pumpUnlocked(tester, vault);

      await tester.tap(notReturned);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Not returned'));
      await tester.pumpAndSettle();

      expect(find.text(reopenRefusedNoCopyFreeMessage), findsOneWidget);
      expect(vault.updatedLoans, isEmpty);
      expect(notReturned, findsOneWidget, reason: 'still in the History');
    });
  });

  // D109: the longer words must hold in the narrow rows. If one of these
  // fails, the words go back to the maintainer; the test is not loosened.
  //
  // What is held at each size: nothing overflows, and no button is pushed
  // off the screen. At the usual text size the words also stand on ONE line.
  // At twice the text size that cannot be asked of a widget test: in the
  // test font every letter is a square, "Mark returned" is then 364 pixels
  // wide, and it stands on two lines. Real letters are about half as wide;
  // whether the words take one line on a phone with its largest font is
  // looked at on the phone (D111).
  for (final (name, size, scale) in [
    ('320 pixels wide', const Size(320, 900), 1.0),
    ('twice the text size', const Size(400, 900), 2.0),
    ('320 pixels wide AND twice the text size', const Size(320, 900), 2.0),
  ]) {
    testWidgets('P4-M3: both loan rows hold their buttons at $name', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final vault = _ScriptedVault(
        const VaultData(borrowers: [borrower], loans: [loan, returned]),
      );
      await pumpUnlocked(
        tester,
        vault,
        books: const {7: 'A title that is long enough to need three dots'},
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(notReturned, 200);
      expect(tester.takeException(), isNull);
      expect(markReturned, findsOneWidget);
      expect(notReturned, findsOneWidget);
      for (final label in ['Mark returned', 'Not returned']) {
        expect(
          liesWithinScreenWidth(tester, find.text(label)),
          isTrue,
          reason: '"$label" is not pushed off the screen',
        );
        if (scale == 1.0) {
          expect(
            standsOnOneLine(tester, find.text(label)),
            isTrue,
            reason: '"$label" stands on one line',
          );
        }
      }
    });
  }

  // N12 regression: the stats Row overflowed at 320px / large text; it is
  // a Wrap now and must lay out without a RenderFlex overflow.
  testWidgets('N12: stats card survives a 320px width', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);

    expect(find.text('Loans'), findsOneWidget);
    expect(find.text('Avg return'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N06: a failed return shows a safe message, no silent no-op', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
      updateResult: left(const StorageFailure('db locked')),
    );
    await pumpUnlocked(tester, vault);

    await tester.tap(markReturned);
    await tester.pumpAndSettle();

    expect(
      find.text('Could not mark this item returned. Please try again.'),
      findsOneWidget,
    );
    // The raw failure reason never reaches the UI (§5).
    expect(find.textContaining('db locked'), findsNothing);
    // Still an active loan: the button stays available for a retry.
    expect(markReturned, findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    // One loan out and one in the History, so both buttons are checked.
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan, returned]),
    );
    await pumpUnlocked(tester, vault);
    await expectMeetsA11yGuidelines(tester);
  });
}
