/// Loads one saved library's optional `availability.json` (network domain
/// use case; ADR 0019, ADR 0015 and ADR 0018 amendments).
///
/// The saved URL is revalidated before resolving `availability.json`, then
/// the shared [PublishedFileLoader] checks the host first and falls back to
/// the saved copy with a note. It writes nothing but the saved copy of the
/// public file (ADR 0015 V15).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/published_availability_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/published_file_loader.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Reads the availability file through the bounded port and the saved copy.
final class LoadPublishedAvailabilityUseCase {
  /// Creates the use case over the injected ports. [clock] returns epoch
  /// milliseconds.
  LoadPublishedAvailabilityUseCase({
    required PublishedAvailabilityFetcher fetch,
    required PublishedAvailabilityDecoder decode,
    required PublishedFileCache cache,
    required int Function() clock,
  }) : _load = PublishedFileLoader<PublishedAvailabilityFile>(
         kind: PublishedFileKind.availability,
         fetch: fetch,
         decode: decode,
         cache: cache,
         clock: clock,
       );

  final PublishedFileLoader<PublishedAvailabilityFile> _load;

  /// Loads the availability file of [siteUrl]. A null success means the
  /// library has no usable `availability.json` (absent, or refused and
  /// therefore treated as absent); any saved copy has been removed.
  Future<Either<Failure, PublishedContent<PublishedAvailabilityFile>?>> call(
    String siteUrl, {
    Future<void>? abortTrigger,
  }) async {
    if (BookmarkUrl.normalize(siteUrl) != siteUrl) {
      return const Left(ValidationFailure('Invalid published site URL.'));
    }
    final url = PublishedSiteUrlPolicy.availabilityUrl(siteUrl);
    if (url == null) {
      return const Left(ValidationFailure('Invalid published site URL.'));
    }
    return _load(siteUrl: siteUrl, url: url, abortTrigger: abortTrigger);
  }
}
