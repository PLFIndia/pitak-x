import 'package:drift/drift.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';

/// Validates the raw kind/detail evidence of one joined catalogue row.
///
/// Display reads deliberately stay fail-soft. Serialization and write-back
/// instead call this guard BEFORE mapping, so an unknown kind or a missing
/// issue-detail row can never be mistaken for a canonical book.
Failure? catalogueInterchangeIntegrityFailure(
  AppDatabase database,
  TypedResult row,
) {
  final base = row.readTable(database.books);
  final kind = ItemKind.fromToken(base.kind);
  if (kind == null) return UnsupportedItemKindFailure(base.kind);
  if (kind == ItemKind.magazineIssue &&
      row.readTableOrNull(database.magazineIssues) == null) {
    return StorageFailure(
      'catalogue integrity: magazine-issue ${base.id} has no detail row',
    );
  }
  return null;
}
