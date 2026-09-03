/// Paste / validate / save dialog for the user's Google Books API key
/// (presentation, AGENTS.md §3.1).
///
/// Security posture (review 2026-09-03):
///  - the pasted key is a quota-bearing credential, so the whole dialog sits
///    inside [SecretOnScreen] → Android FLAG_SECURE is on while it is open
///    (no screenshots / screen-share / recents thumbnail of the key);
///  - the field is masked by default with a show/hide toggle (the user asked
///    to be ABLE to see the key to check a paste, not to see it by default);
///  - the stored key is never loaded back into the field, and no error
///    message ever echoes what was typed;
///  - the text controller is disposed with the dialog. The key does pass
///    through a `String` here — that is the accepted §6.6 exception for this
///    credential (same as the GitHub token), documented in
///    `secure_storage_lookup_key_store.dart`.
///
/// Pops `true` when the stored key changed (saved or removed), `false`/null
/// otherwise, so the caller knows whether to refresh its masked summary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/secret_on_screen.dart';
import 'package:pitaka/features/lookup/domain/google_books_api_key.dart';

/// Add / change / remove the Google Books API key.
class GoogleBooksKeyDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const GoogleBooksKeyDialog({super.key});

  @override
  ConsumerState<GoogleBooksKeyDialog> createState() =>
      _GoogleBooksKeyDialogState();
}

class _GoogleBooksKeyDialogState extends ConsumerState<GoogleBooksKeyDialog> {
  final _key = TextEditingController();
  String? _error;
  bool _hadKey = false;
  bool _reveal = false;

  @override
  void initState() {
    super.initState();
    // Only to decide whether to offer "Remove" — the stored key is never
    // loaded into the text field (it would defeat the masking).
    ref
        .read(lookupKeyStoreProvider)
        .googleBooksApiKey()
        .then((k) => mounted ? setState(() => _hadKey = k != null) : null);
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final normalized = GoogleBooksApiKey.normalize(_key.text);
    if (!GoogleBooksApiKey.isValid(normalized)) {
      setState(
        () => _error =
            'That does not look like a Google API key. Paste the key '
            'exactly as shown in Google Cloud Console.',
      );
      return;
    }
    try {
      await ref.read(lookupKeyStoreProvider).setGoogleBooksApiKey(normalized);
    } on Exception {
      // Secure storage can fail (locked keystore, corrupt entry). Say so
      // instead of pretending the key was saved.
      if (mounted) {
        setState(() => _error = 'Could not save the key. Please try again.');
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _remove() async {
    try {
      await ref.read(lookupKeyStoreProvider).clearGoogleBooksApiKey();
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not remove the key. Please try again.');
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SecretOnScreen(
      child: AlertDialog(
        title: const Text('Google Books API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a free API key in Google Cloud Console (APIs & Services '
              '→ Credentials) with the Books API enabled, then paste it here. '
              'It is stored encrypted on this device and sent only to Google.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              // Masked by default; the eye icon reveals it for checking.
              obscureText: !_reveal,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: 'API key',
                errorText: _error,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _reveal ? 'Hide key' : 'Show key',
                  icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _reveal = !_reveal),
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_hadKey)
            TextButton(onPressed: _remove, child: const Text('Remove key')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
