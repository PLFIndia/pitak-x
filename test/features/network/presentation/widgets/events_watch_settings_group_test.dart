import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_controller.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/presentation/widgets/events_watch_settings_group.dart';

/// PLAN.md §7 / §8 "UI/privacy": every phase renders one safe sentence,
/// the explanation precedes the first enable, Resume/Reset act, and no URL
/// or label ever reaches the screen.
void main() {
  late _FakeController fake;

  Future<void> pump(
    WidgetTester tester,
    EventsWatchView view, {
    // Null = what a release build sees (the DI gate returns null there).
    EventsWatchDebugRunNow? debugRunNow,
  }) async {
    fake = _FakeController(view);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsWatchSupportedProvider.overrideWithValue(true),
          eventsWatchControllerProvider.overrideWith(() => fake),
          eventsWatchDebugRunNowProvider.overrideWithValue(debugRunNow),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: EventsWatchSettingsGroup()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  EventsWatchView view(
    EventsWatchPhase phase, {
    bool needsExplanation = false,
    EventsWatchStatus status = EventsWatchStatus.none,
  }) => EventsWatchView(
    phase: phase,
    status: status,
    needsExplanation: needsExplanation,
  );

  testWidgets('renders nothing on unsupported platforms', (tester) async {
    fake = _FakeController(EventsWatchView.unsupported);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventsWatchSupportedProvider.overrideWithValue(false),
          eventsWatchControllerProvider.overrideWith(() => fake),
        ],
        child: const MaterialApp(
          home: Scaffold(body: EventsWatchSettingsGroup()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Event alerts'), findsNothing);
  });

  testWidgets('first enable shows the explanation; "Turn on" → enable', (
    tester,
  ) async {
    await pump(
      tester,
      view(EventsWatchPhase.setupOffered, needsExplanation: true),
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Event alerts'), findsWidgets);
    expect(find.textContaining('about every 12 hours'), findsWidgets);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['enable']);
  });

  testWidgets('"Not now" → declineOffer, nothing enabled', (tester) async {
    await pump(tester, view(EventsWatchPhase.off, needsExplanation: true));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['declineOffer']);
  });

  testWidgets('acknowledged explanation: toggling on enables directly', (
    tester,
  ) async {
    await pump(tester, view(EventsWatchPhase.off));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsNothing);
    expect(fake.calls, ['enable']);
  });

  testWidgets('ON: switch is on; toggling off → disable', (tester) async {
    await pump(tester, view(EventsWatchPhase.on));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(fake.calls, ['disable']);
  });

  testWidgets('notScheduled: switch on, Resume → resumeScheduling', (
    tester,
  ) async {
    await pump(tester, view(EventsWatchPhase.notScheduled));
    expect(find.textContaining('not scheduled'), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['resumeScheduling']);
  });

  testWidgets('settingsCorrupt: switch disabled, Reset action → reset', (
    tester,
  ) async {
    await pump(tester, view(EventsWatchPhase.settingsCorrupt));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Reset event alerts'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['reset']);
  });

  testWidgets('reset tile asks for confirmation first', (tester) async {
    await pump(tester, view(EventsWatchPhase.on));
    await tester.tap(find.widgetWithText(ListTile, 'Reset event alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.calls, isEmpty);
    await tester.tap(find.widgetWithText(ListTile, 'Reset event alerts'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['reset']);
  });

  testWidgets('blocked renders its sentence', (tester) async {
    await pump(tester, view(EventsWatchPhase.blocked));
    expect(find.textContaining('Notifications are blocked'), findsOneWidget);
  });

  testWidgets('storageError: Try again → reconcile', (tester) async {
    await pump(tester, view(EventsWatchPhase.storageError));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['reconcile']);
  });

  group('debug run hook', () {
    testWidgets('absent when the DI gate returns null (release builds)', (
      tester,
    ) async {
      await pump(tester, view(EventsWatchPhase.on));
      expect(find.textContaining('Run check now'), findsNothing);
    });

    testWidgets('present → enqueues once, no controller action, feedback', (
      tester,
    ) async {
      var runs = 0;
      await pump(
        tester,
        view(EventsWatchPhase.on),
        debugRunNow: () async {
          runs++;
          return right(unit);
        },
      );

      await tester.tap(find.text('Run check now (debug build)'));
      await tester.pumpAndSettle();

      expect(runs, 1);
      expect(fake.calls, isEmpty);
      expect(find.textContaining('Check enqueued'), findsOneWidget);
    });

    testWidgets('failure shows a safe sentence', (tester) async {
      await pump(
        tester,
        view(EventsWatchPhase.on),
        debugRunNow: () async =>
            left(const UnexpectedFailure('scheduler platform boom')),
      );

      await tester.tap(find.text('Run check now (debug build)'));
      await tester.pumpAndSettle();

      expect(find.text('Could not enqueue the check.'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  group('text helpers', () {
    test(
      'status lines: last check, withheld/failed counts, recovery notice',
      () {
        final lines = EventsWatchSettingsGroup.statusLinesFor(
          view(
            EventsWatchPhase.on,
            status: const EventsWatchStatus(
              lastRun: LastRunOutcome(
                finishedAt: 1700000000000,
                checked: 3,
                withheld: 1,
                failed: 2,
                capacityExceeded: false,
              ),
              withheldSites: 1,
              failedSites: 2,
              recoveryNotice: RecoveryNotice.stateReset,
              pendingAlerts: 1,
            ),
          ),
        );
        expect(lines[0], startsWith('Last check'));
        expect(
          lines[0],
          contains('3 checked, 1 could not be read, 2 unreachable.'),
        );
        expect(lines[1], '1 alert(s) waiting to be shown.');
        expect(lines[2], contains('was reset'));
      },
    );

    test('capacity exceeded is a visible sentence', () {
      final lines = EventsWatchSettingsGroup.statusLinesFor(
        view(
          EventsWatchPhase.on,
          status: const EventsWatchStatus(
            lastRun: LastRunOutcome(
              finishedAt: 1,
              checked: 0,
              withheld: 0,
              failed: 0,
              capacityExceeded: true,
            ),
            withheldSites: 0,
            failedSites: 0,
            recoveryNotice: null,
            pendingAlerts: 0,
          ),
        ),
      );
      expect(lines.single, contains('Too many saved libraries'));
    });

    test('no phase sentence contains a URL or placeholder', () {
      for (final phase in EventsWatchPhase.values) {
        final text = EventsWatchSettingsGroup.subtitleFor(view(phase));
        expect(text, isNot(contains('http')), reason: phase.name);
        expect(text, isNot(contains(r'$')), reason: phase.name);
      }
    });
  });
}

/// Records which action was invoked; never touches ports.
final class _FakeController extends EventsWatchController {
  _FakeController(this.view);
  final EventsWatchView view;
  final List<String> calls = [];

  @override
  Future<EventsWatchView> build() async => view;

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
