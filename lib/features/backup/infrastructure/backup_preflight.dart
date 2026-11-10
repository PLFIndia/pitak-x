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
/// decision. It opens no file. The writer does the file work and asks here,
/// which keeps the rules easy to test with small limits and no disk.
///
/// In its own file because the writer is close to the 500-line ceiling.
library;

import 'dart:typed_data';

import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_entry_bounds.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show coverEntryPrefix;
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
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
  if (tooLarge.isEmpty) return (kept: kept, leftOutTitles: const []);

  // `CoverPaths.leafOf` is the app's one rule for "which file does this
  // cover reference name"; a remote or unsafe reference names none.
  bool pictureLeftOut(String? coverUrl) {
    final leaf = CoverPaths.leafOf(coverUrl);
    return leaf != null && tooLarge.contains(leaf);
  }

  return (
    kept: kept,
    leftOutTitles: [
      for (final book in books)
        if (pictureLeftOut(book.coverUrl)) book.title,
      for (final wish in wishlist)
        if (pictureLeftOut(wish.coverUrl)) wish.title,
      for (final periodical in periodicals)
        if (pictureLeftOut(periodical.coverUrl)) periodical.title,
    ],
  );
}

/// One entry the archive is going to hold: its [name], the size the checks
/// judged ([bytes]), and how to get its content when its turn comes.
///
/// Why the content is fetched late (beginner note): a backup can hold
/// thousands of covers. Measuring them is cheap; reading them is not. So the
/// writer first describes every entry, lets [backupRefusalFor] decide, and
/// reads a file only when it is about to go into the ZIP.
final class PlannedBackupEntry {
  /// Creates a planned entry. The third argument fetches the content; it is
  /// called once, by [content].
  const PlannedBackupEntry(this.name, this.bytes, this._read);

  /// The entry's name inside the archive.
  final String name;

  /// The entry's size in bytes, as measured for the checks.
  final int bytes;

  final Uint8List Function() _read;

  /// The entry's content. Throws a [StateError] when it is not exactly
  /// [bytes] long: the file changed after it was measured, so the checks no
  /// longer describe it. The build then fails as a whole (fail closed) and
  /// can simply be run again.
  Uint8List content() {
    final content = _read();
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
    if (entry.name.startsWith(coverEntryPrefix)) covers++;
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
