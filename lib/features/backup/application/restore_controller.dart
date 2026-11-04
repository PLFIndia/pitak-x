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
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'restore_controller.g.dart';

/// Drives a one-shot restore and surfaces its [RestoreSummary].
///
/// Lifecycle ownership (N11): a restore is an authoritative overwrite that
/// must FINISH once started, so the run is owned here, not by the page —
/// modelled on `PublishController`/`ImportController`:
///  - the provider is `keepAlive` (review item 11): navigating away cannot
///    dispose it mid-restore, swallow the terminal state, or let a rebuilt
///    page start a SECOND concurrent restore — and the terminal
///    success/failure stays visible when Restore is reopened until the user
///    chooses a new archive ([clearResult]) or starts a new restore;
///  - `_running` refuses a second call outright;
///  - an unexpected throw becomes a typed `AsyncError(UnexpectedFailure)`
///    instead of escaping into the page's unawaited future;
///  - the post-success list refresh is invalidated HERE (next to the vault
///    session invalidation), so it happens even when the page is gone.
///
/// keepAlive is safe here: the controller holds no secret (the passphrase is
/// wiped in `restore`'s `finally`) and a [RestoreSummary] is only counts and
/// outcome flags.
@Riverpod(keepAlive: true)
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

  /// Forgets the previous restore's terminal result (back to idle).
  ///
  /// The page calls this when the user chooses a NEW archive, so the old
  /// archive's summary or failure is never shown next to the new one. A
  /// running restore is never cleared: its terminal state must reach the
  /// user (the page also disables the picker while loading).
  void clearResult() {
    if (_running || _disposed) return;
    state = const AsyncData(null);
  }

  /// Inspects the archive WITHOUT restoring (N13): the Restore screen runs
  /// this right after a file is picked so it can show what the backup
  /// contains — including the identity it would adopt (§5.10) — and ask for
  /// a passphrase only when the archive actually carries an encrypted vault.
  Future<Either<Failure, ArchiveInspection>> inspectArchive(
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
    state = const AsyncLoading();
    try {
      final restorer = await ref.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archiveBytes: archiveBytes,
        passphrase: passphrase,
      );
      if (!_disposed) {
        final Either<Failure, RestoreSummary> effective;
        if (result case Right(value: final summary)) {
          // §5.10: the catalogue switch succeeded — NOW adopt the archive's
          // identity, network list and website publishing record (additive;
          // failures are reported on the summary, never rolled back into the
          // restore).
          effective = right(await _applyIdentityAndNetwork(summary));
        } else {
          effective = result;
        }
        state = effective.match(
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
              ..invalidate(wishlistControllerProvider)
              // §5.10: the saved-libraries list was replaced above. The
              // network window ALSO rebuilds on its own (its build() watches
              // networkRepositoryProvider, which the generation switch
              // republished) — but that rebuild can run BEFORE the
              // replaceAll above, showing the carried-over pre-restore rows.
              // This invalidation, after the write, guarantees the next
              // build reads the restored list. A no-op when nothing watches.
              ..invalidate(networkControllerProvider);
            // Plan CV7: an ADOPTED publishing record changes the active site
            // and the share address the drawer shows. Only then: in debug
            // builds an invalidation builds its target, and these two read
            // the publishing setup.
            if (summary.publishStateOutcome ==
                PublishStateRestoreOutcome.adopted) {
              ref
                ..invalidate(publishSiteStatusProvider)
                ..invalidate(publishedSiteUrlProvider);
            }
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
    }
  }

  /// Applies the archive's library identity, saved-libraries list and
  /// website publishing record AFTER the catalogue switch
  /// (docs/ARCHITECTURE.md §5.5), and returns the summary with the adoption
  /// outcomes filled in.
  ///
  /// Both steps are ADDITIVE over a restore that already succeeded: a Left
  /// from either is folded into the summary (`identityAdopted: false` /
  /// `networkRestored: 0`, each with its plain sentence on the page) — the
  /// catalogue restore is NEVER rolled back for them. Unexpected throws get
  /// the same treatment (fail closed, keep the restore).
  Future<RestoreSummary> _applyIdentityAndNetwork(
    RestoreSummary summary,
  ) async {
    var identityAdopted = false;
    var identityPartiallyAdopted = false;
    final identity = summary.restoredIdentity;
    if (identity != null) {
      try {
        // Through the LibraryNamespace port (SettingsController) — never the
        // raw repository (N07: the in-memory settings must move with disk).
        final adopted = await ref
            .read(settingsControllerProvider.notifier)
            .adopt(id: identity.id, name: identity.name);
        identityAdopted = adopted.outcome == LibraryAdoptionOutcome.adopted;
        // The ID landed but the name did not: the page must say so instead of
        // "unchanged" (review finding 4).
        identityPartiallyAdopted =
            adopted.outcome == LibraryAdoptionOutcome.partiallyAdopted;
      } on Object {
        // Nothing was published by a throwing adoption; the last good
        // identity stands.
        identityAdopted = false;
      }
    }

    var networkApplied = false;
    var networkRestored = 0;
    final rows = summary.restoredNetwork;
    if (rows != null) {
      try {
        // The generation switch republished `appDatabaseProvider`, so this
        // read hands out the NEW generation's repository.
        final repo = await ref.read(networkRepositoryProvider.future);
        final replaced = await repo.replaceAll(rows);
        if (replaced.isRight()) {
          networkApplied = true;
          networkRestored = rows.length;
        }
      } on Object {
        networkApplied = false;
      }
    }

    return summary.withAdoptionResults(
      identityAdopted: identityAdopted,
      identityPartiallyAdopted: identityPartiallyAdopted,
      networkApplied: networkApplied,
      networkRestored: networkRestored,
      publishStateOutcome: await _adoptPublishState(summary),
    );
  }

  /// Offers the archive's website publishing record to the publish feature
  /// (plan CV7, ADR 0014 amendment). It decides inside the publish queue
  /// whether this phone may take it over — only when the phone has not
  /// published itself — and never undoes the restore. Null when the archive
  /// carried no usable record.
  Future<PublishStateRestoreOutcome?> _adoptPublishState(
    RestoreSummary summary,
  ) async {
    final archived = summary.restoredPublishState;
    if (archived == null) return null;
    try {
      final adopter = await ref.read(publishStateAdopterProvider.future);
      return await adopter.adoptRestored(archived);
    } on Object {
      // The adopter itself never throws; resolving it might. Nothing was
      // written then, so this phone's own state stands (fail closed).
      return PublishStateRestoreOutcome.notApplied;
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
