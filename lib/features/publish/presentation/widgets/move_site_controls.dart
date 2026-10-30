/// Move entry point and progress/result copy for the publish card.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/site/move_site_controller.dart';
import 'package:pitaka/features/publish/application/site/move_site_result.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/presentation/widgets/move_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';

/// Starts write-free preparation; confirmation happens after queue release.
class MoveSiteControls extends ConsumerStatefulWidget {
  /// Creates controls, enabled only when both endpoints are eligible.
  const MoveSiteControls({required this.enabled, super.key});

  /// Whether source and destination preconditions currently hold.
  final bool enabled;

  @override
  ConsumerState<MoveSiteControls> createState() => _MoveSiteControlsState();
}

class _MoveSiteControlsState extends ConsumerState<MoveSiteControls> {
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(moveSiteControllerProvider);
    return SectionCard(
      title: 'Move your site',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Copy the complete catalogue and events site to your other '
            'publishing host, verify it, then retire the old address.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !widget.enabled || operation.busy || _dialogOpen
                ? null
                : () => unawaited(_prepareAndConfirm()),
            icon: const Icon(Icons.move_up),
            label: Text(operation.busy ? 'Moving…' : 'Move to other host'),
          ),
          if (operation.phase case final phase?) ...[
            const SizedBox(height: 8),
            Text(_phaseCopy(phase)),
          ],
          if (operation.result case final result?) ...[
            const SizedBox(height: 8),
            Text(_resultCopy(result)),
          ],
        ],
      ),
    );
  }

  Future<void> _prepareAndConfirm() async {
    final controller = ref.read(moveSiteControllerProvider.notifier);
    final prepared = await controller.prepare();
    if (!mounted || prepared is! MoveSiteConfirmationRequired) return;
    _dialogOpen = true;
    final confirmed = await showMoveSiteDialog(context, prepared.confirmation);
    _dialogOpen = false;
    if (!mounted || !confirmed) return;
    await controller.confirm(prepared.confirmation);
  }

  static String _phaseCopy(MoveSitePhase phase) => switch (phase) {
    MoveSitePhase.preparingSnapshot => 'Preparing snapshot…',
    MoveSitePhase.checkingSites => 'Checking both sites…',
    MoveSitePhase.publishingDestination => 'Publishing destination…',
    // A first GitHub Pages build routinely takes minutes; say so up front.
    MoveSitePhase.verifyingDestination =>
      'Verifying the new site… This can take a few minutes.',
    MoveSitePhase.recordingMove => 'Recording move…',
    MoveSitePhase.updatingOldAddress => 'Updating old address…',
    MoveSitePhase.verifyingOldAddress => 'Verifying old address…',
    // L17: a GitHub Pages moved page waits for a build that can take minutes.
    MoveSitePhase.verifyingOldAddressGitHubPages =>
      'Verifying the old address… ${ReadBackBudget.gitHubPagesWaitNote}',
  };

  static String _resultCopy(MoveSiteResult result) => switch (result) {
    MoveSiteConfirmationRequired() => 'Review the move to continue.',
    MoveSiteFailure(:final reason) => reason,
    MoveSiteAbandoned(:final oldTarget, :final newTarget) =>
      MoveSiteMessages.moveCancelled(oldTarget.siteUrl, newTarget.siteUrl),
    MoveSiteSuccess(
      :final retirementSkipped,
      :final temporaryCleanupFailed,
      :final localStateSaved,
    ) =>
      retirementSkipped
          ? 'New address selected. The old site was not retired.'
          : !localStateSaved
          ? 'The move completed, but local state needs recovery. Retry.'
          : temporaryCleanupFailed
          ? 'Move complete. Temporary file cleanup needs attention.'
          : 'Move complete. Reprint your library card.',
  };
}
