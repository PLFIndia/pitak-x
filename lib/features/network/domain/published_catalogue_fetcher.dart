/// The published-catalogue fetch port (network domain, pure Dart;
/// ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// A function type, not an interface — the same seam style as
/// `DescriptorFetcher`: the viewer needs exactly one operation, "fetch this
/// exact `books.json` URL and hand back either a decoded catalogue or a coarse
/// failure". Tests inject a closure; production injects the bounded
/// infrastructure adapter from `core/di`.
///
/// The optional `abortTrigger` is the caller's cancellation signal: completing
/// it must abort the in-flight socket (see `BoundedHttpFetcher.fetch`). A
/// caller-aborted fetch may report the coarse transport reason; the controller
/// discards that result because its revision is already superseded.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';

/// Fetches and decodes the catalogue at [url] (an exact file URL).
///
/// Never throws for expected failures: every transport refusal, oversize body
/// or unreadable document is a `Left(PublishedCatalogueFailure)`.
typedef PublishedCatalogueFetcher =
    Future<Either<PublishedCatalogueFailure, PublishedCatalogue>> Function(
      String url, {
      Future<void>? abortTrigger,
    });
