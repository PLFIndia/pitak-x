/// Explicit unknown-state whole-Worker replacement confirmation (D.3/R4).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';

/// Shows the reviewed counts and returns true only for explicit replacement.
Future<bool> showReplaceSiteDialog(
  BuildContext context,
  PublishReplacementSummary summary,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Replace your Cloudflare site?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This phone has no verified record of the current site. '
              'Publishing replaces the whole Worker with this phone’s '
              'catalogue (${summary.catalogueItemCount} items) and '
              '${summary.posterCount} event posters. Anything only on the '
              'site — including a newer catalogue or other posters — will be '
              'removed.',
            ),
            if (summary.catalogueIsEmpty) ...[
              const SizedBox(height: 12),
              const Text('Your catalogue has 0 items'),
            ],
            if (summary.eventsIsEmpty) ...[
              const SizedBox(height: 12),
              const Text('Your events page will be empty'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Replace the site'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
