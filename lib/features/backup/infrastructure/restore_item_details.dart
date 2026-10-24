/// Applies the ADR 0014 W2 item-details entries to a restored catalogue and
/// writes the kind-specific rows (infrastructure).
///
/// Extracted from `restore_backup.dart` (which sits at its size cap) per the
/// plan's S21 step: kinds and issue details are JOINED onto the legacy base
/// rows by `bookUid` BEFORE the catalogue write, so the write itself is one
/// straight pass.
///
/// The join rules are W2's, fail-closed on disagreement (P1):
///  - a uid listed nowhere in `item_kinds.json` ⇒ the row is a book;
///  - an `issues[]` entry whose uid's kind is not `magazine-issue`, or whose
///    uid is not in `books.db` at all ⇒ the entry is dropped and counted
///    (`issuesDetached`);
///  - a row DECLARED `magazine-issue` but without a usable `issues[]` entry
///    ⇒ the link is detached (counted) and the row restores as a book —
///    restoring an issue without its details is impossible (the kind is
///    derived from the details, ADR 0013 F5), and guessing is never allowed;
///  - an issue whose `periodicalUid` matches no periodical in the archive ⇒
///    detached and counted, the row becomes a book. This mirrors the W1
///    import orphan rule (one blessed way across both formats): a dangling
///    series link would be silent data corruption, while the base row keeps
///    its (projected, human-readable) title as a book.
///
/// The base rows were already validated by `LegacyDbReader`; the kinds/issue
/// details were re-validated by `ItemDetailsArchiveCodec` at parse time. This
/// file adds no third validation layer — it only joins what both gates
/// already accepted.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';
import 'package:pitaka/features/periodicals/application/issue_reprojection.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/infrastructure/drift_periodical_repository.dart';

/// The outcome of joining the W2 entries onto the restored base rows.
final class RestoredItemDetails {
  /// Creates the join result.
  const RestoredItemDetails({
    required this.books,
    required this.periodicals,
    required this.kindsApplied,
    required this.issuesLinked,
    required this.issuesDetached,
    required this.rowsSkippedUnknownKind,
    required this.periodicalsDropped,
  });

  /// The base rows with their kind `details` applied (unchanged objects for
  /// rows that stayed books).
  final List<CatalogueItem> books;

  /// The validated periodicals to write (empty when the archive carries
  /// none — the table is then cleared, see [writeRestoredPeriodicals]).
  final List<Periodical> periodicals;

  /// Rows that got a non-book kind back (`other`, or an issue that linked).
  final int kindsApplied;

  /// `issues[]` entries successfully joined to a restored row.
  final int issuesLinked;

  /// Issue links NOT honoured: entries dropped at parse time, entries for a
  /// uid absent from `books.db`, entries whose row's declared kind disagrees,
  /// declared issues with no entry, and issues whose series is absent.
  final int issuesDetached;

  /// `kinds[]` rows skipped at parse time (malformed or unknown kind token,
  /// F6). Affected rows restore as books.
  final int rowsSkippedUnknownKind;

  /// `periodicals[]` rows dropped at parse time (invalid or unkeyable).
  final int periodicalsDropped;
}

/// Joins the decoded W2 entries onto [books] (the validated base rows read
/// from `books.db`). Null [kinds]/[periodicals] mean absent-or-unreadable —
/// nothing is applied from them either way (the summary's invalid flags,
/// derived from the manifest, tell the two apart).
RestoredItemDetails applyRestoredItemDetails({
  required List<CatalogueItem> books,
  required DecodedItemKinds? kinds,
  required DecodedPeriodicals? periodicals,
}) {
  final kindsByUid = kinds?.byUid ?? const <String, ItemKind>{};
  final issuesByUid = periodicals?.issuesByBookUid ?? const <String, IssueOf>{};
  final seriesUids = {
    for (final p in periodicals?.periodicals ?? const <Periodical>[])
      p.periodicalUid!.trim(),
  };

  var kindsApplied = 0;
  var issuesLinked = 0;
  // Parse-time drops of issue entries count as detached links up front.
  var issuesDetached = periodicals?.issuesDropped ?? 0;
  // Entries CONSULTED by the loop below (linked or deliberately detached),
  // so the trailing sweep counts each entry exactly once.
  final accountedIssues = <String>{};

  final out = <CatalogueItem>[];
  for (final book in books) {
    final uid = book.itemUid?.trim() ?? '';
    final kind = uid.isEmpty ? null : kindsByUid[uid];
    switch (kind) {
      case null:
      case ItemKind.book:
        // A uid listed nowhere is a book (W2) — the base row is already
        // right. (The writer never lists books; a redundant `book` entry in
        // a hand-made file is valid and says the same thing.)
        out.add(book);
      case ItemKind.other:
        kindsApplied++;
        out.add(book.copyWith(details: const OtherItemOf()));
      case ItemKind.magazineIssue:
        final issue = issuesByUid[uid];
        if (issue == null) {
          // Declared but undetailed: no entry exists to sweep — count the
          // detach here.
          issuesDetached++;
          out.add(book);
        } else if (!seriesUids.contains(issue.periodicalUid.trim())) {
          // Orphaned from its series (absent, or dropped as invalid at parse
          // time): detach and restore the row as the book its base row is.
          issuesDetached++;
          accountedIssues.add(uid);
          out.add(book);
        } else {
          kindsApplied++;
          issuesLinked++;
          accountedIssues.add(uid);
          out.add(book.copyWith(details: issue));
        }
    }
  }

  // Every issues[] entry the loop never consulted is a dropped link: its uid
  // is not in books.db, or its row's declared kind is not magazine-issue
  // (W2: "a detail entry whose uid's kind disagrees ⇒ dropped and counted").
  for (final uid in issuesByUid.keys) {
    if (!accountedIssues.contains(uid)) issuesDetached++;
  }

  return RestoredItemDetails(
    books: out,
    periodicals: periodicals?.periodicals ?? const [],
    kindsApplied: kindsApplied,
    issuesLinked: issuesLinked,
    issuesDetached: issuesDetached,
    rowsSkippedUnknownKind: kinds?.skipped ?? 0,
    periodicalsDropped: periodicals?.periodicalsDropped ?? 0,
  );
}

/// Inserts [books] one row at a time and writes each row's kind detail row
/// through [DriftItemDetails]. Row-by-row on purpose (the same reason
/// `DriftCatalogueItemRepository.insertAll` is): the assigned id — preserved
/// or AUTOINCREMENTed — is needed as the detail row's key, and `db.batch`
/// does not return ids. Must run inside the caller's transaction.
Future<void> insertRestoredItems(
  AppDatabase db,
  List<CatalogueItem> books,
) async {
  final details = DriftItemDetails(db);
  for (final book in books) {
    final id = await db.into(db.books).insert(book.toCompanion());
    await details.write(id, book.details);
  }
}

/// Replaces the periodicals table with [periodicals] — including the
/// empty-list case: restore is an authoritative overwrite, so a flag-less or
/// periodical-free archive clears whatever the snapshot carried over (a
/// restored catalogue of plain books must not keep stale titles whose issues
/// just became books).
///
/// Goes through the repository (its other caller is the merge overwrite, S19)
/// so the uid-minting and delete-all-then-insert semantics stay in ONE place;
/// Drift transactions are zone-scoped, so its transaction joins the caller's.
/// A Left propagates: the caller converts it to a rollback (the restore
/// refuses rather than leave a half-written table).
Future<Either<Failure, int>> writeRestoredPeriodicals(
  AppDatabase db,
  List<Periodical> periodicals,
) {
  return DriftPeriodicalRepository(db).replaceAll(periodicals);
}

/// Reprojects every restored series over the BUILDER database. Must run after
/// both the item details and series have been written, inside the same
/// transaction; a failure therefore discards the whole candidate generation.
Future<Either<Failure, Unit>> reprojectRestoredIssues(AppDatabase db) {
  return IssueReprojection(
    periodicals: DriftPeriodicalRepository(db),
    items: DriftCatalogueItemRepository(db),
  ).callAllStored();
}
