/// N12 widget test (astra-review.md): the lend screen's borrower dropdown
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
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';

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
}
