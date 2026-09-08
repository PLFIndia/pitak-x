import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

/// A real on-disk data generation for restore tests (M02).
///
/// Restore no longer edits the live catalogue in place: it snapshots the
/// active generation's `pitaka.db` file, so tests need a file-backed
/// catalogue, and they read results from whichever generation is active
/// AFTER the restore ([openActiveCatalogue]). `onSwitch` lets a test observe
/// (or veto) the atomic switch the DI layer would perform through
/// `ActiveDataGeneration.activate`.
final class GenerationFixture {
  GenerationFixture(Directory docs) : docsDir = docs.path {
    generations = DataGenerations(docsDir: docsDir);
    active = generations.open();
    db = AppDatabase(NativeDatabase(File(active.catalogueDbPath)));
    store = VaultStore(baseDir: active.vaultDir);
  }

  /// Root the generations live under (`<docsDir>/data`).
  final String docsDir;

  /// The generation store.
  late final DataGenerations generations;

  /// The generation active when the fixture was created (pre-restore state).
  late final DataGeneration active;

  /// A live handle on the pre-restore catalogue. Close it in tearDown.
  late final AppDatabase db;

  /// The pre-restore vault store.
  late final VaultStore store;

  /// Generations activated by restores, in order.
  final switched = <DataGeneration>[];

  /// Absolute path of the pre-restore covers directory.
  String get coversDir => active.coversDir;

  /// Builds a restorer over this fixture. [activate] defaults to the real
  /// pointer switch (recorded in [switched]).
  RestoreBackup restorer({
    required VaultRepository vault,
    required CatalogueReplacementGuard guard,
    Future<DataGeneration> Function(DataGeneration)? activate,
    CatalogueOpener? openCatalogue,
  }) => RestoreBackup(
    vault: vault,
    generations: generations,
    // Resolve lazily: after one restore the active generation has moved.
    activeGeneration: () async => switched.isEmpty ? active : switched.last,
    activate:
        activate ??
        (generation) async {
          final now = generations.activate(generation);
          switched.add(now);
          return now;
        },
    openCatalogue: openCatalogue ?? _defaultOpen,
    workDir: p.join(docsDir, 'restore_work'),
    replacementGuard: guard,
  );

  static AppDatabase _defaultOpen(String path) =>
      AppDatabase(NativeDatabase(File(path)));

  /// The generation currently named by `CURRENT` (re-read from disk).
  DataGeneration current() => generations.open();

  /// Opens the catalogue of the CURRENT generation. Caller closes it.
  AppDatabase openActiveCatalogue() =>
      AppDatabase(NativeDatabase(File(current().catalogueDbPath)));

  /// The vault store of the CURRENT generation.
  VaultStore activeStore() => VaultStore(baseDir: current().vaultDir);
}
