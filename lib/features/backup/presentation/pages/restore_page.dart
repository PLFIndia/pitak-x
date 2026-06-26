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
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/library/application/library_controller.dart';

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
    final bytes = await file.readAsBytes();
    setState(() {
      _archiveBytes = bytes;
      _archiveName = file.name;
    });
  }

  bool get _canRestore =>
      _archiveBytes != null &&
      !_passphrase.isEmpty &&
      !ref.read(restoreControllerProvider).isLoading;

  Future<void> _runRestore() async {
    final bytes = _archiveBytes;
    final secret = _passphrase.takeSecret();
    if (bytes == null || secret == null) {
      secret?.dispose();
      return;
    }
    // The controller takes ownership of `secret` and disposes it.
    await ref
        .read(restoreControllerProvider.notifier)
        .restore(archiveBytes: bytes, passphrase: secret);

    // On success, refresh the library list so restored books show immediately.
    if (ref.read(restoreControllerProvider).hasValue) {
      await ref.read(libraryControllerProvider.notifier).refresh();
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
            child: Text(
              'Restoring replaces everything currently in this app with the '
              'contents of the backup. This cannot be undone.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: state.isLoading ? null : _pickArchive,
            icon: const Icon(Icons.folder_open),
            label: Text(_archiveName ?? 'Choose .pitabak file'),
          ),
          const SizedBox(height: 16),
          SecurePassphraseField(
            controller: _passphrase,
            onSubmitted: _canRestore ? _runRestore : null,
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
        final integrity = summary.isIntact
            ? 'All loans reference an existing book and borrower.'
            : '${summary.danglingLoans.length} loan(s) could not be matched '
                  'after restore.';
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
            Text('Borrowers restored: ${summary.borrowersRestored}'),
            Text('Loans restored: ${summary.loansRestored}'),
            const SizedBox(height: 8),
            Text(integrity, style: textTheme.bodySmall),
          ],
        );
      },
      error: (error, _) {
        final message = _messageFor(error);
        return Text(
          message,
          style: textTheme.bodyMedium?.copyWith(color: scheme.error),
        );
      },
    );
  }

  /// Maps a sealed [Failure] to safe, user-facing copy (AGENTS.md §5: never
  /// surface raw exception text).
  static String _messageFor(Object error) {
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
    if (error is StorageFailure) {
      return 'Something went wrong writing the restored data. '
          'Please try again.';
    }
    return 'Restore failed. Please try again.';
  }
}
