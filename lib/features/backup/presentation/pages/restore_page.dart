/// Restore-from-backup screen (presentation layer, AGENTS.md §3.1).
///
/// Flow: pick a `.pitabak` archive → enter passphrase in a secure field → run
/// [RestoreController] → render a typed outcome (success counts, or a safe
/// message for wrong-passphrase / corrupt / schema-too-new / storage). No
/// business logic here; the controller owns the restore and the secret.
///
/// Restore is an AUTHORITATIVE OVERWRITE of local data — the warning copy makes
/// that explicit before the user proceeds (parity with Kotlin RestoreScreen).
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/bounded_file_read.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/presentation/widgets/restore_summary_widgets.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart'
    show ZipLimits;

/// Screen that restores a backup archive over the current device state.
class RestorePage extends ConsumerStatefulWidget {
  /// Creates the restore page.
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends ConsumerState<RestorePage> {
  final SecurePassphraseController _passphrase = SecurePassphraseController();
  Uint8List? _archiveBytes;
  String? _archiveName;

  /// What the picked archive contains (N13): read from its manifest BEFORE
  /// any restore so the screen can show what will happen and ask for a
  /// passphrase only when the archive actually carries an encrypted vault.
  /// The inspection also carries the identity the archive would adopt (§5.10).
  ArchiveInspection? _inspection;

  /// Why the picked file could not be read as a backup (bad zip/manifest).
  Failure? _inspectError;

  bool _inspecting = false;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(_onPassphraseChanged);
  }

  @override
  void dispose() {
    _passphrase
      ..removeListener(_onPassphraseChanged)
      ..dispose();
    super.dispose();
  }

  void _onPassphraseChanged() => setState(() {});

  Future<void> _pickArchive() async {
    // N11: the picker plugin and the bounded read can throw (platform
    // errors, disappearing files) — fail closed with safe copy instead of an
    // unhandled async error.
    try {
      const group = XTypeGroup(label: 'Pitak backup', extensions: ['pitabak']);
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      if (!mounted) return;
      // Item 11: the controller keeps the last restore's result until a NEW
      // archive is chosen (reopening this page shows it again). The user has
      // now chosen one, so the old archive's summary/failure must go before
      // anything about the new file is shown.
      ref.read(restoreControllerProvider.notifier).clearResult();
      // M05: read under the archive cap. The extractor re-checks the same
      // cap, but enforcing it here means an oversized pick is never buffered
      // at all.
      final bytes = await readPickedFileBounded(
        file,
        maxBytes: ZipLimits.pitakaBackup.maxArchiveBytes,
      );
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _archiveBytes = null;
          _archiveName = null;
          _inspection = null;
          _inspectError = const ValidationFailure(
            'This file is too large to be a Pitak backup.',
          );
          _inspecting = false;
        });
        return;
      }
      setState(() {
        _archiveBytes = bytes;
        _archiveName = file.name;
        _inspection = null;
        _inspectError = null;
        _inspecting = true;
      });
      // N13: bounded manifest read first — no restore, no passphrase yet.
      final inspected = await ref
          .read(restoreControllerProvider.notifier)
          .inspectArchive(bytes);
      if (!mounted) return;
      setState(() {
        _inspecting = false;
        inspected.match((failure) {
          _inspectError = failure;
          _inspection = null;
          // An unreadable archive can never be restored; drop it so the
          // button state cannot lie.
          _archiveBytes = null;
          _archiveName = null;
        }, (inspection) => _inspection = inspection);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _archiveBytes = null;
        _archiveName = null;
        _inspection = null;
        _inspecting = false;
        _inspectError = const ValidationFailure(
          'Could not read that file. Please try again.',
        );
      });
    }
  }

  /// Whether the picked archive needs a passphrase at all (N13): only
  /// archives carrying an encrypted borrowers vault do.
  bool get _needsPassphrase => _inspection?.manifest.hasBackupBlob ?? false;

  bool get _canRestore =>
      _archiveBytes != null &&
      _inspection != null &&
      !_inspecting &&
      (!_needsPassphrase || !_passphrase.isEmpty) &&
      !ref.read(restoreControllerProvider).isLoading;

  Future<void> _runRestore() async {
    final bytes = _archiveBytes;
    final inspection = _inspection;
    if (bytes == null || inspection == null) return;
    // Vault-free archives restore with no passphrase (N13); the restorer
    // fails closed if a vault is present but no secret was supplied.
    final hasVault = inspection.manifest.hasBackupBlob;
    final secret = hasVault ? _passphrase.takeSecret() : null;
    if (hasVault && secret == null) return;
    // The controller takes ownership of `secret` and disposes it.
    //
    // N11: the controller owns the whole run — keep-alive, typed terminal
    // state, and the post-success refresh of the library AND wishlist lists
    // (N04: restore replaces both; derived providers — languages, titles,
    // reminders — follow via their controller watches). Nothing after this
    // await touches `ref`: leaving the page mid-restore must not crash, and
    // the refresh must not depend on the page still being here.
    await ref
        .read(restoreControllerProvider.notifier)
        .restore(archiveBytes: bytes, passphrase: secret);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(restoreControllerProvider);
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
            onPressed: state.isLoading || _inspecting ? null : _pickArchive,
            icon: const Icon(Icons.folder_open),
            label: Text(_archiveName ?? 'Choose .pitabak file'),
          ),
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
          const SizedBox(height: 24),
          RestoreOutcome(state: state),
        ],
      ),
    );
  }
}
