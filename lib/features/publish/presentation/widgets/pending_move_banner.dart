/// Persistent recovery surface for a destination-verified pending move.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/site/move_site_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';

/// Keeps Retry and the verified new address visible until completion or Skip.
class PendingMoveBanner extends ConsumerWidget {
  /// Creates the banner for the journal's exact pending operation.
  const PendingMoveBanner({required this.pending, super.key});

  /// Exact endpoints and immutable retirement descriptor.
  final PendingMove pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(moveSiteControllerProvider);
    return SectionCard(
      title: 'Finish moving your site',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The new site is verified. Your old address stays selected until '
            'retirement finishes.',
          ),
          const SizedBox(height: 8),
          SelectableText('Verified new address: ${pending.newTarget.siteUrl}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: operation.busy
                    ? null
                    : () => unawaited(_retry(context, ref)),
                child: Text(operation.busy ? 'Retrying…' : 'Retry move'),
              ),
              OutlinedButton(
                onPressed: operation.busy
                    ? null
                    : () => unawaited(_warnSkip(context, ref)),
                child: const Text('Skip retirement'),
              ),
            ],
          ),
          if (operation.result case MoveSiteFailure(:final reason)) ...[
            const SizedBox(height: 8),
            Text(reason),
          ],
          if (operation.result case MoveSiteSuccess(:final retirementSkipped))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                retirementSkipped
                    ? 'The new address is selected. The old site was not '
                          'retired.'
                    : 'Move complete. Reprint your library card.',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(moveSiteControllerProvider.notifier).retry();
    if (context.mounted && result is MoveSiteFailure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.reason)));
    }
  }

  Future<void> _warnSkip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip retiring the old site?'),
        content: const Text(
          'Use this only when the old repository, account or Worker no '
          'longer exists. Pitak will check first. The old site will not be '
          'marked as moved, and people using its address will not be '
          'redirected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Skip retirement'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref.read(moveSiteControllerProvider.notifier).skip();
    if (context.mounted && result is MoveSiteFailure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.reason)));
    }
  }
}
