/// Loads one saved library's published catalogue (network domain use case;
/// ADR 0015, docs/ARCHITECTURE.md §5.6).
///
/// The use case exists to keep the URL policy in ONE place: the controller
/// hands over the saved row's `siteUrl`, this class re-normalizes it (a
/// corrupted row must never reach HTTP), resolves the exact `<site>books.json`
/// address, and delegates to the injected [PublishedCatalogueFetcher] port.
///
/// It performs NO repository, settings or descriptor write (V15): viewing a
/// catalogue can never change the saved row, a fingerprint or a conflict
/// badge.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Reads one published catalogue through the bounded fetch port.
final class LoadPublishedCatalogueUseCase {
  /// Creates the use case over the injected fetch port.
  const LoadPublishedCatalogueUseCase({
    required PublishedCatalogueFetcher fetch,
  }) : _fetch = fetch;

  final PublishedCatalogueFetcher _fetch;

  /// Loads the catalogue of the library saved at [siteUrl].
  ///
  /// Returns `Left(PublishedCatalogueFailure(disallowedUrl))` for a URL that is
  /// not an already-canonical Pages site root — before any request is made.
  /// [abortTrigger] lets the caller cancel the actual socket on disposal.
  Future<Either<Failure, PublishedCatalogue>> call(
    String siteUrl, {
    Future<void>? abortTrigger,
  }) async {
    if (BookmarkUrl.normalize(siteUrl) != siteUrl) {
      return const Left(
        PublishedCatalogueFailure(
          PublishedCatalogueFailureReason.disallowedUrl,
        ),
      );
    }
    final url = PublishedSiteUrlPolicy.catalogueUrl(siteUrl);
    if (url == null) {
      return const Left(
        PublishedCatalogueFailure(
          PublishedCatalogueFailureReason.disallowedUrl,
        ),
      );
    }
    return _fetch(url, abortTrigger: abortTrigger);
  }
}
