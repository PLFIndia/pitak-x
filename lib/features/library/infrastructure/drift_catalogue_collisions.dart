/// Best-effort "which row did the UNIQUE index collide with?" lookups
/// (infrastructure-internal; used by `DriftCatalogueItemRepository` after a
/// FAILED write).
///
/// Why this exists (beginner note, S34): SQLite refuses a duplicate with an
/// exception whose text we never want to parse. Instead, after the failed
/// write, the table is asked whether a colliding row exists NOW; if so, the
/// user-facing failure can say "already in your library" and name the row.
/// Everything here is best-effort — any error returns null and the caller
/// falls back to the opaque `StorageFailure` it already had.
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/drift_catalogue_sql.dart';

/// Collision lookups for the `books` ISBN index and the `magazine_issues`
/// identity keys.
final class CatalogueCollisions {
  /// Creates the lookups over [_db].
  CatalogueCollisions(this._db);

  final AppDatabase _db;

  /// Best-effort check, after a FAILED write, that [isbn] is now held by
  /// another row: returns the typed [DuplicateIsbnFailure] describing it, or
  /// null when there is no collision, the ISBN is blank, or the re-read
  /// itself fails (the caller then falls back to [StorageFailure]).
  ///
  /// The lookup uses the ISBN exactly as the mapper would store it (raw;
  /// blanks are never stored), so it finds precisely the row the UNIQUE
  /// index collided with. [excludeId] names the row being updated, which
  /// cannot collide with itself.
  Future<DuplicateIsbnFailure?> isbn(String? isbn, {int? excludeId}) async {
    final raw = isbn;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final row =
          await (_db.select(_db.books)
                ..where((t) => t.isbn.equals(raw))
                ..limit(1))
              .getSingleOrNull();
      if (row == null) return null;
      if (excludeId != null && row.id == excludeId) return null;
      return DuplicateIsbnFailure(
        existingTitle: row.title,
        existingBookId: row.id,
        existingIsRemoved: row.removed,
      );
    } on Object {
      return null; // best-effort only; the caller reports the original error
    }
  }

  /// Best-effort twin of [isbn] for the issue identity keys (ADR
  /// 0013 D6): after a FAILED write of [issue], finds the row that already
  /// holds its key — the numbered key `(series, volume-or-0, number)` for a
  /// single issue, the date range for a bound volume — and names it.
  /// [excludeId] is the row being updated, which cannot collide with itself.
  Future<DuplicateIssueFailure?> issue(IssueOf? issue, {int? excludeId}) async {
    if (issue == null) return null;
    final m = _db.magazineIssues;
    final Expression<bool> key;
    if (issue.isBound) {
      final from = issue.issueDate;
      final until = issue.boundUntil;
      if (from == null || until == null) return null;
      key = m.issueDate.equals(from) & m.boundUntil.equals(until);
    } else {
      final number = issue.issueNumber;
      if (number == null) return null;
      key =
          coalesce<int>([
            m.volume,
            const Constant(0),
          ]).equals(issue.volume ?? 0) &
          m.issueNumber.equals(number) &
          m.boundUntil.isNull();
    }
    try {
      final row =
          await (CatalogueSql.joined(_db)
                ..where(m.periodicalUid.equals(issue.periodicalUid) & key)
                ..limit(1))
              .getSingleOrNull();
      if (row == null) return null;
      final base = row.readTable(_db.books);
      if (excludeId != null && base.id == excludeId) return null;
      return DuplicateIssueFailure(
        existingTitle: base.title,
        existingItemId: base.id,
      );
    } on Object {
      return null; // best-effort only; the caller reports the original error
    }
  }
}
