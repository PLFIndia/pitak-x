/// The WorkManager entry point of background event alerts (PLAN.md §6
/// "entry-point dispatcher").
///
/// This runs in a FRESH Dart isolate with no Flutter UI, started by Android
/// (`BackgroundWorker.kt`). Rules (beginner note):
///  - It wires its dependencies by hand — no Riverpod container, no
///    `appDatabaseProvider`, no vault, no app lock, no refresh controller.
///    The only database access is the read-only `SqliteWatchedLibrariesSource`.
///  - Returning `true` means "done until the next period"; `false` asks
///    WorkManager to retry with backoff. Only infrastructure failures return
///    `false` (`WatchRunReport.requestRetry`).
///  - Android may destroy this engine at any moment (`onStopped` →
///    `engine.destroy()`), so `finally` is best effort; the atomic file
///    stores and the token checks make a half-finished run harmless.
///  - Nothing here logs a URL, label, caption or raw exception.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/core/storage/data_generations.dart';
import 'package:pitaka/features/network/application/events_watch/check_library_events_use_case.dart';
import 'package:pitaka/features/network/infrastructure/bounded_published_events_fetcher.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/file_events_watch_stores.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/local_notifications_notifier.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/noop_events_watch_ports.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/sqlite_watched_libraries_source.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/workmanager_events_watch_scheduler.dart';
import 'package:pitaka/features/network/infrastructure/published_events_codec.dart';
import 'package:workmanager/workmanager.dart';

/// Registered with `Workmanager().initialize` by the foreground. Must be a
/// top-level function with the entry-point pragma so AOT keeps it.
@pragma('vm:entry-point')
void eventsWatchCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != eventsWatchTaskName) return true; // not ours; nothing to do
    return runEventsWatchTask();
  });
}

/// One run with hand-wired production dependencies. Exposed for the
/// dispatcher only; tests exercise `CheckLibraryEventsUseCase` with fakes.
Future<bool> runEventsWatchTask() async {
  http.Client? client;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final generations = DataGenerations(docsDir: docs.path);

    final notifier = LocalNotificationsNotifier();
    final initialized = await notifier.initialize();
    if (initialized.isLeft()) return false;

    final inner = http.Client();
    client = TimeoutHttpClient(
      inner,
      timeout: const Duration(seconds: 30),
      totalDeadline: const Duration(seconds: 60),
      maxResponseBytes: PublishedEventsCodec.defaultMaxBodyBytes,
    );
    final boundedClient = client;

    final useCase = CheckLibraryEventsUseCase(
      settingsStore: FileEventsWatchSettingsStore(docsDir: docs.path),
      stateStore: FileEventsWatchStateStore(docsDir: docs.path),
      source: SqliteWatchedLibrariesSource(
        resolvePath: () => generations.peekActive()?.catalogueDbPath,
      ),
      peekGeneration: () => generations.peekActive()?.name,
      fetcherFor: (siteUrl) => BoundedPublishedEventsFetcher(
        client: boundedClient,
        siteUrl: siteUrl,
      ).fetch,
      notifier: notifier,
      scheduler: WorkmanagerEventsWatchScheduler(),
      clock: const SystemWatchClock(),
    );
    final report = await useCase.run();
    appLog('events_watch: run ${report.stop?.name ?? 'completed'}');
    return !report.requestRetry;
  } on IOException {
    appLog('events_watch: io failure');
    return false;
  } on PlatformException catch (e) {
    appLog('events_watch: platform ${e.code}');
    return false;
  } on MissingPluginException {
    appLog('events_watch: plugin missing');
    return false;
  } finally {
    client?.close();
  }
}
