/// Writer-side mirror of the restore reader's entry bounds (backup
/// infrastructure; magazine remediation S5, finding L5).
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
/// The bounds live here, not inside the writer class, so the check is one
/// small reviewed unit and the writer file stays readable.
library;

import 'dart:convert';

import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// Which W2 entry did not fit, and why.
///
/// A plain enum ON PURPOSE: only plain data crosses the backup worker-isolate
/// boundary, so the worker returns one of these codes (never a `Failure`
/// object) and the calling isolate maps it to user-facing copy.
enum BackupEntryOverflow {
  /// `item_kinds.json` is longer than the reader's 4 MiB entry cap.
  itemKindsTooLarge,

  /// `item_kinds.json` carries more rows than the reader keeps.
  itemKindsTooManyRows,

  /// `periodicals.json` is longer than the reader's 4 MiB entry cap.
  periodicalsTooLarge,

  /// `periodicals.json` carries more rows in one of its lists than the
  /// reader keeps.
  periodicalsTooManyRows,
}

/// The overflow code for one encoded entry, or null when it fits the reader.
///
/// The byte comparison mirrors the reader exactly: an entry is refused only
/// when it is LARGER than the cap, because the reader accepts equality.
BackupEntryOverflow? overflowOf({
  required String json,
  required int rows,
  required BackupEntryOverflow tooLarge,
  required BackupEntryOverflow tooManyRows,
}) {
  if (utf8.encode(json).length > ItemDetailsArchiveCodec.maxBytes) {
    return tooLarge;
  }
  if (rows > ItemDetailsArchiveCodec.maxRows) return tooManyRows;
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
