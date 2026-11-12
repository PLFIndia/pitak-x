/// Builds the catalogue of the new data generation during a restore
/// (infrastructure): phase 6a of the pipeline in `restore_backup.dart`.
///
/// WHY THIS FILE EXISTS (beginner note): `restore_backup.dart` sat exactly
/// at the 500-line ceiling the architecture tests enforce, and the streamed
/// restore (backup rework BR6) has to add to it. This phase is one closed
/// unit: it gets the two generations, the rows to write and the lease, and
/// answers "done" or a typed refusal. So it moved here, as the covers phase
/// (`restore_covers_builder.dart`) and the read phase
/// (`restore_legacy_read.dart`) did before it. The code is the same.
///
/// Nothing here touches live data: the snapshot is READ from the active
/// generation, and every write goes into the builder generation, which is
/// not live yet.
library;

import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/backup/infrastructure/restore_item_details.dart';
import 'package:pitaka/features/backup/infrastructure/restore_legacy_read.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_guard.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/infrastructure/catalogue_item_mapper.dart';
import 'package:pitaka/features/wishlist/infrastructure/wishlist_mapper.dart';
import 'package:sqlite3/sqlite3.dart';

/// Snapshots the live catalogue of [active] into [builder] and replaces its
/// rows with [legacy], inside ONE transaction on that copy.
///
/// [openCatalogue] opens the builder's catalogue copy (the restorer's seam,
/// so tests can inject faults into it). [scope] is the lease of the vault
/// guard: when it is no longer current, the write is rolled back.
///
/// A refusal (the replacement plan says no, the lease ended, the
/// periodicals could not be written) comes back as a `Left`, with the
/// transaction rolled back. Anything unexpected (Drift, SQLite, the disk)
/// is thrown on to the restorer, which turns it into a storage failure.
/// Either way the caller discards the builder generation.
Future<Either<Failure, Unit>> buildRestoredCatalogue({
  required DataGeneration active,
  required DataGeneration builder,
  required LegacyCatalogueRows legacy,
  required CatalogueReplacementScope scope,
  required AppDatabase Function(String path) openCatalogue,
}) async {
  // Snapshot through a private read connection so the copy is consistent
  // and independent of whichever executor the app holds on the live file.
  // `VACUUM INTO` refuses to run inside a transaction and refuses to
  // overwrite; the builder directory is fresh, so the target is absent.
  // A device that never opened its catalogue has no file yet: Drift then
  // creates the builder's schema from scratch when opened below.
  if (File(active.catalogueDbPath).existsSync()) {
    final source = sqlite3.open(
      active.catalogueDbPath,
      mode: OpenMode.readOnly,
    );
    try {
      source.execute('VACUUM INTO ?', [builder.catalogueDbPath]);
    } finally {
      source.dispose();
    }
  }

  final db = openCatalogue(builder.catalogueDbPath);
  try {
    await db.transaction(() async {
      final loanIds = scope.retainedLoanBookIds;
      if (loanIds != null) {
        final local = await db.select(db.books).get();
        final plan = CatalogueReplacementPlan.build(
          local: local.map((row) => row.toDomain()).toList(),
          incoming: legacy.books,
          loanBookIds: loanIds,
        );
        legacy.books = plan.match(
          (failure) => throw _ReplacementRefused(failure),
          (books) => books,
        );
      }
      if (!scope.isCurrent) {
        throw const _ReplacementRefused(CatalogueReplacementScope.cancelled);
      }
      // The books delete cascades to `magazine_issues` (FK, plan A.6); the
      // periodicals table is cleared inside writeRestoredPeriodicals.
      await db.delete(db.books).go();
      await db.delete(db.wishlistBooks).go();
      // W2: row-by-row — the assigned ids key the kind detail rows.
      await insertRestoredItems(db, legacy.books);
      await db.batch((b) {
        for (final w in legacy.wishlist) {
          b.insert(db.wishlistBooks, w.toCompanion());
        }
      });
      // W2: the periodicals write joins this transaction (Drift
      // transactions are zone-scoped); a Left rolls EVERYTHING back —
      // restore never leaves a half-written catalogue.
      final replaced = await writeRestoredPeriodicals(db, legacy.periodicals);
      replaced.match((f) => throw _ReplacementRefused(f), (_) {});
      final reprojected = await reprojectRestoredIssues(db);
      reprojected.match((f) => throw _ReplacementRefused(f), (_) {});
      // Rebuild the derived FTS index from the rows just written.
      await db.rebuildFts();
      if (!scope.isCurrent) {
        throw const _ReplacementRefused(CatalogueReplacementScope.cancelled);
      }
    });
  } on _ReplacementRefused catch (e) {
    // The signal has done its work (the transaction is rolled back) and
    // becomes the typed failure again before it leaves this file.
    return left(e.failure);
  } finally {
    await db.close();
  }
  return right(unit);
}

/// Rollback signal for the transaction above: throwing inside a Drift
/// transaction is what rolls it back. Private to this file; it is converted
/// back to a typed [Failure] before the function returns.
final class _ReplacementRefused implements Exception {
  const _ReplacementRefused(this.failure);
  final Failure failure;
}
