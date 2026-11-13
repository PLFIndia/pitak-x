/// The two read-only views of the Restore screen (backup presentation):
/// what a picked archive contains, and what a finished restore did.
///
/// Moved out of `restore_page.dart` (plan S11) when the website publishing
/// record (ADR 0014 amendment, plan CV6/CV7) added its lines: the page sat at
/// the 500-line ratchet (docs/ARCHITECTURE.md §2.1). The copy is unchanged
/// except for those lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/display_date.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/restore_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/left_out_covers_note.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/publish/domain/publish_state_adoption.dart';

/// Shows what the picked archive contains, straight from the inspection (N13
/// + §5.10: including the identity it would adopt, named when readable).
class RestoreManifestSummary extends StatelessWidget {
  /// Creates the summary for [inspection].
  const RestoreManifestSummary({required this.inspection, super.key});

  /// The bounded, read-only look inside the picked archive.
  final ArchiveInspection inspection;

  @override
  Widget build(BuildContext context) {
    final manifest = inspection.manifest;
    final textTheme = Theme.of(context).textTheme;
    // M15: the manifest is untrusted. `dateFromMillisOrNull` returns null for
    // 0 (unset) AND for a value outside DateTime's range, where
    // `DateTime.fromMillisecondsSinceEpoch` would throw inside build().
    final exported = CatalogueRules.dateFromMillisOrNull(manifest.exportedAt);
    final date = exported == null ? null : formatDisplayDateTime(exported);
    // §5.10 copy: name the identity when the entry parsed; when the manifest
    // announces one that did NOT parse, say so instead of promising it.
    final identity = inspection.identity;
    final String? identityLine;
    if (identity != null) {
      identityLine = identity.name.isEmpty
          ? '• Library identity (restoring adopts it)'
          : '• Library identity for "${identity.name}" (restoring adopts it)';
    } else if (manifest.hasIdentity) {
      identityLine = '• Library identity (unreadable — it will not be adopted)';
    } else {
      identityLine = null;
    }
    // Plan CV6: name the website whose record the backup carries; when the
    // manifest announces one that did NOT parse, say it will not be used.
    final site = inspection.publishState?.activeSite?.siteUrl;
    final String? publishLine;
    if (inspection.publishState != null) {
      publishLine =
          '• Website publishing record${site == null ? '' : ' for $site'} '
          '(used only if this phone has not published yet)';
    } else if (manifest.hasPublishState) {
      publishLine =
          '• Website publishing record (unreadable — it will not be used)';
    } else {
      publishLine = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This backup contains:', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(manifest.hasBooks ? '• Books' : '• No books'),
        Text(manifest.hasWishlist ? '• Wishlist' : '• No wishlist'),
        Text(
          manifest.hasBackupBlob
              ? '• Borrowers vault (encrypted \u2014 passphrase required)'
              : '• No borrowers vault',
        ),
        if (manifest.hasCovers) const Text('• Cover images'),
        if (identityLine != null) Text(identityLine),
        if (identity?.publishedFingerprint != null)
          const Text(
            '• Published site identity (restoring adopts this public label; '
            'check that it came from your own backup)',
          ),
        if (manifest.hasNetwork) const Text('• Saved-libraries list'),
        if (publishLine != null) Text(publishLine),
        if (date != null) ...[
          const SizedBox(height: 4),
          Text('Made on: $date', style: textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Renders the typed restore outcome with user-safe copy (no raw exceptions).
class RestoreOutcome extends StatelessWidget {
  /// Creates the outcome view for the controller's [state].
  const RestoreOutcome({required this.state, super.key});

  /// The restore controller's state.
  final AsyncValue<RestoreSummary?> state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return state.when(
      loading: () => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();
        final String integrity;
        if (summary.existingVaultKept) {
          integrity =
              'The borrowers vault on this phone was kept. All existing '
              'loan links were checked and preserved, including returned '
              'loan history.';
        } else if (summary.isIntact) {
          integrity = 'All loans reference an existing book and borrower.';
        } else {
          integrity =
              '${summary.danglingLoans.length} loan(s) could not be matched '
              'after restore.';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restore complete',
              style: textTheme.titleMedium?.copyWith(color: scheme.primary),
            ),
            const SizedBox(height: 8),
            Text('Books restored: ${summary.booksRestored}'),
            Text('Wishlist restored: ${summary.wishlistRestored}'),
            if (summary.existingVaultKept)
              const Text(
                'Borrowers vault: kept from this phone (not in backup)',
              )
            else ...[
              Text('Borrowers restored: ${summary.borrowersRestored}'),
              Text('Loans restored: ${summary.loansRestored}'),
            ],
            const SizedBox(height: 8),
            Text(integrity, style: textTheme.bodySmall),
            // §5.10: one plain sentence each for the additive extras —
            // adoption/apply failures surface HERE, never as a rolled-back
            // catalogue.
            if (summary.identityInvalid)
              Text(
                'The library identity in this backup could not be read; '
                'your current identity is unchanged.',
                style: textTheme.bodySmall,
              )
            else if (summary.restoredIdentity != null)
              Text(
                // Three outcomes, three sentences: "unchanged" is only true
                // after a rollback, never when the ID was saved and the name
                // was not (review finding 4).
                summary.identityPartiallyAdopted
                    ? 'The backup’s library ID was saved, but its name was '
                          'not. Review this device’s library identity in '
                          'Settings.'
                    : summary.identityAdopted
                    ? 'This device now uses the backup’s library identity.'
                    : 'The library identity in this backup could not be '
                          'adopted; your current identity is unchanged.',
                style: textTheme.bodySmall,
              ),
            if (summary.networkInvalid)
              Text(
                'The saved-libraries list in this backup could not be read; '
                'your current list is unchanged.',
                style: textTheme.bodySmall,
              )
            else if (summary.restoredNetwork != null)
              Text(
                summary.networkApplied
                    ? 'Saved libraries restored: ${summary.networkRestored}'
                    : 'The saved-libraries list could not be written; your '
                          'current list is unchanged.',
                style: textTheme.bodySmall,
              ),
            // §6: dropped rows are counted AND named — a backup that quietly
            // loses libraries reads exactly like one that kept them.
            if (summary.networkRowsDropped > 0)
              Text(
                '${summary.networkRowsDropped} saved-libraries row(s) could '
                'not be read from the backup and were skipped.',
                style: textTheme.bodySmall,
              ),
            // W2 (ADR 0014): one plain sentence each for the item-kind
            // extras — the same additive-extras rule as above.
            if (summary.itemKindsInvalid)
              Text(
                'The item-kind list in this backup could not be read; '
                'magazine issues and other items were restored as books.',
                style: textTheme.bodySmall,
              ),
            if (summary.periodicalsInvalid)
              Text(
                'The magazine titles in this backup could not be read; '
                'no magazine titles were restored.',
                style: textTheme.bodySmall,
              ),
            if (summary.periodicalsRestored > 0)
              Text(
                'Magazine titles restored: ${summary.periodicalsRestored}',
                style: textTheme.bodySmall,
              ),
            // Plan CV7: one plain sentence for the website publishing
            // record — the same additive-extras rule as above.
            if (_publishStateLine(summary) case final line?)
              Text(line, style: textTheme.bodySmall),
            if (summary.hasAdjustments) ...[
              const SizedBox(height: 4),
              if (summary.coversDropped > 0)
                Text(
                  '${summary.coversDropped} cover link(s) were removed '
                  'because they pointed to unsupported sites.',
                  style: textTheme.bodySmall,
                ),
              // D18 + D23: a cover PICTURE above the size a restore takes
              // is skipped and its items are named, the way the
              // create-backup page names the ones it left out (D10).
              if (summary.coverPicturesLeftOut.isNotEmpty)
                LeftOutCoversNote(
                  key: const Key('restore-covers-left-out'),
                  sentence: restoreCoversLeftOutMessage(
                    summary.coverPicturesLeftOut.length,
                  ),
                  titles: summary.coverPicturesLeftOut,
                ),
              // W2: detached/skipped rows restore as plain books — said
              // plainly, never silently (§5.5: dropped and counted).
              if (summary.issuesDetached > 0)
                Text(
                  '${summary.issuesDetached} issue link(s) could not be '
                  'honoured; the affected items were restored as books.',
                  style: textTheme.bodySmall,
                ),
              // S5 (M2): entry drops are a DIFFERENT unit from detached rows —
              // say so separately, never summed into the sentence above.
              if (summary.issueEntriesDropped > 0)
                Text(
                  '${summary.issueEntriesDropped} issue detail(s) in the '
                  'backup could not be used and were ignored.',
                  style: textTheme.bodySmall,
                ),
              if (summary.rowsSkippedUnknownKind > 0)
                Text(
                  '${summary.rowsSkippedUnknownKind} item-kind row(s) in the '
                  'backup could not be read; the affected items were '
                  'restored as books.',
                  style: textTheme.bodySmall,
                ),
              if (summary.periodicalsDropped > 0)
                Text(
                  '${summary.periodicalsDropped} magazine-title row(s) in '
                  'the backup could not be read and were skipped.',
                  style: textTheme.bodySmall,
                ),
            ],
          ],
        );
      },
      error: (error, _) {
        final message = messageFor(error);
        return Text(
          message,
          style: textTheme.bodyMedium?.copyWith(color: scheme.error),
        );
      },
    );
  }

  /// The sentence about the website publishing record, or null when the
  /// backup carried none (plan CV7; "kept" is the plan's own wording, D.3).
  static String? _publishStateLine(RestoreSummary summary) {
    if (summary.publishStateInvalid) {
      return 'The website publishing record in this backup could not be '
          'read; publishing settings on this phone are unchanged.';
    }
    return switch (summary.publishStateOutcome) {
      null => null,
      PublishStateRestoreOutcome.adopted =>
        'This phone now continues the website from the backup: covers '
            'already online will not be uploaded again. If Publish asks you '
            'to connect, sign in to the same account and site.',
      PublishStateRestoreOutcome.keptThisPhone =>
        'Publishing settings on this phone were kept.',
      PublishStateRestoreOutcome.notApplied =>
        'The website publishing record in this backup could not be '
            'applied; publishing settings on this phone are unchanged.',
    };
  }

  /// Maps a sealed [Failure] to safe, user-facing copy (AGENTS.md §5: never
  /// surface raw exception text). Shared by the restore outcome and the
  /// archive-inspection error (N13).
  static String messageFor(Object error) {
    if (error is WrongPassphraseFailure) {
      return 'That passphrase did not unlock the backup. Please try again.';
    }
    if (error is SchemaTooNewFailure) {
      return 'This backup was made by a newer version of the app and can’t be '
          'restored here. Please update first.';
    }
    if (error is BackupCorruptFailure) {
      return 'This file doesn’t look like a valid Pitak backup.';
    }
    if (error is ValidationFailure) {
      return error.message;
    }
    if (error is StorageFailure) {
      return 'Something went wrong writing the restored data. '
          'Please try again.';
    }
    return 'Restore failed. Please try again.';
  }
}
