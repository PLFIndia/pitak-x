/// Worker-isolate adapter for the published-catalogue query engine
/// (network infrastructure; viewer plan S3, ADR 0015).
///
/// The engine itself stays a pure synchronous function
/// ([PublishedQueryEngine.apply]); this adapter is the only place that knows
/// about `dart:isolate`. A 100 000-row filter/sort/group pass takes long enough
/// to drop frames, and the decoded models contain no secrets, so copying them
/// to a worker and back is both safe and worth it.
///
/// `Isolate.run` sends the closure plus the captured catalogue/query objects
/// (plain Dart data, no clients, no closures over app state) and returns the
/// public view models.
library;

import 'dart:isolate';

import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';

/// Runs the query engine in a one-shot worker isolate.
final class IsolatePublishedCatalogueQueryRunner {
  /// Creates the adapter.
  const IsolatePublishedCatalogueQueryRunner();

  /// Applies [query] to [catalogue] off the UI isolate.
  Future<PublishedCatalogueView> run(
    PublishedCatalogue catalogue,
    PublishedCatalogueQuery query,
  ) => Isolate.run(
    () => PublishedQueryEngine.apply(catalogue, query),
    debugName: 'pitaka-published-catalogue-query',
  );
}
