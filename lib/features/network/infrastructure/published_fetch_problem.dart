/// Maps a core transport refusal onto the viewer's saved-copy note reason
/// (network infrastructure; ADR 0018). Shared by the catalogue and events
/// adapters so both files explain a failure the same way.
library;

import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

/// The coarse [PublishedFileProblem] for one [FetchRefusal].
PublishedFileProblem publishedFileProblemFor(FetchRefusal reason) =>
    switch (reason) {
      FetchRefusal.timedOut ||
      FetchRefusal.transport => PublishedFileProblem.unreachable,
      FetchRefusal.tooLarge => PublishedFileProblem.unreadable,
      FetchRefusal.disallowedUrl ||
      FetchRefusal.redirectRefused ||
      FetchRefusal.tooManyRedirects ||
      FetchRefusal.httpStatus => PublishedFileProblem.notServed,
    };
