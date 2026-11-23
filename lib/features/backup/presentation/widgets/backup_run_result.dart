/// What the Create backup page says when a run has ended (presentation
/// layer): one sentence, and under a success the notes about what the
/// finished backup does not carry.
///
/// WHY A WIDGET OF ITS OWN (beginner note): the page brings this block into
/// view when a run ends (decision D177), and for that it needs ONE thing to
/// point at: the whole result, and its first line. It also keeps the page
/// under its size limit.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/live_region.dart';
import 'package:pitaka/features/backup/presentation/create_backup_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/left_out_covers_note.dart';

/// The result of the last run. At most one of [success], [notice] and
/// [error] is set; with none of them the widget takes no room.
class BackupRunResult extends StatelessWidget {
  /// Creates the result block.
  const BackupRunResult({
    required this.sentenceKey,
    required this.success,
    required this.notice,
    required this.error,
    required this.vaultLeftOut,
    required this.missingDescription,
    required this.coversLeftOut,
    super.key,
  });

  /// Key of the sentence itself: the first line of the block.
  final GlobalKey sentenceKey;

  /// The backup was saved, or handed to an app. The notes follow it.
  final String? success;

  /// The user left the system's window. Said plainly, not as an error.
  final String? notice;

  /// The run failed.
  final String? error;

  /// BR4 rider 2 (decision D17): this phone has a borrowers vault, and the
  /// finished backup does not carry it.
  final bool vaultLeftOut;

  /// §7 S6: what the finished backup could not carry, in plain words ("your
  /// library identity and your saved-libraries list"), or null.
  final String? missingDescription;

  /// BR3 (decision D10): titles of the items whose cover picture was left
  /// out of the finished backup.
  final List<String> coversLeftOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final Widget sentence;
    if (success case final text?) {
      sentence = Text(
        text,
        key: sentenceKey,
        style: TextStyle(color: theme.colorScheme.primary),
      );
    } else if (notice case final text?) {
      sentence = Text(
        text,
        key: sentenceKey,
        style: theme.textTheme.bodyMedium,
      );
    } else if (error case final text?) {
      sentence = Text(
        text,
        key: sentenceKey,
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else {
      return const SizedBox.shrink();
    }
    // Decision D190: the whole result is read out by a screen reader when
    // it appears, the sentence first and then its notes. It is the same
    // block the page scrolls into view (D177). With no result the widget
    // has returned above, so a region exists only while there is one.
    return LiveRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          sentence,
          // The notes say what "the backup" does not carry, so they stand
          // under a success only: after any other end there is no backup.
          if (success != null) ...[
            // BR4 rider 2: first among the notes, because borrowers and
            // loans are the largest thing a backup can be missing.
            if (vaultLeftOut) ...[
              const SizedBox(height: 4),
              Text(
                backupVaultLeftOutMessage,
                key: const Key('backup-vault-left-out'),
                style: small,
              ),
            ],
            if (missingDescription case final missing?) ...[
              const SizedBox(height: 4),
              Text(
                'Note: this backup does not carry $missing — it could not be '
                'read. Everything else is inside.',
                style: small,
              ),
            ],
            if (coversLeftOut.isNotEmpty) ...[
              const SizedBox(height: 4),
              // BR3 (decision D10): which items' cover pictures are NOT
              // inside the finished backup. The restore page uses the same
              // note with its own sentence.
              LeftOutCoversNote(
                sentence: coversLeftOutMessage(coversLeftOut.length),
                titles: coversLeftOut,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
