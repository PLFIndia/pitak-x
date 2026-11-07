import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/app_lock/app_lock_controller.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/root_navigator_key.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_controller.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/presentation/widgets/events_watch_lifecycle_relay.dart';

/// PLAN.md §5: the app-start owner bootstraps once, reconciles only while
/// unlocked, and offers default ON with the explanation (decision 1) —
/// never a silent schedule.
void main() {
  late _FakeController controller;
  late _Lock lock;
  late int bootstraps;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required EventsWatchView initial,
    required AppLockPhase phase,
  }) async {
    controller = _FakeController(initial);
    lock = _Lock(phase);
    bootstraps = 0;
    final container = ProviderContainer(
      overrides: [
        eventsWatchSupportedProvider.overrideWithValue(true),
        eventsWatchControllerProvider.overrideWith(() => controller),
        appLockControllerProvider.overrideWith(() => lock),
        eventsWatchBootstrapProvider.overrideWithValue((onTap) async {
          bootstraps++;
          return null;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: EventsWatchLifecycleRelay(
          child: MaterialApp(
            navigatorKey: container.read(rootNavigatorKeyProvider),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('unlocked at start: bootstraps once and reconciles', (
    tester,
  ) async {
    await pump(
      tester,
      initial: const EventsWatchView(
        phase: EventsWatchPhase.off,
        status: EventsWatchStatus.none,
      ),
      phase: AppLockPhase.unlocked,
    );
    expect(bootstraps, 1);
    expect(controller.calls, contains('reconcile'));
  });

  testWidgets('locked at start: no reconcile until unlocked', (tester) async {
    await pump(
      tester,
      initial: const EventsWatchView(
        phase: EventsWatchPhase.off,
        status: EventsWatchStatus.none,
      ),
      phase: AppLockPhase.locked,
    );
    expect(controller.calls, isEmpty);

    lock.forceUnlock();
    await tester.pumpAndSettle();
    expect(controller.calls, ['reconcile']);
  });

  testWidgets('setupOffered while unlocked shows the explanation once; '
      '"Turn on" → enable', (tester) async {
    await pump(
      tester,
      initial: const EventsWatchView(
        phase: EventsWatchPhase.setupOffered,
        status: EventsWatchStatus.none,
        needsExplanation: true,
      ),
      phase: AppLockPhase.unlocked,
    );
    // The listener fires on the first build value; let the dialog appear.
    controller.emit(
      const EventsWatchView(
        phase: EventsWatchPhase.setupOffered,
        status: EventsWatchStatus.none,
        needsExplanation: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(controller.calls, contains('enable'));

    // A second setupOffered value does not re-open the dialog this session.
    controller.emit(
      const EventsWatchView(
        phase: EventsWatchPhase.setupOffered,
        status: EventsWatchStatus.none,
        needsExplanation: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsNothing);
  });

  testWidgets('setupOffered while LOCKED shows nothing', (tester) async {
    await pump(
      tester,
      initial: const EventsWatchView(
        phase: EventsWatchPhase.setupOffered,
        status: EventsWatchStatus.none,
        needsExplanation: true,
      ),
      phase: AppLockPhase.locked,
    );
    controller.emit(
      const EventsWatchView(
        phase: EventsWatchPhase.setupOffered,
        status: EventsWatchStatus.none,
        needsExplanation: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsNothing);
  });
}

final class _FakeController extends EventsWatchController {
  _FakeController(this.initial);
  final EventsWatchView initial;
  final List<String> calls = [];

  @override
  Future<EventsWatchView> build() async => initial;

  void emit(EventsWatchView view) => state = AsyncData(view);

  @override
  Future<void> reconcile() async => calls.add('reconcile');
  @override
  Future<void> enable() async => calls.add('enable');
  @override
  Future<void> declineOffer() async => calls.add('declineOffer');
  @override
  Future<void> disable() async => calls.add('disable');
  @override
  Future<void> resumeScheduling() async => calls.add('resumeScheduling');
  @override
  Future<void> reset() async => calls.add('reset');
}

final class _Lock extends AppLockController {
  _Lock(this.phase);
  final AppLockPhase phase;

  @override
  AppLockState build() => AppLockState(phase: phase);

  void forceUnlock() =>
      state = const AppLockState(phase: AppLockPhase.unlocked);
}
