/// Confirmation for forgetting an UNREADABLE Cloudflare connection (M7).
library;

import 'package:flutter/material.dart';

/// Explains exactly what is and is not deleted, then returns true to forget.
Future<bool> showForgetCloudflareConnectionDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Forget Cloudflare connection?'),
      content: const SingleChildScrollView(
        child: Text(
          'Pitak deletes only the Cloudflare token stored on this phone. '
          'Your public site, its Worker and your share link are not changed.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Forget connection'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
