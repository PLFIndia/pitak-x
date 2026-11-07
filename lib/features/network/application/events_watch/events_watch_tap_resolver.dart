/// Resolves a notification tap payload against the user's CURRENT saved
/// rows (PLAN.md §7: "validate against current user-saved rows at
/// consumption; invalid/removed rows fall back to Network"). Pure.
library;

import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_payload.dart';

/// The saved row a library payload names, or null → open the Network tab.
///
/// Only `bookmark`/`card` rows qualify; a `discovered` row with the same
/// URL is NOT a saved library and must not be opened from an alert.
NetworkLibrary? resolveEventsWatchTap(
  String? payload,
  List<NetworkLibrary> rows,
) {
  final target = EventsWatchPayload.parse(payload);
  if (target is! EventsWatchLibraryTarget) return null;
  for (final row in rows) {
    if (row.siteUrl == target.siteUrl &&
        row.source != NetworkSource.discovered) {
      return row;
    }
  }
  return null;
}
