/// Review finding N12 widget test: the lend screen's borrower dropdown
/// must constrain long names at narrow widths / large text instead of
/// overflowing (isExpanded + ellipsis).
library;

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
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';

import '../../support/a11y.dart';
import 'vault_repository_write_stub.dart';

class _ReadOnlyVault with VaultWriteUnsupported implements VaultRepository {
  _ReadOnlyVault(this.data);
  final VaultData data;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(data);

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async => right('test-blob');
}

class _UnavailableItems implements CatalogueItemRepository {
  _UnavailableItems(this.result);

  final Either<Failure, CatalogueItem?> result;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('lend_page_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('N12: a very long borrower name does not overflow at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final longName = 'A' * 120;
    final data = VaultData(
      borrowers: [Borrower(id: 1, name: longName)],
      loans: const [],
    );
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => _ReadOnlyVault(data)),
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
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Godaan'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text('Lend book'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);

    // Open the menu: the 120-char item must ellipsize, not overflow.
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    expect(find.textContaining('AAAA'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Select the long-named borrower: the closed field shows the name
    // ellipsized inside 320px (isExpanded), still no overflow.
    await tester.tap(find.textContaining('AAAA').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('S9: the locked lending screen uses neutral item copy', (
    tester,
  ) async {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWith((ref) async => store),
          vaultRepositoryProvider.overrideWith(
            (ref) => _ReadOnlyVault(VaultData.empty),
          ),
        ],
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Chess set'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text('Unlock the vault to lend an item.'), findsOneWidget);
    expect(find.textContaining('book'), findsNothing);
  });

  Future<void> expectLendFailure(
    WidgetTester tester,
    _UnavailableItems items,
    String expected,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith(
          (ref) => _ReadOnlyVault(VaultData.empty),
        ),
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
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Frontline — No 5'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Asha');
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    expect(find.textContaining('book'), findsNothing);
  }

  testWidgets('S9: a missing item uses neutral lending error copy', (
    tester,
  ) async {
    await expectLendFailure(
      tester,
      _UnavailableItems(right(null)),
      'That item or borrower no longer exists.',
    );
  });

  testWidgets('S9: a lending read failure uses neutral error copy', (
    tester,
  ) async {
    await expectLendFailure(
      tester,
      _UnavailableItems(left(const StorageFailure('private database detail'))),
      'Could not lend the item. Please try again.',
    );
    expect(find.textContaining('private database detail'), findsNothing);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    const data = VaultData(
      borrowers: [Borrower(id: 1, name: 'Asha')],
      loans: [],
    );
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => _ReadOnlyVault(data)),
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
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Godaan'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
