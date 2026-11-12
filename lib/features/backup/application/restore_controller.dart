/// UI-facing restore controller (application layer, AGENTS.md §4).
///
/// A `@riverpod` AsyncNotifier the Restore screen drives: idle until `restore`
/// is called with the chosen backup file and a `SecretBytes` passphrase. It
/// runs `RestoreBackup` and maps the `Either<Failure, RestoreSummary>` to
/// loading / data / error so the UI can render a safe message.
///
/// Secret ownership (§6.1): this controller takes ownership of the passphrase
/// and disposes it in a `finally` once the restore completes — success or
/// failure — so the bytes never outlive the call.
///
/// THE CHOSEN FILE (backup rework BR6, decision D25): the backup is a
/// private COPY the app's own picker made (`PickedDocument`), a plain
/// duplicate of a whole library. It has one owner at a time, so that it is
/// never left behind and never deleted while it is read:
///
///  - the picker answers "picked": the PAGE owns the copy;
///  - a later pick answers anything but "cancelled": the page owns the new
///    copy and releases the earlier one;
///  - the inspection fails, or the page is left while no restore runs: the
///    page releases the copy;
///  - `restore` starts: THIS CONTROLLER owns the copy, which is in use;
///  - the restore succeeds: the copy is discarded;
///  - the restore fails and the page still holds the copy: it goes back to
///    the page, kept for another try (a wrong passphrase is typed again
///    without choosing the file again);
///  - the restore fails and the page released the copy meanwhile: it is
///    discarded;
///  - `restore` is refused because one runs already: nothing changes;
///  - the app is killed: the sweep at the next start removes the copy.
///
/// "Released" is [RestoreController.releaseArchive], which the page calls.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
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

/// How many cover pictures the running restore has written, of how many
/// (decision D27); null when no restore runs, and before its first cover.
///
/// A notifier of its own, next to the controller, because a restore
/// outlives its page: a page that is reopened during a restore shows the
/// count again. Only [RestoreController] sets it.
///
/// keepAlive (justified): for the same reason as the controller. The value
/// is two whole numbers; it holds nothing secret.
@Riverpod(keepAlive: true)
class RestoreProgress extends _$RestoreProgress {
  @override
  BackupProgress? build() => null;

  /// Shows [progress], or nothing when it is null.
  // A method on purpose: a Riverpod notifier is changed through methods,
  // and a setter here would need a getter that only repeats `state`.
  // ignore: use_setters_to_change_properties
  void show(BackupProgress? progress) => state = progress;
}

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
/// wiped in `restore`'s `finally`). A [RestoreSummary] holds counts and
/// outcome flags and some of the user's own catalogue data: the identity
/// name, the saved-libraries rows, and the titles of the items whose cover
/// picture was left out (D23). All of it is shown on the Restore screen
/// only, never logged, and goes when a new file is chosen.
@Riverpod(keepAlive: true)
class RestoreController extends _$RestoreController {
  /// True while a restore runs — a second call is refused (N11).
  bool _running = false;

  /// The copy of the backup the running restore reads; null when none runs.
  PickedDocument? _archiveInUse;

  /// True when the page gave [_archiveInUse] back while the restore was
  /// still reading it: the copy is then removed when that restore ends,
  /// however it ends.
  bool _releaseWhenDone = false;

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

  /// Lets the user choose a backup file and answers with a private copy of
  /// it, never larger than the largest backup the app reads.
  ///
  /// Never throws: every way a pick can end is one of the seven answers of
  /// [DocumentPickResult]. The caller owns a picked copy (see the table in
  /// the library doc) and gives it back with [releaseArchive].
  Future<DocumentPickResult> pickArchive() async {
    try {
      final picker = await ref.read(documentPickerProvider.future);
      // The cap is the one the restore's reader enforces again when it
      // opens the copy; a larger file could never be a backup of this app.
      return await picker.pickCopy(
        maxBytes: BackupLimits.current.maxArchiveBytes,
      );
    } on Object {
      // The picker itself never throws; resolving it might.
      return const DocumentPickFailed();
    }
  }

  /// "The page no longer wants this copy": removes the picked [archive].
  ///
  /// When a restore is reading that copy right now, it is NOT removed under
  /// it: it goes when that restore has ended. Never throws, and may be
  /// called twice.
  Future<void> releaseArchive(PickedDocument archive) async {
    if (_archiveInUse?.path == archive.path) {
      _releaseWhenDone = true;
      return;
    }
    await _discard(archive);
  }

  /// Removes the picked copy. Best-effort by design: a copy that cannot be
  /// removed now is swept at the next app start.
  Future<void> _discard(PickedDocument archive) async {
    try {
      final picker = await ref.read(documentPickerProvider.future);
      await picker.discard(archive);
    } on Object {
      // Resolving the picker failed, or this controller is already
      // disposed: the sweep at the next start removes the copy.
    }
  }

  /// Passes the count of the running restore on to the page (D27).
  void _showProgress(BackupProgress? progress) {
    if (_disposed) return;
    ref.read(restoreProgressProvider.notifier).show(progress);
  }

  /// Inspects the picked [archive] WITHOUT restoring (N13): the Restore
  /// screen runs this right after a file is picked so it can show what the
  /// backup contains — including the identity it would adopt (§5.10) — and
  /// ask for a passphrase only when the archive actually carries an
  /// encrypted vault.
  Future<Either<Failure, ArchiveInspection>> inspectArchive(
    PickedDocument archive,
  ) async {
    final restorer = await ref.read(restoreBackupProvider.future);
    return restorer.inspectArchive(archive.path);
  }

  /// Restores the picked [archive] using [passphrase]. Takes ownership of
  /// [passphrase] and disposes it when done, and owns [archive] while the
  /// restore reads it (see the table in the library doc for what happens to
  /// the copy afterwards). State becomes loading, then either
  /// `AsyncData(summary)` or `AsyncError(Failure)`.
  ///
  /// [passphrase] is null only for vault-free archives (N13); the restorer
  /// fails closed if a vault is present but no passphrase was supplied.
  Future<void> restore({
    required PickedDocument archive,
    SecretBytes? passphrase,
  }) async {
    if (_running || _disposed) {
      // Refused — but the caller already handed over the secret, so wipe it
      // anyway: ownership transfers at call time, never leaks (§6.1). The
      // copy of the backup is NOT taken over: its owner stays who it was.
      passphrase?.dispose();
      return;
    }
    _running = true;
    _archiveInUse = archive;
    _releaseWhenDone = false;
    // Whether the restore itself went through. Kept apart from `state`,
    // which is not touched once this controller is disposed.
    var succeeded = false;
    state = const AsyncLoading();
    _showProgress(null);
    try {
      final restorer = await ref.read(restoreBackupProvider.future);
      final result = await restorer.restore(
        archivePath: archive.path,
        passphrase: passphrase,
        onProgress: _showProgress,
      );
      succeeded = result.isRight();
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
      _showProgress(null);
      // D25: after a success nobody needs the copy. After a failure it goes
      // back to the page for another try, unless the page gave it back
      // meanwhile. (When this controller itself was disposed during the
      // run, the picker can no longer be reached from here; the copy is
      // then left to the sweep at the next app start.)
      final discard = succeeded || _releaseWhenDone;
      // The run is over BEFORE the copy is removed: a release that arrives
      // from now on removes the copy itself instead of waiting for a
      // restore that has ended.
      _archiveInUse = null;
      _running = false;
      if (discard) await _discard(archive);
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
            .adopt(
              id: identity.id,
              name: identity.name,
              publishedFingerprint: summary.restoredPublishedFingerprint,
            );
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
