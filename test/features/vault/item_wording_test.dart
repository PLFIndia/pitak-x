import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/pending_snapshot.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_edit_page.dart';
import 'package:pitaka/features/vault/presentation/pages/pending_page.dart';

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

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('item_wording_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('S9: Pending labels a loan row as Item #id', (tester) async {
    const snapshot = PendingSnapshot(
      overdue: [Loan(id: 1, itemId: 7, borrowerId: 2, lentDate: 1)],
      dueSoon: [],
      staleMetadataBooks: [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingSnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(home: PendingPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Item #7'), findsOneWidget);
    expect(find.text('Book #7'), findsNothing);
  });

  testWidgets('S9: borrower edit labels a loan row as Item #id', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const borrower = Borrower(id: 2, name: 'Asha');
    const data = VaultData(
      borrowers: [borrower],
      loans: [Loan(id: 1, itemId: 7, borrowerId: 2, lentDate: 1)],
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
        child: const MaterialApp(home: BorrowerEditPage(existing: borrower)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Item #7'), findsOneWidget);
    expect(find.text('Book #7'), findsNothing);
  });
}
