/// The ONLY data a notification tap carries back into the app (PLAN.md §7):
/// a canonical site URL, or "open the Network tab". Parsed strictly; the
/// consumer re-validates a URL against the user's current saved rows.
library;

import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';

/// A parsed tap payload.
sealed class EventsWatchTapTarget {
  const EventsWatchTapTarget();
}

/// Open the saved library at [siteUrl] (if it is still saved).
final class EventsWatchLibraryTarget extends EventsWatchTapTarget {
  /// Creates the library target.
  const EventsWatchLibraryTarget(this.siteUrl);

  /// Canonical site URL.
  final String siteUrl;
}

/// Open the Network tab.
final class EventsWatchNetworkTarget extends EventsWatchTapTarget {
  /// Creates the network target.
  const EventsWatchNetworkTarget();
}

/// Encoder/decoder of tap payloads.
abstract final class EventsWatchPayload {
  static const String _libraryPrefix = 'site:';
  static const String _network = 'network';

  /// Payload for a library alert.
  static String library(String siteUrl) => '$_libraryPrefix$siteUrl';

  /// Payload for the summary alert.
  static String get network => _network;

  /// Parses [payload]. Anything malformed or non-canonical becomes the
  /// Network target rather than an error — a tap must always land somewhere
  /// safe.
  static EventsWatchTapTarget parse(String? payload) {
    if (payload == null) return const EventsWatchNetworkTarget();
    if (payload.startsWith(_libraryPrefix)) {
      final url = payload.substring(_libraryPrefix.length);
      if (BookmarkUrl.normalize(url) == url) {
        return EventsWatchLibraryTarget(url);
      }
    }
    return const EventsWatchNetworkTarget();
  }
}
