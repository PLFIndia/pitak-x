/// Change-passphrase screen (presentation layer, AGENTS.md §3.1, #28A).
///
/// The vault must already be UNLOCKED to reach here, so the controller holds
/// the current passphrase — the user only supplies the NEW one (twice, to guard
/// against a typo locking them out). On success the at-rest blob is re-wrapped
/// under the new passphrase and the held session secret is swapped; the vault
/// key and `borrowers.db` never change.
///
/// Both new-passphrase entries are collected through the wipeable
/// [SecurePassphraseField]; the bytes are compared and forwarded to the
/// controller, which owns the re-wrap. No passphrase is ever held as a String.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/crypto/secure_passphrase_field.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';

/// Screen that changes the vault passphrase (re-wraps the key, #28A).
class ChangePassphrasePage extends ConsumerStatefulWidget {
  /// Creates the change-passphrase page.
  const ChangePassphrasePage({super.key});

  @override
  ConsumerState<ChangePassphrasePage> createState() =>
      _ChangePassphrasePageState();
}

class _ChangePassphrasePageState extends ConsumerState<ChangePassphrasePage> {
  final SecurePassphraseController _next = SecurePassphraseController();
  final SecurePassphraseController _confirm = SecurePassphraseController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next.addListener(_onChanged);
    _confirm.addListener(_onChanged);
  }

  @override
  void dispose() {
    _next
      ..removeListener(_onChanged)
      ..dispose();
    _confirm
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSubmit =>
      !_busy &&
      _next.length >= VaultSessionController.minPassphraseLength &&
      !_confirm.isEmpty;

  Future<void> _submit() async {
    // Take both secrets up front so we own them regardless of the path taken.
    final next = _next.takeSecret();
    final confirm = _confirm.takeSecret();
    if (next == null || confirm == null) {
      next?.dispose();
      confirm?.dispose();
      return;
    }
    // Constant-time-ish byte compare; mismatch ⇒ abort before any crypto.
    if (!_bytesEqual(next, confirm)) {
      next.dispose();
      confirm.dispose();
      setState(() => _error = 'The two passphrases do not match.');
      return;
    }
    // Confirm copy no longer needed; the controller takes ownership of `next`.
    confirm.dispose();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(vaultSessionControllerProvider.notifier)
        .changePassphrase(next);
    if (!mounted) return;
    result.match(
      (f) => setState(() {
        _busy = false;
        _error = _messageFor(f);
      }),
      (_) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Passphrase changed.')));
        Navigator.of(context).pop();
      },
    );
  }

  /// Length-aware byte equality (avoids early-exit on the common prefix).
  bool _bytesEqual(SecretBytes a, SecretBytes b) {
    return a.use(
      (ab) => b.use((bb) {
        if (ab.length != bb.length) return false;
        var diff = 0;
        for (var i = 0; i < ab.length; i++) {
          diff |= ab[i] ^ bb[i];
        }
        return diff == 0;
      }),
    );
  }

  String _messageFor(Failure error) => switch (error) {
    ValidationFailure(:final message) => message,
    WrongPassphraseFailure() => 'Could not change the passphrase.',
    CryptoFailure() => 'Could not re-encrypt the vault key.',
    StorageFailure() => 'Could not save the new passphrase to storage.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change passphrase')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose a new passphrase for your vault. The current passphrase is '
            'used automatically — you only need to enter the new one. Your '
            'borrowers and loans are not re-encrypted; only the key wrapping '
            'changes. The new passphrase is the ONLY way to open the vault and '
            'is never stored on this device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SecurePassphraseField(
            controller: _next,
            label: 'New passphrase',
            autofocus: true,
          ),
          const SizedBox(height: 12),
          SecurePassphraseField(
            controller: _confirm,
            label: 'Confirm new passphrase',
            onSubmitted: _canSubmit ? _submit : null,
          ),
          const SizedBox(height: 8),
          Text(
            'At least ${VaultSessionController.minPassphraseLength} '
            'characters.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Change passphrase'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
