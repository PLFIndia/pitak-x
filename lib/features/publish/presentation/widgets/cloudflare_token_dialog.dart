/// Masked Cloudflare API-token entry and fixed external token-creation link.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/platform/secret_on_screen.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cloudflare's documented account-owned Workers-scripts-only template.
///
/// Account-owned tokens are scoped to ONE selected account by construction.
/// This avoids the user-token template's all-accounts default (M3). The
/// dashboard still requires the user to finish creation.
final Uri cloudflareTokenCreationUri = Uri.parse(
  'https://dash.cloudflare.com/'
  '?to=/:account/api-tokens'
  '&permissionGroupKeys=%5B%7B%22key%22%3A%22workers_scripts%22%2C%22type%22'
  '%3A%22edit%22%7D%5D&name=Pitak%20Library%20Publishing',
);

/// Shows the token dialog. The returned value goes directly into the running
/// controller operation; it is never loaded back into this field later.
Future<CloudflareApiToken?> showCloudflareTokenDialog(BuildContext context) =>
    showDialog<CloudflareApiToken>(
      context: context,
      builder: (_) => const _CloudflareTokenDialog(),
    );

class _CloudflareTokenDialog extends StatefulWidget {
  const _CloudflareTokenDialog();

  @override
  State<_CloudflareTokenDialog> createState() => _CloudflareTokenDialogState();
}

class _CloudflareTokenDialogState extends State<_CloudflareTokenDialog> {
  final _token = TextEditingController();
  bool _reveal = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    // Deliberate paste normalization lives here; the value object itself never
    // repairs a secret by trimming it.
    final token = CloudflareApiToken.tryParse(_token.text.trim());
    if (token == null) {
      setState(() => _error = CloudflareErrorMessages.invalidToken);
      return;
    }
    Navigator.of(context).pop(token);
  }

  Future<void> _openTokenPage() async {
    var opened = false;
    try {
      opened = await launchUrl(
        cloudflareTokenCreationUri,
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      // url_launcher throws a PlatformException, but a non-Exception must not
      // escape and leave the button looking successful (AGENTS §14/M8).
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(CloudflareErrorMessages.tokenPageUnavailable),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecretOnScreen(
      child: AlertDialog(
        title: const Text('Connect Cloudflare Workers'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create an account-owned token with only Workers Scripts · '
                'Edit. Cloudflare asks you to choose the ONE account it can '
                'access. You can also set an optional expiry. A user-owned '
                'token with the same restrictions works too.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Use a Worker dedicated to Pitak. Verification or publishing '
                'replaces all assets currently on that Worker.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openTokenPage,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open token creation page'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: !_reveal,
                keyboardType: TextInputType.visiblePassword,
                // A pasted API token is not a login credential. Explicitly
                // disabling autofill stops password managers and Android's
                // autofill service from offering to save it (fix-plan L13).
                autofillHints: null,
                // Do not let the keyboard learn a token typed by hand.
                enableIMEPersonalizedLearning: false,
                maxLength: CloudflareApiToken.maxLength,
                decoration: InputDecoration(
                  labelText: 'Cloudflare API token',
                  errorText: _error,
                  counterText: '',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _reveal ? 'Hide token' : 'Show token',
                    icon: Icon(
                      _reveal ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _reveal = !_reveal),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Connect')),
        ],
      ),
    );
  }
}
