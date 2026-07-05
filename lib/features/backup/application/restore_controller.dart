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

import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_controller.g.dart';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
@riverpod
class RestoreController extends _$RestoreController {
  @override
  FutureOr<RestoreSummary?> build() => null; // idle until restore() is run

  /// Restores [archiveBytes] using [passphrase]. Takes ownership of
  /// [passphrase] and disposes it when done. State becomes loading, then either
  /// `AsyncData(summary)` or `AsyncError(Failure)`.
  Future<void> restore({
    required Uint8List archiveBytes,
    required SecretBytes passphrase,
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
          // Restore authoritatively replaced device state, including the
          // on-disk vault artifacts (borrowers.db + wrapped-key blob) when the
          // archive carried one. The session controller is keepAlive and
          // decided "uninitialized vs locked" once at build(), so it must be
          // rebuilt or the vault page keeps showing "Create vault".
          // Invalidation also wipes any held session secret via its
          // ref.onDispose (fail-closed: a pre-restore passphrase no longer
          // matches the restored vault key).
          ref.invalidate(vaultSessionControllerProvider);
          return AsyncData(summary);
        },
      );
    } finally {
      // §6.1: wipe the passphrase regardless of outcome.
      passphrase.dispose();
    }
  }
}
