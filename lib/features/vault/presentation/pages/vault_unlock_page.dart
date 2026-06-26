/// Vault unlock screen (presentation layer, AGENTS.md §3.1).
///
/// Read-only viewer: pick a `.pitabak` archive → enter the passphrase in a
/// [SecurePassphraseField] → unlock via the Rust FFI core → navigate to the
/// borrowers/loans view. Writes nothing to device state. The vault key never
/// enters Dart; only decrypted rows come back.
///
/// Why open from an archive (not stored state): nothing on device persists the
/// vault blob/DB yet (that is the deferred secure-storage re-wrap), so the only
/// available vault source today is a backup archive.
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_controller.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_contents_page.dart';

/// Screen to unlock and view an encrypted borrowers vault from an archive.
class VaultUnlockPage extends ConsumerStatefulWidget {
  /// Creates the unlock page.
  const VaultUnlockPage({super.key});

  @override
  ConsumerState<VaultUnlockPage> createState() => _VaultUnlockPageState();
}

class _VaultUnlockPageState extends ConsumerState<VaultUnlockPage> {
  final SecurePassphraseController _passphrase = SecurePassphraseController();
  Uint8List? _archiveBytes;
  String? _archiveName;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(_onChanged);
  }

  @override
  void dispose() {
    _passphrase
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

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

  bool get _canUnlock =>
      _archiveBytes != null &&
      !_passphrase.isEmpty &&
      !ref.read(vaultControllerProvider).isLoading;

  Future<void> _unlock() async {
    final bytes = _archiveBytes;
    final secret = _passphrase.takeSecret();
    if (bytes == null || secret == null) {
      secret?.dispose();
      return;
    }
    await ref
        .read(vaultControllerProvider.notifier)
        .open(archiveBytes: bytes, passphrase: secret);

    final state = ref.read(vaultControllerProvider);
    if (!mounted) return;
    final data = state.valueOrNull;
    if (state.hasValue && data != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VaultContentsPage(data: data)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Borrowers vault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Open a backup to view its borrowers and loans. This is read-only '
            'and nothing is saved to this device.',
            style: Theme.of(context).textTheme.bodyMedium,
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
            onSubmitted: _canUnlock ? _unlock : null,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canUnlock ? _unlock : null,
            child: state.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Unlock'),
          ),
          if (state.hasError) ...[
            const SizedBox(height: 16),
            Text(
              _messageFor(state.error!),
              style: TextStyle(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is WrongPassphraseFailure) {
      return 'That passphrase did not unlock the vault. Please try again.';
    }
    if (error is SchemaTooNewFailure) {
      return 'This backup was made by a newer version of the app.';
    }
    if (error is BackupCorruptFailure) {
      return "This file doesn't look like a valid Pitak backup.";
    }
    return 'Could not open the vault. Please try again.';
  }
}
