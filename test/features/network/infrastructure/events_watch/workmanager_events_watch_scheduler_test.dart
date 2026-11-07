import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/infrastructure/events_watch/workmanager_events_watch_scheduler.dart';

/// PLAN.md §5: a returned method-channel call is not proof of completion.
/// The adapter must confirm the native state and fail when it never
/// matches.
void main() {
  late _FakeGateway gateway;
  WorkmanagerEventsWatchScheduler scheduler() =>
      WorkmanagerEventsWatchScheduler(
        gateway: gateway,
        confirmAttempts: 3,
        confirmInterval: Duration.zero,
      );

  setUp(() => gateway = _FakeGateway());

  test(
    'ensureRegistered succeeds only once isScheduled reports true',
    () async {
      gateway.becomesScheduledAfterPolls = 2;

      final result = await scheduler().ensureRegistered();

      expect(result.isRight(), isTrue);
      expect(gateway.registerCalls, 1);
      expect(gateway.pollCalls, 2);
    },
  );

  test('a register call that returns but never becomes scheduled is a '
      'failure, not a success', () async {
    gateway.becomesScheduledAfterPolls = 99;

    final result = await scheduler().ensureRegistered();

    expect(result.getLeft().toNullable(), isA<UnexpectedFailure>());
    expect(gateway.pollCalls, 3);
  });

  test('cancel succeeds only once isScheduled reports false', () async {
    gateway
      ..scheduled = true
      ..becomesUnscheduledAfterPolls = 1;

    final result = await scheduler().cancel();

    expect(result.isRight(), isTrue);
    expect(gateway.cancelCalls, 1);
  });

  test('a cancel that is never observed fails closed', () async {
    gateway
      ..scheduled = true
      ..becomesUnscheduledAfterPolls = 99;

    final result = await scheduler().cancel();

    expect(result.isLeft(), isTrue);
  });

  test('registration reports the authoritative state', () async {
    gateway.scheduled = true;
    expect(
      (await scheduler().registration()).toNullable(),
      WatchJobRegistration.registered,
    );
    gateway.scheduled = false;
    expect(
      (await scheduler().registration()).toNullable(),
      WatchJobRegistration.notRegistered,
    );
  });

  test('a platform exception from the plugin becomes a typed failure '
      '(registration unknown → caller fails closed)', () async {
    gateway.throwOnPoll = PlatformException(code: 'boom');

    final result = await scheduler().registration();

    expect(result.getLeft().toNullable(), isA<UnexpectedFailure>());
  });

  test('a missing plugin (desktop test host) is a typed failure', () async {
    gateway.throwOnPoll = MissingPluginException();

    expect((await scheduler().ensureRegistered()).isLeft(), isTrue);
  });
}

final class _FakeGateway implements WorkmanagerGateway {
  bool scheduled = false;
  int registerCalls = 0;
  int cancelCalls = 0;
  int pollCalls = 0;
  int becomesScheduledAfterPolls = 0;
  int becomesUnscheduledAfterPolls = 0;
  Exception? throwOnPoll;

  @override
  Future<void> registerPeriodic() async => registerCalls++;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Future<bool> isScheduled() async {
    if (throwOnPoll != null) throw throwOnPoll!;
    pollCalls++;
    if (registerCalls > 0 && pollCalls >= becomesScheduledAfterPolls) {
      scheduled = true;
    }
    if (cancelCalls > 0 && pollCalls >= becomesUnscheduledAfterPolls) {
      scheduled = false;
    }
    return scheduled;
  }
}
