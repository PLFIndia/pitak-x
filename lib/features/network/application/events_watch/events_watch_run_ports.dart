/// The ports and limits one background run needs (PLAN.md §3). Built by
/// `CheckLibraryEventsUseCase`, consumed by `EventsWatchRun`.
library;

import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/published_events_fetcher.dart';

/// Builds the bounded `events.json` fetcher for one canonical site.
typedef EventsFetcherFactory = PublishedEventsFetcher Function(String siteUrl);

/// Resolves the active data generation's NAME without side effects, or null
/// when none is trustworthy (`DataGenerations.peekActive()?.name`).
typedef GenerationPeek = String? Function();

/// The ports and limits a run needs. Immutable; built by the use case.
final class EventsWatchRunPorts {
  /// Creates the port bundle.
  const EventsWatchRunPorts({
    required this.settingsStore,
    required this.source,
    required this.peekGeneration,
    required this.fetcherFor,
    required this.notifier,
    required this.clock,
    required this.runDeadline,
    required this.concurrency,
  });

  /// Foreground-owned settings (re-read by every guard).
  final EventsWatchSettingsStore settingsStore;

  /// Read-only saved-library source.
  final WatchedLibrariesSource source;

  /// Side-effect-free generation peek.
  final GenerationPeek peekGeneration;

  /// Fetcher factory.
  final EventsFetcherFactory fetcherFor;

  /// Notification submission.
  final LocalNotifier notifier;

  /// Clock.
  final WatchClock clock;

  /// Safety limit for the whole run (decision 10).
  final Duration runDeadline;

  /// Concurrent fetches.
  final int concurrency;
}
