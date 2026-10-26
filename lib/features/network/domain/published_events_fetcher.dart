/// The published-events fetch port (network domain, pure Dart).
///
/// A null success means the site has no `events.json` (404), which is normal
/// for sites published before native events support. Other transport and
/// payload failures remain typed [Failure]s rather than being mistaken for
/// "no events".
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';

/// Fetches and decodes an exact `events.json` URL. [abortTrigger] cancels the
/// actual request when the viewer reloads or closes.
typedef PublishedEventsFetcher =
    Future<Either<Failure, PublishedEvents?>> Function(
      String url, {
      Future<void>? abortTrigger,
    });
