/// The published-catalogue ports (network domain, pure Dart; ADR 0015,
/// ADR 0018, docs/ARCHITECTURE.md §5.6).
///
/// Function types, not interfaces — the same seam style as
/// `DescriptorFetcher`: the viewer needs exactly two operations. Tests inject
/// closures; production injects the bounded infrastructure adapter from
/// `core/di`.
///
///  - [PublishedCatalogueFetcher] performs one CONDITIONAL GET of the exact
///    `books.json` URL. A `404` is reported as [PublishedFileFailed] (the
///    catalogue is required), never as [PublishedFileMissing].
///  - [PublishedCatalogueDecoder] re-reads a saved copy with the same bounded
///    codec a download uses.
///
/// The optional `abortTrigger` is the caller's cancellation signal: completing
/// it must abort the in-flight socket (see `BoundedHttpFetcher.fetch`). A
/// caller-aborted fetch may report the coarse transport reason; the controller
/// discards that result because its revision is already superseded.
library;

import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

/// Fetches and decodes the catalogue at an exact file URL, conditionally.
typedef PublishedCatalogueFetcher = PublishedFileFetcher<PublishedCatalogue>;

/// Decodes the bytes of a saved catalogue copy.
typedef PublishedCatalogueDecoder = PublishedFileDecoder<PublishedCatalogue>;
