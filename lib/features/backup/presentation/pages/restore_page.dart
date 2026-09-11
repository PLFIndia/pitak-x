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
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/import_export/domain/bounded_zip_extractor.dart'
    show ZipLimits;
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';

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
  BackupManifest? _manifest;

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
    const group = XTypeGroup(label: 'Pitak backup', extensions: ['pitabak']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    // M05: read under the archive cap. The extractor re-checks the same cap,
    // but enforcing it here means an oversized pick is never buffered at all.
    final bytes = await readPickedFileBounded(
      file,
      maxBytes: ZipLimits.pitakaBackup.maxArchiveBytes,
    );
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _archiveBytes = null;
        _archiveName = null;
        _manifest = null;
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
      _manifest = null;
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
        _manifest = null;
        // An unreadable archive can never be restored; drop it so the
        // button state cannot lie.
        _archiveBytes = null;
        _archiveName = null;
      }, (manifest) => _manifest = manifest);
    });
  }

  /// Whether the picked archive needs a passphrase at all (N13): only
  /// archives carrying an encrypted borrowers vault do.
  bool get _needsPassphrase => _manifest?.hasBackupBlob ?? false;

  bool get _canRestore =>
      _archiveBytes != null &&
      _manifest != null &&
      !_inspecting &&
      (!_needsPassphrase || !_passphrase.isEmpty) &&
      !ref.read(restoreControllerProvider).isLoading;

  Future<void> _runRestore() async {
    final bytes = _archiveBytes;
    final manifest = _manifest;
    if (bytes == null || manifest == null) return;
    // Vault-free archives restore with no passphrase (N13); the restorer
    // fails closed if a vault is present but no secret was supplied.
    final secret = manifest.hasBackupBlob ? _passphrase.takeSecret() : null;
    if (manifest.hasBackupBlob && secret == null) return;
    // The controller takes ownership of `secret` and disposes it.
    await ref
        .read(restoreControllerProvider.notifier)
        .restore(archiveBytes: bytes, passphrase: secret);

    // On success, refresh the library AND wishlist lists so restored rows
    // show immediately (N04: restore replaces both; derived providers —
    // languages, titles, reminders — follow via their controller watches).
    if (ref.read(restoreControllerProvider).hasValue) {
      await ref.read(libraryControllerProvider.notifier).refresh();
      await ref.read(wishlistControllerProvider.notifier).refresh();
    }
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
            // are replaced; events, bookmarks, settings and publishing setup
            // are not in backups at all.
            child: Text(
              'Restoring replaces your books, wishlist and cover images '
              '(including the library logo) with the contents of the backup. '
              'If the backup contains a borrowers vault, it replaces this '
              'device’s vault and you will need to lock and unlock it again; '
              'if it does not, your existing vault must be unlocked first. '
              'Its loan history is kept only when every book link can be '
              'matched safely; otherwise the restore is refused without '
              'replacing data. Everything switches over together: if the '
              'restore fails or is interrupted, your current data stays '
              'exactly as it is. Events, bookmarks, settings and publishing '
              'setup are not restored. This cannot be undone.',
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
              _RestoreOutcome.messageFor(_inspectError!),
              style: textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ],
          if (_manifest != null) ...[
            const SizedBox(height: 12),
            _ManifestSummary(manifest: _manifest!),
          ],
          const SizedBox(height: 16),
          if (_needsPassphrase)
            SecurePassphraseField(
              controller: _passphrase,
              onSubmitted: _canRestore ? _runRestore : null,
            )
          else if (_manifest != null)
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
          _RestoreOutcome(state: state),
        ],
      ),
    );
  }
}

/// Shows what the picked archive contains, straight from its manifest (N13).
class _ManifestSummary extends StatelessWidget {
  const _ManifestSummary({required this.manifest});

  final BackupManifest manifest;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // M15: the manifest is untrusted. `dateFromMillisOrNull` returns null for
    // 0 (unset) AND for a value outside DateTime's range, where
    // `DateTime.fromMillisecondsSinceEpoch` would throw inside build().
    final exported = CatalogueRules.dateFromMillisOrNull(manifest.exportedAt);
    final date = exported == null
        ? null
        : '${exported.year}-'
              '${exported.month.toString().padLeft(2, '0')}-'
              '${exported.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This backup contains:', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(manifest.hasBooks ? '• Books' : '• No books'),
        Text(manifest.hasWishlist ? '• Wishlist' : '• No wishlist'),
        Text(
          manifest.hasBackupBlob
              ? '• Borrowers vault (encrypted \u2014 passphrase required)'
              : '• No borrowers vault',
        ),
        if (manifest.hasCovers) const Text('• Cover images'),
        if (date != null) ...[
          const SizedBox(height: 4),
          Text('Made on: $date', style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Renders the typed restore outcome with user-safe copy (no raw exceptions).
class _RestoreOutcome extends StatelessWidget {
  const _RestoreOutcome({required this.state});

  final AsyncValue<RestoreSummary?> state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return state.when(
      loading: () => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();
        final String integrity;
        if (summary.existingVaultKept) {
          integrity =
              'The borrowers vault on this phone was kept. All existing '
              'loan links were checked and preserved, including returned '
              'loan history.';
        } else if (summary.isIntact) {
          integrity = 'All loans reference an existing book and borrower.';
        } else {
          integrity =
              '${summary.danglingLoans.length} loan(s) could not be matched '
              'after restore.';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restore complete',
              style: textTheme.titleMedium?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 8),
            Text('Books restored: ${summary.booksRestored}'),
            Text('Wishlist restored: ${summary.wishlistRestored}'),
            if (summary.existingVaultKept)
              const Text(
                'Borrowers vault: kept from this phone (not in backup)',
              )
            else ...[
              Text('Borrowers restored: ${summary.borrowersRestored}'),
              Text('Loans restored: ${summary.loansRestored}'),
            ],
            const SizedBox(height: 8),
            Text(integrity, style: textTheme.bodySmall),
            if (summary.hasAdjustments) ...[
              const SizedBox(height: 4),
              Text(
                '${summary.coversDropped} cover link(s) were removed because '
                'they pointed to unsupported sites.',
                style: textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
      error: (error, _) {
        final message = messageFor(error);
        return Text(
          message,
          style: textTheme.bodyMedium?.copyWith(color: scheme.error),
        );
      },
    );
  }

  /// Maps a sealed [Failure] to safe, user-facing copy (AGENTS.md §5: never
  /// surface raw exception text). Shared by the restore outcome and the
  /// archive-inspection error (N13).
  static String messageFor(Object error) {
    if (error is WrongPassphraseFailure) {
      return 'That passphrase did not unlock the backup. Please try again.';
    }
    if (error is SchemaTooNewFailure) {
      return 'This backup was made by a newer version of the app and can’t be '
          'restored here. Please update first.';
    }
    if (error is BackupCorruptFailure) {
      return 'This file doesn’t look like a valid Pitak backup.';
    }
    if (error is ValidationFailure) {
      return error.message;
    }
    if (error is StorageFailure) {
      return 'Something went wrong writing the restored data. '
          'Please try again.';
    }
    return 'Restore failed. Please try again.';
  }
}
