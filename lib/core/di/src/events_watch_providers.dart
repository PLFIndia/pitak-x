/// Background event alerts DI bindings (PLAN.md 2026-11-07, ADR 0024).
///
/// Foreground wiring only. The WorkManager isolate builds its OWN minimal
/// container in `events_watch_dispatcher.dart` and must never touch the
/// providers here that open the Drift database or the vault.
///
/// Platform split (decision 4): on Android the real scheduler/notifier are
/// bound; everywhere else the no-op ports are, so the Settings tile hides
/// itself and nothing is ever scheduled.
library;

import 'package:flutter/foundation.dart';
import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/events_watch_dispatcher.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/file_events_watch_stores.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/local_notifications_notifier.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/noop_events_watch_ports.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/sqlite_watched_libraries_source.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/workmanager_events_watch_scheduler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:workmanager/workmanager.dart';

part 'events_watch_providers.g.dart';

/// True where background alerts exist at all (Android only).
@Riverpod(keepAlive: true)
bool eventsWatchSupported(EventsWatchSupportedRef ref) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Foreground-owned settings document store.
@Riverpod(keepAlive: true)
Future<EventsWatchSettingsStore> eventsWatchSettingsStore(
  EventsWatchSettingsStoreRef ref,
) async {
  final docs = await ref.watch(appDocsDirProvider.future);
  return FileEventsWatchSettingsStore(docsDir: docs.path);
}

/// Worker-owned state document store (the foreground only READS it).
@Riverpod(keepAlive: true)
Future<EventsWatchStateStore> eventsWatchStateStore(
  EventsWatchStateStoreRef ref,
) async {
  final docs = await ref.watch(appDocsDirProvider.future);
  return FileEventsWatchStateStore(docsDir: docs.path);
}

/// Strict read-only source of saved libraries. Peeks the active generation
/// on every read; never uses the Drift connection.
@Riverpod(keepAlive: true)
Future<WatchedLibrariesSource> watchedLibrariesSource(
  WatchedLibrariesSourceRef ref,
) async {
  final generations = await ref.watch(dataGenerationsProvider.future);
  return SqliteWatchedLibrariesSource(
    resolvePath: () => generations.peekActive()?.catalogueDbPath,
  );
}

/// The real notifier on Android; a never-deliverable one elsewhere.
@Riverpod(keepAlive: true)
LocalNotificationsNotifier? androidEventsNotifier(
  AndroidEventsNotifierRef ref,
) => ref.watch(eventsWatchSupportedProvider)
    ? LocalNotificationsNotifier()
    : null;

/// Port view of [androidEventsNotifier].
@Riverpod(keepAlive: true)
LocalNotifier eventsWatchNotifier(EventsWatchNotifierRef ref) =>
    ref.watch(androidEventsNotifierProvider) ?? const NoopLocalNotifier();

/// Runtime permission prompt (Android 13+); refused elsewhere.
@Riverpod(keepAlive: true)
NotificationPermissionRequest eventsWatchPermissionRequest(
  EventsWatchPermissionRequestRef ref,
) {
  final android = ref.watch(androidEventsNotifierProvider);
  return android == null
      ? noopNotificationPermissionRequest
      : android.requestPermission;
}

/// Periodic job scheduler.
@Riverpod(keepAlive: true)
EventsWatchScheduler eventsWatchScheduler(EventsWatchSchedulerRef ref) =>
    ref.watch(eventsWatchSupportedProvider)
    ? WorkmanagerEventsWatchScheduler()
    : const NoopEventsWatchScheduler();

/// Wall clock + stopwatch.
@Riverpod(keepAlive: true)
WatchClock eventsWatchClock(EventsWatchClockRef ref) =>
    const SystemWatchClock();

/// What the foreground must do once at start: register the WorkManager
/// dispatcher and initialize the notifier with the tap callback. Returns
/// the payload of a notification that cold-launched the app, if any.
typedef EventsWatchBootstrap =
    Future<String?> Function(void Function(String? payload) onTap);

Future<String?> _noopBootstrap(void Function(String? payload) onTap) async =>
    null;

/// Android: initialize plugins; elsewhere: nothing.
@Riverpod(keepAlive: true)
EventsWatchBootstrap eventsWatchBootstrap(EventsWatchBootstrapRef ref) {
  final android = ref.watch(androidEventsNotifierProvider);
  if (android == null) return _noopBootstrap;
  return (onTap) async {
    await Workmanager().initialize(eventsWatchCallbackDispatcher);
    final initialized = await android.initialize(onTap: onTap);
    if (initialized.isLeft()) return null;
    return (await android.launchPayload()).toNullable();
  };
}

/// A notification payload waiting for the app to be ready (providers
/// built, app lock passed). Consumed exactly once.
@Riverpod(keepAlive: true)
class EventsWatchRouteQueue extends _$EventsWatchRouteQueue {
  @override
  String? build() => null;

  /// Queues [payload]; a newer tap replaces an older unconsumed one.
  void offer(String? payload) {
    if (payload == null || payload.isEmpty) return;
    state = payload;
  }

  /// Returns and clears the queued payload.
  String? take() {
    final payload = state;
    state = null;
    return payload;
  }
}
