/// Persistent recovery surface for a destination-verified pending move.
///
/// Three explicit exits (fix-plan M4): Retry move, Skip retirement, Cancel
/// move. "Finish without retiring" appears only after the Skip check proved
/// Pitak cannot sign in to the old site, so the user is never offered a
/// destructive-looking action before it is the honest one.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/site/move_site_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
import 'package:pitaka/features/publish/presentation/widgets/pending_move_dialogs.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';

/// Keeps Retry, Skip and Cancel visible until the move is resolved.
class PendingMoveBanner extends ConsumerWidget {
  /// Creates the banner for the journal's exact pending operation.
  const PendingMoveBanner({required this.pending, super.key});

  /// Exact endpoints and immutable retirement descriptor.
  final PendingMove pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operation = ref.watch(moveSiteControllerProvider);
    final result = operation.result;
    final canFinish =
        result is MoveSiteFailure && result.canFinishWithoutRetiring;
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
              if (canFinish)
                FilledButton.tonal(
                  onPressed: operation.busy
                      ? null
                      : () => unawaited(
                          _finishWithoutRetiring(context, ref, result),
                        ),
                  child: const Text('Finish without retiring'),
                )
              else
                OutlinedButton(
                  onPressed: operation.busy
                      ? null
                      : () => unawaited(_warnSkip(context, ref)),
                  child: const Text('Skip retirement'),
                ),
              TextButton(
                onPressed: operation.busy
                    ? null
                    : () => unawaited(_warnCancel(context, ref)),
                child: const Text('Cancel move'),
              ),
            ],
          ),
          if (result case MoveSiteFailure(:final reason)) ...[
            const SizedBox(height: 8),
            Text(reason),
          ],
          if (result case MoveSiteSuccess(:final retirementSkipped))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                retirementSkipped
                    ? 'The new address is selected. The old site was not '
                          'retired.'
                    : 'Move complete. Reprint your library card.',
              ),
            ),
          if (result case MoveSiteAbandoned(:final oldTarget, :final newTarget))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                MoveSiteMessages.moveCancelled(
                  oldTarget.siteUrl,
                  newTarget.siteUrl,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(moveSiteControllerProvider.notifier).retry();
    if (context.mounted && result is MoveSiteFailure) {
      _report(context, result.reason);
    }
  }

  Future<void> _warnSkip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showSkipRetirementDialog(
      context,
      newAddress: pending.newTarget.siteUrl,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref.read(moveSiteControllerProvider.notifier).skip();
    if (context.mounted && result is MoveSiteFailure) {
      _report(context, result.reason);
    }
  }

  Future<void> _finishWithoutRetiring(
    BuildContext context,
    WidgetRef ref,
    MoveSiteFailure previous,
  ) async {
    final confirmed = await showFinishWithoutRetiringDialog(
      context,
      oldAddress: pending.oldTarget.siteUrl,
      newAddress: pending.newTarget.siteUrl,
      oldSiteAnswers: previous.oldSiteAnswers,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(moveSiteControllerProvider.notifier)
        .finishWithoutRetiring();
    if (context.mounted && result is MoveSiteFailure) {
      _report(context, result.reason);
    }
  }

  Future<void> _warnCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCancelMoveDialog(
      context,
      oldAddress: pending.oldTarget.siteUrl,
      newAddress: pending.newTarget.siteUrl,
      oldHost: pending.oldTarget.host,
    );
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(moveSiteControllerProvider.notifier)
        .abandon();
    if (context.mounted && result is MoveSiteFailure) {
      _report(context, result.reason);
    }
  }

  void _report(BuildContext context, String reason) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
  }
}
