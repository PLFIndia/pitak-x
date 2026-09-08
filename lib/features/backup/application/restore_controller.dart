/// UI-facing restore controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the Restore screen drives: idle until `restore`
/// is called with the chosen archive bytes and a `SecretBytes` passphrase. It
/// runs `RestoreBackup` and maps the `Either<Failure, RestoreSummary>` to
/// loading / data / error so the UI can render a safe message.
///
/// Secret ownership (§6.1): this controller takes ownership of the passphrase
/// and disposes it in a `finally` once the restore completes — success or
/// failure — so the bytes never outlive the call.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_controller.g.dart';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
@riverpod
class RestoreController extends _$RestoreController {
  @override
  FutureOr<RestoreSummary?> build() => null; // idle until restore() is run

  /// Inspects the archive's manifest WITHOUT restoring (N13): the Restore
  /// screen runs this right after a file is picked so it can show what the
  /// backup contains and ask for a passphrase only when the archive actually
  /// carries an encrypted vault.
  Future<Either<Failure, BackupManifest>> inspectArchive(
    Uint8List archiveBytes,
  ) async {
    final restorer = await ref.read(restoreBackupProvider.future);
    return restorer.inspectArchive(archiveBytes);
  }

  /// Restores [archiveBytes] using [passphrase]. Takes ownership of
  /// [passphrase] and disposes it when done. State becomes loading, then either
  /// `AsyncData(summary)` or `AsyncError(Failure)`.
  ///
  /// [passphrase] is null only for vault-free archives (N13); the restorer
  /// fails closed if a vault is present but no passphrase was supplied.
  Future<void> restore({
    required Uint8List archiveBytes,
    SecretBytes? passphrase,
  }) async {
    state = const AsyncLoading();
    try {
      final restorer = await ref.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archiveBytes,
        passphrase: passphrase,
      );
      state = result.match(
        (failure) => AsyncError(failure, StackTrace.current),
        (summary) {
          // Restore switched the app onto a new data generation (M02): the
          // vault-store provider has already been republished, and the
          // session controller WATCHES it, so it rebuilds on its own (wiping
          // any held secret via ref.onDispose). The explicit invalidation is
          // kept as belt-and-braces for the keepAlive session: it costs one
          // rebuild and guarantees the vault page never shows a stale
          // "Create vault"/"Unlock" state, even if a future provider change
          // breaks the watch chain.
          ref.invalidate(vaultSessionControllerProvider);
          return AsyncData(summary);
        },
      );
    } finally {
      // §6.1: wipe the passphrase regardless of outcome (null for vault-free
      // archives — nothing to wipe).
      passphrase?.dispose();
    }
  }
}
