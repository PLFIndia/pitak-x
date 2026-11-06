/// Confirmation and cover-consent dialog for published-site restore.
library;

import 'package:flutter/material.dart';

/// Returns null for Cancel, otherwise the selected cover-consent value.
Future<bool?> showRestoreFromSiteDialog(
  BuildContext context, {
  required String siteUrl,
}) async {
  var downloadCovers = true;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Restore from this site'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(siteUrl),
              const SizedBox(height: 12),
              const Text(
                'This puts back every readable item and its public fields. '
                'Your catalogue must be empty.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Notes, descriptions, locations, copy counts, page counts and '
                'the loan vault are not on the website and cannot come back. '
                'The library name, map pin and hub lists are not restored '
                'either; re-enter them before publishing again.',
              ),
              CheckboxListTile(
                value: downloadCovers,
                onChanged: (value) =>
                    setState(() => downloadCovers = value ?? true),
                title: const Text('Also download covers'),
                subtitle: const Text(
                  'Same-site covers download now. Third-party cover links are '
                  'kept but not fetched during restore.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
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
            onPressed: () => Navigator.of(context).pop(downloadCovers),
            child: const Text('Restore'),
          ),
        ],
      ),
    ),
  );
  return accepted;
}
