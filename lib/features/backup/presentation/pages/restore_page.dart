/// Restore-from-backup screen (presentation layer, AGENTS.md §3.1).
///
/// Flow: choose a `.pitabak` archive → enter passphrase in a secure field →
/// run [RestoreController] → render a typed outcome (success counts, or a
/// safe message for wrong-passphrase / corrupt / schema-too-new / storage).
/// No business logic here; the controller owns the restore and the secret.
///
/// THE CHOSEN FILE (backup rework BR6, decision D25): the app's own picker
/// copies the chosen document into a private temporary folder and hands
/// back that copy (`PickedDocument`); the page never holds the file's bytes.
/// The copy is a plain duplicate of a backup, so it has exactly one owner
/// at a time:
///  - this page, from the pick until a restore starts, and again after a
///    restore that FAILED (so a wrong passphrase can be typed again without
///    choosing the file again);
///  - the controller, while a restore reads it.
/// The page gives its copy back (`releaseArchive`) when another file is
/// chosen, when the file turns out not to be a backup, and when the page is
/// left. After a restore that succeeded the copy is gone and the page
/// forgets the file.
///
/// Restore is an AUTHORITATIVE OVERWRITE of local data — the warning copy makes
/// that explicit before the user proceeds (parity with Kotlin RestoreScreen).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';
import 'package:pitaka/features/backup/presentation/restore_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/restore_summary_widgets.dart';

/// Screen that restores a backup archive over the current device state.
class RestorePage extends ConsumerStatefulWidget {
  /// Creates the restore page.
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final SecurePassphraseController _passphrase = SecurePassphraseController();

  /// The restore controller, kept from `initState` so that `dispose` and a
  /// pick that answers after the page was left can still give a copy back.
  /// `ref` cannot be used then; the controller's provider is kept alive,
  /// so this object stays valid (the same pattern as
  /// `SecurePassphraseField`).
  late final RestoreController _controller;

  /// The private copy of the chosen backup file, while this page owns it.
  PickedDocument? _archive;

  /// What the picked archive contains (N13): read from its manifest BEFORE
  /// any restore so the screen can show what will happen and ask for a
  /// passphrase only when the archive actually carries an encrypted vault.
  /// The inspection also carries the identity the archive would adopt (§5.10).
  ArchiveInspection? _inspection;

  /// Why the chosen file could not be used: choosing it did not work, or it
  /// is not a backup (bad zip/manifest).
  Failure? _inspectError;

  /// True while the system's picker is open and the file is copied.
  bool _picking = false;

  bool _inspecting = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(restoreControllerProvider.notifier);
    _passphrase.addListener(_onPassphraseChanged);
  }

  @override
  void dispose() {
    // The page is left: its copy of the backup must not stay behind. When
    // a restore is reading it right now, the controller removes it once
    // that restore has ended.
    final archive = _archive;
    if (archive != null) unawaited(_controller.releaseArchive(archive));
    _passphrase
      ..removeListener(_onPassphraseChanged)
      ..dispose();
    super.dispose();
  }

  void _onPassphraseChanged() => setState(() {});

  Future<void> _pickArchive() async {
    setState(() => _picking = true);
    // Never throws: every way a pick can end is one of seven answers.
    final result = await _controller.pickArchive();
    if (!mounted) {
      // The page was left while the picker was open: nobody wants the copy.
      if (result case DocumentPicked(:final document)) {
        unawaited(_controller.releaseArchive(document));
      }
      return;
    }
    // Each of the seven answers is named; a new one would not compile.
    switch (result) {
      case DocumentPickCancelled():
        // Not an error: an earlier choice stays as it is.
        setState(() => _picking = false);
      case DocumentPicked(:final document):
        _forgetChoice();
        await _inspect(document);
      case DocumentPickTooLarge() ||
          DocumentPickUnreadable() ||
          DocumentPickNotSaved() ||
          DocumentPickUnavailable() ||
          DocumentPickFailed():
        _forgetChoice();
        final message = restorePickMessage(
          result,
          maxArchiveBytes: BackupLimits.current.maxArchiveBytes,
        );
        setState(() {
          _picking = false;
          _inspectError = message == null ? null : ValidationFailure(message);
        });
    }
  }

  /// Drops the earlier choice and everything shown about it, and gives its
  /// copy back.
  void _forgetChoice() {
    // Item 11: the controller keeps the last restore's result until a NEW
    // archive is chosen (reopening this page shows it again). The user has
    // now chosen again, so the old archive's summary/failure must go before
    // anything about the new file is shown.
    _controller.clearResult();
    final earlier = _archive;
    if (earlier != null) unawaited(_controller.releaseArchive(earlier));
    _archive = null;
    _inspection = null;
    _inspectError = null;
  }

  /// N13: looks inside the picked copy — no restore, no passphrase yet.
  Future<void> _inspect(PickedDocument document) async {
    setState(() {
      _picking = false;
      _archive = document;
      _inspecting = true;
    });
    // N11: resolving the restorer and reading the file can throw (platform
    // errors, a file that disappeared) — fail closed with safe copy instead
    // of an unhandled async error.
    Failure? failure;
    ArchiveInspection? inspection;
    try {
      final inspected = await _controller.inspectArchive(document);
      inspected.match((f) => failure = f, (i) => inspection = i);
    } on Object {
      failure = const ValidationFailure(
        'Could not read that file. Please try again.',
      );
    }
    // A file that cannot be restored is not kept: nobody will read the
    // copy again, and the button state must not lie.
    if (inspection == null) unawaited(_controller.releaseArchive(document));
    if (!mounted) return;
    // The user may have chosen again meanwhile; then this answer is stale.
    if (!identical(_archive, document)) return;
    setState(() {
      _inspecting = false;
      _inspection = inspection;
      _inspectError = failure;
      if (inspection == null) _archive = null;
    });
  }

  /// Whether the picked archive needs a passphrase at all (N13): only
  /// archives carrying an encrypted borrowers vault do.
  bool get _needsPassphrase => _inspection?.manifest.hasBackupBlob ?? false;

  bool get _canRestore =>
      _archive != null &&
      _inspection != null &&
      !_inspecting &&
      !_picking &&
      (!_needsPassphrase || !_passphrase.isEmpty) &&
      !ref.read(restoreControllerProvider).isLoading;

  Future<void> _runRestore() async {
    final archive = _archive;
    final inspection = _inspection;
    if (archive == null || inspection == null) return;
    // Vault-free archives restore with no passphrase (N13); the restorer
    // fails closed if a vault is present but no secret was supplied.
    final hasVault = inspection.manifest.hasBackupBlob;
    final secret = hasVault ? _passphrase.takeSecret() : null;
    if (hasVault && secret == null) return;
    // The controller takes ownership of `secret` and disposes it, and it
    // owns the copy of the backup while the restore reads it (D25).
    //
    // N11: the controller owns the whole run — keep-alive, typed terminal
    // state, and the post-success refresh of the library AND wishlist lists
    // (N04: restore replaces both; derived providers — languages, titles,
    // reminders — follow via their controller watches). Leaving the page
    // mid-restore must not crash, and the refresh must not depend on the
    // page still being here.
    await _controller.restore(archive: archive, passphrase: secret);
    if (!mounted) return;
    // After a success the copy is gone (the controller removed it), so the
    // page forgets the file. After a failure the page still owns the copy:
    // the same file can be tried again, for example with the right
    // passphrase.
    final state = ref.read(restoreControllerProvider);
    final succeeded = state is AsyncData && state.value != null;
    if (succeeded && identical(_archive, archive)) {
      setState(() {
        _archive = null;
        _inspection = null;
      });
    }
  }

  /// What the "Choose" button says: the chosen document's name once there
  /// is one. The name is foreign text, for showing only.
  String get _archiveLabel {
    final archive = _archive;
    if (archive == null) return 'Choose .pitabak file';
    return archive.displayName.isEmpty
        ? 'Backup file chosen'
        : archive.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(restoreControllerProvider);
    // D27: how many cover pictures the running restore has written.
    final progress = ref.watch(restoreProgressProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            // N13 + doc-item: "replaces everything" was too broad. The truth:
            // books/wishlist/covers (and the vault when the backup has one)
            // are replaced; events, settings and publishing sign-ins are not
            // in backups at all. §5.10: the archive's library identity IS
            // adopted and its saved-libraries list replaces this device's.
            // Plan CV7: the website publishing record is taken over only on
            // a phone that has not published itself (the contents list says
            // so next to the record).
            // The library logo: its image file rides along with the covers,
            // but the SETTING that marks it as the logo is not in the backup
            // (N04, RestoreController._clearDanglingLogoRef), so the logo is
            // not restored — same statement as the Create-backup page.
            child: Text(
              'Restoring replaces your books, wishlist and cover images '
              'with the contents of the backup. '
              'If the backup contains a borrowers vault, it replaces this '
              'device’s vault and you will need to lock and unlock it again; '
              'if it does not, your existing vault must be unlocked first. '
              'Its loan history is kept only when every book link can be '
              'matched safely; otherwise the restore is refused without '
              'replacing data. If the backup carries a library identity, '
              'this device adopts it, and its saved-libraries list replaces '
              'yours. Everything switches over together: if the restore '
              'fails or is interrupted, your current data stays exactly as '
              'it is. Events, the library logo, app settings and your '
              'publishing sign-in are not restored. This cannot be undone.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: state.isLoading || _inspecting || _picking
                ? null
                : _pickArchive,
            icon: const Icon(Icons.folder_open),
            label: Text(_archiveLabel),
          ),
          if (_picking) ...[
            const SizedBox(height: 12),
            const Text(restoreCopyingMessage),
          ],
          if (_inspecting) ...[
            const SizedBox(height: 12),
            const Text('Reading the backup…'),
          ],
          if (_inspectError != null) ...[
            const SizedBox(height: 12),
            Text(
              RestoreOutcome.messageFor(_inspectError!),
              style: textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ],
          if (_inspection != null) ...[
            const SizedBox(height: 12),
            RestoreManifestSummary(inspection: _inspection!),
          ],
          const SizedBox(height: 16),
          if (_needsPassphrase)
            SecurePassphraseField(
              controller: _passphrase,
              onSubmitted: _canRestore ? _runRestore : null,
            )
          else if (_inspection != null)
            Text(
              'This backup has no borrowers vault, so no passphrase is '
              'needed.',
              style: textTheme.bodyMedium,
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canRestore ? _runRestore : null,
            child: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restore'),
          ),
          // D27: how far the restore is, once it writes cover pictures. The
          // same sentence as on the create-backup page.
          if (progress != null) ...[
            const SizedBox(height: 8),
            Text(
              backupProgressMessage(progress),
              key: const Key('restore-progress'),
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          RestoreOutcome(state: state),
        ],
      ),
    );
  }
}
