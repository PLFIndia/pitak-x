/// Explicit whole-site move confirmation (D.4), with no business logic.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Shows the exact reviewed endpoints and complete-snapshot consequences.
Future<bool> showMoveSiteDialog(
  BuildContext context,
  MoveSiteConfirmation confirmation,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Move your library site?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Current address:'),
            SelectableText(confirmation.oldTarget.siteUrl),
            const SizedBox(height: 8),
            const Text('New address:'),
            SelectableText(confirmation.newTarget.siteUrl),
            if (confirmation.destinationWarning case final warning?) ...[
              const SizedBox(height: 12),
              Text(warning),
            ],
            const SizedBox(height: 12),
            Text(
              'A complete snapshot with ${confirmation.catalogueItemCount} '
              'catalogue items and ${confirmation.posterCount} event posters '
              'will be published and verified first.',
            ),
            if (confirmation.catalogueIsEmpty)
              const Text('Your catalogue has 0 items.'),
            if (confirmation.eventsIsEmpty)
              const Text('Your events page will be empty.'),
            const SizedBox(height: 8),
            const Text(
              'The current site stays untouched until the new site passes '
              'verification. The old address then becomes a moved page.',
            ),
            const SizedBox(height: 8),
            Text(
              confirmation.oldTarget.host == PublishHost.cloudflare
                  ? 'Cloudflare retirement removes every other asset on the '
                        'dedicated Worker.'
                  : 'GitHub retirement touches only Pitak-owned paths that '
                        'you already consented to publish.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Peers do not follow automatically. They can add the new '
              'address and confirm reconciliation when offered.',
            ),
            const SizedBox(height: 8),
            const Text('Reprint your library card after the move.'),
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
          // L16: a move over content this phone did not publish is a
          // replacement, and the action must say so.
          child: Text(
            confirmation.replacesDestinationContent
                ? 'Replace and move'
                : 'Move library',
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
