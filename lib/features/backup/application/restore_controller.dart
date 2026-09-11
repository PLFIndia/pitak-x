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
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_controller.g.dart';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
///
/// Lifecycle ownership (N11): a restore is an authoritative overwrite that
/// must FINISH once started, so the run is owned here, not by the page —
/// modelled on `PublishController`/`ImportController`:
///  - `ref.keepAlive()` pins this autoDispose element for the run, so
///    navigating away mid-restore cannot dispose it, swallow the terminal
///    state, or let a rebuilt page start a SECOND concurrent restore;
///  - `_running` refuses a second call outright;
///  - an unexpected throw becomes a typed `AsyncError(UnexpectedFailure)`
///    instead of escaping into the page's unawaited future;
///  - the post-success list refresh is invalidated HERE (next to the vault
///    session invalidation), so it happens even when the page is gone.
@riverpod
class RestoreController extends _$RestoreController {
  /// True while a restore runs — a second call is refused (N11).
  bool _running = false;

  /// True after this element was disposed (container teardown mid-run).
  bool _disposed = false;

  @override
  FutureOr<RestoreSummary?> build() {
    ref.onDispose(() => _disposed = true);
    return null; // idle until restore() is run
  }

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
    if (_running || _disposed) {
      // Refused — but the caller already handed over the secret, so wipe it
      // anyway: ownership transfers at call time, never leaks (§6.1).
      passphrase?.dispose();
      return;
    }
    _running = true;
    // keepAlive for the duration of the run (PublishController pattern):
    // without it, popping the page mid-restore lets autoDispose destroy this
    // element while the restorer is still working.
    final link = ref.keepAlive();
    state = const AsyncLoading();
    try {
      final restorer = await ref.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archiveBytes,
        passphrase: passphrase,
      );
      if (!_disposed) {
        state = result.match(
          (failure) => AsyncError(failure, StackTrace.current),
          (summary) {
            ref
              // Restore switched the app onto a new data generation (M02): the
              // vault-store provider has already been republished, and the
              // session controller WATCHES it, so it rebuilds on its own
              // (wiping any held secret via ref.onDispose). The explicit
              // invalidation is kept as belt-and-braces for the keepAlive
              // session: it costs one rebuild and guarantees the vault page
              // never shows a stale "Create vault"/"Unlock" state, even if a
              // future provider change breaks the watch chain.
              ..invalidate(vaultSessionControllerProvider)
              // N11: restore replaces books AND the wishlist (M15) — refresh
              // both lists from HERE so a popped Restore page cannot leave the
              // lists underneath stale (this used to be the page's job, lost
              // with its `ref`).
              ..invalidate(libraryControllerProvider)
              ..invalidate(wishlistControllerProvider);
            return AsyncData(summary);
          },
        );
        if (state.hasValue) await _clearDanglingLogoRef();
      }
    } on Object catch (_, stack) {
      // Unexpected plugin/storage throw → typed terminal state, never an
      // unhandled error in the page's unawaited future (§5, N11).
      if (!_disposed) {
        state = AsyncError(const UnexpectedFailure('Restore failed.'), stack);
      }
    } finally {
      // §6.1: wipe the passphrase regardless of outcome (null for vault-free
      // archives — nothing to wipe).
      passphrase?.dispose();
      _running = false;
      link.close();
    }
  }

  /// N04 (S9 dangling-state note): settings are NOT part of a backup, so a
  /// restore can leave the library-logo reference pointing at a cover file
  /// the restored set does not have. Clear such a dangling reference so
  /// Settings does not keep pointing at a file that will never come back.
  ///
  /// Fail-open on purpose: a settings-write Left leaves the reference in
  /// place, which the logo widget already tolerates (it falls back to the
  /// default icon when the file is missing) — the pre-fix status quo.
  Future<void> _clearDanglingLogoRef() async {
    // State, not future: when settings are not loaded (or failed to load)
    // there is nothing safe to compare — skip rather than let best-effort
    // hygiene break a restore that already succeeded. In a running app the
    // settings are loaded long before a restore (app bar, drawer).
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    if (settings == null) return;
    final leaf = CoverPaths.leafOf(settings.libraryLogo);
    if (leaf == null) return; // no logo, or nothing sane to check
    final covers = await ref.read(coverStoreProvider.future);
    if (covers.listLeaves().contains(leaf)) return;
    // The Either result is deliberately ignored: worst case is the pre-fix
    // status quo (display already falls back to the default icon).
    await ref.read(settingsControllerProvider.notifier).setLibraryLogo('');
  }
}
