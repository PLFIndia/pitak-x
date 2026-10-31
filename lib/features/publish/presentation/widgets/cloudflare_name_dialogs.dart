/// Account, subdomain, and Worker-name prompts for Cloudflare setup.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show TextEditingValue, TextInputFormatter;
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// Shows the bounded account picker. A manual choice is distinct from cancel.
Future<CloudflareAccountChoice?> showCloudflareAccountDialog(
  BuildContext context, {
  required List<CloudflareAccount> accounts,
  String? message,
}) => showDialog<CloudflareAccountChoice>(
  context: context,
  builder: (dialogContext) => SimpleDialog(
    title: const Text('Choose a Cloudflare account'),
    children: [
      if (message != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(message),
        ),
      for (final account in accounts)
        ListTile(
          title: Text(account.displayName),
          onTap: () => Navigator.of(
            dialogContext,
          ).pop(CloudflareAccountChoice(account: account)),
        ),
      ListTile(
        leading: const Icon(Icons.edit),
        title: const Text('Enter Account ID manually'),
        onTap: () => Navigator.of(
          dialogContext,
        ).pop(const CloudflareAccountChoice(manual: true)),
      ),
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Cancel'),
      ),
    ],
  ),
);

/// Prompts for a manually supplied 32-character Account ID.
Future<String?> showCloudflareManualAccountDialog(BuildContext context) =>
    _showNameDialog(
      context,
      const _NameDialogConfig(
        title: 'Cloudflare Account ID',
        label: 'Account ID',
        helper: '32 hexadecimal characters',
        explanation:
            'Find the Account ID in Cloudflare. It selects the account before '
            'an account-owned token is verified.',
        actionLabel: 'Continue',
        maxLength: CloudflareAccountId.length,
        errorMessage: CloudflareErrorMessages.invalidAccount,
        validate: CloudflareAccountId.isValid,
      ),
    );

/// Explicitly consents to creating the permanent account-wide subdomain.
Future<String?> showCloudflareCreateSubdomainDialog(
  BuildContext context, {
  String? initial,
}) => _showNameDialog(
  context,
  const _NameDialogConfig(
    title: 'Create workers.dev subdomain',
    label: 'Account subdomain',
    helper: 'Letters, numbers, and hyphens',
    explanation:
        'This account has no workers.dev subdomain. Creating one is explicit '
        'and may be permanent. Pitak checks availability before creating it.',
    actionLabel: 'Create subdomain',
    maxLength: CloudflareSubdomain.maxLength,
    errorMessage: CloudflareErrorMessages.invalidSubdomain,
    validate: CloudflareSubdomain.isValid,
  ),
  initial: initial,
);

/// Accepts an existing subdomain only as an UNVERIFIED candidate (C9).
Future<String?> showCloudflareManualSubdomainDialog(
  BuildContext context, {
  String? initial,
}) => _showNameDialog(
  context,
  const _NameDialogConfig(
    title: 'Enter workers.dev subdomain',
    label: 'Account subdomain',
    helper: 'Letters, numbers, and hyphens',
    explanation:
        'The token cannot read this account-level setting. Pitak treats your '
        'answer as a guess until a verification marker is served from the '
        'exact Worker address. It will not become a share or publish address '
        'before that proof.',
    actionLabel: 'Continue',
    maxLength: CloudflareSubdomain.maxLength,
    errorMessage: CloudflareErrorMessages.invalidSubdomain,
    validate: CloudflareSubdomain.isValid,
  ),
  initial: initial,
);

/// Chooses the dedicated Worker name; adoption consent is a separate prompt.
Future<String?> showCloudflareWorkerNameDialog(
  BuildContext context, {
  String? initial,
}) => _showNameDialog(
  context,
  const _NameDialogConfig(
    title: 'Choose a Worker',
    label: 'Worker name',
    helper: 'Lower-case letters, numbers, and hyphens',
    explanation:
        'Use a Worker dedicated to Pitak. A new Worker is created by the first '
        'deployment. An existing Worker needs separate replacement consent. '
        'Cloudflare uses the name in your site address, which ignores case.',
    actionLabel: 'Continue',
    maxLength: CloudflareWorkerName.maxLength,
    errorMessage: CloudflareErrorMessages.invalidWorker,
    validate: CloudflareWorkerName.isValid,
    // RH2/D9: show the lower-cased name while the user types it, instead of
    // refusing an upper-case name after the fact. A stored mixed-case name
    // stays exactly as pre-filled until the user edits the field.
    formatters: [_LowerCaseTextFormatter()],
  ),
  initial: initial,
);

Future<String?> _showNameDialog(
  BuildContext context,
  _NameDialogConfig config, {
  String? initial,
}) => showDialog<String>(
  context: context,
  builder: (_) => _CloudflareNameDialog(config: config, initial: initial),
);

class _NameDialogConfig {
  const _NameDialogConfig({
    required this.title,
    required this.label,
    required this.helper,
    required this.explanation,
    required this.actionLabel,
    required this.maxLength,
    required this.errorMessage,
    required this.validate,
    this.formatters = const [],
  });

  final String title;
  final String label;
  final String helper;
  final String explanation;
  final String actionLabel;
  final int maxLength;
  final String errorMessage;
  final bool Function(String) validate;
  final List<TextInputFormatter> formatters;
}

/// Lower-cases a Worker name as it is entered (fix-plan RH2).
///
/// A new name becomes a DNS label, which ignores case; showing the lower-case
/// form while typing is clearer than a refusal later. Only ASCII letters are
/// expected here (`[A-Za-z0-9-]`), so lower-casing never changes the length.
class _LowerCaseTextFormatter extends TextInputFormatter {
  const _LowerCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lower = newValue.text.toLowerCase();
    if (lower == newValue.text) return newValue;
    return TextEditingValue(
      text: lower,
      selection: TextSelection.collapsed(offset: lower.length),
    );
  }
}

class _CloudflareNameDialog extends StatefulWidget {
  const _CloudflareNameDialog({required this.config, this.initial});

  final _NameDialogConfig config;
  final String? initial;

  @override
  State<_CloudflareNameDialog> createState() => _CloudflareNameDialogState();
}

class _CloudflareNameDialogState extends State<_CloudflareNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _name.text.trim();
    if (!widget.config.validate(value)) {
      setState(() => _error = widget.config.errorMessage);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.config.explanation),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: widget.config.maxLength,
              inputFormatters: widget.config.formatters,
              decoration: InputDecoration(
                labelText: widget.config.label,
                helperText: widget.config.helper,
                errorText: _error,
                counterText: '',
                border: const OutlineInputBorder(),
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
        FilledButton(
          onPressed: _submit,
          child: Text(widget.config.actionLabel),
        ),
      ],
    );
  }
}
