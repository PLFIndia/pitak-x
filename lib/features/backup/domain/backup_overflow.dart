/// Why a backup was refused: the vocabulary shared by the writer and the
/// create-backup page (backup domain).
///
/// WHY THIS FILE EXISTS (beginner note): the writer refuses to build a backup
/// its own reader would refuse or silently downgrade (S5 for the item-kind
/// entries, BR3 for sizes and counts). A refusal is an expected outcome, so
/// it is a small piece of plain data, never an exception: one code from this
/// enum, the library's actual number, and the limit.
///
/// It lives in the domain (it used to be `BackupEntryOverflow` in
/// infrastructure) so the page can turn a code into a sentence. The
/// presentation layer may not import infrastructure.
library;

/// Which limit a library did not fit.
///
/// A plain enum ON PURPOSE: only plain data crosses the backup worker-isolate
/// boundary, so the worker returns one of these codes (never a `Failure`
/// object) and the calling isolate maps it. The `name` of a code travels in
/// `BackupTooLargeFailure.detail`; do not rename a code without its tests.
enum BackupOverflow {
  /// `item_kinds.json` is larger than the reader's cap for that entry.
  itemKindsTooLarge,

  /// `item_kinds.json` carries more rows than the reader keeps.
  itemKindsTooManyRows,

  /// `periodicals.json` is larger than the reader's cap for that entry.
  periodicalsTooLarge,

  /// `periodicals.json` carries more rows in one of its lists than the
  /// reader keeps.
  periodicalsTooManyRows,

  /// More cover pictures than one backup can hold. Counted after pictures
  /// that are individually too large have been left out.
  tooManyCovers,

  /// `books.db`, the list of all items, is larger than a database may be.
  catalogueTooLarge,

  /// `wishlist.db` is larger than a database may be.
  wishlistTooLarge,

  /// `borrowers.db`, the encrypted vault, is larger than a database may be.
  vaultTooLarge,

  /// Another single entry is larger than its cap: the manifest, the vault's
  /// key record, or an optional entry that was handed to the writer although
  /// it does not fit. The app's own use case leaves an oversized optional
  /// entry out before the writer sees it, so this is a safety net.
  entryTooLarge,

  /// All entries together hold more content than one backup may.
  contentTooLarge,

  /// The finished archive file is larger than the reader accepts.
  archiveTooLarge,
}

/// A refusal in full: which limit (`code`), what the library has (`actual`)
/// and what a backup can hold (`limit`). Both numbers are in the same unit:
/// bytes for the size codes, a count for the others.
///
/// A record, not a class: there is nothing to protect, and it crosses the
/// worker-isolate boundary as plain data.
typedef BackupRefusal = ({BackupOverflow code, int actual, int limit});
