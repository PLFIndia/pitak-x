/// The published-catalogue query-runner port (network domain, pure Dart;
/// viewer plan S3, ADR 0015).
///
/// Filtering, sorting and grouping a large catalogue is CPU work proportional
/// to its row count. The controller needs that work done OFF the UI isolate,
/// but `dart:isolate` is not allowed in the application layer (AGENTS §3.1).
/// So the domain declares the operation and infrastructure implements it with
/// `Isolate.run`; tests inject a synchronous closure.
///
/// The runner is pure: same (catalogue, query) in, same view out.
library;

import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';

/// Applies [query] to [catalogue] and returns the display view.
typedef PublishedCatalogueQueryRunner =
    Future<PublishedCatalogueView> Function(
      PublishedCatalogue catalogue,
      PublishedCatalogueQuery query,
    );
