/// Loads one saved library's independently-published events (network domain).
///
/// The saved URL is revalidated before resolving `events.json`; no repository,
/// settings, identity or local-events write ever occurs.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';
import 'package:pitaka/features/network/domain/published_site_url_policy.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// Reads public events through the bounded fetch port.
final class LoadPublishedEventsUseCase {
  /// Creates the use case over [fetch].
  const LoadPublishedEventsUseCase({required PublishedEventsFetcher fetch})
    : _fetch = fetch;

  final PublishedEventsFetcher _fetch;

  /// Loads events for [siteUrl]. A null success is an absent optional file.
  Future<Either<Failure, PublishedEvents?>> call(
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
    return _fetch(url, abortTrigger: abortTrigger);
  }
}
