/// One background run of the event check (PLAN.md §2–§6). This is the run
/// state machine; the WorkManager dispatcher only builds it and maps its
/// report to success/retry.
///
/// Phases (PLAN.md §3 table), in order:
///  1. Load/guard — settings, state, revocation marker, delivery.
///  2. Reconcile — generation, rows, token; prune; allocate ids.
///  3. Revalidate pending — fetch sites that already have pending alerts,
///     then submit what is eligible.
///  4. Check remaining — fetch every other site, then submit.
///  5. Finish — record the run; return the report.
///
/// Every state change goes through one [WatchStateReducer] (single writer).
/// Every fetch and every show is preceded by the "common guard": settings
/// token unchanged, delivery still possible, generation unchanged, row still
/// saved. Everything shares one monotonic deadline.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_run.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_run_ports.dart';
import 'package:pitaka/features/network/application/events_watch/watch_state_reducer.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_run_report.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_state_reconcile.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// See the file header.
final class CheckLibraryEventsUseCase {
  /// Creates the use case over its ports.
  CheckLibraryEventsUseCase({
    required EventsWatchSettingsStore settingsStore,
    required EventsWatchStateStore stateStore,
    required WatchedLibrariesSource source,
    required GenerationPeek peekGeneration,
    required EventsFetcherFactory fetcherFor,
    required LocalNotifier notifier,
    required EventsWatchScheduler scheduler,
    required WatchClock clock,
    this.runDeadline = const Duration(minutes: 5),
    this.concurrency = 4,
  }) : _settingsStore = settingsStore,
       _stateStore = stateStore,
       _source = source,
       _peekGeneration = peekGeneration,
       _fetcherFor = fetcherFor,
       _notifier = notifier,
       _scheduler = scheduler,
       _clock = clock;

  final EventsWatchSettingsStore _settingsStore;
  final EventsWatchStateStore _stateStore;
  final WatchedLibrariesSource _source;
  final GenerationPeek _peekGeneration;
  final EventsFetcherFactory _fetcherFor;
  final LocalNotifier _notifier;
  final EventsWatchScheduler _scheduler;
  final WatchClock _clock;

  /// Safety limit for the whole run (decision 10).
  final Duration runDeadline;

  /// Concurrent fetches (matches the foreground refresh).
  final int concurrency;

  /// Runs once. Never throws for expected failures.
  Future<WatchRunReport> run() async {
    // ---- 1. Load/guard ---------------------------------------------------
    final settingsRead = await _settingsStore.read();
    final EventsWatchSettings settings;
    switch (settingsRead) {
      case Left():
        return const WatchRunReport.retry();
      case Right(value: WatchDocumentMissing()):
        return const WatchRunReport.stopped(WatchRunStop.settingsMissing);
      case Right(value: WatchDocumentCorrupt()):
      case Right(value: WatchDocumentNewerSchema()):
        return const WatchRunReport.stopped(WatchRunStop.settingsUnreadable);
      case Right(value: WatchDocumentPresent(:final value)):
        settings = value;
    }
    if (!settings.enabled) {
      // The foreground cancels on disable; if that failed, this is the
      // backstop. Best effort: a failure here changes nothing.
      await _scheduler.cancel();
      return const WatchRunReport.stopped(WatchRunStop.disabled);
    }
    final token = settings.token;

    final stateRead = await _stateStore.read();
    EventsWatchState state;
    switch (stateRead) {
      case Left():
        return const WatchRunReport.retry();
      case Right(value: WatchDocumentMissing()):
        state = EventsWatchState.empty();
      case Right(value: WatchDocumentNewerSchema()):
        return const WatchRunReport.stopped(WatchRunStop.stateNewerSchema);
      case Right(value: WatchDocumentCorrupt()):
        final written = await _stateStore.write(
          EventsWatchState.recovered(token: token),
        );
        return written.match(
          (_) =>
              const WatchRunReport.stopped(WatchRunStop.recovered, retry: true),
          (_) => const WatchRunReport.stopped(WatchRunStop.recovered),
        );
      case Right(value: WatchDocumentPresent(:final value)):
        state = value;
    }

    final marker = state.revocationToken;
    if (marker != null && marker.sameAs(token)) {
      await _scheduler.cancel();
      return const WatchRunReport.stopped(WatchRunStop.revoked);
    }

    final delivery = await _notifier.delivery();
    switch (delivery) {
      case Left():
        return const WatchRunReport.retry();
      case Right(value: NotificationDelivery.blocked):
        return _revoke(state, token);
      case Right(value: NotificationDelivery.deliverable):
        break;
    }

    // ---- 2. Reconcile ----------------------------------------------------
    final generation = _peekGeneration();
    if (generation == null) {
      return const WatchRunReport.stopped(WatchRunStop.noGeneration);
    }
    final snapshot = await _source.snapshot();
    final List<WatchedLibrary> libraries;
    switch (snapshot) {
      case Left(value: CapacityFailure()):
        await _stateStore.write(
          state.copyWith(
            lastRun: LastRunOutcome(
              finishedAt: _clock.nowEpochMillis(),
              checked: 0,
              withheld: 0,
              failed: 0,
              capacityExceeded: true,
            ),
          ),
        );
        return const WatchRunReport.stopped(WatchRunStop.capacityExceeded);
      case Left():
        return const WatchRunReport.retry();
      case Right(:final value):
        libraries = value;
    }

    final reducer = WatchStateReducer(store: _stateStore, initial: state);
    final removedIds = <int>[];
    final reconciled = await reducer.commit(
      (latest) => reconcileWatchState(
        latest,
        token: token,
        generation: generation,
        libraries: libraries,
        removedNotificationIds: removedIds,
      ),
    );
    if (reconciled.isLeft()) return const WatchRunReport.retry();
    for (final id in removedIds) {
      await _notifier.cancelLibrary(id); // best effort
    }

    if (libraries.isEmpty) {
      await _scheduler.cancel();
      return const WatchRunReport.stopped(WatchRunStop.noLibraries);
    }

    // ---- 3–5. Site work --------------------------------------------------
    final run = EventsWatchRun(
      ports: EventsWatchRunPorts(
        settingsStore: _settingsStore,
        source: _source,
        peekGeneration: _peekGeneration,
        fetcherFor: _fetcherFor,
        notifier: _notifier,
        clock: _clock,
        runDeadline: runDeadline,
        concurrency: concurrency,
      ),
      reducer: reducer,
      token: token,
      generation: generation,
      libraries: {for (final l in libraries) l.siteUrl: l},
      stopwatch: _clock.startStopwatch(),
    );
    return run.execute();
  }

  /// Definitive permission/channel loss (PLAN.md §6): re-check settings so
  /// an old run cannot invalidate a newer enable, write the marker, then
  /// attempt cancellation regardless of the marker write's outcome.
  Future<WatchRunReport> _revoke(
    EventsWatchState state,
    WatchSettingsToken token,
  ) async {
    final again = await _settingsStore.read();
    final stillCurrent = switch (again) {
      Right(value: WatchDocumentPresent(:final value)) =>
        value.enabled && value.token.sameAs(token),
      _ => false,
    };
    if (!stillCurrent) {
      return const WatchRunReport.stopped(WatchRunStop.tokenChanged);
    }
    final written = await _stateStore.write(
      state.copyWith(
        revocationToken: token,
        pending: const [],
        sites: [
          for (final site in state.sites) site.copyWith(clearBaseline: true),
        ],
      ),
    );
    await _scheduler.cancel();
    await _notifier.cancelAllFeatureAlerts();
    return written.match(
      (_) => const WatchRunReport.stopped(WatchRunStop.revoked, retry: true),
      (_) => const WatchRunReport.stopped(WatchRunStop.revoked),
    );
  }
}
