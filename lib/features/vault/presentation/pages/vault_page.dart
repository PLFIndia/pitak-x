/// Persistent vault screen (presentation layer, AGENTS.md §3.1).
///
/// Drives [VaultSessionController]. Renders one of three states:
///  - uninitialized → "set up vault" (create + choose a passphrase);
///  - locked → "unlock" (enter the passphrase);
///  - unlocked → the borrower list with add / edit / delete + a lock action.
///
/// All crypto lives behind the controller; this widget only collects the
/// passphrase via a secure field and forwards the resulting bytes. The vault
/// key never reaches Dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/presentation/pages/biometric_settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_edit_page.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_profile_page.dart';
import 'package:pitaka/features/vault/presentation/pages/change_passphrase_page.dart';
import 'package:pitaka/features/vault/presentation/pages/pending_page.dart';

/// The persistent borrowers-vault screen.
class VaultPage extends ConsumerWidget {
  /// Creates the vault page.
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vaultSessionControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Borrowers vault'),
        actions: [
          if (async.valueOrNull is VaultUnlocked) ...[
            IconButton(
              tooltip: 'Pending',
              icon: const Icon(Icons.notifications_none),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PendingPage()),
              ),
            ),
            IconButton(
              tooltip: 'Change passphrase',
              icon: const Icon(Icons.password),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangePassphrasePage(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Biometric unlock',
              icon: const Icon(Icons.fingerprint),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BiometricSettingsPage(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Lock',
              icon: const Icon(Icons.lock_outline),
              onPressed: () =>
                  ref.read(vaultSessionControllerProvider.notifier).lock(),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => const Center(child: Text("Couldn't open the vault.")),
        data: (state) => switch (state) {
          VaultUninitialized() => const _PassphraseForm(mode: _FormMode.setup),
          VaultLocked() => const _PassphraseForm(mode: _FormMode.unlock),
          VaultUnlocked(:final data) => _BorrowerList(
            borrowers: data.borrowers,
          ),
        },
      ),
    );
  }
}

enum _FormMode { setup, unlock }

/// Collects a passphrase and either creates (setup) or unlocks the vault.
class _PassphraseForm extends ConsumerStatefulWidget {
  const _PassphraseForm({required this.mode});

  final _FormMode mode;

  @override
  ConsumerState<_PassphraseForm> createState() => _PassphraseFormState();
}

class _PassphraseFormState extends ConsumerState<_PassphraseForm> {
  final SecurePassphraseController _passphrase = SecurePassphraseController();
  bool _busy = false;
  Failure? _error;

  bool _biometricEnrolled = false;

  @override
  void initState() {
    super.initState();
    _passphrase.addListener(_onChanged);
    if (widget.mode == _FormMode.unlock) {
      _checkBiometric();
    }
  }

  Future<void> _checkBiometric() async {
    final enrolled = await ref
        .read(vaultSessionControllerProvider.notifier)
        .isBiometricEnrolled();
    if (!mounted) return;
    setState(() => _biometricEnrolled = enrolled);
  }

  Future<void> _unlockWithBiometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(vaultSessionControllerProvider.notifier)
        .unlockWithBiometric();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.fold((f) => f, (_) => null);
    });
  }

  @override
  void dispose() {
    _passphrase
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _isSetup => widget.mode == _FormMode.setup;

  Future<void> _submit() async {
    final secret = _passphrase.takeSecret();
    if (secret == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(vaultSessionControllerProvider.notifier);
    final result = _isSetup
        ? await notifier.enable(secret)
        : await notifier.unlock(secret);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.fold((f) => f, (_) => null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = !_passphrase.isEmpty && !_busy;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _isSetup
              ? 'Set up an encrypted vault for your borrowers and loans. '
                    'Choose a passphrase you can remember — it is the ONLY '
                    'way to open the vault, and it is never stored on this '
                    'device.'
              : 'Enter your vault passphrase to view and manage borrowers '
                    'and loans.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SecurePassphraseField(
          controller: _passphrase,
          onSubmitted: canSubmit ? _submit : null,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isSetup ? 'Create vault' : 'Unlock'),
        ),
        if (!_isSetup && _biometricEnrolled) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _unlockWithBiometric,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock with biometrics'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_messageFor(_error!), style: TextStyle(color: scheme.error)),
        ],
      ],
    );
  }

  String _messageFor(Failure error) => switch (error) {
    WrongPassphraseFailure() =>
      'That passphrase did not unlock the vault. Please try again.',
    ValidationFailure(:final message) => message,
    CryptoFailure() => 'Could not open the vault (a crypto error occurred).',
    StorageFailure() => 'Could not write the vault to storage.',
    _ => 'Something went wrong. Please try again.',
  };
}

/// The unlocked borrower list with add / edit / delete.
class _BorrowerList extends ConsumerWidget {
  const _BorrowerList({required this.borrowers});

  final List<Borrower> borrowers;

  Future<void> _openEditor(BuildContext context, {Borrower? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BorrowerEditPage(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Borrower borrower,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${borrower.name}?'),
        content: const Text(
          'This removes the borrower. A borrower with active loans cannot be '
          'deleted until their loans are returned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await ref
        .read(vaultSessionControllerProvider.notifier)
        .deleteBorrower(borrower.id);
    if (!context.mounted) return;
    result.match(
      (f) => VaultSnack.show(
        context,
        f is ValidationFailure ? f.message : 'Could not delete this borrower.',
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: borrowers.isEmpty
          ? const Center(
              child: Text('No borrowers yet. Add your first one below.'),
            )
          : ListView.builder(
              itemCount: borrowers.length,
              itemBuilder: (context, i) {
                final b = borrowers[i];
                return ListTile(
                  title: Text(b.name),
                  subtitle: (b.contact != null && b.contact!.trim().isNotEmpty)
                      ? Text(b.contact!)
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BorrowerProfilePage(borrowerId: b.id),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, ref, b),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add borrower'),
      ),
    );
  }
}

/// Small helper to show a SnackBar without importing a heavier utility.
abstract final class VaultSnack {
  /// Shows [message] as a SnackBar in [context].
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
