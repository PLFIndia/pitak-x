/// Dedicated-Worker replacement and marker-only verification consent dialogs.
library;

import 'package:flutter/material.dart';

/// Requires explicit whole-Worker replacement consent before adoption.
Future<bool> showCloudflareWorkerReplacementDialog(
  BuildContext context, {
  required String workerName,
  required bool verificationRequested,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Use this Worker for Pitak?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Worker: $workerName'),
            const SizedBox(height: 12),
            const Text(
              'This Worker is dedicated to Pitak. Verification or publishing '
              'replaces ALL assets currently on it. Files that exist only on '
              'the Worker will be removed.',
            ),
            if (verificationRequested) ...[
              const SizedBox(height: 12),
              const Text(
                'After you consent, Pitak resumes the marker-only address '
                'verification you already approved.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Replace Worker assets'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

/// Explains and confirms the narrow manual-address verification deployment.
Future<bool> showCloudflareVerificationDialog(
  BuildContext context, {
  required String workerName,
  required bool workerExists,
  bool isActiveSite = false,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Verify the Cloudflare address?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Worker: $workerName'),
            const SizedBox(height: 12),
            Text(
              workerExists
                  ? 'This Worker is dedicated to Pitak. Verification replaces '
                        'ALL assets currently on it.'
                  : 'Pitak creates this Worker with only a small verification '
                        'marker.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Pitak deploys only pitak-publish.json with a fresh verification '
              'state, enables workers.dev, and confirms Version URLs are off. '
              'It then reads that exact marker from the candidate address.',
            ),
            if (isActiveSite) ...[
              const SizedBox(height: 12),
              const Text(
                'This Worker is your live site. Verifying it replaces the '
                'whole site with a test page until you publish again.',
              ),
            ],
            const SizedBox(height: 12),
            Text(
              isActiveSite
                  ? 'No catalogue, events, or library.json is uploaded. The '
                        'address becomes a publish target only after '
                        'exact-origin verification succeeds.'
                  : 'No catalogue, events, or library.json is uploaded. Your '
                        'other active site is not retired or changed. The '
                        'address becomes a publish target only after '
                        'exact-origin verification succeeds.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Deploy verification marker'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
