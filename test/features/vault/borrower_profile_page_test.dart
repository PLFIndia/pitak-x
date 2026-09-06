/// N06 widget tests (astra-review.md): the borrower profile must resolve
/// book titles through a read model (not "Book #id"), surface per-return
/// progress and typed failures, and treat repeat returns as no-ops.
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
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_profile_page.dart';

import 'vault_repository_write_stub.dart';

/// Vault fake with a scripted read result and a recordable, scriptable
/// `updateLoan` (the op under test).
class _ScriptedVault with VaultWriteUnsupported implements VaultRepository {
  _ScriptedVault(this.data, {this.updateResult});

  final VaultData data;
  Either<Failure, Unit>? updateResult;
  final List<Loan> updatedLoans = [];

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
    updatedLoans.add(loan);
    return updateResult ?? right(unit);
  }
}

/// Minimal book repo serving titles for the read model.
class _TitleBooks implements BookRepository {
  _TitleBooks(this.byId);
  final Map<int, String> byId;

  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(byId.containsKey(id) ? Book(id: id, title: byId[id]!) : null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  const borrower = Borrower(id: 1, name: 'Asha');
  const loan = Loan(id: 10, bookId: 7, borrowerId: 1, lentDate: 1000);

  setUp(() => tmp = Directory.systemTemp.createTempSync('profile_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Builds an UNLOCKED session over [vault] and pumps the profile page.
  Future<ProviderContainer> pumpUnlocked(
    WidgetTester tester,
    _ScriptedVault vault, {
    Map<int, String> books = const {7: 'Godaan'},
  }) async {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => vault),
        bookRepositoryProvider.overrideWith((ref) async => _TitleBooks(books)),
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
        child: const MaterialApp(home: BorrowerProfilePage(borrowerId: 1)),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('N06: loan rows show the book title, not the internal id', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);

    expect(find.text('Godaan'), findsOneWidget);
    expect(find.textContaining('Book #7'), findsNothing);
  });

  testWidgets('N06: a missing book falls back to "Book #id"', (tester) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault, books: const {});

    expect(find.text('Book #7'), findsOneWidget);
  });

  testWidgets('N06: Return writes the loan and moves it to History', (
    tester,
  ) async {
    final vault = _ScriptedVault(
      const VaultData(borrowers: [borrower], loans: [loan]),
    );
    await pumpUnlocked(tester, vault);

    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();

    expect(vault.updatedLoans, hasLength(1));
    expect(vault.updatedLoans.single.id, 10);
    expect(vault.updatedLoans.single.returnedDate, isNotNull);
    // The row moved to History (returned label visible, Return button gone).
    expect(find.textContaining('Returned'), findsOneWidget);
    expect(find.text('Return'), findsNothing);
  });

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

    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not return this book'), findsOneWidget);
    // The raw failure reason never reaches the UI (§5).
    expect(find.textContaining('db locked'), findsNothing);
    // Still an active loan: the button stays available for a retry.
    expect(find.text('Return'), findsOneWidget);
  });
}
