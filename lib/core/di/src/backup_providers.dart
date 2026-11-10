/// Backup/restore DI bindings (AGENTS.md §4; one DI module per feature).
///
/// What lives here: the `.pitabak` archive writer/restorer. Backup is the
/// most cross-cutting feature (it bundles books, wishlist, the vault store
/// and covers), so this module imports the library, vault, database and
/// platform modules — one direction; none of them import backup.
library;

import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/src/availability_providers.dart';
import 'package:pitaka/core/di/src/database_providers.dart';
import 'package:pitaka/core/di/src/library_providers.dart';
import 'package:pitaka/core/di/src/network_providers.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/core/di/src/publish_state_providers.dart';
import 'package:pitaka/core/di/src/vault_providers.dart';
import 'package:pitaka/core/storage/active_data_generation.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_work_area.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/backup/infrastructure/file_backup_work_area.dart';
import 'package:pitaka/features/backup/infrastructure/restore_backup.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backup_providers.g.dart';

/// The private folders backups are built in (backup rework BR4): one new
/// folder per build under the app's temporary directory, and the one place
/// that removes them again.
///
/// keepAlive (justified): this object remembers which folders are IN USE by
/// a build of this app session, so that a sweep never deletes a backup that
/// is being written or shared. An auto-disposed instance would forget that
/// between two reads.
@Riverpod(keepAlive: true)
Future<BackupWorkArea> backupWorkArea(BackupWorkAreaRef ref) async {
  final temp = await ref.watch(appTempDirProvider.future);
  final docs = await ref.watch(appDocsDirProvider.future);
  return FileBackupWorkArea(
    tempRoot: temp.path,
    // Where versions before BR4 built a backup. Only removed, never written.
    legacyWorkDir: p.join(docs.path, 'backup_create_work'),
  );
}

/// One-time clean-up per app start: removes what a backup left behind when
/// the app was killed in the middle of it (a plain copy of the library).
/// Triggered next to the cover sweep, by the Library screen's first build.
///
/// keepAlive (justified): "once per app session" is the whole point, as for
/// `orphanCoverSweep`. The result is not shown anywhere: when something
/// could not be removed, the next start (and the next backup) tries again.
@Riverpod(keepAlive: true)
Future<void> staleBackupWorkSweep(StaleBackupWorkSweepRef ref) async {
  final workArea = await ref.watch(backupWorkAreaProvider.future);
  await workArea.sweep();
}

/// Creates a `.pitabak` backup of the whole local catalog (#28B): Room-format
/// books/wishlist written from Drift, the persistent vault copied verbatim, and
/// covers bundled — plus the library identity and the saved-libraries list
/// (docs/ARCHITECTURE.md §3 network) and the website publishing record (plan
/// CV6), all gathered best-effort. Returns where the finished archive file
/// is, for the UI to share and then discard.
@riverpod
Future<CreateBackupUseCase> createBackupUseCase(
  CreateBackupUseCaseRef ref,
) async {
  final books = await ref.watch(catalogueItemRepositoryProvider.future);
  final wishlist = await ref.watch(wishlistRepositoryProvider.future);
  final store = await ref.watch(vaultStoreProvider.future);
  final coversDir = await ref.watch(coversDirProvider.future);
  // N10-c: the writer opens SQLite itself inside its worker isolate (an
  // `sqlite3.open` tear-off is not sendable across isolates).
  final writer = BackupArchiveWriter(vaultStore: store, coversDir: coversDir);
  return CreateBackupUseCase(
    books: books,
    wishlist: wishlist,
    periodicals: await ref.watch(periodicalRepositoryProvider.future),
    writer: writer,
    workArea: await ref.watch(backupWorkAreaProvider.future),
    // The identity goes through the namespace port (SettingsController, the
    // single serialised settings writer — N07), never the raw repository.
    namespace: ref.read(settingsControllerProvider.notifier),
    network: await ref.watch(networkRepositoryProvider.future),
    publishState: await ref.watch(publishStateBackupSourceProvider.future),
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
    // Plan J9 (ADR 0019 Decision 3): the restored ids may name other books,
    // so the published item keys are marked unusable inside the publish
    // queue BEFORE the switch. If that cannot be saved, the switch does not
    // happen and the restore fails with the device unchanged. Resolved only
    // here, when a restore really switches, never while building.
    activate: (generation) async {
      final keys = await ref.read(catalogueKeysResetProvider.future);
      return keys.beforeIdsChange(
        () => ref
            .read(activeDataGenerationProvider.notifier)
            .activate(generation),
      );
    },
    workDir: p.join(dir.path, 'restore_work'),
    replacementGuard: ref.read(vaultSessionControllerProvider.notifier),
  );
}
