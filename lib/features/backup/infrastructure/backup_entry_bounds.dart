/// Writer-side mirror of the restore reader's entry bounds (backup
/// infrastructure; magazine remediation S5, finding L5; extended in BR3).
///
/// WHY THIS FILE EXISTS (beginner note): a `.pitabak` archive is written by
/// this app and read back by the same app, but the READER is deliberately
/// suspicious of what it opens — it caps every JSON entry at
/// [ItemDetailsArchiveCodec.maxBytes] and every collection at
/// [ItemDetailsArchiveCodec.maxRows]. A writer that ignored those caps would
/// produce a file its own reader silently downgrades: `other` rows come back
/// as books, issue links detach. That is a backup which looks fine and loses
/// data on restore, so the writer refuses up front instead.
///
/// BR3 adds the size cap of EVERY entry, by entry name ([backupEntryCap]).
/// The writer checks against it now; the reader will use the same function
/// when it learns per-kind caps, so the two sides share one table.
///
/// The bounds live here, not inside the writer class, so the check is one
/// small reviewed unit and the writer file stays readable. They sit in
/// infrastructure, not in the domain, because one of the caps
/// ([ItemDetailsArchiveCodec.maxBytes]) is an infrastructure constant and the
/// domain may not import infrastructure.
library;

import 'dart:convert';

import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_limits.dart';
import 'package:pitaka/features/backup/domain/backup_overflow.dart';
import 'package:pitaka/features/backup/infrastructure/backup_extras_reader.dart'
    show
        identityEntryName,
        manifestEntryName,
        networkEntryName,
        publishStateEntryName;
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/backup/infrastructure/restore_covers_builder.dart'
    show coverEntryPrefix;
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart'
    show booksDbEntryName, wishlistDbEntryName;
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/network/domain/network_archive_codec.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';

/// ZIP entry name of the encrypted vault database.
const String borrowersDbEntryName = 'borrowers.db';

/// ZIP entry name of the vault's wrapped key record (ciphertext).
const String backupBlobEntryName = 'backup_blob';

/// The largest size, in bytes, the entry called [name] may have, or null for
/// a name this app does not write (what the reader does with such an entry
/// is decided when the reader starts to use this table).
///
/// The table of decision D9. Where an entry has a decoder with its own cap,
/// that constant is used directly, so the writer and the reader cannot drift
/// apart; an entry exactly AT its cap is fine, as it is for the decoders.
///
///  - `cover_<name>`: [BackupLimits.maxCoverBytes];
///  - `books.db`, `wishlist.db`, `borrowers.db`:
///    [BackupLimits.maxDatabaseBytes];
///  - `identity.json`: [BackupIdentity.maxBytes];
///  - `network.json`: [NetworkArchiveCodec.maxBytes];
///  - `item_kinds.json`, `periodicals.json`:
///    [ItemDetailsArchiveCodec.maxBytes];
///  - `publish_state.json`: [PublishStateBackupCodec.maxBytes];
///  - `manifest.json`, `backup_blob`: [BackupLimits.maxTextEntryBytes].
int? backupEntryCap(String name, BackupLimits limits) {
  if (name.startsWith(coverEntryPrefix)) return limits.maxCoverBytes;
  return switch (name) {
    booksDbEntryName ||
    wishlistDbEntryName ||
    borrowersDbEntryName => limits.maxDatabaseBytes,
    identityEntryName => BackupIdentity.maxBytes,
    networkEntryName => NetworkArchiveCodec.maxBytes,
    itemKindsEntryName ||
    periodicalsEntryName => ItemDetailsArchiveCodec.maxBytes,
    publishStateEntryName => PublishStateBackupCodec.maxBytes,
    manifestEntryName || backupBlobEntryName => limits.maxTextEntryBytes,
    _ => null,
  };
}

/// The code the writer refuses with when the entry called [name] is larger
/// than its cap. The parts a user knows by name get their own code, so the
/// page can say which part it was; every other entry shares one code.
BackupOverflow backupEntryOverflow(String name) => switch (name) {
  booksDbEntryName => BackupOverflow.catalogueTooLarge,
  wishlistDbEntryName => BackupOverflow.wishlistTooLarge,
  borrowersDbEntryName => BackupOverflow.vaultTooLarge,
  itemKindsEntryName => BackupOverflow.itemKindsTooLarge,
  periodicalsEntryName => BackupOverflow.periodicalsTooLarge,
  _ => BackupOverflow.entryTooLarge,
};

/// The refusal for one encoded W2 entry, or null when it fits the reader.
///
/// The byte comparison mirrors the reader exactly: an entry is refused only
/// when it is LARGER than the cap, because the reader accepts equality.
BackupRefusal? overflowOf({
  required String json,
  required int rows,
  required BackupOverflow tooLarge,
  required BackupOverflow tooManyRows,
}) {
  final bytes = utf8.encode(json).length;
  if (bytes > ItemDetailsArchiveCodec.maxBytes) {
    return (
      code: tooLarge,
      actual: bytes,
      limit: ItemDetailsArchiveCodec.maxBytes,
    );
  }
  if (rows > ItemDetailsArchiveCodec.maxRows) {
    return (
      code: tooManyRows,
      actual: rows,
      limit: ItemDetailsArchiveCodec.maxRows,
    );
  }
  return null;
}

/// How many rows `ItemDetailsArchiveCodec.encodeItemKinds` will emit: the
/// encoder's own rule — a non-book item with a usable uid.
int itemKindRowCount(List<CatalogueItem> items) => items
    .where(
      (item) =>
          item.kind != ItemKind.book &&
          item.itemUid != null &&
          item.itemUid!.trim().isNotEmpty,
    )
    .length;

/// How many rows the LARGER list of `periodicals.json` will carry: one entry
/// per title, plus one per issue row the encoder can key. The reader caps the
/// two lists separately, so the larger count is what has to fit.
int periodicalEntryRowCount(
  List<Periodical> periodicals,
  List<CatalogueItem> items,
) {
  final issues = items
      .where((item) => item.details is IssueOf)
      .where((item) => item.itemUid != null && item.itemUid!.trim().isNotEmpty)
      .length;
  return periodicals.length > issues ? periodicals.length : issues;
}
