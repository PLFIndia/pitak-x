/// The numbers that bound a `.pitabak` backup, in ONE place (backup domain).
///
/// WHY THIS FILE EXISTS (beginner note): a backup is written by this app and
/// read back by this app. The reader is strict on purpose (ADR 0009): it
/// refuses a file with too many entries or too much content, because such a
/// file could also come from someone hostile. A writer that did not know the
/// reader's numbers could build a backup the reader then refuses, which is a
/// backup that cannot be restored (review finding P1-M1). So both sides take
/// their numbers from this one value: the writer refuses to build what the
/// reader would refuse to open.
///
/// Plain numbers only, ON PURPOSE: the writer sends this value into its
/// worker isolate, and only plain data may cross that boundary.
library;

/// Size and count limits of one backup archive.
///
/// A value object: immutable, and every number is checked when it is created.
/// Tests build small limits; the app uses [current].
final class BackupLimits {
  /// Creates limits. Every value must be positive, and one cover, one
  /// database or one text entry must fit into the content as a whole.
  const BackupLimits({
    required this.maxCovers,
    required this.maxContentBytes,
    required this.maxCoverBytes,
    required this.maxDatabaseBytes,
    required this.maxTextEntryBytes,
    this.archiveOverheadBytes = _defaultArchiveOverheadBytes,
  }) : assert(maxCovers > 0, 'maxCovers must be positive'),
       assert(maxContentBytes > 0, 'maxContentBytes must be positive'),
       assert(maxCoverBytes > 0, 'maxCoverBytes must be positive'),
       assert(maxDatabaseBytes > 0, 'maxDatabaseBytes must be positive'),
       assert(maxTextEntryBytes > 0, 'maxTextEntryBytes must be positive'),
       assert(archiveOverheadBytes >= 0, 'archiveOverheadBytes must be >= 0'),
       assert(
         maxContentBytes >= maxCoverBytes &&
             maxContentBytes >= maxDatabaseBytes &&
             maxContentBytes >= maxTextEntryBytes,
         'maxContentBytes must hold the largest single entry',
       );

  static const int _mebibyte = 1024 * 1024;
  static const int _defaultArchiveOverheadBytes = 4 * _mebibyte;

  /// How many entries besides covers a backup can have: `manifest.json`,
  /// `books.db`, `wishlist.db`, `borrowers.db`, `backup_blob`,
  /// `identity.json`, `network.json`, `item_kinds.json`, `periodicals.json`
  /// and `publish_state.json`. A test builds a backup with all of them and
  /// compares the count with this number.
  static const int otherEntries = 10;

  /// The limits in force today. They equal what the reader has always
  /// enforced (4,096 entries, 500 MiB of content, 200 MiB per entry), so no
  /// existing backup is treated differently.
  static const BackupLimits current = BackupLimits(
    maxCovers: 4086,
    maxContentBytes: 500 * _mebibyte,
    maxCoverBytes: 4 * _mebibyte,
    maxDatabaseBytes: 200 * _mebibyte,
    maxTextEntryBytes: 4 * _mebibyte,
  );

  /// Most cover pictures one backup can hold.
  final int maxCovers;

  /// Most content, in bytes, all entries together may hold when unpacked.
  final int maxContentBytes;

  /// Largest single cover picture, in bytes.
  final int maxCoverBytes;

  /// Largest single database (`books.db`, `wishlist.db`, `borrowers.db`), in
  /// bytes.
  final int maxDatabaseBytes;

  /// Largest text entry that has no cap of its own (`manifest.json`,
  /// `backup_blob`), in bytes. The JSON entries with a decoder keep the cap
  /// their decoder already enforces.
  final int maxTextEntryBytes;

  /// How much larger than its content the archive file may be: room for the
  /// entry names and the ZIP directory. Already-compressed data such as JPEG
  /// grows by only a few bytes per block when it is packed.
  final int archiveOverheadBytes;

  /// Most entries one backup can have. Derived, so the number of covers and
  /// the number of entries cannot disagree.
  int get maxEntries => maxCovers + otherEntries;

  /// Largest archive file, in bytes.
  int get maxArchiveBytes => maxContentBytes + archiveOverheadBytes;

  /// The largest of the three per-kind caps. The reader still applies ONE
  /// cap to every entry (it learns the per-kind caps in a later step), and
  /// that one cap must admit the largest kind.
  int get largestEntryBytes {
    var largest = maxCoverBytes;
    if (maxDatabaseBytes > largest) largest = maxDatabaseBytes;
    if (maxTextEntryBytes > largest) largest = maxTextEntryBytes;
    return largest;
  }
}
