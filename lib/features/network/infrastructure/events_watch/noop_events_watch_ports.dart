/// No-op ports for platforms without background event alerts (decision 4:
/// Android only). Desktop/iOS/tests bind these; nothing is ever scheduled
/// or shown, and every "is it possible?" question answers no.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';

/// A notifier that can never deliver.
final class NoopLocalNotifier implements LocalNotifier {
  /// Creates the no-op notifier.
  const NoopLocalNotifier();

  @override
  Future<Either<Failure, NotificationDelivery>> delivery() async =>
      right(NotificationDelivery.blocked);

  @override
  Future<Either<Failure, Unit>> showLibrary(LibraryAlert alert) async =>
      left(const UnexpectedFailure('notifications unsupported'));

  @override
  Future<Either<Failure, Unit>> showSummary({
    required int libraryCount,
  }) async => left(const UnexpectedFailure('notifications unsupported'));

  @override
  Future<Either<Failure, Unit>> cancelLibrary(int notificationId) async =>
      right(unit);

  @override
  Future<Either<Failure, Unit>> cancelAllFeatureAlerts() async => right(unit);
}

/// A scheduler that refuses to register and is never registered.
final class NoopEventsWatchScheduler implements EventsWatchScheduler {
  /// Creates the no-op scheduler.
  const NoopEventsWatchScheduler();

  @override
  Future<Either<Failure, Unit>> ensureRegistered() async =>
      left(const UnexpectedFailure('scheduler unsupported'));

  @override
  Future<Either<Failure, Unit>> cancel() async => right(unit);

  @override
  Future<Either<Failure, WatchJobRegistration>> registration() async =>
      right(WatchJobRegistration.notRegistered);
}

/// A permission request that is always refused permanently.
Future<Either<Failure, NotificationPermissionOutcome>>
noopNotificationPermissionRequest() async =>
    right(NotificationPermissionOutcome.permanentlyDenied);

/// System wall clock + real stopwatch.
final class SystemWatchClock implements WatchClock {
  /// Creates the system clock.
  const SystemWatchClock();

  @override
  int nowEpochMillis() => DateTime.now().millisecondsSinceEpoch;

  @override
  Stopwatch startStopwatch() => Stopwatch()..start();
}
