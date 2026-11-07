/// In-memory fakes of the background event check ports, shared by the
/// use-case and controller tests. Every fake records calls and can inject
/// one failure, so each PLAN.md §8 path can be driven without IO.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_libraries_source.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

final class FakeSettingsStore implements EventsWatchSettingsStore {
  WatchDocumentRead<EventsWatchSettings> doc = const WatchDocumentMissing();
  Failure? readFailure;
  Failure? writeFailure;
  int reads = 0;

  /// Hook run before each read, with the 1-based read count (lets a test
  /// change the document between the run's first and second read).
  void Function(int readNumber)? beforeRead;
  final List<EventsWatchSettings> writes = [];

  EventsWatchSettings? get current => switch (doc) {
    WatchDocumentPresent(:final value) => value,
    _ => null,
  };

  @override
  Future<Either<Failure, WatchDocumentRead<EventsWatchSettings>>> read() async {
    reads++;
    beforeRead?.call(reads);
    if (readFailure != null) return left(readFailure!);
    return right(doc);
  }

  @override
  Future<Either<Failure, Unit>> write(EventsWatchSettings settings) async {
    if (writeFailure != null) return left(writeFailure!);
    writes.add(settings);
    doc = WatchDocumentPresent(settings);
    return right(unit);
  }
}

final class FakeStateStore implements EventsWatchStateStore {
  WatchDocumentRead<EventsWatchState> doc = const WatchDocumentMissing();
  Failure? readFailure;
  Failure? writeFailure;
  final List<EventsWatchState> writes = [];

  EventsWatchState? get current => switch (doc) {
    WatchDocumentPresent(:final value) => value,
    _ => null,
  };

  @override
  Future<Either<Failure, WatchDocumentRead<EventsWatchState>>> read() async {
    if (readFailure != null) return left(readFailure!);
    return right(doc);
  }

  @override
  Future<Either<Failure, Unit>> write(EventsWatchState state) async {
    if (writeFailure != null) return left(writeFailure!);
    writes.add(state);
    doc = WatchDocumentPresent(state);
    return right(unit);
  }
}

final class FakeSource implements WatchedLibrariesSource {
  List<WatchedLibrary> rows = [];
  Failure? snapshotFailure;
  Failure? membershipFailure;
  int membershipCalls = 0;

  /// Hook run before each membership answer (simulates mid-run removal).
  void Function(WatchedLibraryIdentity identity)? onMembership;

  @override
  Future<Either<Failure, List<WatchedLibrary>>> snapshot() async {
    if (snapshotFailure != null) return left(snapshotFailure!);
    return right(List.of(rows));
  }

  @override
  Future<Either<Failure, WatchedMembership>> membership(
    WatchedLibraryIdentity identity,
  ) async {
    membershipCalls++;
    onMembership?.call(identity);
    if (membershipFailure != null) return left(membershipFailure!);
    final present = rows.any((r) => r.identity.sameAs(identity));
    return right(
      present ? WatchedMembership.stillWatched : WatchedMembership.removed,
    );
  }
}

/// Scripted `events.json` responses per site URL.
final class FakeFetchers {
  final Map<
    String,
    PublishedFileFetch<PublishedEvents> Function(String? validator)
  >
  scripts = {};
  final List<(String url, String? validator)> calls = [];

  /// Completes when a fetch for `url` is in flight (for deadline tests).
  final Map<String, Completer<void>> gates = {};

  Future<PublishedFileFetch<PublishedEvents>> Function(
    String url, {
    String? validator,
    Future<void>? abortTrigger,
  })
  factory(String siteUrl) => (url, {validator, abortTrigger}) async {
    calls.add((siteUrl, validator));
    final gate = gates[siteUrl];
    if (gate != null) await gate.future;
    final script = scripts[siteUrl];
    if (script == null) {
      return const PublishedFileFailed(
        failure: NetworkFailure(),
        problem: PublishedFileProblem.unreachable,
      );
    }
    return script(validator);
  };
}

final class FakeNotifier implements LocalNotifier {
  NotificationDelivery deliveryState = NotificationDelivery.deliverable;
  Failure? deliveryFailure;
  Failure? showFailure;
  Failure? summaryFailure;
  final List<LibraryAlert> shown = [];
  final List<int> summaries = [];
  final List<int> cancelled = [];
  int cancelAllCalls = 0;

  @override
  Future<Either<Failure, NotificationDelivery>> delivery() async {
    if (deliveryFailure != null) return left(deliveryFailure!);
    return right(deliveryState);
  }

  @override
  Future<Either<Failure, Unit>> showLibrary(LibraryAlert alert) async {
    if (showFailure != null) return left(showFailure!);
    shown.add(alert);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> showSummary({required int libraryCount}) async {
    if (summaryFailure != null) return left(summaryFailure!);
    summaries.add(libraryCount);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancelLibrary(int notificationId) async {
    cancelled.add(notificationId);
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancelAllFeatureAlerts() async {
    cancelAllCalls++;
    return right(unit);
  }
}

final class FakeScheduler implements EventsWatchScheduler {
  WatchJobRegistration state = WatchJobRegistration.notRegistered;
  Failure? registerFailure;
  Failure? cancelFailure;
  Failure? registrationFailure;
  int registerCalls = 0;
  int cancelCalls = 0;

  @override
  Future<Either<Failure, Unit>> ensureRegistered() async {
    registerCalls++;
    if (registerFailure != null) return left(registerFailure!);
    state = WatchJobRegistration.registered;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancel() async {
    cancelCalls++;
    if (cancelFailure != null) return left(cancelFailure!);
    state = WatchJobRegistration.notRegistered;
    return right(unit);
  }

  @override
  Future<Either<Failure, WatchJobRegistration>> registration() async {
    if (registrationFailure != null) return left(registrationFailure!);
    return right(state);
  }
}

final class FakeClock implements WatchClock {
  int now = 1700000000000;
  Duration elapsed = Duration.zero;

  @override
  int nowEpochMillis() => now;

  @override
  Stopwatch startStopwatch() => _FakeStopwatch(this);
}

final class _FakeStopwatch implements Stopwatch {
  _FakeStopwatch(this.clock);
  final FakeClock clock;

  @override
  Duration get elapsed => clock.elapsed;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
