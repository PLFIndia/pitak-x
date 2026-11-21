import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

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

  /// Where restores of this fixture stage their databases: one `run-…`
  /// folder per restore under [restoreWorkRoot] (BR6). Shared by every
  /// restorer of the fixture, as the app shares one per session.
  late final RunFolders workFolders = RunFolders(
    rootPath: restoreWorkRoot,
    prefix: 'run',
  );

  /// The folder the run folders of restores lie in. After a restore, on
  /// every way out, it holds no run folder (see [restoreRunFolders]).
  String get restoreWorkRoot => p.join(docsDir, 'tmp', 'restore_work');

  /// The run folders that exist right now. Empty before and after a restore.
  List<String> restoreRunFolders() {
    final root = Directory(restoreWorkRoot);
    if (!root.existsSync()) return const [];
    return [for (final entity in root.listSync()) p.basename(entity.path)];
  }

  int _archives = 0;

  /// Writes [bytes] to a new file and returns its path: "the backup file
  /// the user chose", as a restore gets it since BR6. The files lie in a
  /// folder of their own next to the generations, so a test that lists the
  /// data folders does not see them.
  String archiveFile(List<int> bytes) {
    final folder = Directory(p.join(docsDir, 'tmp', 'chosen'))
      ..createSync(recursive: true);
    final path = p.join(folder.path, 'archive-${_archives++}');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Builds a restorer over this fixture. [activate] defaults to the real
  /// pointer switch (recorded in [switched]).
  RestoreBackup restorer({
    required VaultRepository vault,
    required CatalogueReplacementGuard guard,
    Future<DataGeneration> Function(DataGeneration)? activate,
    CatalogueOpener? openCatalogue,
    LegacyDbOpener? openLegacyDb,
    BackupLimits limits = BackupLimits.current,
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
    openLegacyDb: openLegacyDb ?? _defaultLegacyOpen,
    workFolders: workFolders,
    limits: limits,
    replacementGuard: guard,
  );

  static AppDatabase _defaultOpen(String path) =>
      AppDatabase(NativeDatabase(File(path)));

  /// Same as production's default legacy opener (read-only).
  static CommonDatabase _defaultLegacyOpen(String path) =>
      sqlite3.open(path, mode: OpenMode.readOnly);

  /// The generation currently named by `CURRENT` (re-read from disk).
  DataGeneration current() => generations.open();

  /// Opens the catalogue of the CURRENT generation. Caller closes it.
  AppDatabase openActiveCatalogue() =>
      AppDatabase(NativeDatabase(File(current().catalogueDbPath)));

  /// The vault store of the CURRENT generation.
  VaultStore activeStore() => VaultStore(baseDir: current().vaultDir);
}
