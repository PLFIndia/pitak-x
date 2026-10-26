import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_query_runner.dart';

/// The worker-isolate adapter must produce exactly what the pure engine
/// produces (viewer plan S3). This is the only place `dart:isolate` enters the
/// feature, so it is pinned separately from the engine's rule tests.
void main() {
  PublishedCatalogueItem item(int index, String title, {String? language}) =>
      PublishedCatalogueItem(
        sourceIndex: index,
        title: title,
        kind: PublishedItemKind.book,
        language: language,
      );

  final catalogue = PublishedCatalogue(
    declaredSchemaVersion: 1,
    items: [
      item(2, 'zulu', language: 'Zulu'),
      item(0, 'alpha', language: 'Alpha'),
      item(1, 'blank'),
    ],
    periodicals: [
      const PublishedPeriodical(periodicalUid: 'u', title: 'Series'),
    ],
  );

  test('the isolate result equals the pure engine result', () async {
    const query = PublishedCatalogueQuery(sort: PublishedSortOrder.language);
    final isolated = await const IsolatePublishedCatalogueQueryRunner().run(
      catalogue,
      query,
    );
    final pure = PublishedQueryEngine.apply(catalogue, query);

    expect(isolated.shownItems, pure.shownItems);
    expect(isolated.totalItems, pure.totalItems);
    expect(isolated.entries, hasLength(pure.entries.length));
    for (var i = 0; i < pure.entries.length; i++) {
      final a = isolated.entries[i];
      final b = pure.entries[i];
      expect(a.runtimeType, b.runtimeType);
      if (a is PublishedItemEntry && b is PublishedItemEntry) {
        expect(a.item.title, b.item.title);
        expect(a.item.sourceIndex, b.item.sourceIndex);
      }
    }
  });

  test('the isolate result is still unmodifiable', () async {
    final view = await const IsolatePublishedCatalogueQueryRunner().run(
      catalogue,
      const PublishedCatalogueQuery(),
    );
    expect(() => view.entries.add(view.entries.first), throwsUnsupportedError);
  });
}
