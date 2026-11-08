import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_controller.dart';
import 'package:pitaka/features/network/application/events_watch/events_watch_view.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_ports.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';

import 'events_watch_fakes.dart';

/// PLAN.md §5–§6 and §8 "Controller": first-run offer, enable/disable,
/// denied → OFF, revocation marker consumption, Resume (decision 14),
/// failed-save never published, reset, serialized actions.
void main() {
  const incA = '0f6c1d2e-3b4a-4c5d-8e9f-0a1b2c3d4e5f';
  const incB = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
  late FakeSettingsStore settings;
  late FakeStateStore state;
  late FakeSource source;
  late FakeNotifier notifier;
  late FakeScheduler scheduler;
  late NotificationPermissionOutcome permission;
  late int permissionRequests;
  late List<String> incarnations;
  late ProviderContainer container;

  WatchedLibrary lib(int n) => WatchedLibrary(
    identity: WatchedLibraryIdentity(
      rowId: n,
      createdAt: n,
      siteUrl: 'https://l$n.github.io/x/',
    ),
    publicName: null,
  );

  setUp(() {
    settings = FakeSettingsStore();
    state = FakeStateStore();
    source = FakeSource();
    notifier = FakeNotifier();
    scheduler = FakeScheduler();
    permission = NotificationPermissionOutcome.granted;
    permissionRequests = 0;
    incarnations = [incA, incB];
    container = ProviderContainer(
      overrides: [
        eventsWatchSupportedProvider.overrideWithValue(true),
        eventsWatchSettingsStoreProvider.overrideWith((ref) async => settings),
        eventsWatchStateStoreProvider.overrideWith((ref) async => state),
        watchedLibrariesSourceProvider.overrideWith((ref) async => source),
        eventsWatchNotifierProvider.overrideWithValue(notifier),
        eventsWatchSchedulerProvider.overrideWithValue(scheduler),
        eventsWatchPermissionRequestProvider.overrideWithValue(() async {
          permissionRequests++;
          return right(permission);
        }),
        eventsWatchIncarnationGeneratorProvider.overrideWithValue(
          () => incarnations.removeAt(0),
        ),
        networkRepositoryProvider.overrideWith((ref) async => _EmptyRepo()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(eventsWatchControllerProvider, (_, _) {});
  });

  Future<EventsWatchView> view() =>
      container.read(eventsWatchControllerProvider.future);
  EventsWatchController notifierOf() =>
      container.read(eventsWatchControllerProvider.notifier);
  EventsWatchView current() =>
      container.read(eventsWatchControllerProvider).requireValue;

  group('reconcile', () {
    test(
      'fresh install, no libraries → noLibraries, no file written',
      () async {
        expect((await view()).phase, EventsWatchPhase.noLibraries);
        expect(settings.writes, isEmpty);
        expect(scheduler.registerCalls, 0);
      },
    );

    test('fresh install with a saved library → setup offered (default ON '
        'is an OFFER, not a silent schedule)', () async {
      source.rows = [lib(1)];
      final v = await view();
      expect(v.phase, EventsWatchPhase.setupOffered);
      expect(v.needsExplanation, isTrue);
      expect(scheduler.registerCalls, 0);
      expect(permissionRequests, 0);
    });

    test('ON + registered → on; ON + not registered → notScheduled (Resume), '
        'never auto-repaired', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: true),
      );
      scheduler.state = WatchJobRegistration.registered;
      expect((await view()).phase, EventsWatchPhase.on);

      scheduler.state = WatchJobRegistration.notRegistered;
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.notScheduled);
      expect(scheduler.registerCalls, 0);
    });

    test('unknown registration state fails closed to notScheduled', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: true),
      );
      scheduler.registrationFailure = const UnexpectedFailure('x');
      expect((await view()).phase, EventsWatchPhase.notScheduled);
    });

    test('ON with zero libraries cancels the job without a prompt, keeps '
        'settings ON and records the pause under the SAME token', () async {
      final on = EventsWatchSettings.initial(incA).withEnabled(enabled: true);
      settings.doc = WatchDocumentPresent(on);
      scheduler.state = WatchJobRegistration.registered;
      expect((await view()).phase, EventsWatchPhase.noLibraries);
      expect(scheduler.cancelCalls, 1);
      final saved = settings.writes.single;
      expect(saved.enabled, isTrue);
      expect(saved.pausedForNoLibraries, isTrue);
      expect(saved.token.sameAs(on.token), isTrue);
      expect(permissionRequests, 0);

      // A second empty reconcile does not rewrite the document.
      await notifierOf().reconcile();
      expect(settings.writes.length, 1);
    });

    test('a library saved after OUR no-libraries pause resumes automatically '
        'and clears the pause; no prompt, no explanation', () async {
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(
          incA,
        ).withExplanationAcknowledged().withEnabled(enabled: true),
      );
      scheduler.state = WatchJobRegistration.registered;
      expect((await view()).phase, EventsWatchPhase.noLibraries);
      expect(scheduler.state, WatchJobRegistration.notRegistered);

      source.rows = [lib(1)];
      await notifierOf().reconcile();

      expect(current().phase, EventsWatchPhase.on);
      expect(scheduler.registerCalls, 1);
      expect(settings.current!.pausedForNoLibraries, isFalse);
      expect(settings.current!.enabled, isTrue);
      expect(permissionRequests, 0);
    });

    test('a missing registration WITHOUT our pause is still the explicit '
        'Resume state (decision 14), even with libraries saved', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: true),
      );
      scheduler.state = WatchJobRegistration.notRegistered;
      expect((await view()).phase, EventsWatchPhase.notScheduled);
      expect(scheduler.registerCalls, 0);
      expect(settings.writes, isEmpty);
    });

    test('a failed pause save forgets the pause: the next library lands in '
        'Resume, never auto-registers (fail closed)', () async {
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: true),
      );
      scheduler.state = WatchJobRegistration.registered;
      settings.writeFailure = const StorageFailure('disk');
      expect((await view()).phase, EventsWatchPhase.noLibraries);
      expect(scheduler.cancelCalls, 1);

      settings.writeFailure = null;
      source.rows = [lib(1)];
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.notScheduled);
      expect(scheduler.registerCalls, 0);
    });

    test(
      'an explicit disable ends the pause (new token, flag cleared)',
      () async {
        settings.doc = WatchDocumentPresent(
          EventsWatchSettings.initial(
            incA,
          ).withEnabled(enabled: true).withPausedForNoLibraries(paused: true),
        );
        await view();
        await notifierOf().disable();
        expect(settings.current!.pausedForNoLibraries, isFalse);
        expect(settings.current!.enabled, isFalse);
      },
    );

    test('OFF + delivery blocked → blocked (derived, survives the resume '
        'reconcile); OFF + deliverable → off; no libraries wins', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: false),
      );
      notifier.deliveryState = NotificationDelivery.blocked;
      expect((await view()).phase, EventsWatchPhase.blocked);

      await notifierOf().reconcile(); // what a lifecycle resume triggers
      expect(current().phase, EventsWatchPhase.blocked);

      notifier.deliveryState = NotificationDelivery.deliverable;
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.off);

      notifier.deliveryState = NotificationDelivery.blocked;
      source.rows = [];
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.noLibraries);

      expect(settings.writes, isEmpty);
      expect(scheduler.registerCalls, 0);
      expect(permissionRequests, 0);
    });

    test(
      'a delivery check error while OFF shows plain off, never blocked',
      () async {
        source.rows = [lib(1)];
        settings.doc = WatchDocumentPresent(
          EventsWatchSettings.initial(incA).withEnabled(enabled: false),
        );
        notifier.deliveryFailure = const UnexpectedFailure('plugin');
        expect((await view()).phase, EventsWatchPhase.off);
      },
    );

    test('a revocation marker for the current token is consumed: OFF with a '
        'new token, job cancelled, alerts cleared → blocked', () async {
      source.rows = [lib(1)];
      final s = EventsWatchSettings.initial(incA).withEnabled(enabled: true);
      settings.doc = WatchDocumentPresent(s);
      state.doc = WatchDocumentPresent(
        EventsWatchState.empty().copyWith(revocationToken: s.token),
      );
      notifier.deliveryState = NotificationDelivery.deliverable; // re-granted

      expect((await view()).phase, EventsWatchPhase.blocked);
      final saved = settings.writes.single;
      expect(saved.enabled, isFalse);
      expect(saved.token.epoch, s.token.epoch + 1);
      expect(scheduler.cancelCalls, 1);
      expect(notifier.cancelAllCalls, 1);
    });

    test('delivery blocked while ON → OFF + new token → blocked', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(incA).withEnabled(enabled: true),
      );
      notifier.deliveryState = NotificationDelivery.blocked;
      expect((await view()).phase, EventsWatchPhase.blocked);
      expect(settings.current!.enabled, isFalse);
    });

    test('newer settings schema → updateRequired; corrupt → settingsCorrupt; '
        'IO → storageError', () async {
      settings.doc = const WatchDocumentNewerSchema();
      expect((await view()).phase, EventsWatchPhase.updateRequired);
      settings.doc = const WatchDocumentCorrupt();
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.settingsCorrupt);
      settings.readFailure = const StorageFailure('io');
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.storageError);
      expect(settings.writes, isEmpty);
    });

    test('status summarises the worker state file', () async {
      state.doc = WatchDocumentPresent(
        EventsWatchState.empty().copyWith(
          recoveryNotice: RecoveryNotice.stateReset,
          lastRun: const LastRunOutcome(
            finishedAt: 5,
            checked: 2,
            withheld: 1,
            failed: 0,
            capacityExceeded: false,
          ),
        ),
      );
      final v = await view();
      expect(v.status.recoveryNotice, RecoveryNotice.stateReset);
      expect(v.status.lastRun!.checked, 2);
    });
  });

  group('enable', () {
    test('granted → ON persisted BEFORE registering, explanation acknowledged, '
        'fresh incarnation', () async {
      source.rows = [lib(1)];
      await view();

      await notifierOf().enable();

      expect(current().phase, EventsWatchPhase.on);
      final saved = settings.writes.single;
      expect(saved.enabled, isTrue);
      expect(saved.token.incarnation, incA);
      expect(saved.token.epoch, 1);
      expect(saved.needsExplanation, isFalse);
      expect(scheduler.registerCalls, 1);
      expect(permissionRequests, 1);
    });

    test('denied → OFF persisted with a new token and acknowledgement; '
        'blocked phase; nothing registered', () async {
      source.rows = [lib(1)];
      permission = NotificationPermissionOutcome.denied;
      await view();

      await notifierOf().enable();

      expect(current().phase, EventsWatchPhase.blocked);
      final saved = settings.writes.single;
      expect(saved.enabled, isFalse);
      expect(saved.needsExplanation, isFalse);
      expect(scheduler.registerCalls, 0);
    });

    test('a failed settings save is NEVER published as ON and does not '
        'register', () async {
      source.rows = [lib(1)];
      settings.writeFailure = const StorageFailure('disk');
      await view();

      await notifierOf().enable();

      expect(current().phase, EventsWatchPhase.storageError);
      expect(scheduler.registerCalls, 0);
    });

    test(
      'registration failure after a good save → notScheduled (Resume)',
      () async {
        source.rows = [lib(1)];
        scheduler.registerFailure = const UnexpectedFailure('wm');
        await view();

        await notifierOf().enable();

        expect(current().phase, EventsWatchPhase.notScheduled);
        expect(settings.current!.enabled, isTrue);
      },
    );

    test('an ordinary resume after enable never prompts again', () async {
      source.rows = [lib(1)];
      await view();
      await notifierOf().enable();
      await notifierOf().reconcile();
      await notifierOf().reconcile();
      expect(permissionRequests, 1);
      expect(current().phase, EventsWatchPhase.on);
    });
  });

  group('decline, disable, resume, reset', () {
    test('"Not now" persists OFF with the explanation acknowledged', () async {
      source.rows = [lib(1)];
      await view();
      await notifierOf().declineOffer();
      expect(current().phase, EventsWatchPhase.off);
      expect(settings.current!.enabled, isFalse);
      expect(settings.current!.needsExplanation, isFalse);
      await notifierOf().reconcile();
      expect(current().phase, EventsWatchPhase.off);
      expect(current().needsExplanation, isFalse);
    });

    test(
      'disable saves OFF + new token first, then cancels and clears',
      () async {
        source.rows = [lib(1)];
        await view();
        await notifierOf().enable();
        final onToken = settings.current!.token;

        await notifierOf().disable();

        expect(current().phase, EventsWatchPhase.off);
        expect(settings.current!.enabled, isFalse);
        expect(settings.current!.token.epoch, onToken.epoch + 1);
        expect(scheduler.cancelCalls, 1);
        expect(notifier.cancelAllCalls, 1);
      },
    );

    test('disable with a failed save still cancels and reports storageError, '
        'never a false OFF', () async {
      source.rows = [lib(1)];
      await view();
      await notifierOf().enable();
      settings.writeFailure = const StorageFailure('disk');

      await notifierOf().disable();

      expect(current().phase, EventsWatchPhase.storageError);
      expect(scheduler.cancelCalls, 1);
      expect(settings.current!.enabled, isTrue); // disk still says ON
    });

    test('Resume re-registers when settings are ON, without a settings write '
        'or a new prompt', () async {
      source.rows = [lib(1)];
      settings.doc = WatchDocumentPresent(
        EventsWatchSettings.initial(
          incA,
        ).withEnabled(enabled: true).withExplanationAcknowledged(),
      );
      expect((await view()).phase, EventsWatchPhase.notScheduled);

      await notifierOf().resumeScheduling();

      expect(current().phase, EventsWatchPhase.on);
      expect(settings.writes, isEmpty);
      expect(permissionRequests, 0);
      expect(scheduler.registerCalls, 1);
    });

    test(
      'reset → fresh incarnation, epoch 0, OFF; cancelled; cleared',
      () async {
        source.rows = [lib(1)];
        await view();
        await notifierOf().enable();

        await notifierOf().reset();

        expect(current().phase, EventsWatchPhase.off);
        final saved = settings.current!;
        expect(saved.token.incarnation, incB);
        expect(saved.token.epoch, 0);
        expect(saved.enabled, isFalse);
        expect(scheduler.cancelCalls, 1);
        expect(state.writes, isEmpty); // foreground never edits the state file
      },
    );

    test(
      'actions are serialized: a disable queued behind an enable wins',
      () async {
        source.rows = [lib(1)];
        await view();
        final enable = notifierOf().enable();
        final disable = notifierOf().disable();
        await Future.wait([enable, disable]);
        expect(current().phase, EventsWatchPhase.off);
        expect(settings.current!.enabled, isFalse);
        expect(settings.writes.map((w) => w.enabled), [true, false]);
      },
    );
  });

  test('unsupported platform → unsupported view, no port is touched', () async {
    final c = ProviderContainer(
      overrides: [eventsWatchSupportedProvider.overrideWithValue(false)],
    );
    addTearDown(c.dispose);
    c.listen(eventsWatchControllerProvider, (_, _) {});
    final v = await c.read(eventsWatchControllerProvider.future);
    expect(v.phase, EventsWatchPhase.unsupported);
  });
}

/// The network window is only LISTENED to (for row-change triggers); an
/// empty repository keeps it inert.
final class _EmptyRepo implements NetworkRepository {
  @override
  Future<List<NetworkLibrary>> loadAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
