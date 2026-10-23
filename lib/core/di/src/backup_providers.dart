/// Backup/restore DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the `.pitabak` archive writer/restorer. Backup is the
/// most cross-cutting feature (it bundles books, wishlist, the vault store
/// and covers), so this module imports the library, vault, database and
/// platform modules — one direction; none of them import backup.
library;

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/network_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/vault_providers.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backup_providers.g.dart';

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled — plus the library identity and the saved-libraries list
/// (docs/ARCHITECTURE.md §3 network, both gathered best-effort). Returns the archive
/// bytes for the UI to save.
@riverpod
Future<CreateBackupUseCase> createBackupUseCase(
  CreateBackupUseCaseRef ref,
) async {
  final books = await ref.watch(catalogueItemRepositoryProvider.future);
  final wishlist = await ref.watch(wishlistRepositoryProvider.future);
  final store = await ref.watch(vaultStoreProvider.future);
  final coversDir = await ref.watch(coversDirProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  // N10-c: the writer opens SQLite itself inside its worker isolate (an
  // `sqlite3.open` tear-off is not sendable across isolates).
  final writer = BackupArchiveWriter(vaultStore: store, coversDir: coversDir);
  return CreateBackupUseCase(
    books: books,
    wishlist: wishlist,
    periodicals: await ref.watch(periodicalRepositoryProvider.future),
    writer: writer,
    workDir: p.join(dir.path, 'backup_create_work'),
    // The identity goes through the namespace port (SettingsController, the
    // single serialised settings writer — N07), never the raw repository.
    namespace: ref.read(settingsControllerProvider.notifier),
    network: await ref.watch(networkRepositoryProvider.future),
  );
}

/// Backup-archive restorer (authoritative overwrite of local state).
///
/// M02: restore builds a NEW data generation and switches to it atomically
/// through [ActiveDataGeneration.activate], which republishes the paths so the
/// database, covers and vault-store providers all rebuild onto the new set.
/// The active generation is resolved lazily (`ref.read` at call time), not
/// watched: watching would rebuild this restorer mid-switch for no benefit.
@riverpod
Future<RestoreBackup> restoreBackup(RestoreBackupRef ref) async {
  final vault = ref.watch(vaultRepositoryProvider);
  final generations = await ref.watch(dataGenerationsProvider.future);
  final dir = await ref.watch(appDocsDirProvider.future);
  return RestoreBackup(
    vault: vault,
    generations: generations,
    activeGeneration: () => ref.read(activeDataGenerationProvider.future),
    activate: (generation) =>
        ref.read(activeDataGenerationProvider.notifier).activate(generation),
    workDir: p.join(dir.path, 'restore_work'),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
  );
}
