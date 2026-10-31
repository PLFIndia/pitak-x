/// Confirmation for resetting an UNREADABLE publishing record (N7/D10).
library;

import 'package:flutter/material.dart';

/// Explains exactly what a reset does and returns true only on confirmation.
Future<bool> showPublishJournalResetDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset the publishing record?'),
      content: const SingleChildScrollView(
        child: Text(
          'Pitak can’t read its record of where your library is published. '
          'This can happen after installing an older version.\n\n'
          'Reset the record? Your sites are not changed. Your share link is '
          'hidden until your next successful publish, and any unfinished move '
          'is cancelled; the old site keeps its current content.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep the record'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset record'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
