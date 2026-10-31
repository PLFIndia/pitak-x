/// Loads one saved library's independently-published events (network domain;
/// ADR 0016, ADR 0018).
///
/// The saved URL is revalidated before resolving `events.json`, then the
/// shared [PublishedFileLoader] checks the host first and falls back to the
/// saved copy with a note. No repository, settings, identity or local-events
/// write ever occurs; the only write is the saved copy of the public file.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_content.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/domain/repositories/published_file_cache.dart';
import 'package:pitaka/features/network/domain/usecases/published_file_loader.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Reads public events through the bounded fetch port and the saved copy.
final class LoadPublishedEventsUseCase {
  /// Creates the use case over the injected ports. [clock] returns epoch
  /// milliseconds.
  LoadPublishedEventsUseCase({
    required PublishedEventsFetcher fetch,
    required PublishedEventsDecoder decode,
    required PublishedFileCache cache,
    required int Function() clock,
  }) : _load = PublishedFileLoader<PublishedEvents>(
         kind: PublishedFileKind.events,
         fetch: fetch,
         decode: decode,
         cache: cache,
         clock: clock,
       );

  final PublishedFileLoader<PublishedEvents> _load;

  /// Loads events for [siteUrl]. A null success means the library publishes
  /// no `events.json` (its saved copy, if any, has been removed).
  Future<Either<Failure, PublishedContent<PublishedEvents>?>> call(
    String siteUrl, {
    Future<void>? abortTrigger,
  }) async {
    if (BookmarkUrl.normalize(siteUrl) != siteUrl) {
      return const Left(ValidationFailure('Invalid published site URL.'));
    }
    final url = PublishedSiteUrlPolicy.eventsUrl(siteUrl);
    if (url == null) {
      return const Left(ValidationFailure('Invalid published site URL.'));
    }
    return _load(siteUrl: siteUrl, url: url, abortTrigger: abortTrigger);
  }
}
