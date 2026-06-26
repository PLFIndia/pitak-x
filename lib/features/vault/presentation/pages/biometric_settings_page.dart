/// Biometric-unlock settings (presentation, #34 B2). Opt-in, default OFF.
///
/// Reached from the unlocked vault. Lets the user enable biometric unlock
/// (wraps a second copy of the vault key under a hardware-stored secret, gated
/// by the device biometric prompt) or disable it (deletes that secret + blob).
/// The user passphrase is never stored either way; this is a convenience layer
/// over the existing passphrase unlock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';

/// Screen to enable/disable biometric vault unlock.
class BiometricSettingsPage extends ConsumerStatefulWidget {
  /// Creates the biometric-settings page.
  const BiometricSettingsPage({super.key});

  @override
  ConsumerState<BiometricSettingsPage> createState() =>
      _BiometricSettingsPageState();
}

class _BiometricSettingsPageState extends ConsumerState<BiometricSettingsPage> {
  bool _loading = true;
  bool _busy = false;
  bool _enrolled = false;
  BiometricAvailability _availability = BiometricAvailability.unavailable;
  String? _message;

  VaultSessionController get _notifier =>
      ref.read(vaultSessionControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enrolled = await _notifier.isBiometricEnrolled();
    final availability = await _notifier.biometricAvailability();
    if (!mounted) return;
    setState(() {
      _enrolled = enrolled;
      _availability = availability;
      _loading = false;
    });
  }

  Future<void> _toggle({required bool enable}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = enable
        ? await _notifier.enrollBiometric()
        : await _notifier.disableBiometric();
    if (!mounted) return;
    result.match(
      (f) => setState(() {
        _busy = false;
        _message = _messageFor(f);
      }),
      (_) async {
        await _refresh();
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = enable
              ? 'Biometric unlock enabled.'
              : 'Biometric unlock disabled.';
        });
      },
    );
  }

  String _messageFor(Failure error) => switch (error) {
    ValidationFailure(:final message) => message,
    CryptoFailure() => 'Could not set up biometric unlock (crypto error).',
    StorageFailure() => 'Could not access secure storage.',
    _ => 'Something went wrong. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Biometric unlock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Unlock your vault with your fingerprint or face instead of '
                  'typing the passphrase every time. Your passphrase is never '
                  'stored — a separate device key is sealed in secure hardware '
                  'and released only after a successful biometric check. You '
                  'can still always unlock with your passphrase.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_availability != BiometricAvailability.available &&
                    !_enrolled)
                  Text(
                    _availability == BiometricAvailability.notEnrolled
                        ? 'Set up a fingerprint, face, or device PIN in your '
                              'system settings to use this.'
                        : 'This device does not support biometric unlock.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  SwitchListTile(
                    title: const Text('Unlock with biometrics'),
                    value: _enrolled,
                    onChanged: _busy ? null : (v) => _toggle(enable: v),
                  ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator.adaptive()),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(_message!),
                ],
              ],
            ),
    );
  }
}
