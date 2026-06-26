import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';

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

  ProviderContainer container({required bool initialized}) {
    final store = VaultStore(baseDir: tmp.path);
    if (initialized) {
      File(store.dbPath).writeAsBytesSync([0]);
      store.writeBlob('salt.iv.ct');
    }
    final c = ProviderContainer(
      overrides: [
        vaultRepositoryProvider.overrideWithValue(
          _StubVault(
            const VaultData(
              borrowers: [Borrower(id: 1, name: 'Asha')],
              loans: [],
            ),
          ),
        ),
        vaultStoreProvider.overrideWith((ref) async => store),
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
}
