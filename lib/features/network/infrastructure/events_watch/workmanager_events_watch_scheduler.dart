/// WorkManager adapter of `EventsWatchScheduler` (PLAN.md §5).
///
/// Verified against `workmanager 0.6.0` (Step 0, 2026-11-07):
///  - `registerPeriodicTask` / `cancelByUniqueName` return as soon as the
///    native call was *issued* (`WorkmanagerCallHandler.kt:111-119,
///    188-196`): they do NOT await the `androidx.work.Operation`.
///  - `isScheduledByUniqueName` blocks on `getWorkInfosForUniqueWork().get()`
///    and is therefore authoritative (`:170-175`).
///
/// So every mutating call here is followed by a short poll of the
/// authoritative query until the expected state is observed. A call that
/// returned normally but never reaches the expected state is a failure,
/// never a success (beginner note: "the method returned" and "the job is
/// registered" are two different facts; we only trust the second).
///
/// `ExistingWorkPolicy.update` (androidx.work ≥ 2.8) updates the work spec
/// in place without restarting the periodic cycle, and enqueues when absent
/// — one call covers both "keep if unchanged" and "update if changed".
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:workmanager/workmanager.dart';

/// Unique periodic work name. Changing it orphans an existing registration.
const String eventsWatchUniqueWorkName = 'dev.khoj.pitaka.events_watch';

/// Dart task name handed to the background dispatcher.
const String eventsWatchTaskName = 'dev.khoj.pitaka.events_watch.check';

/// Unique name of the DEBUG-ONLY immediate one-off run. Deliberately
/// different from [eventsWatchUniqueWorkName] so it can never replace or
/// cancel the real periodic registration.
const String eventsWatchDebugRunWorkName =
    'dev.khoj.pitaka.events_watch.debug_run';

/// Fixed interval (decision 3). WorkManager adds its own flex window.
const Duration eventsWatchInterval = Duration(hours: 12);

/// Flex window inside which WorkManager may run the job early.
const Duration eventsWatchFlex = Duration(hours: 1);

/// Initial backoff after a `retry` result; exponential thereafter.
const Duration eventsWatchBackoff = Duration(minutes: 30);

/// The three native calls this adapter needs, as an interface so tests can
/// fake the plugin without a platform channel.
abstract interface class WorkmanagerGateway {
  /// See `Workmanager.registerPeriodicTask`.
  Future<void> registerPeriodic();

  /// See `Workmanager.cancelByUniqueName`.
  Future<void> cancel();

  /// See `Workmanager.isScheduledByUniqueName` (authoritative).
  Future<bool> isScheduled();

  /// See `Workmanager.registerOneOffTask`; debug builds only.
  Future<void> registerOneOffNow();
}

/// Production gateway over the plugin singleton.
final class PluginWorkmanagerGateway implements WorkmanagerGateway {
  /// Creates the gateway.
  const PluginWorkmanagerGateway();

  @override
  Future<void> registerPeriodic() => Workmanager().registerPeriodicTask(
    eventsWatchUniqueWorkName,
    eventsWatchTaskName,
    frequency: eventsWatchInterval,
    flexInterval: eventsWatchFlex,
    existingWorkPolicy: ExistingWorkPolicy.update,
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
    ),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: eventsWatchBackoff,
  );

  @override
  Future<void> cancel() =>
      Workmanager().cancelByUniqueName(eventsWatchUniqueWorkName);

  @override
  Future<bool> isScheduled() =>
      Workmanager().isScheduledByUniqueName(eventsWatchUniqueWorkName);

  /// No constraints on purpose: the run must start right away, and an
  /// offline device is itself a case the maintainer wants to observe.
  @override
  Future<void> registerOneOffNow() => Workmanager().registerOneOffTask(
    eventsWatchDebugRunWorkName,
    eventsWatchTaskName,
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

/// See the file header.
final class WorkmanagerEventsWatchScheduler implements EventsWatchScheduler {
  /// Creates the scheduler. [confirmAttempts] × [confirmInterval] bounds
  /// how long a mutating call waits for the native state to match.
  WorkmanagerEventsWatchScheduler({
    WorkmanagerGateway gateway = const PluginWorkmanagerGateway(),
    this.confirmAttempts = 20,
    this.confirmInterval = const Duration(milliseconds: 100),
  }) : _gateway = gateway;

  final WorkmanagerGateway _gateway;

  /// Maximum authoritative polls after a mutating call.
  final int confirmAttempts;

  /// Pause between polls.
  final Duration confirmInterval;

  @override
  Future<Either<Failure, Unit>> ensureRegistered() => _guard(() async {
    await _gateway.registerPeriodic();
    return _confirm(expected: true, reason: 'scheduler register unconfirmed');
  });

  @override
  Future<Either<Failure, Unit>> cancel() => _guard(() async {
    await _gateway.cancel();
    return _confirm(expected: false, reason: 'scheduler cancel unconfirmed');
  });

  @override
  Future<Either<Failure, WatchJobRegistration>> registration() =>
      _guard(() async {
        final scheduled = await _gateway.isScheduled();
        return right(
          scheduled
              ? WatchJobRegistration.registered
              : WatchJobRegistration.notRegistered,
        );
      });

  /// DEBUG BUILDS ONLY — enqueues one immediate run of the worker.
  ///
  /// Why this exists (verified in `work-runtime-2.9.0`, 2026-11-08):
  /// `WorkerWrapper` refuses to run periodic work before its computed next
  /// run time ("Delaying execution … before schedule") and, with a flex
  /// window, the FIRST run time is `enqueue + interval − flex` = 11 h for
  /// our registration. So `adb shell cmd jobscheduler run -f` never reaches
  /// the Dart worker. A one-off request has no such guard; it carries the
  /// same task name, so the dispatcher executes the real check in the real
  /// background engine.
  ///
  /// Not confirmed by polling: a fast run may already have SUCCEEDED by the
  /// first poll, which `isScheduledByUniqueName` reports as false. Reachable
  /// only through `eventsWatchDebugRunNowProvider` (`kDebugMode`); not part
  /// of the `EventsWatchScheduler` port.
  Future<Either<Failure, Unit>> debugRunNow() => _guard(() async {
    await _gateway.registerOneOffNow();
    return right(unit);
  });

  Future<Either<Failure, Unit>> _confirm({
    required bool expected,
    required String reason,
  }) async {
    for (var attempt = 0; attempt < confirmAttempts; attempt++) {
      if (await _gateway.isScheduled() == expected) return right(unit);
      await Future<void>.delayed(confirmInterval);
    }
    return left(UnexpectedFailure(reason));
  }

  /// Plugin/platform errors become typed failures; nothing else is caught.
  Future<Either<Failure, T>> _guard<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      return left(UnexpectedFailure('scheduler platform ${e.code}'));
    } on MissingPluginException {
      return left(const UnexpectedFailure('scheduler plugin missing'));
    }
  }
}
