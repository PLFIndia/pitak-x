/// The three explicit exits from a pending move (fix-plan M4).
///
/// Kept out of `pending_move_banner.dart` so the banner stays a small renderer
/// and the copy lives in one place. Every dialog returns a bool: true means the
/// user chose the action, false means they backed out and nothing happens.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// Asks before cancelling a pending move. Both sites are untouched.
Future<bool> showCancelMoveDialog(
  BuildContext context, {
  required String oldAddress,
  required String newAddress,
  required PublishHost oldHost,
}) async {
  final host = oldHost == PublishHost.github ? 'GitHub' : 'Cloudflare';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancel this move?'),
      content: Text(
        'Pitak will keep publishing to your current site at $oldAddress. '
        'Your share link and card stay the same.\n\n'
        'The new site at $newAddress was already published and stays online '
        'with a copy of your library. Pitak will not change or delete it; '
        'delete it in your $host account if you do not want it online.\n\n'
        'You can start the move again later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep the move pending'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Cancel move'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Asks before skipping retirement of a site that is confirmed gone.
Future<bool> showSkipRetirementDialog(
  BuildContext context, {
  required String newAddress,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Skip retiring the old site?'),
      content: Text(
        'Use this only when the old GitHub repository or Cloudflare Worker '
        'was deleted. Pitak checks first and stops if it still exists.\n\n'
        'Your share link switches to $newAddress. The old address will not '
        'show a moved page.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Skip retirement'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Asks before finishing a move whose old site cannot be signed in to.
///
/// [oldSiteAnswers] selects the honest body: a site that still answers keeps
/// showing old information, while one that does not answer may come back.
Future<bool> showFinishWithoutRetiringDialog(
  BuildContext context, {
  required String oldAddress,
  required String newAddress,
  required bool oldSiteAnswers,
}) async {
  final body = oldSiteAnswers
      ? 'Your old site at $oldAddress still shows your library as it was. '
            'Pitak cannot change or remove it, so visitors there will see old '
            'information and will not be sent to $newAddress.\n\n'
            'Your share link and card will switch to $newAddress. Reprint '
            'your card.'
      : 'Your old site at $oldAddress no longer answers and Pitak cannot sign '
            'in to its account. If it comes back, it will show old '
            'information.\n\n'
            'Your share link and card will switch to $newAddress.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Finish the move without retiring?'),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Finish move'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
