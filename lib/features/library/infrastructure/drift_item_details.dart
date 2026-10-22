/// The one place the per-kind detail tables are read and written
/// (infrastructure; ADR 0013 F4, F6).
///
/// Why one class (beginner note): the base row (`books`) is the same for
/// every kind; what differs per kind is a 1:1 detail row in its own table.
/// Every `switch` here is over the SEALED `ItemDetails` union, so adding a
/// kind with fields means adding a branch to each method — and the compiler
/// points at every one of them (the recipe in ADR 0013).
library;

import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

/// Reads and writes the kind-specific detail row of a catalogue item.
final class DriftItemDetails {
  /// Creates the seam over [_db].
  DriftItemDetails(this._db);

  final AppDatabase _db;

  /// Kind tokens already reported through `appLog` by this instance, so a
  /// catalogue with many rows from a newer build logs each unknown token
  /// once, not once per row.
  final Set<String> _reportedTokens = {};

  /// The details of a row whose stored `kind` is [kindToken], given the
  /// `magazine_issues` row joined to it ([issueRow], null when none).
  ///
  /// Fail-soft on read (F6): an unknown token — a newer build wrote the row
  /// — or a `magazine-issue` row that lost its detail row is returned as a
  /// BOOK (`null`) so the Library stays usable, and logged once per token.
  /// The stored token is untouched; `DriftCatalogueItemRepository.update`
  /// refuses to write such a row back.
  ItemDetails? read(String kindToken, MagazineIssueRow? issueRow) {
    final kind = ItemKind.fromToken(kindToken);
    if (kind == null) {
      _reportOnce(kindToken, 'unknown kind token');
      return null;
    }
    switch (kind) {
      case ItemKind.book:
        return null;
      case ItemKind.other:
        return const OtherItemOf();
      case ItemKind.magazineIssue:
        if (issueRow == null) {
          _reportOnce(kindToken, 'issue row without a magazine_issues row');
          return null;
        }
        return IssueOf(
          periodicalUid: issueRow.periodicalUid,
          volume: issueRow.volume,
          issueNumber: issueRow.issueNumber,
          issueDate: issueRow.issueDate,
          boundUntil: issueRow.boundUntil,
          label: issueRow.issueLabel,
        );
    }
  }

  /// True when [kindToken] is one this build understands.
  static bool isSupported(String kindToken) =>
      ItemKind.fromToken(kindToken) != null;

  /// Writes the detail row for item [itemId] so it matches [details]:
  /// an issue's row is inserted or replaced; a book or an "other" item has
  /// no detail row, so any stale one is removed. Must run inside the same
  /// transaction as the base-row write.
  Future<void> write(int itemId, ItemDetails? details) async {
    switch (details) {
      case null:
      case OtherItemOf():
        await delete(itemId);
      case IssueOf():
        await _db
            .into(_db.magazineIssues)
            .insertOnConflictUpdate(companion(itemId, details));
    }
  }

  /// Removes the detail row of [itemId], if any. The FK cascade already
  /// does this when the base row is deleted; this is for a base row that
  /// stays (an edit that leaves the row with no kind-specific data).
  Future<void> delete(int itemId) async {
    await (_db.delete(
      _db.magazineIssues,
    )..where((t) => t.itemId.equals(itemId))).go();
  }

  /// The Drift companion for [issue] as the detail row of [itemId].
  static MagazineIssuesCompanion companion(int itemId, IssueOf issue) =>
      MagazineIssuesCompanion(
        itemId: Value(itemId),
        periodicalUid: Value(issue.periodicalUid),
        volume: Value(issue.volume),
        issueNumber: Value(issue.issueNumber),
        issueDate: Value(issue.issueDate),
        boundUntil: Value(issue.boundUntil),
        issueLabel: Value(issue.label),
      );

  void _reportOnce(String kindToken, String why) {
    if (_reportedTokens.add(kindToken)) {
      // The token is an enum-like string a build wrote, never user text.
      appLog('catalogue: $why ($kindToken); reading the row as a book');
    }
  }
}
