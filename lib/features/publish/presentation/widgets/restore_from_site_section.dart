/// Connection-tab entry point and progress for published-site restore.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_controller.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_progress.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_state.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
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
            if (state.summary == null) ...[
              const Text(
                'Reconnect your own hosting account, then put the public '
                'catalogue back into an empty app.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    unawaited(_confirmAndRestore(context, ref, target.siteUrl)),
                icon: const Icon(Icons.restore),
                label: const Text('Restore from this site'),
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
