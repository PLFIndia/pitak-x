import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import '../vault/vault_repository_write_stub.dart';

class ReplacementVault with VaultWriteUnsupported implements VaultRepository {
  List<Borrower> borrowers = [const Borrower(id: 1, name: 'Synthetic')];
  final List<Loan> loans = [];
  Failure? readFailure;
  Future<void> Function()? onRead;
  Future<void> Function()? onCreate;
  Future<void> Function()? onInsert;
  int writes = 0;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    await onRead?.call();
    final failure = readFailure;
    return failure == null
        ? right(VaultData(borrowers: List.of(borrowers), loans: List.of(loans)))
        : left(failure);
  }

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async {
    await onCreate?.call();
    File(dbPath).writeAsBytesSync([1]);
    return right('synthetic.blob.only');
  }

  @override
  Future<Either<Failure, int>> insertLoan({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
    required Loan loan,
  }) async {
    await onInsert?.call();
    writes++;
    loans.add(loan.copyWith(id: loans.length + 1));
    return right(loans.length);
  }
}

class ReplacementSettings implements SettingsRepository {
  String id = 'local';
  String name = 'Local';
  Failure? failure;

  @override
  Future<AppSettings> load() async =>
      AppSettings(libraryId: id, libraryName: name);

  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async => right(id);

  @override
  Future<Either<Failure, Unit>> setLibraryId(String value) async {
    if (failure != null) return left(failure!);
    id = value;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setLibraryName(String value) async {
    name = value;
    return right(unit);
  }

  // Unexpected use of any other settings method must fail this fixture.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReplacementHarness {
  ReplacementHarness({AppDatabase? database}) {
    directory = Directory.systemTemp.createTempSync('m03_integration_');
    db = database ?? AppDatabase(NativeDatabase.memory());
    store = VaultStore(baseDir: directory.path);
    books = DriftBookRepository(db);
    container = ProviderContainer(
      overrides: [
        appDocsDirProvider.overrideWith((ref) async => directory),
        appDatabaseProvider.overrideWith((ref) async => db),
        bookRepositoryProvider.overrideWith((ref) async => books),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        vaultRepositoryProvider.overrideWithValue(vault),
        vaultStoreProvider.overrideWith((ref) async => store),
      ],
    );
  }
  late final Directory directory;
  late final AppDatabase db;
  late final DriftBookRepository books;
  late final VaultStore store;
  late final ProviderContainer container;
  final vault = ReplacementVault();
  final settings = ReplacementSettings();

  VaultSessionController get session =>
      container.read(vaultSessionControllerProvider.notifier);

  Future<void> initialize({bool exists = true, bool unlock = true}) async {
    if (exists) {
      File(store.dbPath).writeAsBytesSync([1, 2, 3]);
      store.writeBlob('synthetic.blob.only');
    }
    await container.read(vaultSessionControllerProvider.future);
    if (exists && unlock) {
      final result = await session.unlock(secret());
      if (result.isLeft()) throw StateError('Fixture unlock failed');
    }
  }

  static SecretBytes secret() =>
      SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));

  Future<Either<Failure, Unit>> overwrite(List<Book> incoming) async {
    final useCase = await container.read(mergeLibraryUseCaseProvider.future);
    return useCase.applyOverwrite(
      MergeDiffersDecision(
        incomingBooks: incoming,
        incomingLibraryId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        incomingLibraryName: 'Incoming',
        localLibraryName: 'Local',
        localIsEmpty: false,
      ),
    );
  }

  Future<void> close() async {
    container.dispose();
    await db.close();
    directory.deleteSync(recursive: true);
  }
}
