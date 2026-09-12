import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/infrastructure/drift_book_repository.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
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
  /// [database]: an injected in-memory catalogue (merge/session tests).
  /// [generations]: instead run on the REAL M02 storage chain — a data
  /// generation on disk with a file-backed catalogue — which restore tests
  /// need because restore snapshots the active generation's catalogue FILE and
  /// switches generations. [openCatalogue] lets those tests inject faults into
  /// the builder generation's catalogue.
  ReplacementHarness({
    AppDatabase? database,
    bool generations = false,
    AppDatabase Function(String path)? openCatalogue,
  }) : usesGenerations = generations {
    directory = Directory.systemTemp.createTempSync('m03_integration_');
    if (generations) {
      final store = DataGenerations(docsDir: directory.path);
      final active = store.open();
      db = AppDatabase(NativeDatabase(File(active.catalogueDbPath)));
      this.store = VaultStore(baseDir: active.vaultDir);
    } else {
      db = database ?? AppDatabase(NativeDatabase.memory());
      store = VaultStore(baseDir: directory.path);
    }
    books = DriftBookRepository(db);
    container = ProviderContainer(
      overrides: [
        appDocsDirProvider.overrideWith((ref) async => directory),
        if (!generations) ...[
          // The real coversDir resolves through the active data generation,
          // whose startup adoption would MOVE this harness's hand-placed flat
          // vault files into data/gen-000001. Pin the covers path instead so
          // the fixture's flat layout stays exactly where the tests put it.
          coversDirProvider.overrideWith(
            (ref) async => '${directory.path}/covers',
          ),
          appDatabaseProvider.overrideWith((ref) async => db),
          vaultStoreProvider.overrideWith((ref) async => store),
        ],
        if (generations && openCatalogue != null)
          restoreBackupProvider.overrideWith((ref) async {
            final real = await ref.watch(dataGenerationsProvider.future);
            final dir = await ref.watch(appDocsDirProvider.future);
            return RestoreBackup(
              vault: vault,
              generations: real,
              activeGeneration: () =>
                  ref.read(activeDataGenerationProvider.future),
              activate: (generation) => ref
                  .read(activeDataGenerationProvider.notifier)
                  .activate(generation),
              openCatalogue: openCatalogue,
              workDir: '${dir.path}/restore_work',
              replacementGuard: ref.read(
                vaultSessionControllerProvider.notifier,
              ),
            );
          }),
        bookRepositoryProvider.overrideWith((ref) async => books),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
        vaultRepositoryProvider.overrideWithValue(vault),
      ],
    );
  }

  /// Whether this harness runs on the real generation chain (see constructor).
  final bool usesGenerations;
  late final Directory directory;
  late final AppDatabase db;
  late final DriftBookRepository books;
  late final VaultStore store;
  late final ProviderContainer container;
  final vault = ReplacementVault();
  final settings = ReplacementSettings();

  /// The covers directory of the CURRENT generation (or the flat one).
  Future<String> coversDir() => container.read(coversDirProvider.future);

  /// The book repository over the CURRENT catalogue. After a restore the
  /// active generation has moved, so the pre-restore [books] handle would
  /// read the deleted old file; this one follows the switch.
  Future<DriftBookRepository> currentBooks() async {
    if (!usesGenerations) return books;
    final database = await container.read(appDatabaseProvider.future);
    return DriftBookRepository(database);
  }

  /// The vault store of the CURRENT generation (or the flat one).
  Future<VaultStore> currentStore() async =>
      usesGenerations ? container.read(vaultStoreProvider.future) : store;

  VaultSessionController get session =>
      container.read(vaultSessionControllerProvider.notifier);

  /// The library identity port (N07): the container's REAL
  /// `SettingsController` over [settings], as production wires it.
  LibraryNamespace get namespace =>
      container.read(settingsControllerProvider.notifier);

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

  Future<Either<Failure, MergeResult>> overwrite(List<Book> incoming) async {
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
    if (usesGenerations && container.exists(appDatabaseProvider)) {
      await (await container.read(appDatabaseProvider.future)).close();
    }
    container.dispose();
    await db.close();
    directory.deleteSync(recursive: true);
  }
}
