import 'package:drift/drift.dart' show Value;
import 'package:pitaka/core/database/app_database.dart';

/// Inserts a base catalogue row without passing through a domain or repository
/// validation gate.
///
/// Corruption regression tests need this deliberate bypass: an unknown [kind]
/// or `magazine-issue` without a matching detail row cannot be created through
/// the normal repositories. The helper inserts no detail row, so callers can
/// add exactly the raw evidence their scenario requires.
Future<int> seedRawCatalogueRow(
  AppDatabase database, {
  required String title,
  String kind = 'book',
  String? itemUid,
  String? coverUrl,
  int addedDate = 1,
}) {
  return database
      .into(database.books)
      .insert(
        BooksCompanion.insert(
          title: title,
          itemUid: Value(itemUid),
          coverUrl: Value(coverUrl),
          addedDate: addedDate,
          kind: Value(kind),
        ),
      );
}
