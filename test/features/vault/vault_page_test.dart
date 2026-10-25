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
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

import '../../support/a11y.dart';
import '../periodicals/application/periodical_fakes.dart';
import 'vault_repository_write_stub.dart';

/// Read-only fake: unlock returns a fixed snapshot; writes aren't exercised by
/// these widget tests (covered by the controller test).
class _StubVault with VaultWriteUnsupported implements VaultRepository {
  _StubVault(this._data);
  final VaultData _data;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(_data);
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vault_page_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget host(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: VaultPage()),
  );

  ProviderContainer container({
    required bool initialized,
    VaultData? data,
    FakeItems? items,
  }) {
    final store = VaultStore(baseDir: tmp.path);
    if (initialized) {
      File(store.dbPath).writeAsBytesSync([0]);
      store.writeBlob('salt.iv.ct');
    }
    final c = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(
          _StubVault(
            data ??
                const VaultData(
                  borrowers: [Borrower(id: 1, name: 'Asha')],
                  loans: [],
                ),
          ),
        ),
        vaultStoreProvider.overrideWith((ref) async => store),
        if (items != null)
          catalogueItemRepositoryProvider.overrideWith((ref) async => items),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('uninitialized shows the set-up form', (tester) async {
    await tester.pumpWidget(host(container(initialized: false)));
    await tester.pumpAndSettle();
    expect(find.text('Create vault'), findsOneWidget);
    expect(find.textContaining('Set up an encrypted vault'), findsOneWidget);
  });

  testWidgets('an existing vault shows the unlock form', (tester) async {
    await tester.pumpWidget(host(container(initialized: true)));
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.textContaining('Enter your vault passphrase'), findsOneWidget);
  });

  // Regression (review 2026-09-03, Blocker): the controller used to flip the
  // session to AsyncLoading during unlock, which UNMOUNTED this form; the
  // failure then landed on a dead widget and the user saw a blank form with
  // no message. The message must be visible after a wrong passphrase.
  testWidgets('a wrong passphrase shows the failure message', (tester) async {
    final store = VaultStore(baseDir: tmp.path);
    File(store.dbPath).writeAsBytesSync([0]);
    store.writeBlob('salt.iv.ct');
    final c = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(_WrongPassphraseVault()),
        vaultStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(host(c));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not-the-passphrase');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(
      find.text('That passphrase did not unlock the vault. Please try again.'),
      findsOneWidget,
    );
    // Still on the unlock form, ready for another try.
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
  });

  testWidgets('setup requires 8+ chars and a matching confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(host(container(initialized: false)));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2), reason: 'passphrase + confirm');

    // Too short: button stays disabled even with a confirmation typed.
    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'short');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create vault'),
          )
          .onPressed,
      isNull,
    );

    // Long enough but mismatched: submit is allowed, then refused with a hint
    // and NO vault is created. (Replacing the text is a non-append edit under
    // the field's contract, so clear each field first like a user would.)
    await tester.tap(find.byIcon(Icons.clear).at(0));
    await tester.pump();
    await tester.enterText(fields.at(0), 'correct-horse-battery');
    await tester.tap(find.byIcon(Icons.clear).at(1));
    await tester.pump();
    await tester.enterText(fields.at(1), 'correct-horse-batterX');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
    await tester.pumpAndSettle();
    expect(find.textContaining('do not match'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create vault'), findsOneWidget);
    expect(VaultStore(baseDir: tmp.path).isInitialized(), isFalse);
  });

  const genericItems = [
    CatalogueItem(
      title: 'Frontline — No 5',
      details: IssueOf(periodicalUid: 'per-1', issueNumber: 5),
    ),
    CatalogueItem(title: 'Chess set', details: OtherItemOf()),
  ];
  for (final item in genericItems) {
    testWidgets('S9: an active ${item.kind} loan uses neutral delete copy', (
      tester,
    ) async {
      final items = FakeItems();
      final storedItem = items.seed(item);
      final c = container(
        initialized: true,
        items: items,
        data: VaultData(
          borrowers: const [Borrower(id: 1, name: 'Asha')],
          loans: [Loan(itemId: storedItem.id, borrowerId: 1, lentDate: 1)],
        ),
      );
      await c.read(vaultSessionControllerProvider.future);
      final unlocked = await c
          .read(vaultSessionControllerProvider.notifier)
          .unlock(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
      expect(unlocked.isRight(), isTrue);
      await tester.pumpWidget(host(c));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This borrower still has items out. Mark those loans returned first.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('books out'), findsNothing);
    });
  }

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(host(container(initialized: false)));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}

/// Unlock always fails with the wrong-passphrase failure.
class _WrongPassphraseVault
    with VaultWriteUnsupported
    implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => left(const WrongPassphraseFailure());
}
