/// The sentences the create-backup page shows when a backup is refused,
/// had to leave something out, or is still being packed (presentation
/// layer, AGENTS.md §5: typed failures in, safe text out, never raw
/// exception text).
///
/// WHY THIS FILE EXISTS (beginner note): the writer refuses to build a
/// backup its own reader could not restore (BR3). "Too large" alone leaves
/// the user guessing, so each reason gets one plain sentence with the two
/// numbers that matter: what the library has, and what a backup can hold.
/// Both numbers of a sentence use the same unit.
///
/// Pure functions, kept out of the page so they can be tested without
/// pumping a widget.
library;

import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/display_number.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';

/// Shown on the create-backup page before a backup is made (decision D12).
///
/// Why (beginner note): the backup format may gain things an older Pitak
/// does not know (more covers, larger files). The app promises one
/// direction only: a backup made by an OLDER version restores in a newer
/// one. For the other direction the honest thing is to say so up front,
/// and to say what to do about it.
const String backupNeedsThisVersionMessage =
    'A backup made with this version may not open in an older version of '
    'Pitak. Update Pitak on the other phone before you restore there.';

/// The sentence without numbers. Used when a failure does not say which
/// limit was hit or gives no numbers; it is still true.
const String backupTooLargeFallbackMessage =
    'This catalogue is too large for this backup format. '
    'Nothing was exported.';

const String _nothingExported = 'Nothing was exported.';

/// The line under the button while the cover pictures of a backup are
/// being packed (BR4 rider 3): "Cover 1,234 of 9,000".
///
/// Covers are what a large backup spends its time on, so their count is
/// the honest measure of how far it is. Both numbers are grouped in threes
/// like every other number on this page.
String backupProgressMessage(BackupProgress progress) =>
    'Cover ${formatCount(progress.coversDone)} of '
    '${formatCount(progress.coversTotal)}';

/// The sentence for a refused backup.
///
/// `failure.detail` carries the NAME of a [BackupOverflow] code (a plain
/// String, because `core/` must not import this feature). An unknown name or
/// missing numbers give [backupTooLargeFallbackMessage] instead of a guess.
String backupTooLargeMessage(BackupTooLargeFailure failure) {
  final code = BackupOverflow.values.asNameMap()[failure.detail];
  final actual = failure.actual;
  final limit = failure.limit;
  if (code == null || actual == null || limit == null) {
    return backupTooLargeFallbackMessage;
  }
  // The switch has no default ON PURPOSE: a new code does not compile until
  // it has a sentence here.
  return switch (code) {
    BackupOverflow.tooManyCovers =>
      'This library has ${formatCount(actual)} cover pictures; a backup can '
          'hold ${formatCount(limit)}. $_nothingExported',
    BackupOverflow.contentTooLarge => _size(
      actual,
      limit,
      (has, holds) =>
          'This library needs $has in a backup; a backup can hold $holds. '
          '$_nothingExported',
    ),
    BackupOverflow.archiveTooLarge => _size(
      actual,
      limit,
      (has, holds) =>
          'The backup file would be $has; the largest backup this app can '
          'read back is $holds. $_nothingExported',
    ),
    BackupOverflow.catalogueTooLarge => _part(
      'The list of your items',
      actual,
      limit,
    ),
    BackupOverflow.wishlistTooLarge => _part('Your wishlist', actual, limit),
    BackupOverflow.vaultTooLarge => _part('The borrowers vault', actual, limit),
    BackupOverflow.itemKindsTooLarge => _part(
      'The list of your magazine issues and other non-book items',
      actual,
      limit,
    ),
    BackupOverflow.periodicalsTooLarge => _part(
      'The list of your magazine titles and issues',
      actual,
      limit,
    ),
    BackupOverflow.entryTooLarge => _part(
      'One part of this backup',
      actual,
      limit,
    ),
    BackupOverflow.itemKindsTooManyRows =>
      'This library has ${formatCount(actual)} magazine issues and other '
          'non-book items; a backup can hold ${formatCount(limit)}. '
          '$_nothingExported',
    // The count is the longer of the two lists (titles, issues); the reader
    // caps each list separately, hence "of each".
    BackupOverflow.periodicalsTooManyRows =>
      'This library has ${formatCount(actual)} magazine titles or magazine '
          'issues; a backup can hold ${formatCount(limit)} of each. '
          '$_nothingExported',
  };
}

/// "<Part> takes 210.0 MB; a backup can hold 200.0 MB of it."
String _part(String part, int actual, int limit) => _size(
  actual,
  limit,
  (has, holds) =>
      '$part takes $has; a backup can hold $holds of it. $_nothingExported',
);

/// Formats the two sizes in one unit and hands them to [sentence].
String _size(
  int actual,
  int limit,
  String Function(String has, String holds) sentence,
) {
  final sizes = formatSizePair(actual, limit);
  return sentence(sizes.first, sizes.second);
}

/// How many titles the page lists under [coversLeftOutMessage] before it
/// says "and N more".
const int coversLeftOutTitlesShown = 3;

/// The sentence above the list of items whose cover picture is not inside
/// the backup (decision D10). [count] is the number of such items and must
/// be at least 1.
String coversLeftOutMessage(int count) => count == 1
    ? 'Note: the cover picture of 1 item is too large for a backup and is '
          'not inside. The item itself is inside:'
    : 'Note: the cover pictures of ${formatCount(count)} items are too '
          'large for a backup and are not inside. The items themselves are '
          'inside:';

/// The line under the listed titles when [count] items were left out and
/// only [coversLeftOutTitlesShown] are listed, or null when all are listed.
String? coversLeftOutMoreMessage(int count) {
  final more = count - coversLeftOutTitlesShown;
  return more > 0 ? 'and ${formatCount(more)} more' : null;
}
