/// Takes the borrowers vault for a backup, at a moment when nothing writes
/// to it (backup infrastructure; backup rework BR4 rider 2, review finding
/// P1-m1, decision D17).
///
/// WHY THIS FILE EXISTS (beginner note): the vault is one SQLite database
/// file, and a backup carries a copy of it. Two things could make that copy
/// wrong without anybody noticing:
///
///  1. a borrower or a loan is saved at the very moment the file is copied.
///     The copy is then half old and half new;
///  2. the app was killed in the middle of a vault write. SQLite then leaves
///     a side file (`borrowers.db-journal`) next to the database, and until
///     the vault is opened again the database file ALONE is not a whole
///     database. Tried out for this work: such a file can still open, and
///     show a wrong list of borrowers.
///
/// The answer to 1 is the [VaultIdleGate]: everything here happens while no
/// vault operation of this app runs. The answer to 2 is a rule: when a side
/// file is there, the vault is NOT taken along, and the backup says so
/// ([BackupVaultSnapshot.leftOut]). A backup of everything else that says
/// what is missing is better than no backup, and far better than a backup
/// with a vault that looks fine and is not.
///
/// This file copies nothing itself: the store does
/// (`VaultArtifactsStore.snapshotDatabaseTo`). It only decides, and keeps
/// the steps in one place and in one order.
library;

import 'package:pitaka/features/vault/domain/vault_artifacts_store.dart';
import 'package:pitaka/features/vault/domain/vault_idle_gate.dart';

/// What the vault part of one backup came to. One of three things:
///
///  - there is no vault on this phone ([BackupVaultSnapshot.none]);
///  - the vault was copied ([BackupVaultSnapshot.copied]);
///  - there is a vault, but it was left out ([BackupVaultSnapshot.leftOut]).
final class BackupVaultSnapshot {
  /// No vault has been set up: nothing to carry, and nothing to say.
  const BackupVaultSnapshot.none()
    : copyPath = null,
      blob = null,
      leftOut = false;

  /// The vault database was copied to [copyPath]; [blob] is its wrapped key
  /// (ciphertext), read in the same turn. The store's type allows a null
  /// here; a vault that exists has a key file, so it is not expected.
  const BackupVaultSnapshot.copied({
    required String this.copyPath,
    required this.blob,
  }) : leftOut = false;

  /// A vault exists but does not go into this backup, because a side file
  /// lay next to it. The user is told (decision D17).
  const BackupVaultSnapshot.leftOut()
    : copyPath = null,
      blob = null,
      leftOut = true;

  /// Where the private copy of `borrowers.db` lies. Null when no vault goes
  /// into this backup.
  final String? copyPath;

  /// The vault's wrapped key, already ciphertext. Null when no vault goes
  /// into this backup.
  final String? blob;

  /// True when a vault exists and was left out on purpose.
  final bool leftOut;
}

/// Looks at the vault of [store] and, if it can be trusted, copies its
/// database to [copyPath] (a file in a folder the caller owns).
///
/// Every step runs inside ONE turn at the [gate], so that "is there a
/// vault", the copy and the key all describe the same moment:
///
///  1. no vault: done;
///  2. a side file next to the database: the vault is left out;
///  3. copy the database;
///  4. a side file now: the vault is left out after all. Nothing of this
///     app can write while the gate is held, so this cannot happen. It is
///     the check that the gate does what it promises: if a later change
///     ever lets a write slip past the line, the backup notices instead of
///     packing a half-written vault;
///  5. read the key.
///
/// Completes with an error when the copy fails (for example when the disk
/// is full); the gate is released then as well. When the vault is left out
/// after step 3, the copy stays at [copyPath] unused; the caller removes
/// its folder anyway.
Future<BackupVaultSnapshot> snapshotVaultForBackup({
  required VaultArtifactsStore store,
  required VaultIdleGate gate,
  required String copyPath,
}) => gate.whileVaultIdle(() async {
  if (!store.isInitialized()) return const BackupVaultSnapshot.none();
  if (store.hasUnfinishedWrite()) return const BackupVaultSnapshot.leftOut();
  await store.snapshotDatabaseTo(copyPath);
  if (store.hasUnfinishedWrite()) return const BackupVaultSnapshot.leftOut();
  return BackupVaultSnapshot.copied(copyPath: copyPath, blob: store.readBlob());
});
