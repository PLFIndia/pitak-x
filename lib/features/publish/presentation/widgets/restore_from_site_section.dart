/// Connection-tab entry point and progress for published-site restore.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_controller.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_state.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/restore_from_site_summary.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';

/// Shows Restore only while an active publish target exists.
class RestoreFromSiteSection extends ConsumerWidget {
  /// Creates the restore section.
  const RestoreFromSiteSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = ref.watch(publishSiteStatusProvider).valueOrNull;
    final target = site?.target;
    if (target == null) return const SizedBox.shrink();
    final state = ref.watch(restoreFromPublishedSiteControllerProvider);
    final pending = ref.watch(pendingRestoreIdentityProvider);
    final controller = ref.read(
      restoreFromPublishedSiteControllerProvider.notifier,
    );
    return SectionCard(
      title: 'Restore from this site',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.isRunning) ...[
            Text(_progressText(state.progress)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            if (state.canCancel) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: controller.cancel,
                child: const Text('Cancel restore'),
              ),
            ],
          ] else ...[
            if (state.summary case final summary?)
              RestoreFromSiteSummary(
                summary: summary,
                onRecoverIdentity: () =>
                    unawaited(controller.finishIdentityRecovery()),
                showIdentityRecoveryAction: pending.valueOrNull == null,
              ),
            if (state.status == RestoreFromPublishedSiteStatus.cancelled)
              const Text('Restore cancelled. Nothing was imported.'),
            if (state.failure case final failure?) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage(failure),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            pending.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Checking recovery status…'),
              ),
              error: (_, _) => const Text(
                'Recovery status could not be read. Restore is unavailable '
                'until the app can read its recovery state.',
              ),
              data: (journal) {
                if (journal != null) {
                  return _PendingIdentityRecovery(
                    journal: journal,
                    onRecover: () =>
                        unawaited(controller.finishIdentityRecovery()),
                  );
                }
                if (state.summary != null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reconnect your own hosting account, then put the public '
                      'catalogue back into an empty app.',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(
                        _confirmAndRestore(context, ref, target.siteUrl),
                      ),
                      icon: const Icon(Icons.restore),
                      label: const Text('Restore from this site'),
                    ),
                  ],
                );
              },
            ),
            if (state.status == RestoreFromPublishedSiteStatus.success ||
                state.status == RestoreFromPublishedSiteStatus.error ||
                state.status == RestoreFromPublishedSiteStatus.cancelled) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: controller.clearResult,
                child: const Text('Done'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static Future<void> _confirmAndRestore(
    BuildContext context,
    WidgetRef ref,
    String siteUrl,
  ) async {
    final covers = await showRestoreFromSiteDialog(context, siteUrl: siteUrl);
    if (covers == null || !context.mounted) return;
    await ref
        .read(restoreFromPublishedSiteControllerProvider.notifier)
        .restore(downloadCovers: covers);
  }

  static String _progressText(RestoreFromPublishedSiteProgress progress) =>
      switch (progress.phase) {
        RestoreFromPublishedSitePhase.reading => 'Reading your published site…',
        RestoreFromPublishedSitePhase.covers =>
          'Downloading covers ${progress.completed}/${progress.total}',
        RestoreFromPublishedSitePhase.writing => 'Writing your catalogue…',
      };

  static String _errorMessage(Failure failure) => switch (failure) {
    ValidationFailure(:final message) => message,
    SchemaTooNewFailure() =>
      'This site was written by a newer version of Pitak. Update before '
          'restoring so no data is lost.',
    StorageFailure() =>
      'Pitak could not save the restored data or identity. Please try again.',
    _ => 'Restore failed. Please try again.',
  };
}

/// Journal-backed action shown even when no controller summary survived a
/// process restart. The bound address explains which site must be reconnected.
class _PendingIdentityRecovery extends StatelessWidget {
  const _PendingIdentityRecovery({
    required this.journal,
    required this.onRecover,
  });

  final RestoreIdentityJournal journal;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Published identity recovery pending',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Finish saving the published identity for ${journal.siteUrl}. '
          'Reconnect that same site if it is not connected.',
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onRecover,
          child: const Text('Finish identity recovery'),
        ),
      ],
    );
  }
}
