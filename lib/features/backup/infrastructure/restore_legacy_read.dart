/// Reads the archive's legacy Room databases into validated domain rows
/// (infrastructure) — phase 5 of the restore pipeline in
/// `restore_backup.dart`, extracted when ADR 0014 W2 grew that file past its
/// size cap (B.5: split before extending a capped file).
///
/// The per-table ROW mapping (and the refuse-on-first-invalid contract, M15)
/// lives in `legacy_db_reader.dart`; this file is the orchestration around
/// it: read both DBs through the one opener seam, and carry the combined
/// result.
///
/// Since the streamed restore (backup rework BR6) the two databases arrive
/// as FILES: the worker in `restore_archive_reader.dart` unpacks them from
/// the archive straight into the restore's scratch folder (sqlite3 needs
/// paths). This file no longer writes anything.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/infrastructure/legacy_db_reader.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:sqlite3/common.dart';

/// ZIP entry name of the archive's plain (unencrypted) catalogue database.
const String booksDbEntryName = 'books.db';

/// ZIP entry name of the archive's plain (unencrypted) wishlist database.
const String wishlistDbEntryName = 'wishlist.db';

/// Opens a plain SQLite database file read-only. Injectable for tests.
typedef LegacyDbOpener = CommonDatabase Function(String path);

/// Internal carrier for rows read out of the legacy DBs.
class LegacyCatalogueRows {
  /// The validated catalogue rows (base rows of EVERY kind; W2 kinds are
  /// applied to them later by `restore_item_details.dart`).
  List<CatalogueItem> books = const [];

  /// The validated wishlist rows.
  List<WishlistBook> wishlist = const [];

  /// W2: the validated periodicals to write (empty ⇒ the table is cleared —
  /// restore is an authoritative overwrite).
  List<Periodical> periodicals = const [];

  /// Cover references normalised to null by validation (M15), surfaced in
  /// the restore summary so the user knows a link was removed.
  int coversDropped = 0;
}

/// Reads the archive's staged `books.db` / `wishlist.db` (whichever the
/// manifest announces) into validated rows. [booksDbPath] and
/// [wishlistDbPath] are where the worker staged them, or null when the
/// archive has no such entry. A missing announced entry, an unreadable DB,
/// or a row that fails validation (M15) refuses the whole archive with the
/// typed failure — BEFORE any device write.
Either<Failure, LegacyCatalogueRows> readLegacyCatalogue({
  required String? booksDbPath,
  required String? wishlistDbPath,
  required BackupManifest manifest,
  required LegacyDbOpener open,
}) {
  final rows = LegacyCatalogueRows();
  if (manifest.hasBooks) {
    final path = booksDbPath;
    if (path == null) {
      return left(const BackupCorruptFailure('Archive missing books.db'));
    }
    // M15: the reader validates every row; a Left here is either a typed
    // ValidationFailure (an invalid row — surfaced verbatim) or a
    // BackupCorruptFailure from _withDb (the DB could not be opened/read).
    final readResult = _withDb(
      open,
      path,
      (db) => LegacyDbReader(db).readBooks(),
    );
    final validated = _flatten(readResult);
    if (validated.isLeft()) {
      return left(validated.getLeft().toNullable()!);
    }
    final books = validated.getOrElse((_) => throw StateError('x'));
    rows
      ..books = books.items
      ..coversDropped = rows.coversDropped + books.coversDropped;
  }
  if (manifest.hasWishlist) {
    final path = wishlistDbPath;
    if (path == null) {
      return left(const BackupCorruptFailure('Archive missing wishlist.db'));
    }
    final readResult = _withDb(
      open,
      path,
      (db) => LegacyDbReader(db).readWishlist(),
    );
    final validated = _flatten(readResult);
    if (validated.isLeft()) {
      return left(validated.getLeft().toNullable()!);
    }
    final wishlist = validated.getOrElse((_) => throw StateError('x'));
    rows
      ..wishlist = wishlist.items
      ..coversDropped = rows.coversDropped + wishlist.coversDropped;
  }
  return right(rows);
}

/// Flattens `_withDb`'s outer Either (open/read failure) with the reader's
/// inner Either (a refused row), preserving the typed failure either way.
Either<Failure, LegacyRows<T>> _flatten<T>(
  Either<Failure, Either<Failure, LegacyRows<T>>> nested,
) => nested.match(left, (inner) => inner);

Either<Failure, T> _withDb<T>(
  LegacyDbOpener open,
  String path,
  T Function(CommonDatabase) action,
) {
  CommonDatabase? handle;
  try {
    handle = open(path);
    return right(action(handle));
  } on Object catch (e) {
    return left(BackupCorruptFailure('Could not read legacy DB: $e'));
  } finally {
    handle?.dispose();
  }
}
