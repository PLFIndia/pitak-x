/// Detailed, honest summary of a published-site restore.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/restore/restore_from_published_site_result.dart';

/// Renders counts, losses, identity state and follow-up actions.
class RestoreFromSiteSummary extends StatelessWidget {
  /// Creates the summary view.
  const RestoreFromSiteSummary({
    required this.summary,
    required this.onRecoverIdentity,
    super.key,
  });

  /// Structured restore outcome.
  final RestoreFromPublishedSiteSummary summary;

  /// Starts identity-only recovery when a handoff is pending.
  final VoidCallback onRecoverIdentity;

  @override
  Widget build(BuildContext context) {
    final import = summary.import;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.identityPending
              ? 'Catalogue restored; identity recovery still needs to finish.'
              : 'Restore complete',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text('Items added: ${summary.itemsAdded}'),
        Text('Magazine titles added: ${summary.periodicalsAdded}'),
        if (import.booksSkipped > 0)
          Text(
            'Duplicate items skipped: ${import.booksSkipped} '
            '(matching ISBN or issue identity)',
          ),
        if (import.periodicalsSkipped > 0)
          Text(
            'Duplicate magazine titles skipped: '
            '${import.periodicalsSkipped} (matching ISSN or series identity)',
          ),
        if (summary.rowsDropped > 0)
          Text('Unreadable rows dropped: ${summary.rowsDropped}'),
        if (summary.droppedFields > 0)
          Text('Unreadable optional fields dropped: ${summary.droppedFields}'),
        if (summary.issuesFiledAsBooks > 0)
          Text(
            '${summary.issuesFiledAsBooks} issue(s) were added as books '
            'because their magazine title was not on the site.',
          ),
        if (!summary.downloadCovers)
          Text(
            'Same-site covers not downloaded: ${summary.coversSkipped}. '
            'Their references were left empty.',
          )
        else ...[
          Text('Covers restored: ${summary.coversRestored}'),
          if (summary.coversSkipped > 0)
            Text('Covers skipped or failed: ${summary.coversSkipped}'),
        ],
        if (summary.coversSkippedByBudget > 0)
          Text(
            '${summary.coversSkippedByBudget} cover(s) were skipped because a '
            'download budget was reached; their references were left empty.',
          ),
        if (summary.thirdPartyCoverLinks > 0)
          Text(
            '${summary.thirdPartyCoverLinks} third-party cover link(s) were '
            'kept but not downloaded. They load later only with your '
            'remote-cover consent.',
          ),
        for (final warning in import.warnings) Text(warning),
        const SizedBox(height: 8),
        if (summary.identityMissing)
          const Text(
            'The site had no usable published identity. Other libraries that '
            'saved yours may need to add it again.',
          ),
        if (summary.identityPending) ...[
          const Text(
            'The published fingerprint is not saved yet. Finish identity '
            'recovery before publishing or making a backup that is meant to '
            'preserve this site identity.',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRecoverIdentity,
            child: const Text('Finish identity recovery'),
          ),
        ] else if (!summary.identityMissing) ...[
          const Text(
            'The published fingerprint was preserved, so readers do not need '
            'to remove and re-add this library.',
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'The site name, map pin and hub lists were not restored. Re-enter '
          'them before publishing; readers will see those changes. Private '
          'notes, descriptions, locations, copy counts, page counts, added '
          'dates and loans cannot come back from the website.',
        ),
        if (!summary.identityPending && !summary.identityMissing)
          const Text(
            'Make a backup now (Settings → Backup) so next time nothing is '
            'lost.',
          ),
      ],
    );
  }
}
