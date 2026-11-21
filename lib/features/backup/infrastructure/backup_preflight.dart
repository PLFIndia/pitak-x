/// The checks the backup writer runs BEFORE it builds the ZIP (backup
/// infrastructure, BR3; closes review finding P1-M1 at today's limits).
///
/// WHY THIS FILE EXISTS (beginner note): the restore reader refuses a backup
/// with too many entries or too much content. Before BR3 the writer did not
/// look, so a large library could get a backup that can never be restored,
/// and nobody would know until the day it was needed. The functions here let
/// the writer find that out first and say so, with the numbers.
///
/// Everything in this file is PURE: it gets names and sizes and gives back a
/// decision. It opens no file (a streamed entry carries only the PATH of
/// its file). The writer does the file work and asks here, which keeps the
/// rules easy to test with small limits and no disk.
///
/// In its own file because the writer is close to the 500-line ceiling.
library;

import 'dart:typed_data';

import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/domain/cover_item_titles.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show coverEntryPrefix;
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// One cover picture file: its file name (`leaf`) and its size. The writer
/// gets both from the folder listing, without opening the file.
typedef CoverFileSize = ({String leaf, int bytes});

/// Which cover pictures go into the backup (`kept`), and the titles of the
/// items whose picture does not (`leftOutTitles`).
typedef CoverSelection = ({
  List<CoverFileSize> kept,
  List<String> leftOutTitles,
});

/// Splits the cover [files] into those a backup can hold and those it cannot
/// (decision D10).
///
/// A picture larger than [maxCoverBytes] is left out instead of failing the
/// whole backup: a backup that does not happen is the larger risk. Nothing is
/// hidden, because every item that refers to such a picture is named:
/// [books], [wishlist] entries and magazine titles ([periodicals]), in that
/// order. A picture exactly AT the cap is kept.
///
/// An oversized file that no item refers to is left out without a title:
/// there is nothing to name.
CoverSelection selectBackupCovers({
  required List<CoverFileSize> files,
  required int maxCoverBytes,
  required List<CatalogueItem> books,
  required List<WishlistBook> wishlist,
  required List<Periodical> periodicals,
}) {
  final kept = <CoverFileSize>[];
  final tooLarge = <String>{};
  for (final file in files) {
    if (file.bytes > maxCoverBytes) {
      tooLarge.add(file.leaf);
    } else {
      kept.add(file);
    }
  }
  // The rule "which items show one of these pictures" is shared with the
  // restore side (`cover_item_titles.dart`), so the two notes cannot name
  // different items for the same picture.
  return (
    kept: kept,
    leftOutTitles: titlesOfItemsWithCover(
      coverLeaves: tooLarge,
      books: books,
      wishlist: wishlist,
      periodicals: periodicals,
    ),
  );
}

/// One entry the archive is going to hold: its [name], the size the checks
/// judged ([bytes]), and how to get its content when its turn comes.
///
/// Why the content is fetched late (beginner note): a backup can hold
/// thousands of covers. Measuring them is cheap; reading them is not. So the
/// writer first describes every entry, lets [backupRefusalFor] decide, and
/// reads a file only when it is about to go into the ZIP.
///
/// Two kinds of entry since BR4:
///  - one that is read WHOLE when its turn comes (the default constructor):
///    a text entry that is in memory anyway, or one cover picture, which is
///    small;
///  - one that is STREAMED from a file ([PlannedBackupEntry.streamed]): a
///    database, which can be far too large to hold in memory. Only its path
///    is kept here; the ZIP writer reads it in small pieces.
final class PlannedBackupEntry {
  /// Creates an entry that is read whole. The third argument fetches the
  /// content; it is called once, by [content].
  const PlannedBackupEntry(this.name, this.bytes, Uint8List Function() read)
    : _read = read,
      streamPath = null;

  /// Creates an entry that is fed to the ZIP from the file at [path], in
  /// small pieces. [bytes] is the file's size as measured for the checks.
  const PlannedBackupEntry.streamed(this.name, this.bytes, String path)
    : _read = null,
      streamPath = path;

  /// The entry's name inside the archive.
  final String name;

  /// The entry's size in bytes, as measured for the checks.
  final int bytes;

  /// The file a streamed entry is read from. Null for an entry that is
  /// read whole.
  final String? streamPath;

  final Uint8List Function()? _read;

  /// Whether this entry is a cover picture (by its name, the one rule the
  /// reader also uses).
  bool get isCover => name.startsWith(coverEntryPrefix);

  /// The content of an entry that is read whole. Throws a [StateError] when
  /// it is not exactly [bytes] long: the file changed after it was measured,
  /// so the checks no longer describe it. The build then fails as a whole
  /// (fail closed) and can simply be run again.
  ///
  /// Also throws a [StateError] for a streamed entry, which has no content
  /// in memory by design.
  Uint8List content() {
    final read = _read;
    if (read == null) {
      throw StateError(
        'Backup entry "$name" is streamed from a file; it has no content '
        'in memory',
      );
    }
    final content = read();
    if (content.length != bytes) {
      throw StateError(
        'Backup entry "$name" changed size while the backup was being built',
      );
    }
    return content;
  }
}

/// The reason the reader would refuse a backup made of [entries], or null
/// when it fits [limits]. The checks, in order:
///
///  1. more cover pictures than one backup holds;
///  2. a single entry larger than its cap ([backupEntryCap]);
///  3. more content in total than one backup holds.
///
/// Every comparison is "larger than": exactly at a limit is fine, as it is
/// for the reader.
///
/// Throws a [StateError] for an entry name without a cap, or for more
/// non-cover entries than [BackupLimits.otherEntries]. Both mean the writer
/// was changed without this table, which is a bug: it must not produce a
/// backup nobody checked.
BackupRefusal? backupRefusalFor(
  List<PlannedBackupEntry> entries,
  BackupLimits limits,
) {
  var covers = 0;
  for (final entry in entries) {
    if (entry.isCover) covers++;
  }
  if (covers > limits.maxCovers) {
    return (
      code: BackupOverflow.tooManyCovers,
      actual: covers,
      limit: limits.maxCovers,
    );
  }
  if (entries.length - covers > BackupLimits.otherEntries) {
    throw StateError(
      'A backup has ${entries.length - covers} entries besides covers; '
      'BackupLimits.otherEntries allows ${BackupLimits.otherEntries}',
    );
  }

  var total = 0;
  for (final entry in entries) {
    final cap = backupEntryCap(entry.name, limits);
    if (cap == null) {
      throw StateError('Backup entry "${entry.name}" has no size cap');
    }
    if (entry.bytes > cap) {
      return (
        code: backupEntryOverflow(entry.name),
        actual: entry.bytes,
        limit: cap,
      );
    }
    total += entry.bytes;
  }
  if (total > limits.maxContentBytes) {
    return (
      code: BackupOverflow.contentTooLarge,
      actual: total,
      limit: limits.maxContentBytes,
    );
  }
  return null;
}
