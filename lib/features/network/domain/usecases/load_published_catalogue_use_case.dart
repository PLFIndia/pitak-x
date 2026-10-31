/// Loads one saved library's published catalogue (network domain use case;
/// ADR 0015, ADR 0018, docs/ARCHITECTURE.md §5.6).
///
/// The use case keeps the URL policy in ONE place: the controller hands over
/// the saved row's `siteUrl`, this class re-normalizes it (a corrupted row
/// must never reach HTTP or the saved-copy store), resolves the exact
/// `<site>books.json` address, and runs the shared [PublishedFileLoader]
/// ("check the host first, fall back to the saved copy with a note").
///
/// It performs NO repository, settings or descriptor write (V15): viewing a
/// catalogue can never change the saved row, a fingerprint or a conflict
/// badge. The only thing it writes is the saved copy of the public file.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_catalogue.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_catalogue_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/published_file_loader.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Reads one published catalogue, current or saved.
final class LoadPublishedCatalogueUseCase {
  /// Creates the use case over the injected ports. [clock] returns epoch
  /// milliseconds.
  LoadPublishedCatalogueUseCase({
    required PublishedCatalogueFetcher fetch,
    required PublishedCatalogueDecoder decode,
    required PublishedFileCache cache,
    required int Function() clock,
  }) : _load = PublishedFileLoader<PublishedCatalogue>(
         kind: PublishedFileKind.catalogue,
         fetch: fetch,
         decode: decode,
         cache: cache,
         clock: clock,
       );

  final PublishedFileLoader<PublishedCatalogue> _load;

  static const Failure _disallowed = PublishedCatalogueFailure(
    PublishedCatalogueFailureReason.disallowedUrl,
  );

  /// Loads the catalogue of the library saved at [siteUrl].
  ///
  /// Returns `Left(PublishedCatalogueFailure(disallowedUrl))` for a URL that is
  /// not an already-canonical Pages site root — before any request or saved
  /// copy is touched. [abortTrigger] lets the caller cancel the actual socket
  /// on disposal.
  Future<Either<Failure, PublishedContent<PublishedCatalogue>>> call(
    String siteUrl, {
    Future<void>? abortTrigger,
  }) async {
    if (BookmarkUrl.normalize(siteUrl) != siteUrl) {
      return const Left(_disallowed);
    }
    final url = PublishedSiteUrlPolicy.catalogueUrl(siteUrl);
    if (url == null) return const Left(_disallowed);
    final loaded = await _load(
      siteUrl: siteUrl,
      url: url,
      abortTrigger: abortTrigger,
    );
    // The catalogue port reports a 404 as a failure, never as "missing"; if
    // an adapter ever did, a required file that is absent is still a failure.
    return loaded.flatMap(
      (content) => content == null
          ? const Left(
              PublishedCatalogueFailure(
                PublishedCatalogueFailureReason.httpStatus,
              ),
            )
          : Right(content),
    );
  }
}
